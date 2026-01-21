use crate::server::SharedState;
use axum::{Json, extract::State, response::IntoResponse};
use nadekodon_core::signals;

pub async fn handle_do_download(
    State(state): State<SharedState>,
    Json(payload): Json<signals::DoDownload>,
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
