use crate::utils::logger;
use crate::utils::{
    types::{DownloadState, PartInfo},
    url::is_magnet_url,
};
use anyhow::Result;
use librqbit::{AddTorrent, AddTorrentOptions, AddTorrentResponse, TorrentStatsState};
use std::{
    path::Path,
    sync::{
        Arc,
        atomic::{AtomicU64, Ordering},
    },
    time::{Duration, SystemTime, UNIX_EPOCH},
};
use tokio::fs;

use crate::downloader::worker::DownloadWorker;

impl DownloadWorker {
    pub async fn spawn_torrent_download_task(
        self: &Arc<Self>,
        url: &str,
        dest: &std::path::Path,
    ) -> Result<()> {
        logger::debug(&format!("Starting Torrent download for {}", url));

        let client = self.client.clone();
        let worker = Arc::clone(self);
        let url = url.to_string();
        let dest = dest.to_path_buf();

        let h =
            tokio::spawn(async move { worker.download_torrent_task(&client, &url, &dest).await });

        let mut handles = self.handles.lock().await;
        handles.push(h);
        Ok(())
    }

    async fn download_torrent_task(
        self: &Arc<Self>,
        client: &reqwest::Client,
        url: &str,
        dest: &std::path::Path,
    ) -> Result<()> {
        let output_dir = if dest.exists() && dest.is_dir() {
            dest.to_path_buf()
        } else if let Some(stem) = dest.file_stem() {
            let parent = dest.parent().unwrap_or(Path::new("."));
            parent.join(stem)
        } else {
            dest.to_path_buf()
        };

        if !output_dir.exists() {
            tokio::fs::create_dir_all(&output_dir).await?;
        }

        // Update info dest to finalized output dir
        {
            let mut info = self.info.lock().await;
            info.dest = output_dir.clone();
        }

        let session_guard = self.torrent_session.read().await;
        let session = match session_guard.as_ref() {
            Some(s) => s.clone(),
            None => return Err(anyhow::anyhow!("Torrent session not initialized")),
        };

        let existing_handle = if let Some(hash) = { self.info.lock().await.torrent_hash.clone() } {
            session.with_torrents(|torrents| {
                for (_, handle) in torrents {
                    if hex::encode(handle.info_hash().0) == hash {
                        return Some(handle.clone());
                    }
                }
                None
            })
        } else {
            None
        };

        let handle = if let Some(h) = existing_handle {
            h
        } else {
            let add_torrent = if is_magnet_url(url) {
                AddTorrent::from_url(url)
            } else {
                // Check if it's a local file path
                let path = Path::new(url);
                let bytes = if path.is_file() {
                    fs::read(path).await?
                } else {
                    // It's a torrent file URL, download it first
                    client.get(url).send().await?.bytes().await?.to_vec()
                };
                AddTorrent::from_bytes(bytes)
            };

            let response = session
                .add_torrent(
                    add_torrent,
                    Some(AddTorrentOptions {
                        overwrite: true,
                        output_folder: Some(output_dir.to_string_lossy().to_string()),
                        ..Default::default()
                    }),
                )
                .await?;

            match response {
                AddTorrentResponse::Added(_, h) => h,
                AddTorrentResponse::AlreadyManaged(_, h) => h,
                _ => return Err(anyhow::anyhow!("Failed to add torrent: unknown response")),
            }
        };

        // Store torrent hash
        {
            let mut info = self.info.lock().await;
            info.torrent_hash = Some(hex::encode(handle.info_hash().0));
        }

        handle.wait_until_initialized().await?;
        if handle.is_paused() {
            session.unpause(&handle).await?;
        }

        // Populate parts from torrent files
        {
            let metadata_guard = handle.metadata.load();
            let info = metadata_guard
                .as_ref()
                .expect("Torrent metadata not initialized");
            let mut parts = Vec::new();
            let mut current_pos = 0;
            for file in &info.file_infos {
                let len = file.len;
                parts.push(PartInfo {
                    start: current_pos,
                    end: current_pos + len - 1,
                    current: 0,
                });
                current_pos += len;
            }

            let mut dl_info = self.info.lock().await;
            if dl_info.parts.is_empty() {
                dl_info.parts = parts;
            }

            // Initialize part_progress
            let mut pp = self.part_progress.write().await;
            pp.clear();
            for _ in 0..info.file_infos.len() {
                pp.push(Arc::new(AtomicU64::new(0)));
            }
        }

        // Update total size once
        let stats = handle.stats();
        let total = stats.total_bytes;
        if total > 0 {
            self.update_total_size(Some(total)).await;
        }

        // Downloading Loop
        loop {
            // Properly pause/unpause using Session methods
            if self.paused.load(Ordering::SeqCst) {
                session.pause(&handle).await?;
                while self.paused.load(Ordering::SeqCst) {
                    self.notify_resume.notified().await;
                }
                session.unpause(&handle).await?;
            }

            if self.cancel.load(Ordering::SeqCst) {
                // Pause the torrent instead of deleting it
                session.pause(&handle).await?;
                logger::debug("Torrent download cancelled (paused)");
                return Ok(());
            }

            // Limit speed
            let limit = self.speed_limit.load(Ordering::SeqCst);
            if limit > 0 {
                if let Some(nz_limit) = std::num::NonZeroU32::new(limit as u32) {
                    session.ratelimits.set_download_bps(Some(nz_limit));
                }
            } else {
                session.ratelimits.set_download_bps(None);
            }

            let stats = handle.stats();
            if let TorrentStatsState::Error = stats.state {
                let msg = stats.error.as_deref().unwrap_or("Unknown error");
                return Err(anyhow::anyhow!("Torrent error: {}", msg));
            }

            let downloaded = stats.progress_bytes;
            let total = stats.total_bytes;
            let uploaded = stats.uploaded_bytes;
            self.downloaded.store(downloaded, Ordering::SeqCst);
            self.uploaded.store(uploaded, Ordering::SeqCst);

            if let Some(s) = stats.live {
                let uspeed = s.upload_speed.mbps * 125_000 as f64;
                let mut info = self.info.lock().await;
                info.uspeed = Some(uspeed);
            } else {
                let mut info = self.info.lock().await;
                info.uspeed = None;
            }

            let file_progress = &stats.file_progress;
            let pp = self.part_progress.read().await;
            if pp.len() == file_progress.len() {
                for (i, bytes) in file_progress.iter().enumerate() {
                    pp[i].store(*bytes, Ordering::SeqCst);
                }
            }

            if total > 0 && downloaded >= total {
                break;
            }

            tokio::time::sleep(Duration::from_secs(1)).await;
        }

        // Transition to Seeding if not already
        {
            let mut info = self.info.lock().await;
            if !matches!(info.state, DownloadState::Seeding) {
                info.state = DownloadState::Seeding;
                self.seeding_start.store(
                    SystemTime::now()
                        .duration_since(UNIX_EPOCH)
                        .unwrap()
                        .as_millis() as u64,
                    Ordering::SeqCst,
                );
                logger::debug(&format!("Download {} completed, starting seeding", info.id));
            }
        }

        // Seeding Loop
        loop {
            // Properly pause/unpause using Session methods
            if self.paused.load(Ordering::SeqCst) {
                session.pause(&handle).await?;
                while self.paused.load(Ordering::SeqCst) {
                    self.notify_resume.notified().await;
                }
                session.unpause(&handle).await?;
            }

            if self.cancel.load(Ordering::SeqCst) {
                // Delete the torrent (stop download and cleanup)
                session.delete(handle.id().into(), false).await?;
                logger::debug("Torrent seeding cancelled");
                return Ok(());
            }

            // Limit speed
            let limit = self.speed_limit.load(Ordering::SeqCst);
            if limit > 0 {
                if let Some(nz_limit) = std::num::NonZeroU32::new(limit as u32) {
                    session.ratelimits.set_download_bps(Some(nz_limit));
                }
            } else {
                session.ratelimits.set_download_bps(None);
            }

            let stats = handle.stats();
            if let TorrentStatsState::Error = stats.state {
                let msg = stats.error.as_deref().unwrap_or("Unknown error");
                return Err(anyhow::anyhow!("Torrent error: {}", msg));
            }

            let downloaded = stats.progress_bytes;
            let uploaded = stats.uploaded_bytes;
            self.downloaded.store(downloaded, Ordering::SeqCst);
            self.uploaded.store(uploaded, Ordering::SeqCst);

            if let Some(s) = stats.live {
                let uspeed = s.upload_speed.mbps * 125_000 as f64;
                let mut info = self.info.lock().await;
                info.uspeed = Some(uspeed);
            } else {
                let mut info = self.info.lock().await;
                info.uspeed = None;
            }

            // Check limits
            let settings = self.settings.read().await;
            let info = self.info.lock().await;
            let ratio_limit = info
                .seeding_ratio_override
                .unwrap_or(settings.seeding_ratio);
            let time_limit = info.seeding_time_override.unwrap_or(settings.seeding_time);
            drop(info);

            let ratio = if downloaded > 0 {
                uploaded as f32 / downloaded as f32
            } else {
                0.0
            };

            let seeding_start = self.seeding_start.load(Ordering::SeqCst);
            let now = SystemTime::now()
                .duration_since(UNIX_EPOCH)
                .unwrap()
                .as_millis() as u64;
            let elapsed_mins = if seeding_start > 0 {
                (now - seeding_start) / 1000 / 60
            } else {
                0
            };

            if ratio >= ratio_limit || elapsed_mins >= time_limit {
                logger::debug(&format!(
                    "Seeding limit reached: ratio {:.2}/{}, time {}/{}m",
                    ratio, ratio_limit, elapsed_mins, time_limit
                ));
                session.delete(handle.id().into(), false).await?;
                break;
            }

            tokio::time::sleep(Duration::from_secs(1)).await;
        }

        Ok(())
    }
}
