use anyhow::Result;
use std::sync::atomic::Ordering;
use uuid::Uuid;

use crate::utils::types::{DownloadState, DownloadType};

use crate::downloader::manager::DownloadManager;

impl DownloadManager {
    pub async fn pause(&self, id: Uuid) -> Result<()> {
        let w = { self.workers.lock().await.get(&id).cloned() };
        match w {
            Some(worker) => {
                {
                    let info = worker.info.lock().await;
                    if cfg!(target_os = "android") && info.download_type == DownloadType::YTDLP {
                        return Ok(());
                    }
                }

                worker.pause().await?;
                if self.active.lock().await.remove(&id)
                    && self.concurrency.load(Ordering::SeqCst) > 0
                {
                    self.concurrency.fetch_sub(1, Ordering::SeqCst);
                }
                self.process_queue().await;
                Ok(())
            }
            None => Err(anyhow::anyhow!("Worker not found")),
        }
    }

    pub async fn resume(&self, id: Uuid) -> Result<()> {
        let w = { self.workers.lock().await.get(&id).cloned() };
        match w {
            Some(worker) => {
                {
                    let mut info = worker.info.lock().await;
                    match info.state {
                        DownloadState::Paused => {
                            info.state = DownloadState::Queued;
                        }
                        _ => {
                            return Ok(());
                        }
                    }
                }
                self.process_queue().await;
                Ok(())
            }
            None => Err(anyhow::anyhow!("Worker not found")),
        }
    }

    pub async fn cancel(&self, id: Uuid) -> Result<()> {
        let w = { self.workers.lock().await.get(&id).cloned() };
        match w {
            Some(worker) => {
                {
                    let info = worker.info.lock().await;
                    if cfg!(target_os = "android") && info.download_type == DownloadType::YTDLP {
                        return Ok(());
                    }
                }

                worker.cancel().await?;
                self.active.lock().await.remove(&id);
                let conc = self.concurrency.load(Ordering::SeqCst);
                if conc > 0 {
                    self.concurrency.store(conc - 1, Ordering::SeqCst);
                };
                self.process_queue().await;
                Ok(())
            }
            None => Err(anyhow::anyhow!("Worker not found")),
        }
    }

    pub async fn update_download_url(&self, id: Uuid, new_url: String) -> Result<()> {
        let worker = {
            let workers = self.workers.lock().await;
            workers.get(&id).cloned()
        };

        if let Some(worker) = worker {
            let was_running = worker.started.load(Ordering::SeqCst);

            if was_running {
                let safe_info = worker.info.lock().await.clone();
                self.cancel(safe_info.id).await?;
                tokio::time::sleep(tokio::time::Duration::from_secs(2)).await;
                worker.started.store(false, Ordering::SeqCst);
            }

            worker.update_url(new_url).await?;

            if was_running {
                let mut info_lock = worker.info.lock().await;
                info_lock.state = DownloadState::Queued;
                drop(info_lock);
                self.process_queue().await;
            }
        }
        Ok(())
    }
}
