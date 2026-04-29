use anyhow::Result;
use std::{
    path::{Component, PathBuf},
    sync::Arc,
};
use uuid::Uuid;

use crate::utils::logger;
use crate::utils::types::{DownloadInfo, DownloadType};

use crate::downloader::manager::DownloadManager;
use crate::downloader::worker::DownloadWorker;

impl DownloadManager {
    pub async fn start(&self, id: Uuid) -> Result<()> {
        let worker_opt = { self.workers.lock().await.get(&id).cloned() };
        let worker = match worker_opt {
            Some(w) => w,
            None => return Err(anyhow::anyhow!("Worker not found")),
        };

        {
            self.active.lock().await.insert(id);
        }

        let w = Arc::clone(&worker);

        tokio::spawn(async move {
            if let Err(e) = w.start().await {
                logger::error(&format!("Worker start encountered error: {:#?}", e));
            }
        });
        Ok(())
    }

    pub async fn add_download(
        self: &Arc<Self>,
        url: String,
        dest: PathBuf,
        cookie: Option<String>,
        user_agent: Option<String>,
        referer: Option<String>,
        category: Option<String>,
    ) -> Result<Uuid> {
        if dest.components().any(|c| matches!(c, Component::ParentDir)) {
            return Err(anyhow::anyhow!(
                "Path traversal is not allowed in destination"
            ));
        }

        let id = Uuid::new_v4();
        let worker = DownloadWorker::new(
            id,
            self.client.clone(),
            self.settings.clone(),
            url,
            dest,
            self.sender.clone(),
            self.torrent_session.clone(),
            cookie,
            user_agent,
            referer,
            category,
            std::sync::Arc::downgrade(self),
        )
        .await
        .map_err(|e| anyhow::anyhow!("{}", e))?;
        self.workers.lock().await.insert(id, worker);
        self.process_queue().await;
        Ok(id)
    }

    pub async fn load_snapshot(self: &Arc<Self>, downloads: Vec<DownloadInfo>) {
        let mut workers = self.workers.lock().await;

        for info in downloads {
            let id = info.id;
            if info
                .dest
                .components()
                .any(|c| matches!(c, Component::ParentDir))
            {
                logger::warn(&format!(
                    "Download with id {} has path traversal, skipping.",
                    &id
                ));
                continue;
            }
            let result = DownloadWorker::from_info(
                info,
                self.client.clone(),
                self.settings.clone(),
                self.sender.clone(),
                self.torrent_session.clone(),
                std::sync::Arc::downgrade(self),
            )
            .await;

            match result {
                Ok(worker) => {
                    workers.insert(id, worker);
                }
                Err(e) => {
                    logger::error(&format!("Failed to create worker for {}: {}", id, e));
                }
            }
        }
    }

    pub async fn delete_worker(&self, id: Uuid, delete_file: bool) -> Result<()> {
        // First cancel if it exists (this handles stopping, active set, concurrency)
        let _ = self.cancel(id).await;

        // Retrieve info before removing worker to check type and paths
        let info_opt = {
            let workers = self.workers.lock().await;
            if let Some(w) = workers.get(&id) {
                Some(w.info().await)
            } else {
                None
            }
        };

        // Then remove from workers map
        self.workers.lock().await.swap_remove(&id);

        // Add to pending deletions for DB
        self.pending_deletions.lock().await.push(id);

        if let Some(info) = info_opt {
            if matches!(info.download_type, DownloadType::Torrent) {
                let session_guard = self.torrent_session.read().await;
                if let Some(session) = session_guard.as_ref() {
                    // Try to delete using torrent_hash if available
                    if let Some(hash) = &info.torrent_hash {
                        let hash_to_delete = session.with_torrents(|torrents| {
                            for (id, torrent_handle) in torrents {
                                if hex::encode(torrent_handle.info_hash().0) == *hash {
                                    return Some(id);
                                }
                            }
                            None
                        });

                        if let Some(id) = hash_to_delete {
                            let _ = session
                                .delete(librqbit::api::TorrentIdOrHash::Id(id), delete_file)
                                .await;
                        }
                    }
                }
            } else {
                // Normal or HLS
                if delete_file {
                    if info.dest.exists() {
                        if info.dest.is_dir() {
                            tokio::fs::remove_dir_all(&info.dest).await.ok();
                        } else {
                            tokio::fs::remove_file(&info.dest).await.ok();
                        }
                    }
                    // Cleanup HLS temp dir
                    if matches!(info.download_type, DownloadType::HLS) {
                        let temp_dir = info
                            .dest
                            .parent()
                            .unwrap()
                            .join(format!("temp_{}", info.id));
                        if temp_dir.exists() {
                            tokio::fs::remove_dir_all(&temp_dir).await.ok();
                        }
                    }
                }
            }
        }

        Ok(())
    }
}
