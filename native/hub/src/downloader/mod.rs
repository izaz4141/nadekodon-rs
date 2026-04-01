// pub mod main;

extern crate nadekodon_core as core;
use crate::signals;
use crate::utils::logger;
use core::downloader;
use core::signals as csignals;
use core::utils::types::{DownloadInfo, DownloadState, DownloadType, WorkerEvent};

use reqwest::Client;
use rinf::{DartSignal, RustSignal};
use std::collections::HashMap;
use std::{
    sync::Arc,
    time::{Duration, SystemTime, UNIX_EPOCH},
};
use tokio::sync::oneshot;
use uuid::Uuid;

static FFMPEG_WAITERS: std::sync::OnceLock<
    std::sync::Mutex<HashMap<String, oneshot::Sender<signals::FfmpegResult>>>,
> = std::sync::OnceLock::new();

pub async fn handle_ffmpeg_results() {
    let receiver = signals::FfmpegResult::get_dart_signal_receiver();
    while let Some(signal_pack) = receiver.recv().await {
        let result = signal_pack.message;
        let waiters_lock = FFMPEG_WAITERS.get_or_init(|| std::sync::Mutex::new(HashMap::new()));
        if let Ok(mut waiters) = waiters_lock.lock()
            && let Some(sender) = waiters.remove(&result.id)
        {
            let _ = sender.send(result);
        }
    }
}

pub async fn perform_ffmpeg_request_android(args: Vec<String>) -> Result<bool, String> {
    let id = Uuid::new_v4().to_string();
    let (tx, rx) = oneshot::channel();

    {
        let waiters_lock = FFMPEG_WAITERS.get_or_init(|| std::sync::Mutex::new(HashMap::new()));
        if let Ok(mut waiters) = waiters_lock.lock() {
            waiters.insert(id.clone(), tx);
        }
    }

    signals::RequestFfmpeg {
        id: id.clone(),
        args,
    }
    .send_signal_to_dart();

    match rx.await {
        Ok(result) => {
            if result.success {
                Ok(true)
            } else {
                Err(result.log)
            }
        }
        Err(e) => Err(format!("Failed to receive ffmpeg result: {:?}", e)),
    }
}

async fn handle_merge_success(
    manager: &Arc<downloader::DownloadManager>,
    video_id: Option<Uuid>,
    audio_id: Option<Uuid>,
    dest: &std::path::PathBuf,
    url: &Option<String>,
    video_dest: Option<&std::path::PathBuf>,
    audio_dest: Option<&std::path::PathBuf>,
    referer: Option<String>,
) {
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
        let _ = manager.delete_worker(aid, true).await;
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
        seeding_ratio_override: None,
        seeding_time_override: None,
    };

    manager.load_snapshot(vec![final_info]).await;

    if let Some(v_path) = video_dest {
        let _ = tokio::fs::remove_file(v_path).await;
    }
    if let Some(a_path) = audio_dest {
        let _ = tokio::fs::remove_file(a_path).await;
    }
}

