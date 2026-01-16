pub mod main;

use crate::signals;
use crate::utils::{
    helper::calc_speed,
    logger,
    types::{DMSettings, DownloadInfo, DownloadState, DownloadType},
    url::get_url_info,
};
pub use main::DownloadManager;

use anyhow::{Result, anyhow};
use reqwest::Client;
use std::sync::Arc;
use std::time::{Duration, SystemTime, UNIX_EPOCH};
use uuid::Uuid;

async fn handle_merge_success(
    manager: &Arc<DownloadManager>,
    video_id: Option<Uuid>,
    audio_id: Option<Uuid>,
    dest: &std::path::PathBuf,
    url: &Option<String>,
    video_dest: Option<&std::path::PathBuf>,
    audio_dest: Option<&std::path::PathBuf>,
    referer: Option<String>,
) -> Result<()> {
    let mut total_size = 0;
    if let Some(vid) = video_id {
        if let Ok(info) = manager.info(vid).await {
            total_size += info.downloaded;
        }
        let _ = manager.delete_worker(vid, true).await;
    }
    if let Some(aid) = audio_id {
        if let Ok(info) = manager.info(aid).await {
            total_size += info.downloaded;
        }
        manager.delete_worker(aid, true).await?;
    }

    let final_info = DownloadInfo {
        id: Uuid::new_v4(),
        url: url.clone().unwrap_or_default(),
        dest: dest.clone(),
        total_size: Some(total_size),
        downloaded: total_size,
        uploaded: 0,
        uspeed: None,
        state: DownloadState::Completed,
        history: Vec::new(),
        parts: Vec::new(),
        added_at: SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .unwrap()
            .as_millis() as u64,
        updated_at: SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .unwrap()
            .as_millis() as u64,
        download_type: DownloadType::YTDLP,
        torrent_hash: None,
        referer,
        category: None,
    };

    manager.load_snapshot(vec![final_info]).await;

    if let Some(v_path) = video_dest {
        tokio::fs::remove_file(v_path).await?;
    }
    if let Some(a_path) = audio_dest {
        tokio::fs::remove_file(a_path).await?;
    }
    Ok(())
}

async fn wait_for_download(manager: Arc<DownloadManager>, id: Uuid) -> Result<()> {
    loop {
        match manager.info(id).await {
            Ok(info) => match info.state {
                DownloadState::Completed => return Ok(()),
                DownloadState::Error(e) => return Err(anyhow!(e)),
                _ => (),
            },
            Err(e) => return Err(anyhow!(e)),
        }
        tokio::time::sleep(Duration::from_secs(1)).await;
    }
}

/// Function to spawn the single global DownloadManager at startup
pub async fn start_download_manager(client: Client) -> Arc<DownloadManager> {
    let settings = DMSettings {
        speed_limit: 0,
        concurrency_limit: 3,
        download_threads: 8,
        download_timeout: 30,
        download_retries: 5,
        seeding_ratio: 1.0,
        seeding_time: 30,
        download_dir: "Downloads".to_string(),
    };
    let manager = DownloadManager::new(client, settings).await;
    manager
}

pub async fn query_url_info_internal(
    client: Client,
    data: signals::QueryUrl,
) -> Result<signals::UrlQueryOutput> {
    let url = data.url;
    let cookie = data.cookie;
    let user_agent = data.user_agent;
    let referer = data.referer;

    let result = tokio::time::timeout(
        Duration::from_secs(20),
        get_url_info(client.clone(), &url, cookie, user_agent, referer),
    )
    .await?;

    match result {
        Ok(info) => {
            let is_webpage = match &info.content_type {
                Some(ct) => {
                    let ct_lower = ct.to_ascii_lowercase();
                    ct_lower.contains("text/html") || ct_lower.contains("application/xhtml+xml")
                }
                None => false,
            };
            Ok(signals::UrlQueryOutput {
                url: info.url,
                name: info.name,
                total_size: info.total_size,
                accept_ranges: info.accept_ranges,
                content_type: info.content_type,
                is_webpage: is_webpage,
                error: false,
            })
        }
        Err(e) => {
            let err_str = format!("Failed to query info for {}: {:?}", url, e);
            logger::error(&err_str);
            Ok(signals::UrlQueryOutput {
                url: url,
                name: err_str,
                total_size: None,
                accept_ranges: false,
                content_type: None,
                is_webpage: false,
                error: true,
            })
        }
    }
}

