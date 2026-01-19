use anyhow::Result;
use std::{
    path::Path,
    sync::{Arc, atomic::Ordering},
};

use crate::utils::{
    types::{DownloadState, DownloadType, WorkerEvent},
    url::{is_hls_url, is_magnet_url, is_torrent_file},
};

use crate::downloader::worker::DownloadWorker;

impl DownloadWorker {
    pub async fn start(self: &Arc<Self>) -> Result<()> {
        if self.check_and_resume().await? {
            return Ok(());
        }
        self.started.store(true, Ordering::SeqCst);
        self.cancel.store(false, Ordering::SeqCst);

        let threads = self.threads;
        let (url, dest) = self.extract_info().await;

        if (Path::new(&url).is_file() && is_torrent_file(&url, &None)) || is_magnet_url(&url) {
            {
                let mut info = self.info.lock().await;
                info.download_type = DownloadType::Torrent;
            }
            self.spawn_torrent_download_task(&url, &dest).await?;
            self.spawn_sampler_and_monitor().await?;
            return Ok(());
        }

        let head_data = self.fetch_head(&url).await?;

        if is_torrent_file(&url, &head_data.content_type) {
            {
                let mut info = self.info.lock().await;
                info.download_type = DownloadType::Torrent;
            }
            self.spawn_torrent_download_task(&url, &dest).await?;
        } else if is_hls_url(&url, &head_data.content_type) {
            {
                let mut info = self.info.lock().await;
                info.download_type = DownloadType::HLS;
            }
            self.spawn_hls_download_task(&url, &dest).await?;
        } else {
            self.update_total_size(head_data.total_size).await;
            let is_single_thread =
                !head_data.accept_ranges || head_data.total_size.is_none() || threads <= 1;
            let size = head_data.total_size.unwrap_or(0);

            let has_existing_parts = {
                let info = self.info.lock().await;
                !info.parts.is_empty()
            };

            if !has_existing_parts {
                self.prepare_file(&dest, size, is_single_thread)?;
            }

            self.spawn_download_tasks(
                &url,
                &dest,
                size,
                threads,
                is_single_thread,
                head_data.accept_ranges,
            )
            .await?;
        }

        self.spawn_sampler_and_monitor().await?;

        Ok(())
    }

    async fn check_and_resume(self: &Arc<Self>) -> Result<bool> {
        let was_paused = self.paused.load(Ordering::SeqCst);
        let has_started = self.started.load(Ordering::SeqCst);

        if was_paused && has_started {
            // This is a resume of an in-progress download
            let worker = Arc::clone(self);
            worker.resume().await?; // This sets paused to false
            return Ok(true);
        }

        // This is a fresh start (either brand new or from a queued-paused state)
        self.paused.store(false, Ordering::SeqCst); // Explicitly reset the flag

        let mut info = self.info.lock().await;
        match info.state {
            DownloadState::Completed => {
                let _ = self.event_tx.send(WorkerEvent::Completed(info.id)).await;
                Ok(true)
            }
            DownloadState::Running => Ok(true),
            _ => {
                info.state = DownloadState::Running;
                Ok(false)
            }
        }
    }
}
