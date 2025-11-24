pub mod main;

use std::{str::from_utf8, sync::Arc, time::{Duration, SystemTime, UNIX_EPOCH}};
use reqwest::Client;
use uuid::Uuid;

use main::{DownloadManager};
use crate::utils::{
    types::{
        DMSettings, DownloadState, DownloadInfo
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
    GetDownloadDetails, DownloadDetails, PartInfo,
    PauseDownload, ResumeDownload, CancelDownload, DeleteDownload,
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

                let mut audio_path_base = temp_dest_base.clone();
                let mut video_path_base = temp_dest_base.clone();

                if audio_format.is_some() && video_format.is_some() {
                    if let Some(mut file_name) = audio_path_base.file_name()
                        .and_then(|s| s.to_string_lossy().into_owned().into()) {
                            file_name.push_str("_audio"); 
                            audio_path_base.set_file_name(file_name); 
                    }
                    if let Some(mut file_name) = video_path_base.file_name()
                        .and_then(|s| s.to_string_lossy().into_owned().into()) {
                            file_name.push_str("_video"); 
                            video_path_base.set_file_name(file_name); 
                    }

                    if let Some(format) = &video_format {
                        dest = dest.with_extension(format.ext.clone());
                    }
                }
                
                let audio_id = if let Some(format) = audio_format {
                    let path = audio_path_base.with_extension(format.ext);
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
                    let path = video_path_base.with_extension(format.ext);
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
                    
                    let is_webm = dest.extension()
                        .and_then(|ext| ext.to_str())
                        .map(|ext| ext.eq_ignore_ascii_case("webm"))
                        .unwrap_or(false);
                    
                    if is_webm {
                        command.arg("-c:v").arg("copy");
                        command.arg("-c:a").arg("libopus");
                    } else {
                        command.arg("-c").arg("copy");
                    }
                    
                    command.arg("-map").arg("0:v:0");
                    command.arg("-map").arg("1:a:0");
                    command.arg("-y");
                    command.arg(&dest);
    
                    match command.output().await {
                        Ok(output) => {
                            if output.status.success() {
                                logger::debug("Merge successful");

                                let mut total_size = 0;
                                if let Some(vid) = video_id {
                                    if let Ok(info) = manager.info(vid).await {
                                        total_size += info.downloaded;
                                    }
                                    let _ = manager.delete_worker(vid).await;
                                }
                                if let Some(aid) = audio_id {
                                    if let Ok(info) = manager.info(aid).await {
                                        total_size += info.downloaded;
                                    }
                                    let _ = manager.delete_worker(aid).await;
                                }

                                let final_info = DownloadInfo {
                                    id: Uuid::new_v4(),
                                    url: data.url.clone().unwrap_or_default(),
                                    dest: dest.clone(),
                                    total_size: Some(total_size),
                                    downloaded: total_size,
                                    state: DownloadState::Completed,
                                    history: Vec::new(),
                                    parts: Vec::new(),
                                    added_at: SystemTime::now().duration_since(UNIX_EPOCH).unwrap().as_millis() as u64,
                                    updated_at: SystemTime::now().duration_since(UNIX_EPOCH).unwrap().as_millis() as u64,
                                };
                                
                                manager.load_snapshot(vec![final_info]).await;

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
                    part_info: info.parts.iter().map(|p| PartInfo {
                        start: p.start,
                        end: p.end,
                        current: p.current,
                    }).collect(),
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

pub async fn delete_download(manager: Arc<DownloadManager>) {
    let receiver = DeleteDownload::get_dart_signal_receiver();
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
        manager.delete_worker(id).await;
        logger::debug(&format!("Deleted worker with id {}", id));
    }
}

pub async fn handle_update_download_url(manager: Arc<DownloadManager>) {
    let receiver = crate::signals::UpdateDownloadUrl::get_dart_signal_receiver();
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
        match manager.update_download_url(id, data.new_url.clone()).await {
            Ok(_) => logger::debug(&format!("Updated URL for worker {}", id)),
            Err(e) => logger::error(&format!("Failed to update URL for worker {}: {:?}", id, e)),
        }
    }
}

pub async fn get_download_list(manager: Arc<DownloadManager>) {
    let mut receiver = GetDownloadList::get_dart_signal_receiver();
    while let Some(dart_signal) = receiver.recv().await {
        let query = dart_signal.message;
        
        match manager.list_all().await {
            Ok(list) => {
                // 1. Filter
                let mut filtered: Vec<DownloadInfo> = list.into_iter()
                    .filter(|info| {
                        let state_str = match &info.state {
                            DownloadState::Queued => "Queued",
                            DownloadState::Running => "Running",
                            DownloadState::Paused => "Paused",
                            DownloadState::Completed => "Completed",
                            DownloadState::Cancelled => "Cancelled",
                            DownloadState::Error(_) => "Error",
                        };
                        
                        let matches_status = query.statuses.contains(&state_str.to_string());
                        
                        let matches_search = if let Some(q) = &query.search_query {
                            let q = q.to_lowercase();
                            let name = info.dest.file_name()
                                .and_then(|s| s.to_str())
                                .unwrap_or("")
                                .to_lowercase();
                            let url = info.url.to_lowercase();
                            name.contains(&q) || url.contains(&q)
                        } else {
                            true
                        };

                        matches_status && matches_search
                    })
                    .collect();

                // 2. Sort
                let sort_by = query.sort_by.unwrap_or(0);
                let ascending = query.ascending.unwrap_or(false);

                match sort_by {
                    1 => { // Name
                        filtered.sort_by(|a, b| {
                            let name_a = a.dest.file_name().and_then(|s| s.to_str()).unwrap_or("");
                            let name_b = b.dest.file_name().and_then(|s| s.to_str()).unwrap_or("");
                            if ascending {
                                name_a.cmp(name_b)
                            } else {
                                name_b.cmp(name_a)
                            }
                        });
                    },
                    2 => { // Size
                        filtered.sort_by(|a, b| {
                            let size_a = a.total_size.unwrap_or(0);
                            let size_b = b.total_size.unwrap_or(0);
                            if ascending {
                                size_a.cmp(&size_b)
                            } else {
                                size_b.cmp(&size_a)
                            }
                        });
                    },
                    3 => { // Speed
                        filtered.sort_by(|a, b| {
                            let speed_a = calc_speed(a.history.clone()) as u64;
                            let speed_b = calc_speed(b.history.clone()) as u64;
                            if ascending {
                                speed_a.cmp(&speed_b)
                            } else {
                                speed_b.cmp(&speed_a)
                            }
                        });
                    },
                    _ => { // Date (Insertion Order)
                        filtered.sort_by(|a, b| {
                            if ascending {
                                a.added_at.cmp(&b.added_at)
                            } else {
                                b.added_at.cmp(&a.added_at)
                            }
                        });
                    }
                }

                let total_count = filtered.len() as u64;

                // 3. Find Anchor
                let anchor_index = if let Some(anchor_id_str) = query.anchor_id {
                    filtered.iter().position(|x| x.id.to_string() == anchor_id_str)
                } else {
                    None
                };

                // 4. Calculate Range
                let (start, end) = match anchor_index {
                    Some(idx) => {
                        let s = idx.saturating_sub(query.before as usize);
                        let e = (idx + query.after as usize + 1).min(filtered.len());
                        (s, e)
                    }
                    None => {
                        // If no anchor or anchor not found, start from 0
                        let s = 0;
                        let e = (query.after as usize + 1).min(filtered.len());
                        (s, e)
                    }
                };

                // 5. Slice and Map
                let slice = &filtered[start..end];
                let mut download_list = Vec::new();
                
                for info in slice {
                    let state_str = match &info.state {
                        DownloadState::Queued => "Queued".to_string(),
                        DownloadState::Running => "Running".to_string(),
                        DownloadState::Paused => "Paused".to_string(),
                        DownloadState::Completed => "Completed".to_string(),
                        DownloadState::Cancelled => "Cancelled".to_string(),
                        DownloadState::Error(_) => "Error".to_string(),
                    };
                    let speed = calc_speed(info.history.clone());
                    let glance = DownloadGlance {
                        id: info.id.to_string(),
                        name: info.dest
                            .file_name()
                            .and_then(|s| s.to_str())
                            .unwrap_or("")
                            .to_string(),
                        dest: info.dest.to_string_lossy().to_string(),
                        total_size: info.total_size,
                        downloaded: info.downloaded,
                        speed: speed,
                        state: state_str,
                    };
                    download_list.push(glance);
                }

                DownloadList { 
                    list: download_list,
                    total_count,
                    start_index: start as u64,
                    tag: query.tag,
                }.send_signal_to_dart();
            }
            Err(e) => {
                logger::error(&format!("Failed to get download list: {:?}", e));
            }
        }
    }
}
