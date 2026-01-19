use anyhow::Result;
use futures::StreamExt;
use std::{
    sync::{
        Arc,
        atomic::{AtomicU64, Ordering},
    },
    time::Duration,
};
use tokio::{fs::File as TokioFile, io::AsyncWriteExt, time::timeout};

use crate::utils::logger;
use crate::utils::types::PartInfo;

use crate::downloader::worker::DownloadWorker;

impl DownloadWorker {
    pub async fn spawn_hls_download_task(
        self: &Arc<Self>,
        url: &str,
        dest: &std::path::Path,
    ) -> Result<()> {
        logger::debug(&format!("Starting HLS download for {}", url));

        {
            let mut info = self.info.lock().await;
            if info.parts.is_empty() {
                info.parts.push(PartInfo {
                    start: 0,
                    end: 0, // Unknown size for HLS
                    current: 0,
                });
            }
        }

        let progress = {
            let pp = self.part_progress.read().await;
            if pp.is_empty() {
                drop(pp);
                let new_progress = Arc::new(AtomicU64::new(0));
                let mut pp = self.part_progress.write().await;
                pp.push(new_progress.clone());
                new_progress
            } else {
                pp[0].clone()
            }
        };

        let client = self.client.clone();
        let worker = Arc::clone(self);

        let url = url.to_string();
        let dest = dest.to_path_buf();

        let h = tokio::spawn(async move {
            worker
                .download_hls_stream(&client, &url, &dest, progress)
                .await
        });

        let mut handles = self.handles.lock().await;
        handles.push(h);
        Ok(())
    }

