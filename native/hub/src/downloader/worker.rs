use std::{
    cmp::min, num::NonZeroU32, 
    path::{Path, PathBuf}, 
    sync::{Arc, atomic::{Ordering, AtomicI64}}, 
    time::{Instant, Duration}
};


use anyhow::{anyhow, Context, Result};
use bytes::Bytes;
use futures::StreamExt;
use governor::{clock::DefaultClock, state::InMemoryState, DefaultDirectRateLimiter, Quota, RateLimiter};
use nonzero_ext::nonzero;
use reqwest::header::{HeaderMap, HeaderValue, ACCEPT_RANGES, CONTENT_LENGTH, ETAG, IF_RANGE, RANGE};
use sqlx::{sqlite::SqlitePoolOptions, Pool, Sqlite, SqlitePool, FromRow};
use thiserror::Error;
use time::{OffsetDateTime};
use tokio::{fs, io::AsyncWriteExt, sync::{Mutex, Semaphore}, task::JoinHandle};
use uuid::Uuid;
use dashmap::DashMap;

#[derive(Debug, Error)]
pub enum DWError {
    #[error("Server does not support range requests")] 
    NoRange,
}


#[derive(Debug, Clone)]
struct DownloadRecord {
    id: String,
    url: String,
    path: String,
    downloaded: i64,
    status: String,
    etag: Option<String>,
    total_size: Option<i64>,
}
#[derive(Debug, FromRow)]
struct Part {
    id: i32,
    idx: i32,
    start: i64,
    end: i64,
    downloaded: i64, // or i64/bool depending on your schema
    status: String,
}

#[derive(Clone)]
pub struct DownloadWorker {
    id: String,
    db: SqlitePool,
    client: reqwest::Client,
    num_part: i64,
    max_concurrency: usize,
    downloaded: Arc<AtomicI64>,
    status: Arc<Mutex<String>>,   // mutable, shared across tasks
    path: PathBuf,                // full file path for final download
    url: String,                  // NEW
    etag: Option<String>,         // NEW
    total_size: Option<i64>,      // NEW
    limiter: Arc<DefaultDirectRateLimiter>,
    progress_map: Arc<DashMap<(String, i32), (i64, String)>>, 
}

impl DownloadWorker {
    pub async fn new(
        db: SqlitePool,
        path: impl AsRef<Path>,            // final file path
        num_part: i64,
        max_concurrency: usize,
        max_speed_bytes_per_sec: u32,
    ) -> anyhow::Result<Self> {
        let path = path.as_ref().to_path_buf();
        if let Some(parent) = path.parent() {
            fs::create_dir_all(parent).await.ok();
        }

        let client = reqwest::Client::builder()
            .user_agent("rust-downloader/1.0")
            .build()?;

        let q = Quota::per_second(
            NonZeroU32::new(max_speed_bytes_per_sec).unwrap_or(nonzero!(1u32))
        );
        let limiter = Arc::new(RateLimiter::direct(q));

        Ok(Self {
            db: db.clone(),
            client,
            num_part,
            max_concurrency: max_concurrency.max(1),
            downloaded: Arc::new(AtomicI64::new(0)),
            status: Arc::new(Mutex::new("queued".to_string())),
            path, 
            limiter,
            progress_map: Arc::new(DashMap::new()),
        })
    }


    pub async fn enqueue(&self, url: &str, path: impl AsRef<Path>) -> Result<String> {
        let id = Uuid::new_v4().to_string();
        let now = now_unix();
        sqlx::query(
            "INSERT INTO downloads (id, url, path, status, created_at, updated_at) VALUES (?, ?, ?, 'queued', ?, ?)",
        )
        .bind(&id)
        .bind(url)
        .bind(path.as_ref().to_string_lossy().to_string())
        .bind(now)
        .bind(now)
        .execute(&self.db)
        .await?;
        Ok(id)
    }

