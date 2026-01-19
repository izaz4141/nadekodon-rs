use std::fmt;
use std::path::PathBuf;
use std::sync::Arc;

use tokio::sync::{Notify, RwLock};

use crate::downloader::manager::DownloadManager;
use crate::utils::database::DatabaseManager;
use crate::utils::logger;
use crate::utils::types::DMSettings;

#[derive(Clone)]
pub struct AppContext {
    dm: Arc<RwLock<Option<Arc<DownloadManager>>>>,
    db: Arc<RwLock<Option<Arc<DatabaseManager>>>>,
    pub shutdown_signal: Arc<Notify>,
}

impl fmt::Debug for AppContext {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        f.debug_struct("AppContext")
            .field("dm", &self.dm)
            .field("shutdown_signal", &self.shutdown_signal)
            .finish()
    }
}

impl AppContext {
    pub async fn new(
        dm_client: reqwest::Client,
        dm_settings: DMSettings,
        shutdown_signal: Arc<Notify>,
    ) -> Arc<Self> {
        let context = Arc::new(AppContext {
            dm: Arc::new(RwLock::new(None)),
            db: Arc::new(RwLock::new(None)),
            shutdown_signal,
        });

        let weak_context = Arc::downgrade(&context);
        let dm = DownloadManager::new(dm_client, dm_settings, weak_context).await;

        *context.dm.write().await = Some(dm);

        context
    }

    pub async fn dm(&self) -> Arc<DownloadManager> {
        self.dm
            .read()
            .await
            .as_ref()
            .expect("DownloadManager not initialized")
            .clone()
    }

    pub async fn db(&self) -> Arc<DatabaseManager> {
        self.db
            .read()
            .await
            .as_ref()
            .expect("DatabaseManager not initialized")
            .clone()
    }

    pub async fn start_database_manager(
        self: &Arc<Self>,
        db_path: PathBuf,
        db_done_signal: Arc<Notify>,
    ) -> Result<Arc<DatabaseManager>, sqlx::Error> {
        let pool = DatabaseManager::init_db(&db_path).await?;
        let weak_ctx = Arc::downgrade(self);
        let db = DatabaseManager::new(pool, weak_ctx, self.shutdown_signal.clone(), db_done_signal)
            .await;

        *self.db.write().await = Some(db.clone());

        match db.load_downloads().await {
            Ok(downloads) => {
                logger::debug(&format!("Loaded {} downloads from DB", downloads.len()));
                let dm = self.dm().await;
                dm.load_snapshot(downloads).await;
            }
            Err(e) => {
                logger::error(&format!("Failed to load downloads from DB: {:?}", e));
            }
        }

        // This will keep running until shutdown
        db.clone().run_loop().await;

        Ok(db)
    }

    pub async fn shutdown(&self) {
        self.shutdown_signal.notify_waiters();
        if let Some(dm) = self.dm.read().await.as_ref() {
            dm.shutdown().await;
        }
    }
}
