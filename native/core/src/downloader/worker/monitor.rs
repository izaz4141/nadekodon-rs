use anyhow::Result;
use futures::future::join_all;
use std::{
    sync::{Arc, atomic::Ordering},
    time::{Duration, SystemTime, UNIX_EPOCH},
};
use tokio::{sync::Notify, time::interval};

use crate::utils::logger;
use crate::utils::types::{DownloadState, WorkerEvent};

use crate::downloader::constants::*;
use crate::downloader::worker::DownloadWorker;

impl DownloadWorker {
    pub async fn spawn_sampler_and_monitor(self: &Arc<Self>) -> Result<()> {
        let stop_flag = Arc::new(Notify::new());
        let stop_clone = stop_flag.clone();

        self.spawn_sampler(stop_flag);
        self.spawn_monitor(stop_clone).await?;
        Ok(())
    }

    fn spawn_sampler(self: &Arc<Self>, stop_flag: Arc<Notify>) {
        let sampler_worker = Arc::clone(self);
        tokio::spawn(async move {
            let mut samp = interval(Duration::from_secs(HISTORY_SAMPLE_INTERVAL_SECS));
            loop {
                while sampler_worker.paused.load(Ordering::SeqCst) {
                    sampler_worker.notify_resume.notified().await;
                    continue;
                }
                if sampler_worker.cancel.load(Ordering::SeqCst) {
                    break;
                }

                tokio::select! {
                    _ = samp.tick() => {
                        let current_value = match sampler_worker.info.lock().await.state.clone(){
                            DownloadState::Running => sampler_worker.downloaded.load(Ordering::SeqCst),
                            DownloadState::Seeding => sampler_worker.uploaded.load(Ordering::SeqCst),
                            _ => continue
                        };
                        let previous_value = sampler_worker
                            .history
                            .read()
                            .await
                            .last()
                            .map(|(_, value)| *value);
                        let ts_ms = SystemTime::now().duration_since(UNIX_EPOCH).unwrap().as_millis();
                        let ts_sec = SystemTime::now().duration_since(UNIX_EPOCH).unwrap().as_secs();

                        sampler_worker.history.write().await.push((ts_ms as u128, current_value));
                        let hist_len = sampler_worker.history.read().await.len();
                        if hist_len > MAX_HISTORY {
                            let remove = hist_len - MAX_HISTORY;
                            sampler_worker.history.write().await.drain(0..remove);
                        }

                        let settings = sampler_worker.settings.read().await;
                        let timeout_secs = settings.stalled_time * 60;
                        drop(settings);
                        let last_prog = sampler_worker.last_progress.load(Ordering::SeqCst);
                        let time_diff = ts_sec.saturating_sub(last_prog);

                        if let Some(previous_value) = previous_value {
                            if current_value != previous_value {
                                sampler_worker.last_progress.store(ts_sec, Ordering::SeqCst);
                                sampler_worker.stalled.store(false, Ordering::SeqCst);
                                continue;
                            }
                        } else {
                            continue;
                        }

                        if timeout_secs > 0 && time_diff >= timeout_secs {
                            let mut info = sampler_worker.info.lock().await;
                            info.state = DownloadState::Stalled;
                            sampler_worker.stalled.store(true, Ordering::SeqCst);
                            let id = info.id;
                            drop(info);
                            let _ = sampler_worker
                                .event_tx
                                .send(WorkerEvent::Stalled(id))
                                .await;
                            logger::debug(&format!("Download {} marked as stalled", id));

                        }
                    }
                    _ = stop_flag.notified() => {
                        break;
                    }
                }
            }
        });
    }

    async fn spawn_monitor(self: &Arc<Self>, stop_flag: Arc<Notify>) -> Result<()> {
        let monitor_worker = Arc::clone(self);
        let handles = {
            let mut guard = monitor_worker.handles.lock().await;
            std::mem::take(&mut *guard)
        };

        tokio::spawn(async move {
            let results = join_all(handles).await;
            stop_flag.notify_waiters();

            for (i, res) in results.into_iter().enumerate() {
                match res {
                    Ok(Ok(())) => {}
                    Ok(Err(e)) => {
                        let err_str = format!("Monitor: segment {} failed {:?}", i, e);
                        logger::error(&err_str);
                        let mut info = monitor_worker.info.lock().await;
                        info.state = DownloadState::Error(err_str.clone());
                        let id = info.id;
                        drop(info);
                        monitor_worker.sync_to_info().await;
                        let _ = monitor_worker
                            .event_tx
                            .send(WorkerEvent::Error(id, err_str))
                            .await;
                        return;
                    }
                    Err(e) => {
                        let err_str = format!("Monitor: join error {:?}", &e);
                        logger::error(&err_str);
                        let mut info = monitor_worker.info.lock().await;
                        info.state = DownloadState::Error(err_str.clone());
                        let id = info.id;
                        drop(info);
                        monitor_worker.sync_to_info().await;
                        let _ = monitor_worker
                            .event_tx
                            .send(WorkerEvent::Error(id, err_str))
                            .await;
                        return;
                    }
                }
            }
            if !monitor_worker.cancel.load(Ordering::SeqCst) {
                let mut info = monitor_worker.info.lock().await;
                if info.total_size.is_none() {
                    info.total_size = Some(monitor_worker.downloaded.load(Ordering::SeqCst));
                }
                info.state = DownloadState::Completed;
                let id = info.id;
                drop(info);
                monitor_worker.sync_to_info().await;
                let _ = monitor_worker
                    .event_tx
                    .send(WorkerEvent::Completed(id))
                    .await;
            }
        });

        Ok(())
    }
}
