use crate::server::SharedState;
use axum::{
    Form, Json, Router,
    extract::{Multipart, Query, State},
    http::StatusCode,
    response::IntoResponse,
    routing::{get, post},
};
use axum_extra::extract::cookie::{Cookie, CookieJar};
use nadekodon_core::utils::types::DownloadState;
use nadekodon_core::utils::{helper, logger, security};
use serde::{Deserialize, Serialize};
use std::collections::HashSet;
use std::path::PathBuf;

#[derive(Deserialize)]
struct AuthQuery {
    username: String,
    password: String,
}

pub fn get_router(state: SharedState) -> Router<SharedState> {
    let auth_router = Router::new()
        .route("/app/version", get(app_version))
        .route("/app/webapiVersion", get(webapi_version))
        .route("/torrents/add", post(torrents_add))
        .route("/torrents/info", get(torrents_info))
        .route("/torrents/properties", get(torrents_properties))
        .route("/torrents/files", get(torrents_files))
        .route("/torrents/delete", post(torrents_delete))
        .layer(axum::middleware::from_fn_with_state(state, auth_middleware));

    Router::new()
        .route("/auth/login", post(login))
        .merge(auth_router)
}

async fn login(
    State(state): State<SharedState>,
    jar: CookieJar,
    Form(auth): Form<AuthQuery>,
) -> impl IntoResponse {
    let current_username = state.username.read().await;
    let current_hash = state.password.read().await;

    if auth.username == *current_username
        && security::validate_password(&current_hash, &auth.password).unwrap_or(false)
    {
        let cookie = Cookie::build(("SID", state.api_key.read().await.clone()))
            .path("/")
            .http_only(true)
            .build();
        (jar.add(cookie), "Ok.").into_response()
    } else {
        (StatusCode::FORBIDDEN, "Fails.").into_response()
    }
}

async fn auth_middleware(
    State(state): State<SharedState>,
    jar: CookieJar,
    req: axum::http::Request<axum::body::Body>,
    next: axum::middleware::Next,
) -> impl IntoResponse {
    if let Some(cookie) = jar.get("SID") {
        if cookie.value() == state.api_key.read().await.clone() {
            return next.run(req).await;
        }
    }
    StatusCode::FORBIDDEN.into_response()
}

async fn app_version() -> &'static str {
    "v4.6.1"
}

async fn webapi_version() -> &'static str {
    "2.8.3"
}

async fn torrents_add(
    State(state): State<SharedState>,
    mut multipart: Multipart,
) -> impl IntoResponse {
    let mut urls = Vec::new();
    let mut torrent_files = Vec::new();
    let mut savepath = None;
    let mut cookie = None;
    let mut category = None;

    // Parse multipart
    while let Ok(Some(field)) = multipart.next_field().await {
        let name = field.name().unwrap_or("").to_string();
        if name == "urls" {
            if let Ok(text) = field.text().await {
                for line in text.lines() {
                    let u = line.trim();
                    if !u.is_empty() {
                        urls.push(u.to_string());
                    }
                }
            }
        } else if name == "torrents" {
            if let Ok(bytes) = field.bytes().await {
                torrent_files.push(bytes.to_vec());
            }
        } else if name == "savepath" {
            if let Ok(text) = field.text().await {
                savepath = Some(text);
            }
        } else if name == "cookie" {
            if let Ok(text) = field.text().await {
                cookie = Some(text);
            }
        } else if name == "category" {
            if let Ok(text) = field.text().await {
                category = Some(text);
            }
        }
    }

    let default_save_dir = {
        let settings = state.dm.settings.read().await;
        settings.download_dir.clone()
    };

    let dest_dir = if let Some(sp) = &savepath {
        PathBuf::from(sp)
    } else {
        PathBuf::from(default_save_dir)
    };

    // Process URLs
    for url in urls {
        let url_info = nadekodon_core::utils::url::get_url_info(
            state.dm.client.clone(),
            &url,
            cookie.clone(),
            None,
            None,
        )
        .await;

        let actual_url = match url_info {
            Ok(info) => info.url,
            Err(_) => url.clone(),
        };

        match state
            .dm
            .add_download(
                actual_url.clone(),
                dest_dir.clone(),
                cookie.clone(),
                None,
                None,
                category.clone(),
            )
            .await
        {
            Ok(id) => logger::debug(&format!(
                "Added download via API: {} (ID: {}) category: {:?}",
                actual_url, id, category
            )),
            Err(e) => logger::error(&format!("Failed to add download via API: {}", e)),
        }
    }

    // Process Torrent Files
    for bytes in torrent_files {
        // Save to temp file
        let temp_hash = uuid::Uuid::new_v4().to_string();
        let temp_path = std::env::temp_dir().join(format!("{}.torrent", temp_hash));

        if let Err(e) = std::fs::write(&temp_path, bytes) {
            logger::error(&format!("Failed to save temp torrent file: {}", e));
            continue;
        }

        let torrent_url = temp_path.to_string_lossy().to_string();

        match state
            .dm
            .add_download(
                torrent_url.clone(),
                dest_dir.clone(),
                None,
                None,
                None,
                category.clone(),
            )
            .await
        {
            Ok(id) => logger::debug(&format!(
                "Added torrent file via API: {} (ID: {}) category: {:?}",
                torrent_url, id, category
            )),
            Err(e) => logger::error(&format!("Failed to add torrent file via API: {}", e)),
        }
    }

    (StatusCode::OK, "Ok.")
}

