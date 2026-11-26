use crate::response::json_error;
use crate::server::SharedState;
use axum::{
    Json,
    body::Body,
    extract::{Query, State},
    http::{StatusCode, header},
    response::{IntoResponse, Response},
};
use futures_util::{StreamExt, stream};
use nadekodon_core::signals::{GetDownloadListRequest, GetDownloadListResponse};
use serde::Deserialize;
use std::sync::atomic::Ordering;
use std::time::Duration;
use utoipa::{IntoParams, ToSchema};

const DEFAULT_STREAM_INTERVAL_MS: u64 = 500;
const MIN_STREAM_INTERVAL_MS: u64 = 100;
const MAX_STREAM_INTERVAL_MS: u64 = 10_000;
const DEFAULT_STREAM_MAX_SECONDS: u64 = 600;
const MIN_STREAM_MAX_SECONDS: u64 = 10;
const MAX_STREAM_MAX_SECONDS: u64 = 3600;
const STREAM_TICK_TIMEOUT: Duration = Duration::from_secs(5);

#[utoipa::path(
    post,
    path = "/api/nadeko/download/list",
    tags = ["nadeko.download"],
    security(("ApiKeyAuth" = [])),
    request_body = GetDownloadListRequest,
    responses(
        (status = 200, description = "Download list", body = GetDownloadListResponse),
        (status = 500, description = "Server error")
    )
)]
pub async fn handle_get_download_list(
    State(state): State<SharedState>,
    Json(payload): Json<GetDownloadListRequest>,
) -> impl IntoResponse {
    match nadekodon_core::downloader::get_download_list_internal(&state.context.dm().await, payload)
        .await
    {
        Ok(list) => Json(list).into_response(),
        Err(e) => {
            json_error(axum::http::StatusCode::INTERNAL_SERVER_ERROR, e.to_string()).into_response()
        }
    }
}

#[derive(Debug, Deserialize, IntoParams, ToSchema)]
pub struct DownloadListStreamParams {
    /// Push interval in milliseconds (clamped to 100..=10000). Defaults to 500.
    pub interval_ms: Option<u64>,
    /// Maximum connection lifetime in seconds (clamped to 10..=3600). Defaults to 600.
    pub max_seconds: Option<u64>,
}

#[utoipa::path(
    post,
    path = "/api/nadeko/download/list/stream",
    tags = ["nadeko.download"],
    security(("ApiKeyAuth" = [])),
    params(DownloadListStreamParams),
    request_body = GetDownloadListRequest,
    responses(
        (status = 200, description = "NDJSON stream of download list snapshots", body = String, content_type = "application/x-ndjson"),
        (status = 500, description = "Server error")
    )
)]
pub async fn handle_get_download_list_stream(
    State(state): State<SharedState>,
    Query(params): Query<DownloadListStreamParams>,
    Json(payload): Json<GetDownloadListRequest>,
) -> Response {
    let manager = state.context.dm().await;
    let restart_requested = state.restart_requested.clone();
    let shutdown_requested = state.shutdown_requested.clone();
    let interval_ms = params
        .interval_ms
        .unwrap_or(DEFAULT_STREAM_INTERVAL_MS)
        .clamp(MIN_STREAM_INTERVAL_MS, MAX_STREAM_INTERVAL_MS);
    let max_seconds = params
        .max_seconds
        .unwrap_or(DEFAULT_STREAM_MAX_SECONDS)
        .clamp(MIN_STREAM_MAX_SECONDS, MAX_STREAM_MAX_SECONDS);
    let max_ticks = (max_seconds.saturating_mul(1000) / interval_ms).max(1);

    let mut ticker = tokio::time::interval(Duration::from_millis(interval_ms));
    ticker.set_missed_tick_behavior(tokio::time::MissedTickBehavior::Delay);

    let frames = stream::unfold(
        (
            manager,
            payload,
            ticker,
            restart_requested,
            shutdown_requested,
        ),
        |(manager, payload, mut ticker, restart_requested, shutdown_requested)| async move {
            ticker.tick().await;

            // End long-lived streams promptly when the server is restarting or
            // shutting down, so graceful shutdown does not wait for the cap.
            if restart_requested.load(Ordering::SeqCst) || shutdown_requested.load(Ordering::SeqCst)
            {
                return None;
            }

            let frame = match tokio::time::timeout(
                STREAM_TICK_TIMEOUT,
                nadekodon_core::downloader::get_download_list_internal(&manager, payload.clone()),
            )
            .await
            {
                Ok(Ok(list)) => serde_json::to_string(&list),
                Ok(Err(e)) => serde_json::to_string(&serde_json::json!({
                    "id": payload.id,
                    "error": e.to_string(),
                })),
                Err(_) => serde_json::to_string(&serde_json::json!({
                    "id": payload.id,
                    "error": "Timed out while building download list",
                })),
            };

            match frame {
                Ok(mut line) => {
                    line.push('\n');
                    Some((
                        Ok::<_, std::convert::Infallible>(axum::body::Bytes::from(line)),
                        (
                            manager,
                            payload,
                            ticker,
                            restart_requested,
                            shutdown_requested,
                        ),
                    ))
                }
                Err(e) => {
                    nadekodon_core::utils::logger::error(&format!(
                        "Failed to serialize download list stream frame: {}",
                        e
                    ));
                    None
                }
            }
        },
    )
    .take(max_ticks as usize);

    Response::builder()
        .status(StatusCode::OK)
        .header(header::CONTENT_TYPE, "application/x-ndjson")
        .header(header::CACHE_CONTROL, "no-cache, no-transform")
        .header("X-Accel-Buffering", "no")
        .header(header::X_CONTENT_TYPE_OPTIONS, "nosniff")
        .body(Body::from_stream(frames))
        .unwrap_or_else(|e| {
            nadekodon_core::utils::logger::error(&format!(
                "Failed to build download list stream response: {}",
                e
            ));
            StatusCode::INTERNAL_SERVER_ERROR.into_response()
        })
}
