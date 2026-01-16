extern crate nadekodon_core as core;
use core::downloader::DownloadManager;
use core::signals;
use core::utils::settings::update_settings_internal;

use rinf::DartSignal;
use std::sync::Arc;

use crate::signals::UpdateSettings;
use crate::utils::logger;

pub async fn update_settings(dm: Arc<DownloadManager>) {
    let receiver = UpdateSettings::get_dart_signal_receiver();

    while let Some(signal_pack) = receiver.recv().await {
        let data = signal_pack.message;
        let core_settings = signals::UpdateSettings {
            download_dir: data.download_dir,
            download_retries: data.download_retries,
            download_threads: data.download_threads,
            download_timeout: data.download_timeout,
            seeding_time: data.seeding_time,
            concurrency_limit: data.concurrency_limit,
            seeding_ratio: data.seeding_ratio,
            speed_limit: data.speed_limit,
        };
        let dm_new = update_settings_internal(dm.clone(), core_settings).await;
        logger::debug(&format!("Updated DM Settings to {:?}", &dm_new));
    }
}