#[derive(Deserialize, Debug)]
struct TorrentsInfoQuery {
    filter: Option<String>,
    category: Option<String>,
    tag: Option<String>,
    sort: Option<String>,
    reverse: Option<bool>,
    limit: Option<usize>,
    offset: Option<isize>,
    hashes: Option<String>,
}
#[derive(Serialize, Clone)]
struct TorrentsInfoResponse {
    added_on: u64,
    amount_left: u64,
    category: String,
    completed: u64,
    completion_on: i64,
    content_path: String,
    dl_limit: i64,
    dlspeed: u64,
    downloaded: u64,
    eta: i64,
    hash: String,
    last_activity: u64,
    name: String,
    progress: f64,
    ratio: f64,
    save_path: String,
    size: u64,
    state: String,
    tags: String,
    total_size: u64,
    up_limit: i64,
    uploaded: u64,
    upspeed: u64,
}
async fn torrents_info(
    State(state): State<SharedState>,
    Query(query): Query<TorrentsInfoQuery>,
) -> impl IntoResponse {
    let downloads = state.dm.list_all().await.unwrap_or_default();

    // 1. Filtering
    let filtered: Vec<_> = downloads
        .into_iter()
        .filter(|d| d.torrent_hash.is_some())
        .filter(|d| {
            // Filter by hashes
            if let Some(hashes_str) = &query.hashes {
                let hashes: Vec<&str> = hashes_str.split('|').collect();
                let d_hash = d.torrent_hash.as_ref().unwrap(); // Safe because of filter above
                if !hashes.contains(&d_hash.as_str()) {
                    return false;
                }
            }

            // Filter by state
            if let Some(filter) = &query.filter {
                let match_filter = match filter.as_str() {
                    "all" => true,
                    "downloading" => {
                        matches!(d.state, DownloadState::Running)
                    }
                    "seeding" => matches!(d.state, DownloadState::Seeding),
                    "completed" => {
                        matches!(d.state, DownloadState::Completed)
                    }
                    "paused" => matches!(d.state, DownloadState::Paused),
                    "active" => matches!(d.state, DownloadState::Running | DownloadState::Seeding),
                    "inactive" => matches!(
                        d.state,
                        DownloadState::Paused | DownloadState::Queued | DownloadState::Completed
                    ),
                    "resumed" => !matches!(d.state, DownloadState::Paused),
                    "stalled" => false, // We don't have "stalled" state yet
                    "errored" => matches!(d.state, DownloadState::Error(_)),
                    _ => true,
                };
                if !match_filter {
                    return false;
                }
            }

            // Filter by category
            if let Some(cat) = &query.category {
                if cat.is_empty() {
                    if d.category.is_some() {
                        return false;
                    }
                } else {
                    if d.category.as_deref() != Some(cat) {
                        return false;
                    }
                }
            }

            // Filter by tag
            if let Some(tag) = &query.tag {
                if tag.is_empty() {
                    // Assuming no tags yet
                } else {
                    return false; // No tags implemented
                }
            }

            true
        })
        .collect();

    // 2. Mapping
    let mut info_futures = Vec::new();
    for d in filtered {
        info_futures.push(async move {
            let hash = d.torrent_hash.clone().unwrap_or_else(|| d.id.to_string());
            let total_size = d.total_size.unwrap_or(0);
            let downloaded = d.downloaded;
            let progress = if total_size > 0 {
                downloaded as f64 / total_size as f64
            } else if downloaded > 0 {
                1.0
            } else {
                0.0
            };

            let amount_left = total_size.saturating_sub(downloaded);
            let dlspeed = helper::calc_speed(d.history.clone()) as u64;
            let upspeed = d.uspeed.unwrap_or(0.0) as u64;

            let eta = if dlspeed > 0 && amount_left > 0 {
                (amount_left / dlspeed) as i64
            } else if amount_left == 0 {
                0
            } else {
                8640000 // Placeholder for unknown ETA
            };

            let qbt_state = match d.state {
                DownloadState::Queued => "queuedDL",
                DownloadState::Running => "downloading",
                DownloadState::Paused => "pausedDL",
                DownloadState::Completed => "uploading",
                DownloadState::Seeding => "uploading",
                DownloadState::Cancelled => "error",
                DownloadState::Error(_) => "error",
            };

            let last_activity = d.updated_at / 1000;
            let completion_on =
                if matches!(d.state, DownloadState::Completed | DownloadState::Seeding) {
                    (d.updated_at / 1000) as i64
                } else {
                    -1
                };

            let mut content_path = d.dest.to_string_lossy().to_string();
            if d.dest.is_dir() {
                if let Ok(mut entries) = tokio::fs::read_dir(&d.dest).await {
                    let mut first_entry = None;
                    let mut count = 0;
                    while let Ok(Some(entry)) = entries.next_entry().await {
                        count += 1;
                        if count == 1 {
                            first_entry = Some(entry.path());
                        } else {
                            break;
                        }
                    }
                    if count == 1 {
                        if let Some(path) = first_entry {
                            content_path = path.to_string_lossy().to_string();
                        }
                    }
                }
            }

            TorrentsInfoResponse {
                added_on: d.added_at / 1000,
                amount_left,
                category: d.category.unwrap_or_default(),
                completed: downloaded,
                completion_on,
                content_path,
                dl_limit: -1, // Not exposed per-torrent in settings yet
                dlspeed,
                downloaded,
                eta,
                hash,
                last_activity,
                name: d
                    .dest
                    .file_name()
                    .map(|s| s.to_string_lossy().to_string())
                    .unwrap_or(d.url),
                progress,
                ratio: if downloaded > 0 {
                    d.uploaded as f64 / downloaded as f64
                } else {
                    0.0
                },
                save_path: d
                    .dest
                    .parent()
                    .map(|p| p.to_string_lossy().to_string())
                    .unwrap_or_default(),
                size: total_size,
                state: qbt_state.to_string(),
                tags: "".to_string(),
                total_size,
                up_limit: -1,
                uploaded: d.uploaded,
                upspeed,
            }
        });
    }
    let mut info_list: Vec<TorrentsInfoResponse> = futures::future::join_all(info_futures).await;

    // 3. Sorting
    if let Some(sort_key) = &query.sort {
        info_list.sort_by(|a, b| {
            let cmp = match sort_key.as_str() {
                "name" => a.name.cmp(&b.name),
                "size" => a.size.cmp(&b.size),
                "progress" => a
                    .progress
                    .partial_cmp(&b.progress)
                    .unwrap_or(std::cmp::Ordering::Equal),
                "dlspeed" => a.dlspeed.cmp(&b.dlspeed),
                "upspeed" => a.upspeed.cmp(&b.upspeed),
                "added_on" => a.added_on.cmp(&b.added_on),
                "completion_on" => a.completion_on.cmp(&b.completion_on),
                "ratio" => a
                    .ratio
                    .partial_cmp(&b.ratio)
                    .unwrap_or(std::cmp::Ordering::Equal),
                "amount_left" => a.amount_left.cmp(&b.amount_left),
                _ => a.added_on.cmp(&b.added_on),
            };
            if query.reverse.unwrap_or(false) {
                cmp.reverse()
            } else {
                cmp
            }
        });
    }

    // 4. Pagination
    let offset = query.offset.unwrap_or(0);
    let start = if offset >= 0 {
        offset as usize
    } else {
        info_list.len().saturating_sub(offset.abs() as usize)
    };

    let end = if let Some(limit) = query.limit {
        (start + limit).min(info_list.len())
    } else {
        info_list.len()
    };

    let paged_list = if start < info_list.len() {
        info_list[start..end].to_vec()
    } else {
        Vec::new()
    };

    Json(paged_list)
}

