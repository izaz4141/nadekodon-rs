use crate::utils::logger;
use crate::utils::types::{
    CategoryInfo, DownloadInfo, DownloadProgress, DownloadState, DownloadType, PartInfo,
};

use sqlx::{Pool, Row, Sqlite, sqlite::SqlitePoolOptions};
use std::collections::{HashMap, HashSet};
use std::path::{Component, Path, PathBuf};
use std::sync::{
    Arc, Weak,
    atomic::{AtomicBool, Ordering},
};
use std::time::{Duration, SystemTime, UNIX_EPOCH};
use tokio::sync::{Mutex, Notify, RwLock};
use tokio::time::sleep;
use uuid::Uuid;

use crate::app_context::AppContext;
use crate::downloader::manager::DownloadManager;

/// A failed write that still needs to reach SQLite.
///
/// Only one operation is kept per download: a later `Delete` always replaces a
/// queued `Upsert` so a retried insert can never resurrect a deleted row.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
enum PendingOp {
    Upsert,
    Delete,
}

#[derive(Debug, Default)]
struct Outbox {
    ops: HashMap<Uuid, PendingOp>,
    warned: HashSet<Uuid>,
}

impl Outbox {
    fn note(&mut self, id: Uuid, op: PendingOp) {
        match op {
            PendingOp::Delete => {
                self.ops.insert(id, PendingOp::Delete);
            }
            PendingOp::Upsert => {
                self.ops.entry(id).or_insert(PendingOp::Upsert);
            }
        }
    }

    fn clear(&mut self, id: Uuid) {
        self.ops.remove(&id);
        self.warned.remove(&id);
    }

    fn warn_once(&mut self, id: Uuid, action: &str, err: &sqlx::Error) {
        if self.warned.insert(id) {
            logger::error(&format!(
                "Database {} failed for {}; will retry: {:?}",
                action, id, err
            ));
        }
    }
}

/// The progress columns written by the periodic tick.
#[derive(Debug, Clone, PartialEq, Eq)]
struct ProgressCheckpoint {
    downloaded: u64,
    uploaded: u64,
    state: String,
}

fn now_ms() -> u64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap_or_default()
        .as_millis() as u64
}

pub struct DatabaseManager {
    pool: Pool<Sqlite>,
    context: Weak<AppContext>,
    shutdown_signal: Arc<Notify>,
    db_done_signal: Arc<Notify>,
    /// Serializes read-worker-then-write sequences. Never acquire this while
    /// holding the workers map or the categories lock.
    write_gate: Mutex<()>,
    last_saved: RwLock<HashMap<Uuid, ProgressCheckpoint>>,
    /// Mutated only while `write_gate` is held.
    outbox: Mutex<Outbox>,
    categories_dirty: AtomicBool,
}

impl std::fmt::Debug for DatabaseManager {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.debug_struct("DatabaseManager")
            .field("pool", &self.pool)
            .field("categories_dirty", &self.categories_dirty)
            .finish()
    }
}

impl DatabaseManager {
    pub async fn new(
        pool: Pool<Sqlite>,
        context: Weak<AppContext>,
        shutdown_signal: Arc<Notify>,
        db_done_signal: Arc<Notify>,
    ) -> Arc<Self> {
        Arc::new(Self {
            pool,
            context,
            shutdown_signal,
            db_done_signal,
            write_gate: Mutex::new(()),
            last_saved: RwLock::new(HashMap::new()),
            outbox: Mutex::new(Outbox::default()),
            categories_dirty: AtomicBool::new(false),
        })
    }

    /// Timer-only task: never owns the pool and never blocks an action.
    pub async fn run_loop(self: Arc<Self>) {
        loop {
            tokio::select! {
                _ = sleep(Duration::from_secs(5)) => {
                    self.retry_outbox().await;
                    self.save_active_progress().await;
                    if self.categories_dirty.load(Ordering::SeqCst) {
                        self.save_categories().await;
                    }
                }
                _ = self.shutdown_signal.notified() => {
                    // Only ongoing progress + outbox + categories need flushing;
                    // every other change was committed when it happened.
                    self.save_active_progress().await;
                    self.save_categories().await;
                    self.retry_outbox().await;
                    self.db_done_signal.notify_waiters();
                    break;
                }
            }
        }
    }

