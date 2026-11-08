use anyhow::Result;
use std::{
    sync::atomic::Ordering,
    time::{SystemTime, UNIX_EPOCH},
};

use crate::utils::logger;
use crate::utils::types::{DownloadInfo, DownloadProgress};

use crate::downloader::worker::DownloadWorker;

impl DownloadWorker {
    fn now_ms() -> u64 {
        SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .unwrap_or_default()
            .as_millis() as u64
    }

    /// Progress-only snapshot: no history, metadata, or other allocations.
    pub async fn progress_snapshot(&self) -> DownloadProgress {
        let (id, state, mut parts) = {
            let info = self.info.lock().await;
            (info.id, info.state.clone(), info.parts.clone())
        };

        let pp = self.part_progress.read().await;
        if parts.len() == pp.len() {
            for (i, p) in pp.iter().enumerate() {
                parts[i].current = p.load(Ordering::SeqCst);
            }
        }

        DownloadProgress {
            id,
            downloaded: self.downloaded.load(Ordering::SeqCst),
            uploaded: self.uploaded.load(Ordering::SeqCst),
            state,
            parts,
            updated_at: Self::now_ms(),
        }
    }

    /// Persist this worker through the app context's database manager.
    pub async fn persist_to_db(&self) {
        let Some(dm) = self.dm.upgrade() else {
            logger::error("DownloadManager dropped before persistence could run");
            return;
        };
        let id = self.info.lock().await.id;
        dm.persist(id).await;
    }

    pub async fn sync_to_info(&self) {
        let mut info = self.info.lock().await;
        info.downloaded = self.downloaded.load(Ordering::SeqCst);
        info.uploaded = self.uploaded.load(Ordering::SeqCst);
        info.history = self.history.read().await.clone();
        info.updated_at = SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .unwrap()
            .as_millis() as u64;

        let pp = self.part_progress.read().await.clone();
        if info.parts.len() == pp.len() {
            for (i, p) in pp.iter().enumerate() {
                info.parts[i].current = p.load(Ordering::SeqCst);
            }
        }
    }

    pub async fn snapshot_info(&self) -> DownloadInfo {
        let mut meta = self.info.lock().await.clone();
        let d = self.downloaded.load(Ordering::SeqCst);
        meta.downloaded = d;
        let u = self.uploaded.load(Ordering::SeqCst);
        meta.uploaded = u;
        let hist = self.history.read().await;
        meta.history = hist.clone();

        // Sync part progress
        let pp = self.part_progress.read().await.clone();
        if meta.parts.len() == pp.len() {
            for (i, p) in pp.iter().enumerate() {
                meta.parts[i].current = p.load(Ordering::SeqCst);
            }
        }
        meta
    }

    pub async fn extract_info(&self) -> (String, std::path::PathBuf) {
        let info = self.info.lock().await;
        (info.url.clone(), info.dest.clone())
    }

    pub async fn info(&self) -> DownloadInfo {
        self.snapshot_info().await
    }

    pub async fn update_url(&self, new_url: String) -> Result<()> {
        let mut info = self.info.lock().await;
        info.url = new_url;
        Ok(())
    }

    pub async fn update_total_size(&self, size: Option<u64>) {
        if let Some(s) = size {
            let mut info = self.info.lock().await;
            info.total_size = Some(s);
            // If we have a single part with unknown size (end == 0), update it
            if info.parts.len() == 1 && info.parts[0].end == 0 {
                info.parts[0].end = s.saturating_sub(1);
            }
        }
    }

    pub async fn set_category(&self, category: String) -> Result<()> {
        let dm_ref = self
            .dm
            .upgrade()
            .ok_or_else(|| anyhow::anyhow!("DownloadManager dropped"))?;
        dm_ref
            .create_category(category.clone(), None)
            .await
            .map_err(|e| anyhow::anyhow!("{}", e))?;

        {
            let mut info = self.info.lock().await;
            info.category = Some(category);
        }
        self.persist_to_db().await;
        Ok(())
    }

    pub async fn clear_category(&self) {
        {
            let mut info = self.info.lock().await;
            info.category = None;
        }
        self.persist_to_db().await;
    }

    pub async fn set_seeding_limits(&self, ratio: Option<f32>, time: Option<u64>) {
        {
            let mut info = self.info.lock().await;
            info.seeding_ratio_override = ratio;
            info.seeding_time_override = time;
        }
        self.persist_to_db().await;
    }
}
