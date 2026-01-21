use axum::{Json, response::IntoResponse};
use nadekodon_core::utils::security;
use serde::Deserialize;

#[derive(Deserialize)]
pub struct HashRequest {
    plain_text: String,
    salt: String,
}

pub async fn handle_hashing_password(Json(payload): Json<HashRequest>) -> impl IntoResponse {
    match security::hash_password(&payload.plain_text, &payload.salt) {
        Ok(encrypted) => (axum::http::StatusCode::OK, encrypted).into_response(),
        Err(e) => (axum::http::StatusCode::INTERNAL_SERVER_ERROR, e.to_string()).into_response(),
    }
}