    pub async fn load_downloads(&self) -> Result<Vec<DownloadInfo>, sqlx::Error> {
        let rows = sqlx::query(
            r#"
            SELECT id, url, dest, total_size, downloaded, uploaded, state, parts, added_at, updated_at, download_type, torrent_hash, referer, category, seeding_ratio_override, seeding_time_override
            FROM downloads
            "#
        )
        .fetch_all(&self.pool)
        .await?;

        let mut downloads = Vec::new();
        for row in rows {
            let id_str: String = row.get("id");
            let id = Uuid::parse_str(&id_str).unwrap_or_default();
            let url: String = row.get("url");
            let dest_str: String = row.get("dest");
            let dest = PathBuf::from(dest_str);
            if dest.components().any(|c| matches!(c, Component::ParentDir)) {
                logger::warn(&format!(
                    "Skipping Download with id '{}' due to invalid save_path: {}",
                    id.to_string(),
                    dest.display()
                ));
                continue;
            }

            let total_size: Option<i64> = row.get("total_size");
            let total_size = total_size.map(|s| s as u64);
            let downloaded: i64 = row.get("downloaded");
            let downloaded = downloaded as u64;
            let uploaded: i64 = row.get("uploaded");
            let uploaded = uploaded as u64;

            let state_str: String = row.get("state");
            let state = if state_str.contains("Error") {
                DownloadState::Error(state_str)
            } else if state_str.contains("Seeding") {
                DownloadState::Seeding
            } else if state_str.contains("StalledDL") {
                DownloadState::StalledDL
            } else if state_str.contains("StalledUP") {
                DownloadState::StalledUP
            } else if state_str.contains("Cancelled") {
                DownloadState::Cancelled
            } else if state_str.contains("Completed") {
                DownloadState::Completed
            } else {
                DownloadState::Paused
            };

            let parts_str: Option<String> = row.get("parts");
            let parts: Vec<PartInfo> = if let Some(p) = parts_str {
                serde_json::from_str(&p).unwrap_or_default()
            } else {
                Vec::new()
            };

            let added_at: i64 = row.get("added_at");
            let added_at = added_at as u64;
            let updated_at: i64 = row.get("updated_at");
            let updated_at = updated_at as u64;

            let download_type_str: Option<String> = row.get("download_type");
            let download_type = if let Some(dt) = download_type_str {
                serde_json::from_str(&format!("\"{}\"", dt)).unwrap_or(DownloadType::Normal)
            } else {
                DownloadType::Normal
            };

            let torrent_hash: Option<String> = row.get("torrent_hash");
            let referer: Option<String> = row.get("referer");
            let category: Option<String> = row.get("category");
            let seeding_ratio_override: Option<f32> = row.get("seeding_ratio_override");
            let seeding_time_override: Option<i64> = row.get("seeding_time_override");
            let seeding_time_override = seeding_time_override.map(|s| s as u64);

            downloads.push(DownloadInfo {
                id,
                url,
                dest,
                total_size,
                downloaded,
                uploaded,
                uspeed: None,
                state,
                history: Vec::new(),
                parts,
                added_at,
                updated_at,
                download_type,
                torrent_hash,
                referer,
                category,
                seeding_ratio_override,
                seeding_time_override,
            });
        }

        Ok(downloads)
    }

    pub async fn load_categories(&self) -> Result<HashMap<String, CategoryInfo>, sqlx::Error> {
        let rows = sqlx::query("SELECT name, save_path FROM categories")
            .fetch_all(&self.pool)
            .await?;

        let mut categories = HashMap::new();
        for row in rows {
            let name: String = row.get("name");
            let save_path: Option<String> = row.get("save_path");
            let save_path = save_path.map(PathBuf::from);
            if let Some(path) = &save_path {
                if path.components().any(|c| matches!(c, Component::ParentDir)) {
                    logger::warn(&format!(
                        "Skipping category '{}' due to invalid save_path: {}",
                        name,
                        path.display()
                    ));
                    continue;
                }
            }
            categories.insert(name.clone(), CategoryInfo { name, save_path });
        }

        Ok(categories)
    }