pub async fn spawn_download_worker_internal(
    manager: &Arc<DownloadManager>,
    data: signals::DoDownload,
) -> Result<()> {
    let mut dest = std::path::PathBuf::from(data.dest);
    let manager = Arc::clone(manager);

    if data.is_ytdl {
        tokio::spawn(async move {
            let video_format = data.video_format;
            let audio_format = data.audio_format;

            let temp_dest_base = dest.clone();

            let mut video_dest: Option<std::path::PathBuf> = None;
            let mut audio_dest: Option<std::path::PathBuf> = None;

            let mut audio_path_base = temp_dest_base.clone();
            let mut video_path_base = temp_dest_base.clone();

            if audio_format.is_some() && video_format.is_some() {
                if let Some(mut file_name) = audio_path_base
                    .file_name()
                    .and_then(|s| s.to_string_lossy().into_owned().into())
                {
                    file_name.push_str("_audio");
                    audio_path_base.set_file_name(file_name);
                }
                if let Some(mut file_name) = video_path_base
                    .file_name()
                    .and_then(|s| s.to_string_lossy().into_owned().into())
                {
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
                match manager
                    .add_download(
                        format.url.clone(),
                        path,
                        None,
                        None,
                        data.referer.clone(),
                        None,
                    )
                    .await
                {
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
                match manager
                    .add_download(
                        format.url.clone(),
                        path,
                        None,
                        None,
                        data.referer.clone(),
                        None,
                    )
                    .await
                {
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

                if cfg!(target_os = "android") {
                    let mut args = Vec::new();
                    if let Some(v_path) = video_dest.as_ref() {
                        args.push("-i".to_string());
                        args.push(v_path.to_string_lossy().to_string());
                    }
                    if let Some(a_path) = audio_dest.as_ref() {
                        args.push("-i".to_string());
                        args.push(a_path.to_string_lossy().to_string());
                    }

                    let is_webm = dest
                        .extension()
                        .and_then(|ext| ext.to_str())
                        .map(|ext| ext.eq_ignore_ascii_case("webm"))
                        .unwrap_or(false);

                    if is_webm {
                        args.push("-c:v".to_string());
                        args.push("copy".to_string());
                        args.push("-c:a".to_string());
                        args.push("libopus".to_string());
                    } else {
                        args.push("-c".to_string());
                        args.push("copy".to_string());
                    }

                    args.push("-map".to_string());
                    args.push("0:v:0".to_string());
                    args.push("-map".to_string());
                    args.push("1:a:0".to_string());
                    args.push("-y".to_string());
                    args.push(dest.to_string_lossy().to_string());

                    match perform_ffmpeg_request_android(args).await {
                        Ok(_) => {
                            logger::debug("Merge successful (Android)");
                            let _ = handle_merge_success(
                                &manager,
                                video_id,
                                audio_id,
                                &dest,
                                &data.url,
                                video_dest.as_ref(),
                                audio_dest.as_ref(),
                                data.referer.clone(),
                            )
                            .await;
                        }
                        Err(e) => {
                            logger::error(&format!("ffmpeg error (Android): {}", e));
                        }
                    }
                } else {
                    let mut command = tokio::process::Command::new("ffmpeg");
                    if let Some(v_path) = video_dest.as_ref() {
                        command.arg("-i").arg(v_path);
                    }
                    if let Some(a_path) = audio_dest.as_ref() {
                        command.arg("-i").arg(a_path);
                    }

                    let is_webm = dest
                        .extension()
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
                                let _ = handle_merge_success(
                                    &manager,
                                    video_id,
                                    audio_id,
                                    &dest,
                                    &data.url,
                                    video_dest.as_ref(),
                                    audio_dest.as_ref(),
                                    data.referer.clone(),
                                )
                                .await;
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
            }
        });
        Ok(())
    } else if let Some(url) = data.url {
        match manager
            .add_download(
                url.clone(),
                dest,
                data.cookie,
                data.user_agent,
                data.referer,
                None,
            )
            .await
        {
            Ok(id) => {
                logger::debug(&format!("Spawned worker for {} with id {}", url, id));
                Ok(())
            }
            Err(e) => {
                logger::error(&format!("Failed to spawn worker for {}: {:?}", url, e));
                Err(e)
            }
        }
    } else {
        Err(anyhow!("Something went wrong at spawning download worker."))
    }
}

pub async fn get_download_list_internal(
    manager: &Arc<DownloadManager>,
    query: signals::GetDownloadList,
) -> Result<signals::DownloadList> {
    match manager.list_all().await {
        Ok(list) => {
            let mut filtered: Vec<DownloadInfo> = list
                .into_iter()
                .filter(|info| {
                    let state_str = info.state.to_string();
                    let matches_status = query.statuses.contains(&state_str.to_string());

                    let matches_search = if let Some(q) = &query.search_query {
                        let q = q.to_lowercase();
                        let name = info
                            .dest
                            .file_name()
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

            let sort_by = query.sort_by.unwrap_or(0);
            let ascending = query.ascending.unwrap_or(false);

            match sort_by {
                1 => {
                    filtered.sort_by(|a, b| {
                        let name_a = a.dest.file_name().and_then(|s| s.to_str()).unwrap_or("");
                        let name_b = b.dest.file_name().and_then(|s| s.to_str()).unwrap_or("");
                        if ascending {
                            name_a.cmp(name_b)
                        } else {
                            name_b.cmp(name_a)
                        }
                    });
                }
                2 => {
                    filtered.sort_by(|a, b| {
                        let size_a = a.total_size.unwrap_or(0);
                        let size_b = b.total_size.unwrap_or(0);
                        if ascending {
                            size_a.cmp(&size_b)
                        } else {
                            size_b.cmp(&size_a)
                        }
                    });
                }
                3 => {
                    filtered.sort_by(|a, b| {
                        let speed_a = calc_speed(a.history.clone()) as u64;
                        let speed_b = calc_speed(b.history.clone()) as u64;
                        if ascending {
                            speed_a.cmp(&speed_b)
                        } else {
                            speed_b.cmp(&speed_a)
                        }
                    });
                }
                _ => {
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

            let anchor_index = if let Some(anchor_id_str) = query.anchor_id {
                filtered
                    .iter()
                    .position(|x| x.id.to_string() == anchor_id_str)
            } else {
                None
            };

            let (start, end) = match anchor_index {
                Some(idx) => {
                    let s = idx.saturating_sub(query.before as usize);
                    let e = (idx + query.after as usize + 1).min(filtered.len());
                    (s, e)
                }
                None => {
                    let s = 0;
                    let e = (query.after as usize + 1).min(filtered.len());
                    (s, e)
                }
            };

            let slice = &filtered[start..end];
            let mut download_list = Vec::new();

            for info in slice {
                let state_str = info.state.to_string();
                let dspeed: f64 = calc_speed(info.history.clone());
                let uspeed: Option<f64> = match info.uspeed {
                    Some(s) => Some(s),
                    _ => None,
                };
                let glance = signals::DownloadGlance {
                    id: info.id.to_string(),
                    download_type: info.download_type.to_string(),
                    name: info
                        .dest
                        .file_name()
                        .and_then(|s| s.to_str())
                        .unwrap_or("")
                        .to_string(),
                    dest: info.dest.to_string_lossy().to_string(),
                    total_size: info.total_size,
                    downloaded: info.downloaded,
                    uploaded: info.uploaded,
                    dspeed: dspeed,
                    uspeed: uspeed,
                    state: state_str,
                    referer: info.referer.clone(),
                };
                download_list.push(glance);
            }

            Ok(signals::DownloadList {
                list: download_list,
                total_count,
                start_index: start as u64,
                tag: query.tag,
            })
        }
        Err(e) => Err(e),
    }
}

pub async fn get_download_details_internal(
    manager: &Arc<DownloadManager>,
    id_str: &str,
) -> Result<Option<signals::DownloadDetails>> {
    let id = Uuid::parse_str(id_str)?;

    match manager.info(id).await {
        Ok(info) => {
            let state_str = info.state.to_string();
            let speed = calc_speed(info.history);
            let mut uploaded = None;
            let mut upload_speed = None;
            let mut peers = None;
            let mut ratio = None;
            let mut eta = None;

            if matches!(info.download_type, DownloadType::Torrent) {
                uploaded = Some(info.uploaded);
                if let Some(hash) = &info.torrent_hash {
                    let session_guard = manager.torrent_session.read().await;
                    if let Some(session) = session_guard.as_ref() {
                        let handle_opt = session.with_torrents(|torrents| {
                            for (_, handle) in torrents {
                                if hex::encode(handle.info_hash().0) == *hash {
                                    return Some(handle.clone());
                                }
                            }
                            None
                        });

                        if let Some(handle) = handle_opt {
                            let stats = handle.stats();
                            if let Some(live_stats) = stats.live {
                                upload_speed =
                                    Some((live_stats.upload_speed.mbps * 125_000.0) as f64);
                                if let Some(duration) = live_stats.time_remaining {
                                    eta = Some(duration.to_string());
                                }
                                peers = Some(live_stats.snapshot.peer_stats.live as u64);
                            }

                            if stats.progress_bytes > 0 {
                                ratio =
                                    Some(stats.uploaded_bytes as f64 / stats.progress_bytes as f64);
                            } else {
                                ratio = Some(0.0);
                            }
                        }
                    }
                }
            }

            Ok(Some(signals::DownloadDetails {
                id: info.id.to_string(),
                name: info
                    .dest
                    .file_name()
                    .and_then(|s| s.to_str())
                    .unwrap_or("")
                    .to_string(),
                url: info.url,
                dest: info.dest.display().to_string(),
                total_size: info.total_size,
                downloaded: info.downloaded,
                speed: speed,
                state: state_str,
                part_info: info
                    .parts
                    .iter()
                    .map(|p| signals::PartInfo {
                        start: p.start,
                        end: p.end,
                        current: p.current,
                    })
                    .collect(),
                uploaded,
                upload_speed,
                peers,
                ratio,
                eta,
                referer: info.referer,
            }))
        }
        Err(e) => {
            logger::error(&format!("Failed to get download details: {:?}", e));
            Err(e)
        }
    }
}

pub async fn perform_ffmpeg_request_android(_args: Vec<String>) -> Result<bool, String> {
    Ok(false)
}