#[derive(Deserialize, Debug)]
struct TorrentsPropertiesQuery {
    hash: String,
}

#[derive(Serialize, Clone)]
pub struct TorrentsPropertiesResponse {
    pub save_path: String,
    pub creation_date: i64,
    pub piece_size: i64,
    pub comment: String,
    pub total_wasted: i64,
    pub total_uploaded: i64,
    pub total_uploaded_session: i64,
    pub total_downloaded: i64,
    pub total_downloaded_session: i64,
    pub up_limit: i64,
    pub dl_limit: i64,
    pub time_elapsed: i64,
    pub seeding_time: i64,
    pub nb_connections: i32,
    pub nb_connections_limit: i32,
    pub share_ratio: f64,
    pub addition_date: i64,
    pub completion_date: i64,
    pub created_by: String,
    pub dl_speed_avg: i64,
    pub dl_speed: i64,
    pub eta: i64,
    pub last_seen: i64,
    pub peers: i32,
    pub peers_total: i32,
    pub pieces_have: i32,
    pub pieces_num: i32,
    pub reannounce: i64,
    pub seeds: i32,
    pub seeds_total: i32,
    pub total_size: i64,
    pub up_speed_avg: i64,
    pub up_speed: i64,
    #[serde(rename = "isPrivate")] // qBittorrent uses camelCase for this specific field
    pub is_private: bool,
}
async fn torrents_properties(
    State(state): State<SharedState>,
    Query(query): Query<TorrentsPropertiesQuery>,
) -> impl IntoResponse {
    let downloads = state.dm.list_all().await.unwrap_or_default();

    // Find the specific torrent by hash
    let target_torrent = downloads
        .into_iter()
        .find(|d| d.torrent_hash.as_deref() == Some(&query.hash));

    match target_torrent {
        Some(d) => {
            let amount_left = d.total_size.unwrap_or(0).saturating_sub(d.downloaded) as i64;
            let dlspeed = helper::calc_speed(d.history.clone()) as i64;
            let upspeed = d.uspeed.unwrap_or(0.0) as i64;

            let eta = if dlspeed > 0 && amount_left > 0 {
                (amount_left / dlspeed) as i64
            } else if amount_left == 0 {
                0
            } else {
                -1
            };
            let resp = TorrentsPropertiesResponse {
                save_path: d.dest.to_string_lossy().into_owned(),
                addition_date: (d.added_at / 1000) as i64,
                total_size: d.total_size.unwrap_or(0) as i64,
                creation_date: (d.added_at / 1000) as i64,
                piece_size: -1,
                comment: "".to_string(),
                total_wasted: 0,
                total_uploaded: d.uploaded as i64,
                total_uploaded_session: 0,
                total_downloaded: d.downloaded as i64,
                total_downloaded_session: 0,
                up_limit: -1,
                dl_limit: -1,
                time_elapsed: 0,
                seeding_time: 0,
                nb_connections: 0,
                nb_connections_limit: -1,
                share_ratio: 0.0,
                completion_date: -1,
                created_by: "".to_string(),
                dl_speed_avg: dlspeed.clone(),
                dl_speed: dlspeed,
                eta: eta,
                last_seen: (d.updated_at / 1000) as i64,
                peers: 0,
                peers_total: 0,
                pieces_have: 0,
                pieces_num: 0,
                reannounce: 0,
                seeds: 0,
                seeds_total: 0,
                up_speed_avg: upspeed.clone(),
                up_speed: upspeed,
                is_private: false,
            };
            Json(resp).into_response()
        }
        None => (StatusCode::NOT_FOUND, "Torrent hash was not found").into_response(),
    }
}