    pub async fn init_db(path: &Path) -> Result<Pool<Sqlite>, sqlx::Error> {
        if let Some(parent) = path.parent() {
            std::fs::create_dir_all(parent).unwrap_or_default();
        }

        if !path.exists()
            && let Err(e) = std::fs::File::create(path)
        {
            logger::error(&format!(
                "Failed to create db file at {}: {}",
                path.display(),
                e
            ));
            return Err(sqlx::Error::Io(e));
        }

        let db_url = format!("sqlite://{}", path.display());

        let pool = SqlitePoolOptions::new()
            .max_connections(4)
            .after_connect(|conn, _metadata| {
                Box::pin(async move {
                    sqlx::query("PRAGMA journal_mode=WAL")
                        .execute(&mut *conn)
                        .await?;
                    sqlx::query("PRAGMA synchronous=NORMAL")
                        .execute(&mut *conn)
                        .await?;
                    sqlx::query("PRAGMA busy_timeout=5000")
                        .execute(&mut *conn)
                        .await?;
                    sqlx::query("PRAGMA foreign_keys=ON")
                        .execute(&mut *conn)
                        .await?;
                    Ok(())
                })
            })
            .connect(&db_url)
            .await?;

        sqlx::query(
            r#"
            CREATE TABLE IF NOT EXISTS downloads (
                id TEXT PRIMARY KEY,
                url TEXT NOT NULL,
                dest TEXT NOT NULL,
                total_size INTEGER,
                downloaded INTEGER NOT NULL,
                uploaded INTEGER NOT NULL DEFAULT 0,
                state TEXT NOT NULL,
                parts TEXT,
                added_at INTEGER NOT NULL DEFAULT 0,
                updated_at INTEGER NOT NULL,
                download_type TEXT,
                torrent_hash TEXT,
                referer TEXT,
                category TEXT
            );
            "#,
        )
        .execute(&pool)
        .await?;

        let _ = sqlx::query("ALTER TABLE downloads ADD COLUMN uploaded INTEGER NOT NULL DEFAULT 0")
            .execute(&pool)
            .await;

        let _ = sqlx::query("ALTER TABLE downloads ADD COLUMN download_type TEXT")
            .execute(&pool)
            .await;

        let _ = sqlx::query("ALTER TABLE downloads ADD COLUMN torrent_hash TEXT")
            .execute(&pool)
            .await;

        let _ = sqlx::query("ALTER TABLE downloads ADD COLUMN referer TEXT")
            .execute(&pool)
            .await;

        let _ = sqlx::query("ALTER TABLE downloads ADD COLUMN category TEXT")
            .execute(&pool)
            .await;

        let _ = sqlx::query("ALTER TABLE downloads ADD COLUMN seeding_ratio_override REAL")
            .execute(&pool)
            .await;

        let _ = sqlx::query("ALTER TABLE downloads ADD COLUMN seeding_time_override INTEGER")
            .execute(&pool)
            .await;

        sqlx::query(
            r#"
            CREATE TABLE IF NOT EXISTS categories (
                name TEXT PRIMARY KEY,
                save_path TEXT
            );
            "#,
        )
        .execute(&pool)
        .await?;

        Ok(pool)
    }

