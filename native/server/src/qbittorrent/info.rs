use crate::server::SharedState;
use axum::{
    Json,
    extract::{Query, State},
    response::IntoResponse,
};
use nadekodon_core::utils::helper;
use nadekodon_core::utils::types::DownloadState;
use serde::{Deserialize, Serialize};
use utoipa::{IntoParams, ToSchema};

#[derive(Deserialize, Debug, IntoParams)]
#[into_params(parameter_in = Query)]
pub struct TorrentsInfoQuery {
    pub filter: Option<String>,
    pub category: Option<String>,
    pub tag: Option<String>,
    pub sort: Option<String>,
    pub reverse: Option<bool>,
    pub limit: Option<usize>,
    pub offset: Option<isize>,
    pub hashes: Option<String>,
}

#[derive(Serialize, ToSchema, Clone)]
pub struct TorrentsInfoResponse {
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

#[utoipa::path(
    get,
    path = "/api/qbittorrent/torrents/info",
    tag = "qbit.torrents",
    security(("SIDCookie" = [])),
    params(TorrentsInfoQuery),
    responses(
        (status = 200, description = "Torrent info list", body = Vec<TorrentsInfoResponse>)
    )
)]
pub async fn torrents_info(
    State(state): State<SharedState>,
    Query(query): Query<TorrentsInfoQuery>,
) -> impl IntoResponse {
    let downloads = state
        .context
        .dm()
        .await
        .list_all()
        .await
        .unwrap_or_default();

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
                        DownloadState::Paused
                            | DownloadState::StalledDL
                            | DownloadState::StalledUP
                            | DownloadState::Queued
                            | DownloadState::Completed
                            | DownloadState::Error(_)
                    ),
                    "resumed" => !matches!(d.state, DownloadState::Paused),
                    "stalled" => {
                        matches!(d.state, DownloadState::StalledDL | DownloadState::StalledUP)
                    }
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
                } else if d.category.as_deref() != Some(cat) {
                    return false;
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
                DownloadState::StalledDL => "stalledDL",
                DownloadState::StalledUP => "stalledUP",
                DownloadState::Cancelled => "error",
                DownloadState::Error(_) => "error",
            };

            let last_activity = d.updated_at / 1000;
            let completion_on = if matches!(
                d.state,
                DownloadState::Completed
                    | DownloadState::Seeding
                    | DownloadState::StalledDL
                    | DownloadState::StalledUP
            ) {
                (d.updated_at / 1000) as i64
            } else {
                -1
            };

            let mut content_path = d.dest.to_string_lossy().to_string();
            if d.dest.is_dir()
                && let Ok(mut entries) = tokio::fs::read_dir(&d.dest).await
            {
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
                if count == 1
                    && let Some(path) = first_entry
                {
                    content_path = path.to_string_lossy().to_string();
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
        info_list.len().saturating_sub(offset.unsigned_abs())
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
