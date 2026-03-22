use crate::server::SharedState;
use axum::{Json, extract::State, http::StatusCode, response::IntoResponse};
use nadekodon_core::utils::security;
use serde::Deserialize;

#[derive(Deserialize)]
pub struct VerifyPasswordRequest {
    password: String,
}

pub async fn handle_verify_password(
    State(state): State<SharedState>,
    Json(payload): Json<VerifyPasswordRequest>,
) -> impl IntoResponse {
    let current_hash = state.password.read().await;

    let is_valid = security::validate_password(&current_hash, &payload.password).unwrap_or(false);

    if is_valid {
        (StatusCode::OK, Json(serde_json::json!({ "valid": true }))).into_response()
    } else {
        (
            StatusCode::UNAUTHORIZED,
            Json(serde_json::json!({ "valid": false, "error": "Invalid password" })),
        )
            .into_response()
    }
}
