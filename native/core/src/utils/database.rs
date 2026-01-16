use crate::downloader::main::DownloadManager;
use crate::utils::logger;
use crate::utils::types::{DownloadInfo, DownloadState, DownloadType, PartInfo};

use sqlx::{Pool, Row, Sqlite, sqlite::SqlitePoolOptions};
use std::sync::Arc;
use std::time::Duration;
use tokio::time::sleep;
use std::path::{PathBuf, Path};
use uuid::Uuid;
use tokio::sync::Notify;

pub async fn start_database_manager(
    dm: Arc<DownloadManager>,
    shutdown_signal: Arc<Notify>,
    db_done_signal: Arc<Notify>,
    db_path: PathBuf,
) {
    match init_db(&db_path).await {
        Ok(pool) => {
            logger::debug(&format!(
                "Database initialized at {}",
                db_path.display()
            ));

            match load_downloads(&pool).await {
                Ok(downloads) => {
                    logger::debug(&format!(
                        "Loaded {} downloads from DB",
                        downloads.len()
                    ));
                    dm.load_snapshot(downloads).await;
                }
                Err(e) => {
                    logger::error(&format!(
                        "Failed to load downloads from DB: {:?}",
                        e
                    ));
                }
            }

            start_db_loop(pool, dm, shutdown_signal, db_done_signal).await;
        }
        Err(e) => {
            logger::error(&format!(
                "Failed to initialize database: {:?}",
                e
            ));
        }
    }
}

pub async fn load_downloads(pool: &Pool<Sqlite>) -> Result<Vec<DownloadInfo>, sqlx::Error> {
    let rows = sqlx::query(
        r#"
        SELECT id, url, dest, total_size, downloaded, uploaded, state, parts, added_at, updated_at, download_type, torrent_hash, referer
        FROM downloads
        "#
    )
    .fetch_all(pool)
    .await?;

    let mut downloads = Vec::new();
    for row in rows {
        let id_str: String = row.get("id");
        let id = Uuid::parse_str(&id_str).unwrap_or_default();
        let url: String = row.get("url");
        let dest_str: String = row.get("dest");
        let dest = PathBuf::from(dest_str);
        let total_size: Option<i64> = row.get("total_size");
        let total_size = total_size.map(|s| s as u64);
        let downloaded: i64 = row.get("downloaded");
        let downloaded = downloaded as u64;
        let uploaded: i64 = row.get("uploaded");
        let uploaded = uploaded as u64;

        let state_str: String = row.get("state");
        let state = if state_str.contains("Completed") {
            DownloadState::Completed
        } else if state_str.contains("Seeding") {
            DownloadState::Seeding
        } else if state_str.contains("Cancelled") {
            DownloadState::Cancelled
        } else if state_str.contains("Error") {
            DownloadState::Error(state_str)
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

        downloads.push(DownloadInfo {
            id: id,
            url: url,
            dest: dest,
            total_size: total_size,
            downloaded: downloaded,
            uploaded: uploaded,
            uspeed: None,
            state: state,
            history: Vec::new(),
            parts: parts,
            added_at: added_at,
            updated_at: updated_at,
            download_type: download_type,
            torrent_hash: torrent_hash,
            referer: referer,
            category: None,
        });
    }

    Ok(downloads)
}

pub async fn init_db(path: &Path) -> Result<Pool<Sqlite>, sqlx::Error> {
    // Ensure parent directory exists
    if let Some(parent) = path.parent() {
        std::fs::create_dir_all(parent).unwrap_or_default();
    }

    // Create database file if it doesn't exist
    if !path.exists() {
        if let Err(e) = std::fs::File::create(&path) {
            logger::error(&format!(
                "Failed to create db file at {}: {}",
                path.display(),
                e
            ));
            return Err(sqlx::Error::Io(e));
        }
    }

    // Build sqlite URL safely
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

    // Best-effort migrations
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

    Ok(pool)
}

pub async fn start_db_loop(
    pool: Pool<Sqlite>,
    dm: Arc<DownloadManager>,
    shutdown_signal: Arc<Notify>,
    db_done_signal: Arc<Notify>,
) {
    loop {
        tokio::select! {
            _ = sleep(Duration::from_secs(5)) => {},
            _ = shutdown_signal.notified() => {
                logger::debug("Database shutdown signal received, saving...");
                dm.sync_active_workers().await;
                save_downloads(&pool, &dm).await;
                let session_guard = dm.torrent_session.write().await;
                if let Some(session) = session_guard.as_ref() {
                    let _ = session.stop().await;
                }
                db_done_signal.notify_waiters();
                break;
            }
        }

        save_downloads(&pool, &dm).await;
    }
}

pub async fn save_downloads(pool: &Pool<Sqlite>, dm: &Arc<DownloadManager>) {
    // Process pending deletions
    let deletions = dm.drain_pending_deletions().await;
    let mut failed_deletions = Vec::new();
    for id in deletions {
        let id_str = id.to_string();
        if let Err(e) = sqlx::query("DELETE FROM downloads WHERE id = ?")
            .bind(id_str)
            .execute(pool)
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

        let parts = serde_json::to_string(&download.parts).unwrap_or_default();

        let result = sqlx::query(
            r#"
            INSERT INTO downloads (id, url, dest, total_size, downloaded, uploaded, state, parts, added_at, updated_at, download_type, torrent_hash, referer)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(id) DO UPDATE SET
                total_size = excluded.total_size,
                downloaded = excluded.downloaded,
                uploaded = excluded.uploaded,
                state = excluded.state,
                parts = excluded.parts,
                updated_at = excluded.updated_at,
                download_type = excluded.download_type,
                torrent_hash = excluded.torrent_hash,
                referer = excluded.referer;
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
        .execute(pool)
        .await;

        if let Err(e) = result {
            logger::error(&format!("Failed to save download to DB: {:?}", e));
        }
    }
}
