use std::{collections::HashMap, path::PathBuf, sync::Arc};
use anyhow::Result;
use tokio::{fs, sync::Mutex, time::{interval, Duration}};
use sqlx::{sqlite::SqlitePoolOptions, Pool, Sqlite, SqlitePool};

use crate::downloader::worker::DownloadWorker;
use crate::utils::time::now_unix;
use crate::signals::DownloadProgress;
use rinf::{DartSignal, RustSignal, debug_print};

/// Handle to a single active or completed download task
pub struct DownloadHandle {
    pub id: String,
    pub worker: DownloadWorker,
}

/// Manager that owns all workers and supervises downloads
pub struct DownloadManager {
    db: SqlitePool,
    pub db_path: PathBuf,
    pub base_dir: PathBuf,
    pub part_num: i64,
    pub max_concurrency: usize,
    pub max_speed: u32,
    pub workers: Arc<Mutex<HashMap<String, DownloadHandle>>>,
}

impl DownloadManager {
    pub async fn new(
        db_path: impl Into<PathBuf>, 
        base_dir: impl Into<PathBuf>, 
        part_num: i64, 
        max_concurrency: usize, 
        max_speed: u32,
    ) -> Result<Self> {
        let db_path: PathBuf = db_path.into();
        let base_dir: PathBuf = base_dir.into();

        let db_url = format!("sqlite:{}", db_path.to_string_lossy());
        let db = SqlitePoolOptions::new()
            .max_connections(5)
            .connect(&db_url)
            .await?;

        let this = Self {
            db,
            db_path,
            base_dir,
            part_num,
            max_concurrency,
            max_speed,
            workers: Arc::new(Mutex::new(HashMap::new())),
        };

        this.init_db().await?;
        Ok(this)
    }

    /// Create databse if doesnt exist
    async fn init_db(&self) -> Result<()> {
        // INTEGER timestamps (unix seconds) for fast comparisons
        sqlx::query(
            r#"
            CREATE TABLE IF NOT EXISTS downloads (
                id TEXT PRIMARY KEY,
                url TEXT NOT NULL,
                path TEXT NOT NULL,
                status TEXT NOT NULL,
                etag TEXT,
                total_size INTEGER,
                created_at INTEGER NOT NULL,
                updated_at INTEGER NOT NULL
            );
        "#,
        )
        .execute(&self.db)
        .await?;

        sqlx::query(
            r#"
            CREATE TABLE IF NOT EXISTS parts (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                download_id TEXT NOT NULL,
                idx INTEGER NOT NULL,
                start INTEGER NOT NULL,
                end INTEGER NOT NULL,
                downloaded INTEGER NOT NULL DEFAULT 0,
                status TEXT NOT NULL DEFAULT 'queued',
                UNIQUE(download_id, idx),
                FOREIGN KEY(download_id) REFERENCES downloads(id) ON DELETE CASCADE
            );
        "#,
        )
        .execute(&self.db)
        .await?;

        sqlx::query(
            r#"
            CREATE TABLE IF NOT EXISTS download_history (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                download_id TEXT NOT NULL,
                bytes INTEGER NOT NULL,
                timestamp INTEGER NOT NULL,
                FOREIGN KEY(download_id) REFERENCES downloads(id) ON DELETE CASCADE
            );
        "#,
        )
        .execute(&self.db)
        .await?;
        Ok(())
    }

    /// Spawn a new download worker and track it
    pub async fn spawn_worker(&self, url: &str, path: &str) -> Result<String> {
        let worker = Arc::new(
            DownloadWorker::new(
                self.db.clone(),        // ✅ reuse pool
                &self.base_dir,         // ✅ reuse same base dir
                self.part_num,          // default part size / count
                self.max_concurrency,
                self.max_speed,
            )
            .await?,
        );

        let id = worker.enqueue(url, path).await?;
        let handle = DownloadHandle { id: id.clone(), worker: worker.clone() };

        self.workers.lock().await.insert(id.clone(), handle);

        // Spawn async task to run the worker
        let w_clone = worker.clone();
        let id_clone = id.clone();
        tokio::spawn(async move {
            if let Err(e) = w_clone.run(&id_clone).await {
                debug_print!("Worker {} failed: {:?}", id_clone, e);
            } else {
                debug_print!("Worker {} completed", id_clone);
            }
        });

        Ok(id)
    }

    /// Push history entry and keep only last 30 rows per download_id
    pub async fn push_download_history(
        &self,
        download_id: &str,
        bytes: i64,
    ) -> Result<()> {
        let now = now_unix();

        // Insert new history entry
        sqlx::query(
            r#"
            INSERT INTO download_history (download_id, bytes, timestamp)
            VALUES (?1, ?2, ?3)
            "#,
        )
        .bind(download_id)
        .bind(bytes)
        .bind(now)
        .execute(&self.db)
        .await?;

        // Trim history to last 30 entries
        sqlx::query(
            r#"
            DELETE FROM download_history
            WHERE download_id = ?1
              AND id NOT IN (
                  SELECT id
                  FROM download_history
                  WHERE download_id = ?1
                  ORDER BY timestamp DESC
                  LIMIT 30
              )
            "#,
        )
        .bind(download_id)
        .execute(&self.db)
        .await?;

        Ok(())
    }

    pub fn start_progress_loop(self: Arc<Self>) {
        tokio::spawn(async move {
            let mut ticker = interval(Duration::from_millis(1000)); // update every second
            loop {
                ticker.tick().await;

                // Take a snapshot of worker handles (release lock quickly)
                let workers_snapshot = {
                    let workers = self.workers.lock().await;
                    workers.clone() // assuming workers: HashMap<String, DownloadWorkerHandle>
                };

                // For each worker, emit its progress
                for (id, _handle) in workers_snapshot {
                    if let Err(e) = self.emit_progress(&id, false).await {
                        eprintln!("Failed to emit progress for {id}: {e}");
                    }
                }
            }
        });
    }

    /// Aggregate progress from DB + worker memory and send to Dart
    pub async fn emit_progress(&self, download_id: &str, finished: bool) -> anyhow::Result<()> {
        // Sum downloaded from all parts and get total from DB
        let (db_downloaded, total): (i64, i64) = sqlx::query_as(
            "SELECT COALESCE(SUM(p.downloaded),0), COALESCE(MAX(d.total_size),0)
             FROM parts p JOIN downloads d ON d.id = p.download_id
             WHERE p.download_id = ?",
        )
        .bind(download_id)
        .fetch_one(&self.db)
        .await?;

        // Check if worker has in-memory progress too
        let in_memory_downloaded = {
            let workers = self.workers.lock().await;
            workers
                .get(download_id)
                .map(|handle| handle.worker.downloaded.load(std::sync::atomic::Ordering::Relaxed))
                .unwrap_or(0)
        };

        let downloaded = db_downloaded.max(in_memory_downloaded);

        // Compute recent speed from history table
        let now = now_unix();
        let cutoff = now - 3;
        let recent_bytes: (i64,) = sqlx::query_as(
            "SELECT COALESCE(SUM(bytes),0) FROM download_history
             WHERE download_id = ? AND timestamp >= ?",
        )
        .bind(download_id)
        .bind(cutoff)
        .fetch_one(&self.db)
        .await?;
        let speed = (recent_bytes.0 as f64 / 3.0).max(0.0) as u64;

        let progress = DownloadProgress {
            id: download_id.to_string(),
            downloaded: downloaded as u64,
            total: if total > 0 { Some(total as u64) } else { None },
            speed,
            finished,
        };

        progress.send_signal_to_dart();
        Ok(())
    }
}