use crate::response::{json_error, json_ok};
use crate::server::SharedState;
use axum::{Json, extract::State, response::IntoResponse};
use nadekodon_core::signals::UpdateDownloadUrlRequest;
use uuid::Uuid;

#[utoipa::path(
    post,
    path = "/api/nadeko/download/update-url",
    tags = ["nadeko.download"],
    security(("ApiKeyAuth" = [])),
    request_body = UpdateDownloadUrlRequest,
    responses(
        (status = 200, description = "URL updated"),
        (status = 400, description = "Invalid ID")
    )
)]
pub async fn handle_update_url(
    State(state): State<SharedState>,
    Json(payload): Json<UpdateDownloadUrlRequest>,
) -> impl IntoResponse {
    if let Ok(id) = Uuid::parse_str(&payload.id) {
        let _ = state
            .context
            .dm()
            .await
            .update_download_url(id, payload.new_url)
            .await;
        json_ok().into_response()
    } else {
        json_error(axum::http::StatusCode::BAD_REQUEST, "Invalid ID").into_response()
    }
}