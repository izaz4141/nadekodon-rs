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

use crate::utils::logger;
use rinf::{DartSignal, RustSignal};
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
                logger::error(&format!("Failed to query info for {}: {:?}", url, e));
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


async fn wait_for_download(manager: Arc<DownloadManager>, id: Uuid) -> Result<(), String> {
    loop {
        match manager.info(id).await {
            Ok(info) => match info.state {
                DownloadState::Completed => return Ok(()),
                DownloadState::Error(e) => return Err(e),
                _ => (),
            },
            Err(e) => return Err(e.to_string()),
        }
        tokio::time::sleep(Duration::from_secs(1)).await;
    }
}

pub async fn spawn_download_worker(manager: Arc<DownloadManager>) {
    let receiver = DoDownload::get_dart_signal_receiver();
    while let Some(signal_pack) = receiver.recv().await {
        let data = signal_pack.message;
        let mut dest = std::path::PathBuf::from(data.dest);
        let manager = Arc::clone(&manager);

        if data.is_ytdl {
            tokio::spawn(async move {
                let video_format = data.video_format;
                let audio_format = data.audio_format;

                let mut temp_dest_base = dest.clone(); 
                
                let mut video_dest: Option<std::path::PathBuf> = None;
                let mut audio_dest: Option<std::path::PathBuf> = None;

                if audio_format.is_some() && video_format.is_some() {

                    if let Some(mut file_name) = temp_dest_base.file_name()
                        .and_then(|s| s.to_string_lossy().into_owned().into()) {
                            file_name.push_str("_part"); 
                            temp_dest_base.set_file_name(file_name); 
                    }
                    if let Some(format) = &video_format {
                        dest = dest.with_extension(format.ext.clone());
                    }
                }
                
                let audio_id = if let Some(format) = audio_format {
                    let path = temp_dest_base.with_extension(format.ext);
                    audio_dest = Some(path.clone());
                    match manager.add_download(format.url.clone(), path).await {
                        Ok(id) => Some(id),
                        Err(e) => {
                            logger::error(&format!("Failed to spawn ytdl audio worker: {:?}", e));
                            None
                        }
                    }
                } else {
                    None
                };

                let video_id = if let Some(format) = video_format {
                    let path = temp_dest_base.with_extension(format.ext);
                    video_dest = Some(path.clone());
                    match manager.add_download(format.url.clone(), path).await {
                        Ok(id) => Some(id),
                        Err(e) => {
                            logger::error(&format!("Failed to spawn ytdl video worker: {:?}", e));
                            None
                        }
                    }
                } else {
                    None
                };

                let mut handles = Vec::new();
                if let Some(vid) = video_id {
                    let manager_clone = Arc::clone(&manager);
                    handles.push(tokio::spawn(async move {
                        wait_for_download(manager_clone, vid).await
                    }));
                }
                if let Some(aid) = audio_id {
                    let manager_clone = Arc::clone(&manager);
                    handles.push(tokio::spawn(async move {
                        wait_for_download(manager_clone, aid).await
                    }));
                }

                for handle in handles {
                    if let Err(e) = handle.await.unwrap() {
                        logger::error(&format!("Download failed: {}", e));
                        return;
                    }
                }

                if video_id.is_some() && audio_id.is_some() {
                    logger::debug("Downloads complete, starting merge");
                    let mut command = tokio::process::Command::new("ffmpeg");
                    if let Some(v_path) = video_dest.as_ref() { 
                        command.arg("-i").arg(v_path);
                    }
                    if let Some(a_path) = audio_dest.as_ref() { 
                        command.arg("-i").arg(a_path);
                    }
                    command.arg("-c").arg("copy");
                    command.arg("-map").arg("0:v:0");
                    command.arg("-map").arg("1:a:0");
                    command.arg("-y");
                    command.arg(&dest);
    
                    match command.output().await {
                        Ok(output) => {
                            if output.status.success() {
                                logger::debug("Merge successful");
                                if let Some(v_path) = video_dest.as_ref() { 
                                    let _ = tokio::fs::remove_file(v_path).await;
                                }
                                if let Some(a_path) = audio_dest.as_ref() { 
                                    let _ = tokio::fs::remove_file(a_path).await;
                                }
                            } else {
                                logger::error(&format!(
                                    "ffmpeg error: {}",
                                    String::from_utf8_lossy(&output.stderr)
                                ));
                            }
                        }
                        Err(e) => {
                            logger::error(&format!("ffmpeg execution failed: {}", e));
                        }
                    }
                }
            });
        } else if let Some(url) = data.url {
            match manager.add_download(url.clone(), dest).await {
                Ok(id) => logger::debug(&format!("Spawned worker for {} with id {}", url, id)),
                Err(e) => {
                    logger::error(&format!("Failed to spawn worker for {}: {:?}", url, e))
                }
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
                logger::error(&format!("Invalid UUID from Dart: {:?}", e));
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
                logger::error(&format!("Failed to get download details: {:?}", e));
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
                logger::error(&format!("Invalid UUID from Dart: {:?}", e));
                continue;
            }
        };

        let manager = Arc::clone(&manager);
        match manager.pause(id).await {
            Ok(_) => logger::debug(&format!("Paused worker with id {}", id)),
            Err(e) => logger::error(&format!("Failed to pause worker for {:?}", e)),
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
                logger::error(&format!("Invalid UUID from Dart: {:?}", e));
                continue;
            }
        };

        let manager = Arc::clone(&manager);
        match manager.resume(id).await {
            Ok(_) => logger::debug(&format!("Resumed worker with id {}", id)),
            Err(e) => logger::error(&format!("Failed to resume worker for {:?}", e)),
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
                logger::error(&format!("Invalid UUID from Dart: {:?}", e));
                continue;
            }
        };

        let manager = Arc::clone(&manager);
        match manager.cancel(id).await {
            Ok(_) => logger::debug(&format!("Canceled worker with id {}", id)),
            Err(e) => logger::error(&format!("Failed to cancel worker for {:?}", e)),
        }
    }
}
