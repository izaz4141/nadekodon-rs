use crate::server::SharedState;
use axum::{Json, extract::State, response::IntoResponse};
use nadekodon_core::signals::DoDownload;

#[utoipa::path(
    post,
    path = "/api/nadeko/download/create",
    tags = ["nadeko.download"],
    security(("ApiKeyAuth" = [])),
    request_body = DoDownload,
    responses(
        (status = 200, description = "Download started"),
        (status = 500, description = "Server error")
    )
)]
pub async fn handle_create_download(
    State(state): State<SharedState>,
    Json(payload): Json<DoDownload>,
) -> impl IntoResponse {
    match nadekodon_core::downloader::spawn_download_worker_internal(
        &state.context.dm().await,
        payload,
    )
    .await
    {
        Ok(_) => (axum::http::StatusCode::OK, "Download added".to_string()),
        Err(e) => (axum::http::StatusCode::INTERNAL_SERVER_ERROR, e.to_string()),
    }
}
