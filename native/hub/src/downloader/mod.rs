mod worker;
mod manager;

use std::{sync::Arc};
use worker::DownloadWorker;
use manager::DownloadManager;

use crate::signals::DoDownload;
use rinf::{DartSignal, RustSignal, debug_print};

/// Function to spawn the single global DownloadManager at startup
pub async fn start_download_manager() -> Arc<DownloadManager> {
    let manager = Arc::new(
        DownloadManager::new(
            "nadekodon.sqlite",
            "downloads",
            8, 
            4,               // concurrency
            1024 * 1024 * 5, // max 5 MB/s global speed
        )
        .await
        .expect("Failed to initialize DownloadManager"), // panic if init fails
    );

    manager
}




/// Connector that receives Dart signals and spawns download workers
pub async fn spawn_download_worker(manager: Arc<DownloadManager>) {
    let receiver = DoDownload::get_dart_signal_receiver();
    while let Some(signal_pack) = receiver.recv().await {
        let download_data = signal_pack.message;

        let url = download_data.url;
        let path = download_data.path;

        let m_clone = manager.clone();
        tokio::spawn(async move {
            match m_clone.spawn_worker(&url, &path).await {
                Ok(id) => debug_print!("Spawned worker for {} with id {}", url, id),
                Err(e) => debug_print!("Failed to spawn worker for {}: {:?}", url, e),
            }
        });
    }
}