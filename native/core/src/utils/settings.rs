use std::sync::Arc;

use crate::downloader::manager::DownloadManager;
use crate::signals::UpdateSettings;
use crate::utils::logger;
use crate::utils::types::DMSettings;

pub async fn update_settings_internal(
    dm: Arc<DownloadManager>,
    settings: UpdateSettings,
) -> DMSettings {
    let dm_old = dm.settings.read().await;
    let dm_new = DMSettings {
        speed_limit: settings.speed_limit.unwrap_or(dm_old.speed_limit),
        concurrency_limit: settings
            .concurrency_limit
            .unwrap_or(dm_old.concurrency_limit),
        download_threads: settings.download_threads.unwrap_or(dm_old.download_threads),
        download_timeout: settings.download_timeout.unwrap_or(dm_old.download_timeout),
        download_retries: settings.download_retries.unwrap_or(dm_old.download_retries),
        seeding_ratio: settings.seeding_ratio.unwrap_or(dm_old.seeding_ratio),
        seeding_time: settings.seeding_time.unwrap_or(dm_old.seeding_time),
        download_dir: settings
            .download_dir
            .clone()
            .unwrap_or(dm_old.download_dir.clone()),
        stalled_time: settings.stalled_time.unwrap_or(dm_old.stalled_time),
    };
    drop(dm_old);
    let _ = dm.update_settings(dm_new.clone()).await;
    logger::debug(&format!("Updated DM Settings to {:?}", &dm_new));
    dm_new
}
