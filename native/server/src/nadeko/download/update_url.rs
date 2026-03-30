use crate::server::SharedState;
use axum::{Json, extract::State, response::IntoResponse};
use serde::Deserialize;
use utoipa::ToSchema;
use uuid::Uuid;

#[derive(Deserialize, ToSchema)]
pub struct UpdateUrlRequest {
    pub id: String,
    pub new_url: String,
}

#[utoipa::path(
    post,
    path = "/api/nadeko/download/update-url",
    tags = ["nadeko.download"],
    security(("ApiKeyAuth" = [])),
    request_body = UpdateUrlRequest,
    responses(
        (status = 200, description = "URL updated"),
        (status = 400, description = "Invalid ID")
    )
)]
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