    /// Full-row upsert for one download, read under the write gate so a delete
    /// or a newer action can never be overwritten by a stale snapshot.
    pub async fn save_download(&self, id: Uuid) {
        let _gate = self.write_gate.lock().await;

        let Some(ctx) = self.context.upgrade() else {
            logger::error(&format!(
                "AppContext dropped while saving download {}; skipping write",
                id
            ));
            return;
        };
        let dm = ctx.dm().await;
        let Some(worker) = dm.get_worker(id).await else {
            // The worker was removed (delete/merge). Never re-insert it.
            return;
        };

        let mut info = worker.snapshot_info().await;
        info.updated_at = now_ms();

        match self.upsert_full(&info).await {
            Ok(()) => {
                self.outbox.lock().await.clear(id);
                self.last_saved.write().await.insert(
                    id,
                    ProgressCheckpoint {
                        downloaded: info.downloaded,
                        uploaded: info.uploaded,
                        state: format!("{:?}", info.state),
                    },
                );
            }
            Err(e) => {
                let mut outbox = self.outbox.lock().await;
                outbox.note(id, PendingOp::Upsert);
                outbox.warn_once(id, "save", &e);
            }
        }
    }

    /// Immediate row removal. A failure is retried through the outbox and can
    /// never be downgraded to an upsert.
    pub async fn delete_download(&self, id: Uuid) {
        let _gate = self.write_gate.lock().await;

        let result = sqlx::query("DELETE FROM downloads WHERE id = ?")
            .bind(id.to_string())
            .execute(&self.pool)
            .await;

        match result {
            Ok(_) => {
                let mut outbox = self.outbox.lock().await;
                outbox.clear(id);
                drop(outbox);
                self.last_saved.write().await.remove(&id);
            }
            Err(e) => {
                let mut outbox = self.outbox.lock().await;
                outbox.note(id, PendingOp::Delete);
                outbox.warn_once(id, "delete", &e);
            }
        }
    }

    /// Periodic progress flush. Only `DownloadManager::ongoing` ids are read,
    /// in chunks of 64 rows per gate acquisition + transaction.
    pub async fn save_active_progress(&self) {
        let Some(ctx) = self.context.upgrade() else {
            return;
        };
        let dm = ctx.dm().await;
        let ids = dm.ongoing_ids().await;

        if ids.is_empty() {
            self.last_saved.write().await.clear();
            return;
        }

        let live: HashSet<Uuid> = ids.iter().copied().collect();
        self.last_saved
            .write()
            .await
            .retain(|id, _| live.contains(id));

        for chunk in ids.chunks(64) {
            let _gate = self.write_gate.lock().await;

            let mut writes: Vec<(DownloadProgress, bool)> = Vec::new();
            let mut vanished = Vec::new();

            for id in chunk {
                let Some(worker) = dm.get_worker(*id).await else {
                    vanished.push(*id);
                    continue;
                };

                let progress = worker.progress_snapshot().await;
                let checkpoint = ProgressCheckpoint {
                    downloaded: progress.downloaded,
                    uploaded: progress.uploaded,
                    state: format!("{:?}", progress.state),
                };
                let previous = self.last_saved.read().await.get(id).cloned();
                if previous.as_ref() == Some(&checkpoint) {
                    continue;
                }

                // `parts` only carries per-part byte offsets; skip its JSON
                // entirely when no bytes moved (the seeding fast path).
                let include_parts = previous
                    .as_ref()
                    .map(|p| p.downloaded != progress.downloaded)
                    .unwrap_or(true);
                writes.push((progress, include_parts));
            }

            if !vanished.is_empty() {
                for id in &vanished {
                    dm.ongoing_remove(*id).await;
                }
                let mut last_saved = self.last_saved.write().await;
                for id in &vanished {
                    last_saved.remove(id);
                }
            }

            if writes.is_empty() {
                continue;
            }

            match self.write_chunk(&dm, &writes).await {
                Ok(()) => {
                    let mut last_saved = self.last_saved.write().await;
                    for (progress, _) in &writes {
                        last_saved.insert(
                            progress.id,
                            ProgressCheckpoint {
                                downloaded: progress.downloaded,
                                uploaded: progress.uploaded,
                                state: format!("{:?}", progress.state),
                            },
                        );
                    }
                }
                Err(e) => {
                    let mut outbox = self.outbox.lock().await;
                    for (progress, _) in &writes {
                        outbox.note(progress.id, PendingOp::Upsert);
                        outbox.warn_once(progress.id, "progress", &e);
                    }
                }
            }
        }
    }