    pub async fn insert_part(
        &self,
        download_id: &str,
        idx: i32,
        start: i64,
        end: i64,
    ) -> Result<()> {
        sqlx::query(
            r#"
            INSERT OR IGNORE INTO parts (download_id, idx, start, end, downloaded, status)
            VALUES (?1, ?2, ?3, ?4, 0, 'queued')
            "#,
        )
        .bind(download_id)
        .bind(idx)
        .bind(start)
        .bind(end)
        .execute(&self.db)
        .await?;
        Ok(())
    }

    /// Called once per download worker
    pub fn start_progress_updater(&self) -> JoinHandle<()> {
        let db = self.db.clone();
        let map = self.progress_map.clone();

        tokio::spawn(async move {
            let mut ticker = tokio::time::interval(Duration::from_secs(1));
            loop {
                ticker.tick().await;

                for entry in map.iter() {
                    let ((download_id, idx), (downloaded, status)) = entry.pair();

                    let _ = sqlx::query(
                        r#"
                        UPDATE parts
                        SET downloaded = ?, status = ?
                        WHERE download_id = ? AND idx = ?
                        "#,
                    )
                    .bind(*downloaded)
                    .bind(status.as_str())
                    .bind(download_id)
                    .bind(*idx)
                    .execute(&db)
                    .await;
                }
            }
        })
    }
    
    /// Part just updates memory, not DB
    pub fn update_progress_in_memory(&self, download_id: &str, idx: i32, downloaded: i64, status: &str) {
        self.progress_map.insert((download_id.to_string(), idx), (downloaded, status.to_string()));
    }

    /// Start or resume a single download by id
    pub async fn run(&self, download_id: &str) -> Result<()> {
        self.update_status(download_id, "running").await.ok();

        let record = self.fetch_record(download_id).await?;
        let (total_size, etag, accept_ranges) = self.probe(&record.url).await?;

        sqlx::query("UPDATE downloads SET total_size = ?, etag = ?, updated_at = ? WHERE id = ?")
            .bind(total_size as i64)
            .bind(etag.clone())
            .bind(now_unix())
            .bind(download_id)
            .execute(&self.db)
            .await?;

        if !accept_ranges {
            return Err(DWError::NoRange.into());
        }

        self.ensure_parts(download_id, total_size).await?;

        // 🚀 start global updater for this download
        let updater_handle = self.start_progress_updater();

        let semaphore = Arc::new(Semaphore::new(self.max_concurrency));
        let mut handles = vec![];

        let parts: Vec<(Part)> = sqlx::query_as(
            "SELECT id, idx, start, end, downloaded, status FROM parts WHERE download_id = ? ORDER BY idx ASC",
        )
        .bind(download_id)
        .fetch_all(&self.db)
        .await?;

        for part in parts {
            let permit = semaphore.clone().acquire_owned().await.unwrap();
            let this = self.clone();
            let d_id = download_id.to_string();
            let etag_clone = etag.clone();

            let handle = tokio::spawn(async move {
                let _p = permit;
                if let Err(e) = this
                    .run_part(
                        &d_id,
                        part.id,
                        part.start,
                        part.end,
                        part.downloaded,
                        &part.status,
                        etag_clone.as_deref(),
                    )
                    .await
                {
                    let _ = sqlx::query("UPDATE parts SET status = 'failed' WHERE id = ?")
                        .bind(part.id)
                        .execute(&this.db)
                        .await;
                    return Err(e);
                }
                Ok::<_, anyhow::Error>(())
            });

            handles.push(handle);
        }

        // wait for all parts
        let mut ok = true;
        for h in handles {
            match h.await {
                Ok(Ok(())) => {}
                _ => ok = false,
            }
        }

        // 🛑 stop updater
        updater_handle.abort();

        if ok {
            self.concat_parts(download_id).await?;
            self.update_status(download_id, "done").await?;
        } else {
            self.update_status(download_id, "failed").await?;
        }

        Ok(())
    }

