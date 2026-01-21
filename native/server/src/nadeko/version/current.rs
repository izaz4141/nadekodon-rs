use axum::{Json, extract::Query, response::IntoResponse};
use serde_json::json;
use std::collections::HashMap;

pub async fn handle_version_current(
    Query(params): Query<HashMap<String, String>>,
) -> impl IntoResponse {
    let app = match params.get("app") {
        Some(v) => v.as_str(),
        None => {
            return (
                axum::http::StatusCode::BAD_REQUEST,
                "Missing app parameter".to_string(),
            )
                .into_response();
        }
    };

    match nadekodon_core::utils::version::get_local_version(app).await {
        Ok(version) => Json(json!({ "version": version })).into_response(),
        Err(e) => {
            nadekodon_core::utils::logger::error(&format!("Cant get local {}: {:#?}", &app, &e));
            (axum::http::StatusCode::NOT_FOUND, e).into_response()
        }
    }
}
