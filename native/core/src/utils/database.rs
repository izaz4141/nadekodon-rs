use crate::utils::logger;
use crate::utils::types::{CategoryInfo, DownloadInfo, DownloadState, DownloadType, PartInfo};

use sqlx::{Pool, Row, Sqlite, sqlite::SqlitePoolOptions};
use std::collections::HashMap;
use std::path::{Component, Path, PathBuf};
use std::sync::{Arc, Weak};
use std::time::Duration;
use tokio::sync::Notify;
use tokio::time::sleep;
use uuid::Uuid;

use crate::app_context::AppContext;

#[derive(Debug)]
pub struct DatabaseManager {
    pool: Pool<Sqlite>,
    context: Weak<AppContext>,
    shutdown_signal: Arc<Notify>,
    db_done_signal: Arc<Notify>,
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
        })
    }

    pub async fn run_loop(self: Arc<Self>) {
        loop {
            tokio::select! {
                _ = sleep(Duration::from_secs(5)) => {
                    self.save_downloads().await;
                }
                _ = self.shutdown_signal.notified() => {
                    if let Some(ctx) = self.context.upgrade() {
                        let dm = ctx.dm().await;
                        dm.sync_active_workers().await;
                    }
                    self.save_downloads().await;
                    self.save_categories().await;
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
            } else if state_str.contains("Stalled") {
                DownloadState::Stalled
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
            .max_connections(5)
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

    pub async fn save_downloads(&self) {
        if let Some(ctx) = self.context.upgrade() {
            let dm = ctx.dm().await;
            let deletions = dm.drain_pending_deletions().await;
            let mut failed_deletions = Vec::new();
            for id in deletions {
                let id_str = id.to_string();
                if let Err(e) = sqlx::query("DELETE FROM downloads WHERE id = ?")
                    .bind(id_str)
                    .execute(&self.pool)
                    .await
                {
                    logger::error(&format!(
                        "Failed to delete download {} from DB: {:?}",
                        id, e
                    ));
                    failed_deletions.push(id);
                }
            }

            if !failed_deletions.is_empty() {
                dm.requeue_pending_deletions(failed_deletions).await;
            }

            let downloads = match dm.list_all().await {
                Ok(d) => d,
                Err(e) => {
                    logger::error(&format!("Failed to get downloads list: {:?}", e));
                    return;
                }
            };
            for download in downloads {
                let id = download.id.to_string();
                let url = download.url;
                let dest = download.dest.to_string_lossy().to_string();
                let total_size = download.total_size.map(|s| s as i64);
                let downloaded = download.downloaded as i64;
                let uploaded = download.uploaded as i64;
                let state = format!("{:?}", download.state);
                let added_at = download.added_at as i64;
                let updated_at = download.updated_at as i64;
                let download_type = format!("{:?}", download.download_type);
                let torrent_hash = download.torrent_hash;
                let referer = download.referer;
                let category = download.category;
                let seeding_ratio_override = download.seeding_ratio_override;
                let seeding_time_override = download.seeding_time_override.map(|s| s as i64);

                let parts = serde_json::to_string(&download.parts).unwrap_or_default();

                let result = sqlx::query(
                    r#"
                    INSERT INTO downloads (id, url, dest, total_size, downloaded, uploaded, state, parts, added_at, updated_at, download_type, torrent_hash, referer, category, seeding_ratio_override, seeding_time_override)
                    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                    ON CONFLICT(id) DO UPDATE SET
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
                    "#
                )
                .bind(id)
                .bind(url)
                .bind(dest)
                .bind(total_size)
                .bind(downloaded)
                .bind(uploaded)
                .bind(state)
                .bind(parts)
                .bind(added_at)
                .bind(updated_at)
                .bind(download_type)
                .bind(torrent_hash)
                .bind(referer)
                .bind(category)
                .bind(seeding_ratio_override)
                .bind(seeding_time_override)
                .execute(&self.pool)
                .await;

                if let Err(e) = result {
                    logger::error(&format!("Failed to save download to DB: {:?}", e));
                }
            }
        }
    }

    pub async fn save_categories(&self) {
        if let Some(ctx) = self.context.upgrade() {
            let dm = ctx.dm().await;
            let categories = dm.categories.read().await.clone();
            for (_name, info) in categories {
                let save_path = info
                    .save_path
                    .as_ref()
                    .map(|p| p.to_string_lossy().to_string());

                let result = sqlx::query(
                    r#"
                    INSERT INTO categories (name, save_path) VALUES (?, ?)
                    ON CONFLICT(name) DO UPDATE SET save_path = excluded.save_path;
                    "#,
                )
                .bind(&info.name)
                .bind(save_path)
                .execute(&self.pool)
                .await;

                if let Err(e) = result {
                    logger::error(&format!("Failed to save category {}: {:?}", info.name, e));
                }
            }
        }
    }
}
