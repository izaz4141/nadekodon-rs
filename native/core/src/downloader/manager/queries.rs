use anyhow::Result;
use std::sync::Arc;
use uuid::Uuid;

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

    pub async fn list_all(&self) -> Result<Vec<DownloadInfo>> {
        let map = self.workers.lock().await;
        let mut out = Vec::new();
        for w in map.values() {
            out.push(w.info().await);
        }
        Ok(out)
    }

    pub async fn list_torrents(&self, hashes: Option<Vec<&str>>) -> Vec<DownloadInfo> {
        let map = self.workers.lock().await;
        let mut out = Vec::new();
        for w in map.values() {
            let info = w.info().await;
            if info.torrent_hash.is_some() {
                if let Some(filter_hashes) = &hashes {
                    if let Some(ref h) = info.torrent_hash {
                        if !filter_hashes.contains(&h.as_str()) {
                            continue;
                        }
                    }
                }
                out.push(info);
            }
        }
        out
    }
}
