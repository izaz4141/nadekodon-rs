use crate::server::SharedState;
use axum::{Json, extract::State, response::IntoResponse};
use serde::Deserialize;
use utoipa::ToSchema;
use uuid::Uuid;

#[derive(Deserialize, ToSchema)]
pub struct IdRequest {
    pub id: String,
}

#[utoipa::path(
    post,
    path = "/api/nadeko/download/pause",
    tags = ["nadeko.download"],
    security(("ApiKeyAuth" = [])),
    request_body = IdRequest,
    responses(
        (status = 200, description = "Download paused"),
        (status = 400, description = "Invalid ID")
    )
)]
pub async fn handle_pause_download(
    State(state): State<SharedState>,
    Json(payload): Json<IdRequest>,
) -> impl IntoResponse {
    if let Ok(id) = Uuid::parse_str(&payload.id) {
        let _ = state.context.dm().await.pause(id).await;
        axum::http::StatusCode::OK
    } else {
        axum::http::StatusCode::BAD_REQUEST
    }
}
