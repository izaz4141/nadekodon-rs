mod main;

use std::{str::from_utf8, sync::Arc, time::Duration};
use uuid::Uuid;
use tokio::time::interval;

use main::{DownloadManager, DownloadWorker, DownloadState, DownloadInfo};
use crate::utils;

use rinf::{DartSignal, RustSignal, debug_print};
use crate::signals::{
    QueryUrl, UrlQueryOutput, DoDownload, 
    GetDownloadList, DownloadList, DownloadGlance,
    GetDownloadDetails, DownloadDetails,
    PauseDownload, ResumeDownload, CancelDownload,
};

/// Function to spawn the single global DownloadManager at startup
pub async fn start_download_manager() -> Arc<DownloadManager> {
    let manager = DownloadManager::new(3);
    manager
}

pub async fn query_url_info() {
    let receiver = QueryUrl::get_dart_signal_receiver();
    while let Some(signal_pack) = receiver.recv().await {
        let data = signal_pack.message;
        let url = data.url;

        match utils::url::get_url_info(&url).await {
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
        match manager.add_download(url.clone(), dest.clone(), 8, 0).await {
            Ok(id) => debug_print!("Spawned worker for {} with id {}", url, id),
            Err(e) => debug_print!("Failed to spawn worker for {}: {:?}", url, e),
        }
    }
}

pub async fn list_downloads(manager: Arc<DownloadManager>) {
    let mut time_interval = tokio::time::interval(Duration::from_secs(1));

    loop {
        time_interval.tick().await;

        let manager = Arc::clone(&manager);
        match manager.list_all().await {
            Ok(list) => {
                let mut download_list = Vec::new();
                for info in list {
                    let state_str = match &info.state {
                        DownloadState::Queued => "Queued".to_string(),
                        DownloadState::Running => "Running".to_string(),
                        DownloadState::Paused => "Paused".to_string(),
                        DownloadState::Completed => "Completed".to_string(),
                        DownloadState::Cancelled => "Cancelled".to_string(),
                        DownloadState::Error(_) => "Error".to_string(),
                    };
                    let speed = utils::helper::calc_speed(info.history);
                    let glance = DownloadGlance {
                        id: info.id.to_string(),
                        name: info.dest
                            .file_name()
                            .and_then(|s| s.to_str())
                            .unwrap_or("")
                            .to_string(),
                        total_size: info.total_size,
                        downloaded: info.downloaded,
                        speed: speed,
                        state: state_str.clone(),
                    };
                    download_list.push(glance);
                }
                DownloadList { list: download_list }.send_signal_to_dart();
            }
            Err(e) => {
                debug_print!("Failed to get download details: {:?}", e);
            }
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
                let speed = utils::helper::calc_speed(info.history);
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
                    threads: info.threads,
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
