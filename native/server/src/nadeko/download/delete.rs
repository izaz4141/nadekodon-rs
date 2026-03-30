use crate::server::SharedState;
use axum::{Json, extract::State, response::IntoResponse};
use serde::Deserialize;
use utoipa::ToSchema;
use uuid::Uuid;

#[derive(Deserialize, ToSchema)]
pub struct DeleteDownloadRequest {
    pub id: String,
    pub delete_file: bool,
}

#[utoipa::path(
    post,
    path = "/api/nadeko/download/delete",
    tags = ["nadeko.download"],
    security(("ApiKeyAuth" = [])),
    request_body = DeleteDownloadRequest,
    responses(
        (status = 200, description = "Download deleted"),
        (status = 400, description = "Invalid ID")
    )
)]
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
