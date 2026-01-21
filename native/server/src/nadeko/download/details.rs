use crate::server::SharedState;
use axum::{
    Json,
    extract::{Path, State},
    response::IntoResponse,
};

pub async fn handle_get_download_details(
    State(state): State<SharedState>,
    Path(id): Path<String>,
) -> impl IntoResponse {
    match nadekodon_core::downloader::get_download_details_internal(&state.context.dm().await, &id)
        .await
    {
        Ok(Some(details)) => Json(details).into_response(),
        _ => axum::http::StatusCode::NOT_FOUND.into_response(),
    }
}
