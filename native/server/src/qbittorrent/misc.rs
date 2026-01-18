use crate::server::SharedState;
use axum::{Form, extract::State, http::StatusCode, response::IntoResponse};
use serde::Deserialize;

#[derive(Deserialize)]
pub struct TorrentsSetShareLimitsForm {
    hashes: String,
    #[serde(rename = "ratioLimit")]
    ratio_limit: Option<f32>,
    #[serde(rename = "seedingTimeLimit")]
    seeding_time_limit: Option<i64>,
    #[serde(rename = "inactiveSeedingTimeLimit")]
    _inactive_seeding_time_limit: Option<i64>,
}

pub async fn torrents_set_share_limits(
    State(state): State<SharedState>,
    Form(query): Form<TorrentsSetShareLimitsForm>,
) -> impl IntoResponse {
    let hashes: Vec<&str> = if query.hashes == "all" {
        Vec::new()
    } else {
        query.hashes.split('|').collect()
    };

    let ratio = match query.ratio_limit {
        Some(-2.0) => None,
        Some(-1.0) => Some(f32::MAX),
        Some(v) => Some(v),
        None => None,
    };

    let time = match query.seeding_time_limit {
        Some(-2) => None,
        Some(-1) => Some(u64::MAX),
        Some(v) => Some(v as u64),
        None => None,
    };

    let torrents = state
        .context
        .dm()
        .await
        .list_torrents(if hashes.is_empty() {
            None
        } else {
            Some(hashes)
        })
        .await;

    for info in torrents {
        if let Some(worker) = state.context.dm().await.get_worker(info.id).await {
            worker.set_seeding_limits(ratio, time).await;
        }
    }

    (StatusCode::OK, "Ok.").into_response()
}