async fn wait_for_download(
    manager: Arc<downloader::DownloadManager>,
    id: Uuid,
) -> Result<(), String> {
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

pub async fn query_url_info(client: Client) {
    let receiver = signals::QueryUrl::get_dart_signal_receiver();
    while let Some(signal_pack) = receiver.recv().await {
        let data = signal_pack.message;
        let core_query = csignals::QueryUrl {
            url: data.url,
            cookie: data.cookie,
            user_agent: data.user_agent,
            referer: data.referer,
        };
        if let Ok(u) = downloader::query_url_info_internal(client.clone(), core_query).await {
            if u.error {
                logger::error(&u.name);
            }
            signals::UrlQueryOutput {
                name: u.name,
                url: u.url,
                total_size: u.total_size,
                accept_ranges: u.accept_ranges,
                content_type: u.content_type,
                is_webpage: u.is_webpage,
                error: u.error,
            }
            .send_signal_to_dart()
        }
    }
}

pub async fn spawn_download_worker(manager: Arc<downloader::DownloadManager>) {
    let receiver = signals::DoDownload::get_dart_signal_receiver();
    while let Some(signal_pack) = receiver.recv().await {
        let drequest = signal_pack.message;
        let video_format: Option<csignals::YtdlFormat> =
            drequest.video_format.map(|vf| csignals::YtdlFormat {
                format_id: vf.format_id,
                ext: vf.ext,
                filesize: vf.filesize,
                url: vf.url,
                vcodec: vf.vcodec,
                acodec: vf.acodec,
                note: vf.note,
            });
        let audio_format: Option<csignals::YtdlFormat> =
            drequest.audio_format.map(|af| csignals::YtdlFormat {
                format_id: af.format_id,
                ext: af.ext,
                filesize: af.filesize,
                url: af.url,
                vcodec: af.vcodec,
                acodec: af.acodec,
                note: af.note,
            });
        let coredrequest = csignals::DoDownload {
            url: drequest.url.clone(),
            dest: drequest.dest,
            video_format,
            audio_format,
            is_ytdl: drequest.is_ytdl,
            cookie: drequest.cookie,
            user_agent: drequest.user_agent,
            referer: drequest.referer,
        };
        match downloader::spawn_download_worker_internal(&manager, coredrequest).await {
            Ok(_) => logger::debug(&format!("Spawned worker for {:?}", &drequest.url)),
            Err(e) => logger::error(&format!(
                "Failed to spawn worker for {:?}: {:?}",
                &drequest.url, e
            )),
        };
    }
}

pub async fn pause_download(manager: Arc<downloader::DownloadManager>) {
    let receiver = signals::PauseDownload::get_dart_signal_receiver();
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

pub async fn resume_download(manager: Arc<downloader::DownloadManager>) {
    let receiver = signals::ResumeDownload::get_dart_signal_receiver();
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

pub async fn cancel_download(manager: Arc<downloader::DownloadManager>) {
    let receiver = signals::CancelDownload::get_dart_signal_receiver();
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

pub async fn delete_download(manager: Arc<downloader::DownloadManager>) {
    let receiver = signals::DeleteDownload::get_dart_signal_receiver();
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
        let _ = manager.delete_worker(id, data.delete_file).await;
        logger::debug(&format!("Deleted worker with id {}", id));
    }
}

pub async fn handle_update_download_url(manager: Arc<downloader::DownloadManager>) {
    let receiver = signals::UpdateDownloadUrl::get_dart_signal_receiver();
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

pub async fn get_download_details(manager: Arc<downloader::DownloadManager>) {
    let receiver = signals::GetDownloadDetails::get_dart_signal_receiver();
    while let Some(signal_pack) = receiver.recv().await {
        let data = signal_pack.message;
        let manager = Arc::clone(&manager);
        if let Ok(Some(details)) =
            downloader::get_download_details_internal(&manager, &data.id).await
        {
            let part_info: Vec<signals::PartInfo> = details
                .part_info
                .into_iter()
                .map(|p| signals::PartInfo {
                    start: p.start,
                    end: p.end,
                    current: p.current,
                })
                .collect();
            signals::DownloadDetails {
                id: details.id,
                name: details.name,
                url: details.url,
                dest: details.dest,
                total_size: details.total_size,
                downloaded: details.downloaded,
                uploaded: details.uploaded,
                speed: details.speed,
                upload_speed: details.upload_speed,
                state: details.state,
                part_info,
                peers: details.peers,
                ratio: details.ratio,
                eta: details.eta,
                referer: details.referer,
            }
            .send_signal_to_dart();
        }
    }
}

pub async fn get_download_list(manager: Arc<downloader::DownloadManager>) {
    let receiver = signals::GetDownloadList::get_dart_signal_receiver();
    while let Some(dart_signal) = receiver.recv().await {
        let query = dart_signal.message;
        let cquery = csignals::GetDownloadList {
            anchor_id: query.anchor_id,
            before: query.before,
            after: query.after,
            statuses: query.statuses,
            tag: query.tag,
            search_query: query.search_query,
            sort_by: query.sort_by,
            ascending: query.ascending,
        };
        let manager = Arc::clone(&manager);
        match downloader::get_download_list_internal(&manager, cquery).await {
            Ok(list) => {
                let dl: Vec<signals::DownloadGlance> = list
                    .list
                    .into_iter()
                    .map(|p| signals::DownloadGlance {
                        id: p.id,
                        download_type: p.download_type,
                        name: p.name,
                        dest: p.dest,
                        total_size: p.total_size,
                        downloaded: p.downloaded,
                        uploaded: p.uploaded,
                        dspeed: p.dspeed,
                        uspeed: p.uspeed,
                        state: p.state,
                        referer: p.referer,
                    })
                    .collect();
                signals::DownloadList {
                    list: dl,
                    total_count: list.total_count,
                    start_index: list.start_index,
                    tag: list.tag,
                }
                .send_signal_to_dart()
            }
            Err(e) => logger::error(&format!("Failed to get download list: {:?}", e)),
        }
    }
}

pub async fn handle_init_torrent_persistence(manager: Arc<downloader::DownloadManager>) {
    let receiver = signals::InitTorrentPersistence::get_dart_signal_receiver();
    while let Some(signal) = receiver.recv().await {
        let persistence_path = std::path::PathBuf::from(signal.message.path);
        manager.init_torrent_session(persistence_path).await;
    }
}

pub async fn listen_worker_events(manager: Arc<downloader::DownloadManager>) {
    let mut rx = manager.subscribe();
    while let Ok(event) = rx.recv().await {
        match &event {
            WorkerEvent::Completed(id) => {
                logger::debug(&format!("Worker {:?} finished: Completed", id));
            }
            WorkerEvent::Cancelled(id) => {
                logger::debug(&format!("Worker {:?} finished: Cancelled", id));
            }
            WorkerEvent::Error(id, msg) => {
                logger::error(&format!("Worker {:?} finished: Error - {}", id, msg));
            }
        }
    }
}
