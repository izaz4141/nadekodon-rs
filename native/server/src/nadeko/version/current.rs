use axum::{Json, extract::Query, response::IntoResponse};
use serde::{Deserialize, Serialize};
use utoipa::{IntoParams, ToSchema};

#[derive(Deserialize, IntoParams)]
pub struct VersionCurrentQuery {
    pub app: String,
}

#[derive(Serialize, ToSchema)]
pub struct VersionCurrentResponse {
    pub version: String,
}

#[utoipa::path(
    get,
    path = "/api/nadeko/version/current",
    tags = ["nadeko.version"],
    security(("ApiKeyAuth" = [])),
    params(VersionCurrentQuery),
    responses(
        (status = 200, description = "Current version", body = VersionCurrentResponse),
        (status = 400, description = "Invalid request"),
        (status = 404, description = "App not found")
    )
)]
pub async fn handle_version_current(
    Query(params): Query<VersionCurrentQuery>,
) -> impl IntoResponse {
    let app = &params.app;

    match nadekodon_core::utils::version::get_local_version(app).await {
        Ok(version) => Json(VersionCurrentResponse { version: version }).into_response(),
        Err(e) => {
            nadekodon_core::utils::logger::error(&format!("Cant get local {}: {:#?}", &app, &e));
            (axum::http::StatusCode::NOT_FOUND, e).into_response()
        }
    }
}
