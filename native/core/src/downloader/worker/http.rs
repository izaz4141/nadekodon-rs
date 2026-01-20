use anyhow::Result;
use futures::StreamExt;
use reqwest::header::{ACCEPT_RANGES, CONTENT_LENGTH, RANGE};
use std::{
    sync::{
        Arc,
        atomic::{AtomicU64, Ordering},
    },
    time::Duration,
};
use tokio::{
    fs::File as TokioFile,
    io::{AsyncSeekExt, AsyncWriteExt, SeekFrom},
    time::timeout,
};

use crate::utils::logger;
use crate::utils::types::{HeadData, PartInfo};

use crate::downloader::worker::DownloadWorker;

impl DownloadWorker {
    pub async fn fetch_head(&self, url: &str) -> Result<HeadData> {
        let client = self.client.clone();
        let mut request_builder = client.head(url);
        if let Some(cookie) = &self.cookie {
            request_builder = request_builder.header(
                reqwest::header::COOKIE,
                reqwest::header::HeaderValue::from_str(cookie)?,
            );
        }
        if let Some(ua) = &self.user_agent {
            request_builder = request_builder.header(
                reqwest::header::USER_AGENT,
                reqwest::header::HeaderValue::from_str(ua)?,
            );
        }
        let head = request_builder.send().await?;
        // let status = head.status();

        let total_size = head
            .headers()
            .get(CONTENT_LENGTH)
            .and_then(|hv| hv.to_str().ok())
            .and_then(|s| s.parse::<u64>().ok());

        let accept_ranges = head
            .headers()
            .get(ACCEPT_RANGES)
            .and_then(|hv| hv.to_str().ok())
            .map(|s| s.to_ascii_lowercase().contains("bytes"))
            .unwrap_or(false);

        let content_type = head
            .headers()
            .get(reqwest::header::CONTENT_TYPE)
            .and_then(|v| v.to_str().ok())
            .map(|s| s.to_string());

        Ok(HeadData {
            total_size,
            accept_ranges,
            content_type,
        })
    }

    pub fn prepare_file(
        &self,
        dest: &std::path::Path,
        size: u64,
        is_single_thread: bool,
    ) -> Result<()> {
        let f = std::fs::File::create(dest)?;
        if !is_single_thread {
            f.set_len(size)?
        };
        Ok(())
    }

    pub async fn spawn_download_tasks(
        self: &Arc<Self>,
        url: &str,
        dest: &std::path::Path,
        size: u64,
        threads: u64,
        is_single_thread: bool,
        accept_ranges: bool,
    ) -> Result<()> {
        let client = self.client.clone();
        let mut handles = Vec::new();

        // Initialize parts if empty
        {
            let mut info = self.info.lock().await;
            if info.parts.is_empty() {
                if is_single_thread {
                    let end_pos = if size == 0 {
                        u64::MAX
                    } else {
                        size.saturating_sub(1)
                    };
                    info.parts.push(PartInfo {
                        start: 0,
                        end: end_pos,
                        current: 0,
                    });
                } else {
                    let part_size = size / threads;
                    for i in 0..threads {
                        let start = i * part_size;
                        let end = if i == threads - 1 {
                            size - 1
                        } else {
                            start + part_size - 1
                        };
                        info.parts.push(PartInfo {
                            start,
                            end,
                            current: 0,
                        });
                    }
                }
            }
        }

        let parts = {
            let info = self.info.lock().await;
            info.parts.clone()
        };

        let progress_vec = {
            let pp = self.part_progress.read().await;
            if pp.len() == parts.len() && !pp.is_empty() {
                pp.clone()
            } else {
                drop(pp);
                let mut new_progress = Vec::new();
                for part in &parts {
                    new_progress.push(Arc::new(AtomicU64::new(part.current)));
                }
                let mut pp = self.part_progress.write().await;
                *pp = new_progress.clone();
                new_progress
            }
        };

        for (i, part) in parts.iter().enumerate() {
            let client = client.clone();
            let worker = Arc::clone(self);
            let url = url.to_string();
            let dest = dest.to_path_buf();
            let progress = progress_vec[i].clone();

            progress.store(part.current, Ordering::SeqCst);

            let start = part.start;
            let end = part.end;

            let h = tokio::spawn(async move {
                worker
                    .download_task(
                        i as u64,
                        &client,
                        &url,
                        &dest,
                        start,
                        end,
                        is_single_thread,
                        accept_ranges,
                        progress,
                    )
                    .await
            });
            handles.push(h);
        }

        let mut guard = self.handles.lock().await;
        *guard = handles;
        Ok(())
    }

