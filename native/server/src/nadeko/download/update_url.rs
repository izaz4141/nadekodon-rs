use crate::server::SharedState;
use axum::{Json, extract::State, response::IntoResponse};
use serde::Deserialize;
use uuid::Uuid;

#[derive(Deserialize)]
pub struct UpdateUrlRequest {
    id: String,
    new_url: String,
}

pub async fn handle_update_url(
    State(state): State<SharedState>,
    Json(payload): Json<UpdateUrlRequest>,
) -> impl IntoResponse {
    if let Ok(id) = Uuid::parse_str(&payload.id) {
        let _ = state
            .context
            .dm()
            .await
            .update_download_url(id, payload.new_url)
            .await;
        axum::http::StatusCode::OK
    } else {
        axum::http::StatusCode::BAD_REQUEST
    }
}