    /// Full reconciliation of the category table in a single transaction.
    /// Retried on the next tick if it fails.
    pub async fn save_categories(&self) {
        let _gate = self.write_gate.lock().await;

        let Some(ctx) = self.context.upgrade() else {
            return;
        };
        let dm = ctx.dm().await;
        let categories: Vec<CategoryInfo> = {
            let map = dm.categories.read().await;
            map.values().cloned().collect()
        };

        match self.reconcile_categories(&categories).await {
            Ok(()) => self.categories_dirty.store(false, Ordering::SeqCst),
            Err(e) => {
                self.categories_dirty.store(true, Ordering::SeqCst);
                logger::error(&format!("Failed to save categories; will retry: {:?}", e));
            }
        }
    }

    async fn reconcile_categories(&self, categories: &[CategoryInfo]) -> Result<(), sqlx::Error> {
        let mut tx = self.pool.begin().await?;

        for info in categories {
            let save_path = info
                .save_path
                .as_ref()
                .map(|p| p.to_string_lossy().to_string());

            sqlx::query(
                r#"
                INSERT INTO categories (name, save_path) VALUES (?, ?)
                ON CONFLICT(name) DO UPDATE SET save_path = excluded.save_path;
                "#,
            )
            .bind(&info.name)
            .bind(save_path)
            .execute(&mut *tx)
            .await?;
        }

        let existing: Vec<String> = sqlx::query_scalar("SELECT name FROM categories")
            .fetch_all(&mut *tx)
            .await?;
        let keep: HashSet<&str> = categories.iter().map(|c| c.name.as_str()).collect();
        for name in existing {
            if !keep.contains(name.as_str()) {
                sqlx::query("DELETE FROM categories WHERE name = ?")
                    .bind(name)
                    .execute(&mut *tx)
                    .await?;
            }
        }

        tx.commit().await
    }

    async fn retry_outbox(&self) {
        let _gate = self.write_gate.lock().await;

        let entries: Vec<(Uuid, PendingOp)> = {
            let outbox = self.outbox.lock().await;
            outbox.ops.iter().map(|(id, op)| (*id, *op)).collect()
        };
        if entries.is_empty() {
            return;
        }

        let Some(ctx) = self.context.upgrade() else {
            return;
        };
        let dm = ctx.dm().await;

        for (id, op) in entries {
            match op {
                PendingOp::Delete => {
                    match sqlx::query("DELETE FROM downloads WHERE id = ?")
                        .bind(id.to_string())
                        .execute(&self.pool)
                        .await
                    {
                        Ok(_) => {
                            self.outbox.lock().await.clear(id);
                            self.last_saved.write().await.remove(&id);
                        }
                        Err(e) => {
                            self.outbox.lock().await.warn_once(id, "delete retry", &e);
                        }
                    }
                }
                PendingOp::Upsert => {
                    let Some(worker) = dm.get_worker(id).await else {
                        // Deleted while queued: treat the stale upsert as a delete.
                        match sqlx::query("DELETE FROM downloads WHERE id = ?")
                            .bind(id.to_string())
                            .execute(&self.pool)
                            .await
                        {
                            Ok(_) => {
                                self.outbox.lock().await.clear(id);
                                self.last_saved.write().await.remove(&id);
                            }
                            Err(e) => {
                                let mut outbox = self.outbox.lock().await;
                                outbox.note(id, PendingOp::Delete);
                                outbox.warn_once(id, "delete retry", &e);
                            }
                        }
                        continue;
                    };

                    let mut info = worker.snapshot_info().await;
                    info.updated_at = now_ms();
                    match self.upsert_full(&info).await {
                        Ok(()) => {
                            self.outbox.lock().await.clear(id);
                            self.last_saved.write().await.insert(
                                id,
                                ProgressCheckpoint {
                                    downloaded: info.downloaded,
                                    uploaded: info.uploaded,
                                    state: format!("{:?}", info.state),
                                },
                            );
                        }
                        Err(e) => {
                            self.outbox.lock().await.warn_once(id, "save retry", &e);
                        }
                    }
                }
            }
        }
    }

