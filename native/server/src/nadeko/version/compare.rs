use axum::{Json, response::IntoResponse};
use serde::Deserialize;
use serde_json::json;

#[derive(Deserialize)]
pub struct CompareVersionsRequest {
    versions: Vec<String>,
}

pub async fn handle_compare_versions(
    Json(payload): Json<CompareVersionsRequest>,
) -> impl IntoResponse {
    let latest = nadekodon_core::utils::version::compare_versions(&payload.versions);
    Json(json!({ "latest": latest }))
}
