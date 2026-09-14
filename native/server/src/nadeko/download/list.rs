use crate::response::json_error;
use crate::server::SharedState;
use axum::{Json, extract::State, response::IntoResponse};
use nadekodon_core::signals::{GetDownloadListResponse, GetDownloadListRequest};

#[utoipa::path(
    post,
    path = "/api/nadeko/download/list",
    tags = ["nadeko.download"],
    security(("ApiKeyAuth" = [])),
    request_body = GetDownloadListRequest,
    responses(
        (status = 200, description = "Download list", body = GetDownloadListResponse),
        (status = 500, description = "Server error")
    )
)]
pub async fn handle_get_download_list(
    State(state): State<SharedState>,
    Json(payload): Json<GetDownloadListRequest>,
) -> impl IntoResponse {
    match nadekodon_core::downloader::get_download_list_internal(&state.context.dm().await, payload)
        .await
    {
        Ok(list) => Json(list).into_response(),
        Err(e) => json_error(axum::http::StatusCode::INTERNAL_SERVER_ERROR, e.to_string())
            .into_response(),
    }
}
