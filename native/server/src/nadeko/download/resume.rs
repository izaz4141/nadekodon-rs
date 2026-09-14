use crate::response::{json_error, json_ok};
use crate::server::SharedState;
use axum::{Json, extract::State, response::IntoResponse};
use nadekodon_core::signals::ResumeDownloadRequest;
use uuid::Uuid;

#[utoipa::path(
    post,
    path = "/api/nadeko/download/resume",
    tags = ["nadeko.download"],
    security(("ApiKeyAuth" = [])),
    request_body = ResumeDownloadRequest,
    responses(
        (status = 200, description = "Download resumed"),
        (status = 400, description = "Invalid ID")
    )
)]
pub async fn handle_resume_download(
    State(state): State<SharedState>,
    Json(payload): Json<ResumeDownloadRequest>,
) -> impl IntoResponse {
    if let Ok(id) = Uuid::parse_str(&payload.id) {
        let _ = state.context.dm().await.resume(id).await;
        json_ok().into_response()
    } else {
        json_error(axum::http::StatusCode::BAD_REQUEST, "Invalid ID").into_response()
    }
}