use crate::server::SharedState;
use axum::{Json, extract::State, response::IntoResponse};
use serde::Deserialize;
use uuid::Uuid;

#[derive(Deserialize)]
pub struct IdRequest {
    id: String,
}

pub async fn handle_cancel_download(
    State(state): State<SharedState>,
    Json(payload): Json<IdRequest>,
) -> impl IntoResponse {
    if let Ok(id) = Uuid::parse_str(&payload.id) {
        let _ = state.context.dm().await.cancel(id).await;
        axum::http::StatusCode::OK
    } else {
        axum::http::StatusCode::BAD_REQUEST
    }
}
