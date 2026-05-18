use crate::server::SharedState;
use axum::{
    Json,
    extract::{Query, State},
    http::StatusCode,
    response::IntoResponse,
};
use serde::{Deserialize, Serialize};
use std::collections::HashSet;
use utoipa::{IntoParams, ToSchema};

#[derive(Deserialize, Debug, IntoParams)]
#[into_params(parameter_in = Query)]
pub struct TorrentsFilesQuery {
    pub hash: String,
    pub indexes: Option<String>,
}
#[derive(Serialize, ToSchema)]
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

#[utoipa::path(
    get,
    path = "/api/v2/torrents/files",
    tag = "qbit.torrents",
    security(("SIDCookie" = [])),
    params(TorrentsFilesQuery),
    responses(
        (status = 200, description = "Torrent files", body = Vec<TorrentFileResponse>),
        (status = 400, description = "Invalid hash"),
        (status = 404, description = "Torrent not found")
    )
)]
pub async fn torrents_files(
    State(state): State<SharedState>,
    Query(query): Query<TorrentsFilesQuery>,
) -> impl IntoResponse {
    let dm = state.context.dm().await;
    let session_guard = dm.torrent_session.read().await;
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
