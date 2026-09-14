use crate::response::json_error;
use crate::server::SharedState;
use axum::{
    Json,
    extract::{Path, State},
    response::IntoResponse,
};
use nadekodon_core::signals::GetDownloadDetailsResponse;
use serde::Deserialize;
use utoipa::{IntoParams, ToSchema};

#[derive(Deserialize, ToSchema, IntoParams)]
#[into_params(parameter_in = Path)]
pub struct DownloadDetailsPath {
    pub id: String,
}

#[utoipa::path(
    get,
    path = "/api/nadeko/download/details/{id}",
    tags = ["nadeko.download"],
    security(("ApiKeyAuth" = [])),
    params(DownloadDetailsPath),
    responses(
        (status = 200, description = "Download details", body = GetDownloadDetailsResponse),
        (status = 404, description = "Download not found")
    )
)]
pub async fn handle_get_download_details(
    State(state): State<SharedState>,
    Path(payload): Path<DownloadDetailsPath>,
) -> impl IntoResponse {
    match nadekodon_core::downloader::get_download_details_internal(
        &state.context.dm().await,
        &payload.id,
    )
    .await
    {
        Ok(Some(details)) => Json(details).into_response(),
        Ok(None) => json_error(axum::http::StatusCode::NOT_FOUND, "Download not found")
            .into_response(),
        Err(_) => json_error(axum::http::StatusCode::NOT_FOUND, "Download not found")
            .into_response(),
    }
}
