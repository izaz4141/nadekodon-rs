use axum::{Json, response::IntoResponse};
use nadekodon_core::signals::{CompareVersionsRequest, CompareVersionsResponse};

#[utoipa::path(
    post,
    path = "/api/nadeko/version/compare",
    tags = ["nadeko.version"],
    security(("ApiKeyAuth" = [])),
    request_body = CompareVersionsRequest,
    responses(
        (status = 200, description = "Comparison result", body = CompareVersionsResponse)
    )
)]
pub async fn handle_compare_versions(
    Json(payload): Json<CompareVersionsRequest>,
) -> impl IntoResponse {
    let latest = nadekodon_core::utils::version::compare_versions(&payload.versions);
    Json(CompareVersionsResponse { latest: latest })
}