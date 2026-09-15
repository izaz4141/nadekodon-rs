use crate::response::json_error;
use crate::server::SharedState;
use axum::{Json, extract::State, response::IntoResponse};
use nadekodon_core::signals::{DoDownloadRequest, DoDownloadResponse};

#[utoipa::path(
    post,
    path = "/api/nadeko/download/create",
    tags = ["nadeko.download"],
    security(("ApiKeyAuth" = [])),
    request_body = DoDownloadRequest,
    responses(
        (status = 200, description = "Download started", body = DoDownloadResponse),
        (status = 500, description = "Server error")
    )
)]
pub async fn handle_create_download(
    State(state): State<SharedState>,
    Json(payload): Json<DoDownloadRequest>,
) -> impl IntoResponse {
    let request_id = payload.id.clone();
    match nadekodon_core::downloader::spawn_download_worker_internal(
        &state.context.dm().await,
        payload,
    )
    .await
    {
        Ok(ids) => Json(DoDownloadResponse {
            id: request_id,
            success: true,
            download_ids: ids.into_iter().map(|id| id.to_string()).collect(),
        })
        .into_response(),
        Err(e) => json_error(axum::http::StatusCode::INTERNAL_SERVER_ERROR, e.to_string())
            .into_response(),
    }
}