    async fn upsert_full(&self, info: &DownloadInfo) -> Result<(), sqlx::Error> {
        let mut tx = self.pool.begin().await?;
        Self::upsert_conn(&mut tx, info).await?;
        tx.commit().await
    }

    async fn write_chunk(
        &self,
        dm: &Arc<DownloadManager>,
        writes: &[(DownloadProgress, bool)],
    ) -> Result<(), sqlx::Error> {
        let mut tx = self.pool.begin().await?;

        for (progress, include_parts) in writes {
            let id = progress.id.to_string();
            let state = format!("{:?}", progress.state);
            let updated_at = progress.updated_at as i64;

            let rows = if *include_parts {
                let parts = serde_json::to_string(&progress.parts).unwrap_or_default();
                sqlx::query(
                    r#"
                    UPDATE downloads
                    SET downloaded = ?, uploaded = ?, state = ?, parts = ?, updated_at = ?
                    WHERE id = ?
                    "#,
                )
                .bind(progress.downloaded as i64)
                .bind(progress.uploaded as i64)
                .bind(state)
                .bind(parts)
                .bind(updated_at)
                .bind(id)
                .execute(&mut *tx)
                .await?
                .rows_affected()
            } else {
                sqlx::query(
                    r#"
                    UPDATE downloads
                    SET uploaded = ?, state = ?, updated_at = ?
                    WHERE id = ?
                    "#,
                )
                .bind(progress.uploaded as i64)
                .bind(state)
                .bind(updated_at)
                .bind(id)
                .execute(&mut *tx)
                .await?
                .rows_affected()
            };

            // Row missing (e.g. added before its first action write landed):
            // fall back to a full insert using the latest worker state.
            if rows == 0
                && let Some(worker) = dm.get_worker(progress.id).await
            {
                let mut info = worker.snapshot_info().await;
                info.updated_at = now_ms();
                Self::upsert_conn(&mut tx, &info).await?;
            }
        }

        tx.commit().await
    }

    async fn upsert_conn(
        conn: &mut sqlx::Transaction<'_, Sqlite>,
        info: &DownloadInfo,
    ) -> Result<(), sqlx::Error> {
        let parts = serde_json::to_string(&info.parts).unwrap_or_default();

        sqlx::query(
            r#"
            INSERT INTO downloads (id, url, dest, total_size, downloaded, uploaded, state, parts, added_at, updated_at, download_type, torrent_hash, referer, category, seeding_ratio_override, seeding_time_override)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(id) DO UPDATE SET
                url = excluded.url,
                dest = excluded.dest,
                total_size = excluded.total_size,
                downloaded = excluded.downloaded,
                uploaded = excluded.uploaded,
                state = excluded.state,
                parts = excluded.parts,
                updated_at = excluded.updated_at,
                download_type = excluded.download_type,
                torrent_hash = excluded.torrent_hash,
                referer = excluded.referer,
                category = excluded.category,
                seeding_ratio_override = excluded.seeding_ratio_override,
                seeding_time_override = excluded.seeding_time_override;
            "#,
        )
        .bind(info.id.to_string())
        .bind(&info.url)
        .bind(info.dest.to_string_lossy().to_string())
        .bind(info.total_size.map(|s| s as i64))
        .bind(info.downloaded as i64)
        .bind(info.uploaded as i64)
        .bind(format!("{:?}", info.state))
        .bind(parts)
        .bind(info.added_at as i64)
        .bind(info.updated_at as i64)
        .bind(format!("{:?}", info.download_type))
        .bind(info.torrent_hash.as_deref())
        .bind(info.referer.as_deref())
        .bind(info.category.as_deref())
        .bind(info.seeding_ratio_override)
        .bind(info.seeding_time_override.map(|s| s as i64))
        .execute(&mut **conn)
        .await?;

        Ok(())
    }
}
