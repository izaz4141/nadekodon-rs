use std::{fs, path::PathBuf, sync::Arc};
use rinf::{DartSignal, RustSignal, SignalPiece, debug_print};

use crate::signals::UpdateSettings;
use crate::utils::types::{
    DMSettings, ServerSettings,
};
use crate::downloader::main::DownloadManager;

pub async fn update_settings(dm: Arc<DownloadManager>) {
    let receiver = UpdateSettings::get_dart_signal_receiver();

    while let Some(signal_pack) = receiver.recv().await {
        let data = signal_pack.message;
        let data_clone = Arc::new(data);

        let dm_old = dm.settings.read().await;
        let dm_new = DMSettings {
            speed_limit: data_clone.speed_limit.unwrap_or(dm_old.speed_limit),
            concurrency_limit: data_clone.concurrency_limit.unwrap_or(dm_old.concurrency_limit),
            download_threads: data_clone.download_threads.unwrap_or(dm_old.download_threads),
            download_timeout: data_clone.download_timeout.unwrap_or(dm_old.download_timeout),
            download_retries: data_clone.download_retries.unwrap_or(dm_old.download_retries),
        };
        drop(dm_old);

        debug_print!("Updated dm settings to {:?}", &dm_new);
        let _ = dm.update_settings(dm_new).await;
        match data_clone.server_port {
            Some(p) => {
                let server_settings = ServerSettings {
                    port: data_clone.server_port,
                };
            }
            None => {}
        }
    }
}