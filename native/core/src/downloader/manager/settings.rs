use anyhow::Result;
use uuid::Uuid;

use crate::utils::types::DMSettings;

use crate::downloader::manager::DownloadManager;

impl DownloadManager {
    pub async fn update_settings(&self, new: DMSettings) -> Result<()> {
        let concurrency_changed;
        {
            let mut settings = self.settings.write().await;
            concurrency_changed = settings.concurrency_limit != new.concurrency_limit;

            settings.download_dir = new.download_dir;
            settings.speed_limit = new.speed_limit;
            settings.download_threads = new.download_threads;
            settings.concurrency_limit = new.concurrency_limit;
            settings.download_timeout = new.download_timeout;
            settings.download_retries = new.download_retries;
            settings.seeding_ratio = new.seeding_ratio;
            settings.seeding_time = new.seeding_time;
        }

        if concurrency_changed {
            self.process_queue().await;
        }

        Ok(())
    }

    pub async fn shutdown(&self) {
        let session_guard = self.torrent_session.write().await;
        if let Some(session) = session_guard.as_ref() {
            let _ = session.stop().await;
        }
    }

    pub async fn drain_pending_deletions(&self) -> Vec<Uuid> {
        let mut pending = self.pending_deletions.lock().await;
        let drained = pending.clone();
        pending.clear();
        drained
    }

    pub async fn requeue_pending_deletions(&self, ids: Vec<Uuid>) {
        let mut pending = self.pending_deletions.lock().await;
        pending.extend(ids);
    }
}