#[derive(Deserialize, Debug)]
struct TorrentsFilesQuery {
    hash: String,
    indexes: Option<String>,
}
#[derive(Serialize)]
pub struct TorrentFileResponse {
    pub index: usize,
    pub name: String,
    pub size: u64,
    pub progress: f32,
    pub priority: i32,
    pub is_seed: bool,
    pub piece_range: [usize; 2],
    pub availability: f32,
}
async fn torrents_files(
    State(state): State<SharedState>,
    Query(query): Query<TorrentsFilesQuery>,
) -> impl IntoResponse {
    let session_guard = state.dm.torrent_session.read().await;
    let session = match session_guard.as_ref() {
        Some(s) => s,
        None => {
            return (StatusCode::INTERNAL_SERVER_ERROR, "Session not initialized").into_response();
        }
    };
    let tid = match query.hash.parse() {
        Ok(i) => i,
        _ => return (StatusCode::BAD_REQUEST, "Problem with hash").into_response(),
    };

    let handle = match session.get(librqbit::api::TorrentIdOrHash::Hash(tid)) {
        Some(h) => h,
        None => return (StatusCode::NOT_FOUND, "Torrent not found").into_response(),
    };

    let metadata_guard = handle.metadata.load();
    let info = match metadata_guard.as_ref() {
        Some(i) => i,
        None => {
            return (StatusCode::INTERNAL_SERVER_ERROR, "Metadata not available").into_response();
        }
    };

    let stats = handle.stats();

    let target_indexes: Option<HashSet<usize>> = query
        .indexes
        .as_ref()
        .map(|idx_str| idx_str.split('|').filter_map(|s| s.parse().ok()).collect());

    let files: Vec<TorrentFileResponse> = info
        .file_infos
        .iter()
        .enumerate()
        .filter(|(i, _)| match &target_indexes {
            Some(indexes) => indexes.contains(i),
            None => true,
        })
        .map(|(idx, file)| {
            let file_progress = stats.file_progress.get(idx).copied().unwrap_or(0);
            let progress = if file.len > 0 {
                file_progress as f64 / file.len as f64
            } else {
                0.0
            };
            let piece_range = file.piece_range_usize();

            TorrentFileResponse {
                index: idx,
                name: file.relative_filename.to_string_lossy().to_string(),
                size: file.len,
                progress: progress as f32,
                priority: 0,
                is_seed: stats.finished,
                piece_range: [piece_range.start, piece_range.end.saturating_sub(1)],
                availability: if stats.finished { 1.0 } else { progress as f32 },
            }
        })
        .collect();

    Json(files).into_response()
}

