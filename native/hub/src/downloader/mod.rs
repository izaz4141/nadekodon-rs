pub mod main;

use std::{str::from_utf8, sync::Arc, time::Duration};
use reqwest::Client;
use uuid::Uuid;

use main::{DownloadManager};
use crate::utils::{
    types::{
        DMSettings, DownloadState
    },
    url::get_url_info,
    helper::calc_speed,
};

use rinf::{DartSignal, RustSignal, debug_print};
use crate::signals::{
    UpdateSettings,
    QueryUrl, UrlQueryOutput, DoDownload, 
    GetDownloadList, DownloadList, DownloadGlance,
    GetDownloadDetails, DownloadDetails,
    PauseDownload, ResumeDownload, CancelDownload,
};

/// Function to spawn the single global DownloadManager at startup
pub async fn start_download_manager(client: Client) -> Arc<DownloadManager> {
    let settings = DMSettings {
        speed_limit: 0,
        concurrency_limit: 3,
        download_threads: 8,
        download_timeout: 30,
        download_retries: 5,
    };
    let manager = DownloadManager::new(client, settings);
    manager
}

pub async fn query_url_info(client: Client) {
    let receiver = QueryUrl::get_dart_signal_receiver();
    while let Some(signal_pack) = receiver.recv().await {
        let data = signal_pack.message;
        let url = data.url;

        match get_url_info(client.clone(), &url).await {
            Ok(info) => {
                let is_webpage = match &info.content_type {
                    Some(ct) => {
                        let ct_lower = ct.to_ascii_lowercase();
                        ct_lower.contains("text/html")
                            || ct_lower.contains("application/xhtml+xml")
                    }
                    None => false,
                };
                UrlQueryOutput {
                    url: info.url,
                    name: info.name,
                    total_size: info.total_size,
                    accept_ranges: info.accept_ranges,
                    content_type: info.content_type,
                    is_webpage: is_webpage,
                    error: false,
                }.send_signal_to_dart();
            }
            Err(e) => {
                debug_print!("Failed to query info for {}: {:?}", url, e);
                UrlQueryOutput {
                    url: url,
                    name: "Error".to_string(),
                    total_size: None,
                    accept_ranges: false,
                    content_type: None,
                    is_webpage: false,
                    error: true,
                }.send_signal_to_dart();
            },
        }
    }
}


pub async fn spawn_download_worker(manager: Arc<DownloadManager>) {
    let receiver = DoDownload::get_dart_signal_receiver();
    while let Some(signal_pack) = receiver.recv().await {
        let data = signal_pack.message;

        let url = data.url;
        let dest = std::path::PathBuf::from(data.dest);

        let manager = Arc::clone(&manager);
        match manager.add_download(url.clone(), dest).await {
            Ok(id) => debug_print!("Spawned worker for {} with id {}", url, id),
            Err(e) => debug_print!("Failed to spawn worker for {}: {:?}", url, e),
        }
    }
}

pub async fn get_download_details(manager: Arc<DownloadManager>) {
    let receiver = GetDownloadDetails::get_dart_signal_receiver();
    while let Some(signal_pack) = receiver.recv().await {
        let data = signal_pack.message;

        let id = match Uuid::parse_str(&data.id) {
            Ok(uuid) => uuid,
            Err(e) => {
                debug_print!("Invalid UUID from Dart: {:?}", e);
                continue;
            }
        };

        let manager = Arc::clone(&manager);
        match manager.info(id).await {
            Ok(info) => {
                let state_str = match &info.state {
                    DownloadState::Queued => "Queued".to_string(),
                    DownloadState::Running => "Running".to_string(),
                    DownloadState::Paused => "Paused".to_string(),
                    DownloadState::Completed => "Completed".to_string(),
                    DownloadState::Cancelled => "Cancelled".to_string(),
                    DownloadState::Error(e) => format!("Error: {}", e),
                };
                let speed = calc_speed(info.history);
                DownloadDetails {
                    id: info.id.to_string(),
                    name: info.dest
                        .file_name()
                        .and_then(|s| s.to_str())
                        .unwrap_or("").to_string(),
                    url: info.url,
                    dest: info.dest.display().to_string(),
                    total_size: info.total_size,
                    downloaded: info.downloaded,
                    speed: speed,
                    state: state_str,
                }.send_signal_to_dart();
            }
            Err(e) => {
                debug_print!("Failed to get download details: {:?}", e);
            }
        }
    }
}

pub async fn pause_download(manager: Arc<DownloadManager>) {
    let receiver = PauseDownload::get_dart_signal_receiver();
    while let Some(signal_pack) = receiver.recv().await {
        let data = signal_pack.message;

        let id = match Uuid::parse_str(&data.id) {
            Ok(uuid) => uuid,
            Err(e) => {
                debug_print!("Invalid UUID from Dart: {:?}", e);
                continue;
            }
        };

        let manager = Arc::clone(&manager);
        match manager.pause(id).await {
            Ok(_) => debug_print!("Paused worker with id {}", id),
            Err(e) => debug_print!("Failed to pause worker for {:?}", e),
        }
    }
}

pub async fn resume_download(manager: Arc<DownloadManager>) {
    let receiver = ResumeDownload::get_dart_signal_receiver();
    while let Some(signal_pack) = receiver.recv().await {
        let data = signal_pack.message;

        let id = match Uuid::parse_str(&data.id) {
            Ok(uuid) => uuid,
            Err(e) => {
                debug_print!("Invalid UUID from Dart: {:?}", e);
                continue;
            }
        };

        let manager = Arc::clone(&manager);
        match manager.resume(id).await {
            Ok(_) => debug_print!("Resumed worker with id {}", id),
            Err(e) => debug_print!("Failed to resume worker for {:?}", e),
        }
    }
}

pub async fn cancel_download(manager: Arc<DownloadManager>) {
    let receiver = CancelDownload::get_dart_signal_receiver();
    while let Some(signal_pack) = receiver.recv().await {
        let data = signal_pack.message;

        let id = match Uuid::parse_str(&data.id) {
            Ok(uuid) => uuid,
            Err(e) => {
                debug_print!("Invalid UUID from Dart: {:?}", e);
                continue;
            }
        };

        let manager = Arc::clone(&manager);
        match manager.cancel(id).await {
            Ok(_) => debug_print!("Canceled worker with id {}", id),
            Err(e) => debug_print!("Failed to cancel worker for {:?}", e),
        }
    }
}
