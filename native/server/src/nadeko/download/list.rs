use crate::server::SharedState;
use axum::{Json, extract::State, response::IntoResponse};
use nadekodon_core::signals;

pub async fn handle_get_download_list(
    State(state): State<SharedState>,
    Json(payload): Json<signals::GetDownloadList>,
) -> impl IntoResponse {
    match nadekodon_core::downloader::get_download_list_internal(&state.context.dm().await, payload)
        .await
    {
        Ok(list) => Json(list).into_response(),
        Err(e) => (axum::http::StatusCode::INTERNAL_SERVER_ERROR, e.to_string()).into_response(),
    }
}
