use crate::server::SharedState;
use axum::{Form, extract::State, http::StatusCode, response::IntoResponse};
use serde::{Deserialize, Serialize};
use utoipa::ToSchema;

#[derive(Deserialize, Serialize, ToSchema)]
pub struct TorrentsSetShareLimitsForm {
    pub hashes: String,
    #[serde(rename = "ratioLimit")]
    pub ratio_limit: Option<f32>,
    #[serde(rename = "seedingTimeLimit")]
    pub seeding_time_limit: Option<i64>,
    #[serde(rename = "inactiveSeedingTimeLimit")]
    pub _inactive_seeding_time_limit: Option<i64>,
}

#[utoipa::path(
    post,
    path = "/api/v2/torrents/setShareLimits",
    tag = "qbit.torrents",
    security(("SIDCookie" = [])),
    request_body = TorrentsSetShareLimitsForm,
    responses(
        (status = 200, description = "Share limits set")
    )
)]
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

#[derive(Deserialize, Serialize, ToSchema)]
pub struct TorrentsTopPrioForm {
    pub hashes: String,
}

#[utoipa::path(
    post,
    path = "/api/v2/torrents/topPrio",
    tag = "qbit.torrents",
    security(("SIDCookie" = [])),
    request_body = TorrentsTopPrioForm,
    responses(
        (status = 200, description = "Priority set")
    )
)]
pub async fn torrents_top_prio(
    State(state): State<SharedState>,
    Form(query): Form<TorrentsTopPrioForm>,
) -> impl IntoResponse {
    let hashes: Vec<&str> = if query.hashes == "all" {
        Vec::new()
    } else {
        query.hashes.split('|').collect()
    };

    state.context.dm().await.set_top_priority(hashes).await;

    (StatusCode::OK, "Ok.").into_response()
}

#[derive(Deserialize, Serialize, ToSchema)]
pub struct TorrentsSetForceStartForm {
    pub _hashes: String,
    pub _value: Option<bool>,
}

#[utoipa::path(
    post,
    path = "/api/v2/torrents/setForceStart",
    tag = "qbit.torrents",
    security(("SIDCookie" = [])),
    request_body = TorrentsSetForceStartForm,
    responses(
        (status = 200, description = "Force start set")
    )
)]
pub async fn torrents_set_force_start(
    State(_state): State<SharedState>,
    Form(_query): Form<TorrentsSetForceStartForm>,
) -> impl IntoResponse {
    (StatusCode::OK, "Ok.").into_response()
}
