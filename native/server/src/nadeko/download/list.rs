use crate::server::SharedState;
use axum::{Json, extract::State, response::IntoResponse};
use nadekodon_core::signals::{DownloadList, GetDownloadList};

#[utoipa::path(
    post,
    path = "/api/nadeko/download/list",
    tags = ["nadeko.download"],
    security(("ApiKeyAuth" = [])),
    request_body = GetDownloadList,
    responses(
        (status = 200, description = "Download list", body = DownloadList),
        (status = 500, description = "Server error")
    )
)]
pub async fn handle_get_download_list(
    State(state): State<SharedState>,
    Json(payload): Json<GetDownloadList>,
) -> impl IntoResponse {
    match nadekodon_core::downloader::get_download_list_internal(&state.context.dm().await, payload)
        .await
    {
        Ok(list) => Json(list).into_response(),
        Err(e) => (axum::http::StatusCode::INTERNAL_SERVER_ERROR, e.to_string()).into_response(),
    }
}