    async fn download_task(
        self: &Arc<Self>,
        i: u64,
        client: &reqwest::Client,
        url: &str,
        dest: &std::path::Path,
        start: u64,
        end: u64,
        is_single_thread: bool,
        accept_ranges: bool,
        progress: Arc<AtomicU64>,
    ) -> Result<()> {
        let worker = Arc::clone(self);

        // Resume from where we left off
        let mut segment_progress = progress.load(Ordering::SeqCst);
        let mut attempt = 0u8;

        let (timeout_duration, download_retries) = {
            let s = self.settings.read().await;
            let t = if s.download_timeout == 0 {
                Duration::from_secs(3153600000) // 100 years
            } else {
                Duration::from_secs(s.download_timeout)
            };
            (t, s.download_retries)
        };

        loop {
            while self.paused.load(std::sync::atomic::Ordering::SeqCst) {
                self.notify_resume.notified().await;
            }
            if self.cancel.load(Ordering::SeqCst) {
                logger::debug(&format!("Segment {} canceled early", i));
                return Ok(());
            }

            let current_start = start + segment_progress;
            if end != u64::MAX && current_start >= end {
                return Ok(());
            }

            let mut request_builder = client.get(url);
            if let Some(cookie) = &self.cookie {
                request_builder = request_builder.header(
                    reqwest::header::COOKIE,
                    reqwest::header::HeaderValue::from_str(cookie)?,
                );
            }
            if let Some(ua) = &self.user_agent {
                request_builder = request_builder.header(
                    reqwest::header::USER_AGENT,
                    reqwest::header::HeaderValue::from_str(ua)?,
                );
            }
            if accept_ranges {
                let range = format!("bytes={}-{}", current_start, end);
                request_builder = request_builder.header(RANGE, &range);
            }
            let resp = match request_builder.send().await {
                Ok(r) => match r.error_for_status() {
                    Ok(v) => v,
                    Err(e) => return Err(anyhow::anyhow!("Segment {} bad status: {}", i, e)),
                },
                Err(e) => {
                    logger::error(&format!("Segment {} request failed: {:?}", i, e));
                    if attempt >= download_retries {
                        self.cancel().await?;
                        return Err(anyhow::anyhow!("Segment {} request failed: {:?}", i, e));
                    }
                    attempt += 1;
                    continue;
                }
            };

            let mut file = TokioFile::options().write(true).open(dest).await?;
            if accept_ranges {
                file.seek(SeekFrom::Start(current_start)).await?;
            }
            let mut stream = resp.bytes_stream();

            while let Ok(next_chunk) = timeout(timeout_duration, stream.next()).await {
                while self.paused.load(Ordering::SeqCst) {
                    self.notify_resume.notified().await;
                }

                if self.cancel.load(Ordering::SeqCst) {
                    logger::debug(&format!("Segment {} cancelled", i));
                    return Ok(());
                }

                let next_chunk = match next_chunk {
                    Some(Ok(chunk)) => {
                        if chunk.is_empty() {
                            continue;
                        }
                        chunk
                    }

                    Some(Err(e)) => {
                        logger::error(&format!("Segment {}: stream error {:?}", i, e));
                        if attempt >= download_retries {
                            self.cancel().await?;
                            return Err(anyhow::anyhow!("Segment {} stream error: {}", i, e));
                        }
                        if !accept_ranges {
                            self.downloaded.store(0, Ordering::SeqCst);
                            // Reset segment progress for single thread non-range
                            segment_progress = 0;
                            progress.store(0, Ordering::SeqCst);
                        }
                        attempt += 1;
                        continue;
                    }

                    None => {
                        if is_single_thread || (end != u64::MAX && start + segment_progress >= end)
                        {
                            break;
                        }
                        if attempt >= download_retries {
                            self.cancel().await?;
                            return Err(anyhow::anyhow!(
                                "Segment {}: stream ended unexpectedly",
                                i
                            ));
                        }
                        if !accept_ranges {
                            self.downloaded.store(0, Ordering::SeqCst);
                            segment_progress = 0;
                            progress.store(0, Ordering::SeqCst);
                        }
                        attempt += 1;
                        continue;
                    }
                };

                if let Err(e) = file.write_all(&next_chunk).await {
                    logger::error(&format!("Segment {}: file write error {:?}", i, e));
                    if attempt >= download_retries {
                        self.cancel().await?;
                        return Err(anyhow::anyhow!("Segment {} file write failed: {}", i, e));
                    }
                    if !accept_ranges {
                        self.downloaded.store(0, Ordering::SeqCst);
                        segment_progress = 0;
                        progress.store(0, Ordering::SeqCst);
                    }
                    attempt += 1;
                    continue;
                }

                let len = next_chunk.len() as u64;
                segment_progress += len;
                self.downloaded.fetch_add(len, Ordering::SeqCst);
                progress.store(segment_progress, Ordering::SeqCst);

                if end != u64::MAX && start + segment_progress >= end {
                    break;
                }
                worker.limit_speed().await;
            }

            if is_single_thread || (end != u64::MAX && start + segment_progress >= end) {
                return Ok(());
            }
        }
        // Err(anyhow::anyhow!("Segment {} failed after retries", i))
    }
}
