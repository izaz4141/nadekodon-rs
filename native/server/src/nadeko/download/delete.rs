use crate::server::SharedState;
use axum::{Json, extract::State, response::IntoResponse};
use serde::Deserialize;
use uuid::Uuid;

#[derive(Deserialize)]
pub struct DeleteDownloadRequest {
    id: String,
    delete_file: bool,
}

pub async fn handle_delete_download(
    State(state): State<SharedState>,
    Json(payload): Json<DeleteDownloadRequest>,
) -> impl IntoResponse {
    if let Ok(id) = Uuid::parse_str(&payload.id) {
        let _ = state
            .context
            .dm()
            .await
            .delete_worker(id, payload.delete_file)
            .await;
        axum::http::StatusCode::OK
    } else {
        axum::http::StatusCode::BAD_REQUEST
    }
}
