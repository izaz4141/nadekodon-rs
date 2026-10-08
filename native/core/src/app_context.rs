use std::fmt;
use std::path::PathBuf;
use std::sync::Arc;
use std::time::Duration;

use serde_json::Value;
use tokio::sync::{Notify, RwLock};

use crate::downloader::manager::DownloadManager;
use crate::utils::config::{self, AppConfig};
use crate::utils::database::DatabaseManager;
use crate::utils::logger;
use crate::utils::types::DMSettings;

#[derive(Clone)]
pub struct AppContext {
    dm: Arc<RwLock<Option<Arc<DownloadManager>>>>,
    db: Arc<RwLock<Option<Arc<DatabaseManager>>>>,
    config: Arc<RwLock<Option<Arc<AppConfig>>>>,
    master_key: Arc<RwLock<String>>,
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
            config: Arc::new(RwLock::new(None)),
            master_key: Arc::new(RwLock::new(String::new())),
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

    /// Sets the master key for config secrets. Call before [`Self::init_config`].
    pub async fn set_master_key(&self, master_key: String) {
        *self.master_key.write().await = master_key;
    }

    pub async fn master_key(&self) -> String {
        self.master_key.read().await.clone()
    }

    /// Whether [`AppContext::init_config`] has already loaded a config.
    pub async fn is_config_loaded(&self) -> bool {
        self.config.read().await.is_some()
    }

    /// Loads the config at `path`, bootstrapping defaults when missing.
    /// Returns `true` on first-run bootstrap.
    pub async fn init_config(&self, path: String) -> anyhow::Result<bool> {
        let (app_config, is_first_run) =
            config::load_or_bootstrap(path, self.master_key().await).await?;
        *self.config.write().await = Some(app_config);
        Ok(is_first_run)
    }

    /// Current config, reloaded from disk when externally modified.
    pub async fn cfg(&self) -> Arc<AppConfig> {
        let current = self
            .config
            .read()
            .await
            .clone()
            .unwrap_or_else(|| panic!("No config loaded; call init_config first"));

        let need_reload = match tokio::fs::metadata(&current.path).await {
            Ok(meta) => meta
                .modified()
                .ok()
                .and_then(|m| m.duration_since(std::time::UNIX_EPOCH).ok())
                .map(|d| d.as_secs() > current.mtime)
                .unwrap_or(false),
            Err(_) => false,
        };
        if !need_reload {
            return current;
        }

        let mut write = self.config.write().await;
        match config::load_config(
            current.path.to_string_lossy().into_owned(),
            self.master_key().await,
        )
        .await
        {
            Ok(new_config) => {
                *write = Some(new_config.clone());
                new_config
            }
            Err(e) => {
                logger::error(&format!("Failed to reload config: {}", e));
                current
            }
        }
    }

    /// Persists `settings`: encrypts secrets, writes atomically, refreshes
    /// the in-memory copy.
    pub async fn save_config(&self, settings: &Value) -> anyhow::Result<()> {
        let path = self
            .config
            .read()
            .await
            .as_ref()
            .map(|c| c.path.clone())
            .ok_or_else(|| anyhow::anyhow!("Config not initialized"))?;

        config::save_config(&path, settings, &self.master_key().await).await?;

        let new_config = config::load_config(path.to_string_lossy().into_owned(), self.master_key().await)
            .await?;
        *self.config.write().await = Some(new_config);
        Ok(())
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

        // Wait for the pre-clean so pruned rows aren't restored. Poll (not a
        // one-shot Notify) so an early publish can't be missed.
        {
            let dm = self.dm().await;
            let deadline = std::time::Instant::now() + Duration::from_secs(10);
            loop {
                let ready = dm.pruned_torrent_hashes.read().await.is_some();
                if ready || std::time::Instant::now() >= deadline {
                    if !ready {
                        logger::warn(
                            "Timed out waiting for torrent pre-clean; orphaned torrent rows may remain",
                        );
                    }
                    break;
                }
                tokio::time::sleep(Duration::from_millis(100)).await;
            }
            let pruned_count = dm
                .pruned_torrent_hashes
                .read()
                .await
                .as_ref()
                .map(|s| s.len())
                .unwrap_or(0);
            logger::debug(&format!(
                "Torrent pre-clean reported {} pruned hash(es)",
                pruned_count
            ));
        }

        match db.load_categories().await {
            Ok(categories) => {
                logger::debug(&format!("Loaded {} categories from DB", categories.len()));
                let dm = self.dm().await;
                let mut cats = dm.categories.write().await;
                for (name, info) in categories {
                    cats.entry(name).or_insert(info);
                }
            }
            Err(e) => {
                logger::error(&format!("Failed to load categories from DB: {:?}", e));
            }
        }

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
