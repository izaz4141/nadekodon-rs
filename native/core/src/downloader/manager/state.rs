use futures::future::join_all;
use indexmap::IndexMap;
use std::{sync::Arc, time::Duration};
use tokio::time::{Interval, interval};
use uuid::Uuid;

use crate::utils::helper::calc_speed;

use crate::downloader::manager::DownloadManager;
use crate::downloader::worker::DownloadWorker;

impl DownloadManager {
    pub async fn set_top_priority(&self, hashes: Vec<&str>) {
        let workers = self.workers.lock().await;

        let mut to_top: Vec<(Uuid, Arc<DownloadWorker>)> = Vec::new();
        let mut others: Vec<(Uuid, Arc<DownloadWorker>)> = Vec::new();

        for (id, worker) in workers.iter() {
            let info = worker.info().await;
            if let Some(ref hash) = info.torrent_hash {
                if hashes.is_empty() || hashes.contains(&hash.as_str()) {
                    to_top.push((*id, worker.clone()));
                } else {
                    others.push((*id, worker.clone()));
                }
            } else {
                others.push((*id, worker.clone()));
            }
        }

        drop(workers);

        let mut new_order = IndexMap::new();
        for (id, worker) in to_top {
            new_order.insert(id, worker);
        }
        for (id, worker) in others {
            new_order.insert(id, worker);
        }

        let mut workers = self.workers.lock().await;
        *workers = new_order;
    }

    pub async fn sync_active_workers(&self) {
        let active_ids = {
            let active = self.active.lock().await;
            active.iter().cloned().collect::<Vec<_>>()
        };

        let workers = self.workers.lock().await;
        for id in active_ids {
            if let Some(w) = workers.get(&id) {
                w.sync_to_info().await;
            }
        }
    }

    pub async fn recalculate_speed_limits(&self, mut interval: Interval) {
        loop {
            interval.tick().await;
            let global_limit = self.settings.read().await.speed_limit;
            if global_limit == 0 {
                let active = self.active.lock().await;
                let workers = self.workers.lock().await;
                for id in active.iter() {
                    if let Some(w) = workers.get(id) {
                        w.change_speed_limit(0).await;
                    }
                }
                continue;
            }

            let worker_refs = {
                let active = self.active.lock().await;
                let workers = self.workers.lock().await;
                active
                    .iter()
                    .filter_map(|id| workers.get(id).cloned())
                    .collect::<Vec<_>>()
            };

            let histories = join_all(
                worker_refs
                    .iter()
                    .map(|w| async { w.history.read().await.clone() }),
            )
            .await;

            let mut worker_speeds = Vec::new();
            let mut total_speed = 0u64;

            for (i, w) in worker_refs.iter().enumerate() {
                let s = calc_speed(histories[i].clone()) as u64;
                total_speed += s;
                worker_speeds.push((w.clone(), s));
            }

            if total_speed == 0 {
                let even_limit = global_limit / worker_speeds.len().max(1) as u64;
                for (w, _) in worker_speeds {
                    w.change_speed_limit(even_limit).await;
                }
                continue;
            }

            for (w, speed) in worker_speeds {
                let share = ((speed as f64 / total_speed as f64) * global_limit as f64) as u64;
                w.change_speed_limit(share.max((global_limit as f64 * 0.05) as u64))
                    .await;
            }
        }
    }

    pub async fn updater(self: &Arc<Self>) {
        let interval2 = interval(Duration::from_secs(1));
        let mgr2 = self.clone();

        tokio::spawn(async move {
            mgr2.recalculate_speed_limits(interval2).await;
        });
    }
}
