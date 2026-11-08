use anyhow::Result;
use std::sync::Arc;
use uuid::Uuid;

use crate::utils::logger;
use crate::utils::types::DownloadInfo;

use crate::downloader::manager::DownloadManager;
use crate::downloader::worker::DownloadWorker;

impl DownloadManager {
    pub async fn get_worker(&self, id: Uuid) -> Option<Arc<DownloadWorker>> {
        let workers = self.workers.lock().await;
        workers.get(&id).cloned()
    }

    pub async fn info(&self, id: Uuid) -> Result<DownloadInfo> {
        let w = {
            let map = self.workers.lock().await;
            map.get(&id).cloned()
        };
        match w {
            Some(worker) => Ok(worker.info().await),
            None => Err(anyhow::anyhow!("Worker not found")),
        }
    }

    /// Worker ids whose byte counters may still move.
    pub async fn ongoing_ids(&self) -> Vec<Uuid> {
        let ongoing = self.ongoing.lock().await;
        ongoing.iter().copied().collect()
    }

    pub async fn ongoing_add(&self, id: Uuid) {
        self.ongoing.lock().await.insert(id);
    }

    pub async fn ongoing_remove(&self, id: Uuid) {
        self.ongoing.lock().await.remove(&id);
    }

    /// Full-row commit for one download. Reads the latest worker state under
    /// the database write gate.
    pub async fn persist(&self, id: Uuid) {
        let Some(ctx) = self.context.upgrade() else {
            logger::error(&format!(
                "AppContext dropped while persisting download {}",
                id
            ));
            return;
        };
        ctx.db().await.save_download(id).await;
    }

    /// Immediate row removal for a download that no longer exists.
    pub async fn delete_persisted(&self, id: Uuid) {
        let Some(ctx) = self.context.upgrade() else {
            logger::error(&format!(
                "AppContext dropped while deleting download {}",
                id
            ));
            return;
        };
        ctx.db().await.delete_download(id).await;
    }

    pub async fn list_all(&self) -> Result<Vec<DownloadInfo>> {
        let workers: Vec<Arc<DownloadWorker>> = {
            let map = self.workers.lock().await;
            map.values().cloned().collect()
        };

        let mut out = Vec::with_capacity(workers.len());
        for w in workers {
            out.push(w.info().await);
        }
        Ok(out)
    }

    pub async fn list_torrents(&self, hashes: Option<Vec<&str>>) -> Vec<DownloadInfo> {
        let workers: Vec<Arc<DownloadWorker>> = {
            let map = self.workers.lock().await;
            map.values().cloned().collect()
        };

        let mut out = Vec::new();
        for w in workers {
            let info = w.info().await;
            if info.torrent_hash.is_some() {
                if let Some(filter_hashes) = &hashes
                    && let Some(ref h) = info.torrent_hash
                    && !filter_hashes.contains(&h.as_str())
                {
                    continue;
                }
                out.push(info);
            }
        }
        out
    }
}