    async fn download_hls_stream(
        self: &Arc<Self>,
        client: &reqwest::Client,
        url: &str,
        dest: &std::path::Path,
        progress: Arc<AtomicU64>,
    ) -> Result<()> {
        let playlist_content = client.get(url).send().await?.text().await?;

        let base_url = {
            let mut url_parts = url.split('/').collect::<Vec<_>>();
            url_parts.pop();
            url_parts.join("/") + "/"
        };

        let mut segment_urls = Vec::new();
        for line in playlist_content.lines() {
            if !line.starts_with('#') && !line.is_empty() {
                if line.starts_with("http") {
                    segment_urls.push(line.to_string());
                } else {
                    segment_urls.push(format!("{}{}", base_url, line));
                }
            }
        }

        if segment_urls.is_empty() {
            return Err(anyhow::anyhow!("No segments found in HLS playlist"));
        }

        let temp_dir = dest
            .parent()
            .unwrap()
            .join(format!("temp_{}", self.info.lock().await.id));
        tokio::fs::create_dir_all(&temp_dir).await?;

        let mut segment_paths = Vec::new();
        let (timeout_duration, download_retries) = {
            let s = self.settings.read().await;
            let t = if s.download_timeout == 0 {
                Duration::from_secs(3153600000) // 100 years
            } else {
                Duration::from_secs(s.download_timeout)
            };
            (t, s.download_retries)
        };

        for (i, segment_url) in segment_urls.iter().enumerate() {
            if self.cancel.load(Ordering::SeqCst) {
                return Ok(());
            }

            let mut attempt = 0u8;
            let segment_path = temp_dir.join(format!("segment_{}.ts", i));

            loop {
                while self.paused.load(Ordering::SeqCst) {
                    self.notify_resume.notified().await;
                }

                let mut file = match TokioFile::create(&segment_path).await {
                    Ok(f) => f,
                    Err(e) => {
                        logger::error(&format!("HLS Segment {} file creation error: {:?}", i, e));
                        if attempt >= download_retries {
                            return Err(anyhow::anyhow!(
                                "HLS Segment {} file creation failed: {}",
                                i,
                                e
                            ));
                        }
                        attempt += 1;
                        continue;
                    }
                };

                let resp = match client.get(segment_url).send().await {
                    Ok(r) => match r.error_for_status() {
                        Ok(v) => v,
                        Err(e) => {
                            logger::error(&format!("HLS Segment {} request failed: {:?}", i, e));
                            if attempt >= download_retries {
                                return Err(anyhow::anyhow!(
                                    "HLS Segment {} request failed: {:?}",
                                    i,
                                    e
                                ));
                            }
                            attempt += 1;
                            continue;
                        }
                    },
                    Err(e) => {
                        logger::error(&format!("HLS Segment {} connection failed: {:?}", i, e));
                        if attempt >= download_retries {
                            return Err(anyhow::anyhow!(
                                "HLS Segment {} connection failed: {:?}",
                                i,
                                e
                            ));
                        }
                        attempt += 1;
                        continue;
                    }
                };

                let mut stream = resp.bytes_stream();
                let mut success = true;
                let mut stream_finished = false;

                while let Ok(next_chunk) = timeout(timeout_duration, stream.next()).await {
                    while self.paused.load(Ordering::SeqCst) {
                        self.notify_resume.notified().await;
                    }
                    if self.cancel.load(Ordering::SeqCst) {
                        logger::debug(&format!("Segment {} cancelled", i));
                        return Ok(());
                    }

                    match next_chunk {
                        Some(Ok(chunk)) => {
                            if let Err(e) = file.write_all(&chunk).await {
                                logger::error(&format!("HLS Segment {} write error: {:?}", i, e));
                                success = false;
                                break;
                            }
                            let len = chunk.len() as u64;
                            self.downloaded.fetch_add(len, Ordering::SeqCst);
                            progress.fetch_add(len, Ordering::SeqCst);
                            self.limit_speed().await;
                        }
                        Some(Err(e)) => {
                            logger::error(&format!("HLS Segment {} stream error: {:?}", i, e));
                            success = false;
                            break;
                        }
                        None => {
                            stream_finished = true;
                            break;
                        }
                    }
                }

                if success && stream_finished {
                    break;
                } else {
                    if attempt >= download_retries {
                        if !stream_finished && success {
                            return Err(anyhow::anyhow!("HLS Segment {} timed out", i));
                        }
                        return Err(anyhow::anyhow!("HLS Segment {} failed after retries", i));
                    }
                    attempt += 1;
                }
            }
            segment_paths.push(segment_path);
        }

        let list_path = temp_dir.join("mylist.txt");
        let mut list_file = TokioFile::create(&list_path).await?;
        for path in &segment_paths {
            let line = format!("file '{}'\n", path.to_str().unwrap());
            list_file.write_all(line.as_bytes()).await?;
        }
        list_file.flush().await?;

        if cfg!(target_os = "android") {
            let mut args = Vec::new();
            args.push("-f".to_string());
            args.push("concat".to_string());
            args.push("-safe".to_string());
            args.push("0".to_string());
            args.push("-i".to_string());
            args.push(list_path.to_string_lossy().to_string());
            args.push("-c".to_string());
            args.push("copy".to_string());
            args.push("-y".to_string());
            args.push(dest.to_string_lossy().to_string());

            match crate::downloader::perform_ffmpeg_request_android(args).await {
                Ok(_) => {}
                Err(e) => return Err(anyhow::anyhow!("ffmpeg execution failed (Android): {}", e)),
            }
        } else {
            let mut command = tokio::process::Command::new("ffmpeg");
            command
                .arg("-f")
                .arg("concat")
                .arg("-safe")
                .arg("0")
                .arg("-i")
                .arg(&list_path)
                .arg("-c")
                .arg("copy")
                .arg("-y")
                .arg(dest);

            match command.output().await {
                Ok(output) => {
                    if !output.status.success() {
                        let stderr = String::from_utf8_lossy(&output.stderr);
                        return Err(anyhow::anyhow!("ffmpeg failed: {}", stderr));
                    }
                }
                Err(e) => return Err(anyhow::anyhow!("ffmpeg execution failed: {}", e)),
            }
        }

        tokio::fs::remove_dir_all(&temp_dir).await?;

        Ok(())
    }
}
