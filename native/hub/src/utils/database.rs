use crate::signals::InitDatabase;
use crate::utils::logger;

extern crate nadekodon_core as core;
use core::downloader::DownloadManager;
use core::utils::database::{init_db, load_downloads, start_db_loop};
use rinf::DartSignal;
use std::sync::Arc;
use tokio::sync::Notify;

pub async fn start_database_manager(
    dm: Arc<DownloadManager>,
    shutdown_signal: Arc<Notify>,
    db_done_signal: Arc<Notify>,
) {
    let receiver = InitDatabase::get_dart_signal_receiver();
    while let Some(signal_pack) = receiver.recv().await {
        let path = signal_pack.message.path;
        let dm = dm.clone();
        let shutdown_signal = shutdown_signal.clone();
        let db_done_signal = db_done_signal.clone();

        tokio::spawn(async move {
            match init_db(&path).await {
                Ok(pool) => {
                    logger::debug(&format!("Database initialized at {}", path));

                    // Load existing downloads
                    match load_downloads(&pool).await {
                        Ok(downloads) => {
                            logger::debug(&format!("Loaded {} downloads from DB", downloads.len()));
                            dm.load_snapshot(downloads).await;
                        }
                        Err(e) => {
                            logger::error(&format!("Failed to load downloads from DB: {:?}", e));
                        }
                    }

                    start_db_loop(pool, dm, shutdown_signal, db_done_signal).await;
                }
                Err(e) => {
                    logger::error(&format!("Failed to initialize database: {:?}", e));
                }
            }
        });
    }
}