    pub async fn run_part(
        &self,
        download_id: &str,
        part_idx: i32, // idx (not part_id pk, but the index of the part in that download)
        start: i64,
        end: i64,
        downloaded: i64,
        status: &str,
        etag: Option<&str>,
    ) -> Result<()> {
        let range_start = start + downloaded;
        if range_start > end {
            // just update memory state instead of DB directly
            self.update_progress_in_memory(download_id, part_idx, end as i64, "done");
            return Ok(());
        }

        let mut headers = HeaderMap::new();
        let range_value = format!("bytes={}-{}", range_start, end);
        headers.insert(RANGE, HeaderValue::from_str(&range_value)?);
        if let Some(tag) = etag {
            headers.insert(IF_RANGE, HeaderValue::from_str(tag).unwrap_or(HeaderValue::from_static("*")));
        }

        let record = self.fetch_record(download_id).await?;
        let resp = self.client.get(&record.url).headers(headers).send().await?;
        if !resp.status().is_success() {
            return Err(anyhow!("HTTP status {}", resp.status()));
        }

        let mut stream = resp.bytes_stream();
        let part_path = self.part_path(download_id, part_idx);
        tokio::fs::create_dir_all(part_path.parent().unwrap()).await.ok();
        let mut file = if downloaded == 0 {
            tokio::fs::File::create(&part_path).await?
        } else {
            tokio::fs::OpenOptions::new().append(true).open(&part_path).await?
        };

        let mut downloaded = downloaded;

        while let Some(chunk) = stream.next().await {
            let chunk: Bytes = chunk?;

            // throttle
            if let Some(nz) = NonZeroU32::new(chunk.len() as u32) {
                self.limiter.until_n_ready(nz).await;
            }

            file.write_all(&chunk).await?;
            let chunk_len = chunk.len() as i64;
            downloaded += chunk_len;

            // ✅ update only memory, not DB
            self.update_progress_in_memory(download_id, part_idx, downloaded as i64, "downloading");
            self.downloaded.fetch_add(chunk_len, Ordering::Relaxed);
        }

        file.flush().await?;

        // ✅ final state in memory
        self.update_progress_in_memory(download_id, part_idx, downloaded as i64, "done");

        Ok(())
    }

    async fn concat_parts(&self, download_id: &str) -> Result<()> {
        let dest = &self.path;
        if let Some(parent) = dest.parent() {
            fs::create_dir_all(parent).await?;
        }
        let mut dest_file = fs::File::create(dest).await?;

        let part_indices: Vec<i32> = sqlx::query_scalar(
            "SELECT idx FROM parts WHERE download_id = ? ORDER BY idx ASC",
        )
        .bind(download_id)
        .fetch_all(&self.db)
        .await?;

        for &idx in &part_indices {
            let part_path = self.part_path(download_id, idx);
            let mut f = fs::File::open(&part_path).await?;
            tokio::io::copy(&mut f, &mut dest_file).await?;
        }
        dest_file.flush().await?;

        // cleanup
        for idx in part_indices {
            let _ = fs::remove_file(self.part_path(download_id, idx)).await;
        }
        let _ = fs::remove_dir(self.parts_dir(download_id)).await;

        Ok(())
    }


    async fn ensure_parts(&self, download_id: &str, total_size: i64) -> Result<()> {
        // If parts already exist, just return (resume mode)
        let existing: (i64,) = sqlx::query_as("SELECT COUNT(*) FROM parts WHERE download_id = ?")
            .bind(download_id)
            .fetch_one(&self.db)
            .await?;
        if existing.0 > 0 {
            return Ok(());
        }

        let num_part = self.num_part.max(1); // make sure at least 1 part
        let part_size = (total_size + num_part - 1) / num_part; // ceiling division
        let mut offset = 0i64;

        let mut tx = self.db.begin().await?;

        for idx in 0..num_part {
            let end = min(offset + part_size - 1, total_size - 1);
            sqlx::query(
                "INSERT INTO parts (download_id, idx, start, end, downloaded, status) VALUES (?, ?, ?, ?, 0, 'queued')"
            )
            .bind(download_id)
            .bind(idx as i32)
            .bind(offset)
            .bind(end)
            .execute(&mut *tx)
            .await?;

            offset = end + 1;
            if offset >= total_size {
                break;
            }
        }

        tx.commit().await?;
        Ok(())
    }