#[derive(Deserialize, Debug)]
struct TorrentsDeleteQuery {
    hashes: String,
    #[serde(rename = "deleteFiles")]
    delete_files: Option<bool>,
}
async fn torrents_delete(
    State(state): State<SharedState>,
    Query(query): Query<TorrentsDeleteQuery>,
) -> impl IntoResponse {
    let hashes: Vec<&str> = query.hashes.split('|').collect();
    let delete_files = query.delete_files.unwrap_or(false);

    let downloads = state.dm.list_all().await.unwrap_or_default();

    for hash in hashes {
        if hash.is_empty() {
            continue;
        }

        let target = downloads
            .iter()
            .find(|d| d.torrent_hash.as_deref() == Some(hash));

        if let Some(d) = target {
            if let Err(e) = state.dm.delete_worker(d.id, delete_files).await {
                logger::error(&format!("Failed to delete torrent {}: {}", hash, e));
            } else {
                logger::debug(&format!(
                    "Deleted torrent: {} (files: {})",
                    hash, delete_files
                ));
            }
        } else {
            logger::error(&format!("Torrent not found for deletion: {}", hash));
            return (StatusCode::NOT_FOUND, "Torrent not found").into_response();
        }
    }

    (StatusCode::OK, "Ok.").into_response()
}
