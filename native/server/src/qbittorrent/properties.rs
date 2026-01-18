use crate::server::SharedState;
use axum::{
    Json,
    extract::{Query, State},
    http::StatusCode,
    response::IntoResponse,
};
use nadekodon_core::utils::helper;
use serde::{Deserialize, Serialize};

#[derive(Deserialize, Debug)]
pub struct TorrentsPropertiesQuery {
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
pub async fn torrents_properties(
    State(state): State<SharedState>,
    Query(query): Query<TorrentsPropertiesQuery>,
) -> impl IntoResponse {
    let downloads = state
        .context
        .dm()
        .await
        .list_all()
        .await
        .unwrap_or_default();

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