    async fn probe(&self, url: &str) -> Result<(i64, Option<String>, bool)> {
        // try HEAD
        let head = self.client.head(url).send().await?;
        let mut accept_ranges = false;
        let mut etag: Option<String> = None;
        let mut total_size: Option<i64> = None;

        if head.status().is_success() {
            let headers = head.headers();
            accept_ranges = headers
                .get(ACCEPT_RANGES)
                .map(|v| v.to_str().unwrap_or("") == "bytes")
                .unwrap_or(false);
            etag = headers.get(ETAG).and_then(|v| v.to_str().ok()).map(|s| s.to_string());
            total_size = headers
                .get(CONTENT_LENGTH)
                .and_then(|v| v.to_str().ok())
                .and_then(|s| s.parse::<i64>().ok());
        }
        // If HEAD didn't give enough, try a tiny ranged GET (0-0)
        if total_size.is_none() || !accept_ranges {
            let mut h = HeaderMap::new();
            h.insert(RANGE, HeaderValue::from_static("bytes=0-0"));
            let resp = self.client.get(url).headers(h).send().await?;
            let headers = resp.headers();
            accept_ranges |= headers
                .get(ACCEPT_RANGES)
                .map(|v| v.to_str().unwrap_or("") == "bytes")
                .unwrap_or(false);
            etag = etag.or_else(|| headers.get(ETAG).and_then(|v| v.to_str().ok()).map(|s| s.to_string()));
            // Try to parse content-range: bytes 0-0/XYZ
            if let Some(cr) = headers.get("content-range").and_then(|v| v.to_str().ok()) {
                if let Some(total) = cr.split('/').last().and_then(|s| s.parse::<i64>().ok()) {
                    total_size = Some(total);
                }
            }
        }
        let total = total_size.context("Could not determine content length")?;
        Ok((total, etag, accept_ranges))
    }

    async fn fetch_record(&self, id: &str) -> Result<DownloadRecord> {
        let row: (String, String, String, String, Option<String>, Option<i64>) = sqlx::query_as(
            "SELECT id, url, path, status, etag, total_size FROM downloads WHERE id = ?",
        )
        .bind(id)
        .fetch_one(&self.db)
        .await?;
        Ok(DownloadRecord {
            id: row.0,
            url: row.1,
            path: row.2,
            status: row.3,
            etag: row.4,
            total_size: row.5,
        })
    }

    async fn update_status(&self, id: &str, status: &str) -> Result<()> {
        sqlx::query("UPDATE downloads SET status = ?, updated_at = ? WHERE id = ?")
            .bind(status)
            .bind(now_unix())
            .bind(id)
            .execute(&self.db)
            .await?;
        let mut s = self.status.lock().await;
        *s = status.to_string();
        Ok(())
    }

    fn parts_dir(&self, download_id: &str) -> PathBuf {
        self.path.with_extension("parts")
    }

    fn part_path(&self, download_id: &str, idx: i32) -> PathBuf {
        self.parts_dir(download_id).join(format!("{}.part", idx))
    }
}

#[inline]
fn now_unix() -> i64 {
    OffsetDateTime::now_utc().unix_timestamp()
}

/// Calculate download speed (bytes/sec) for the last `window_secs`
pub async fn calc_speed(db: &SqlitePool, download_id: &str, window_secs: i64) -> sqlx::Result<f64> {
    let now = now_unix();
    let cutoff = now - window_secs;

    let (total_bytes,): (i64,) = sqlx::query_as(
        "SELECT COALESCE(SUM(bytes),0) FROM download_history WHERE download_id = ? AND timestamp >= ?",
    )
    .bind(download_id)
    .bind(cutoff)
    .fetch_one(db)
    .await?;

    Ok(total_bytes as f64 / window_secs as f64)
}

struct ProgressThrottle {
    last_emit: Instant,
    interval: Duration,
}

impl ProgressThrottle {
    fn new(interval: Duration) -> Self {
        Self { last_emit: Instant::now() - interval, interval }
    }

    fn should_emit(&mut self) -> bool {
        if self.last_emit.elapsed() >= self.interval {
            self.last_emit = Instant::now();
            true
        } else {
            false
        }
    }
}
