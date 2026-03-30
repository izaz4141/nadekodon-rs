use axum::{Json, response::IntoResponse};
use nadekodon_core::utils::security;
use serde::Deserialize;
use utoipa::ToSchema;

#[derive(Deserialize, ToSchema)]
pub struct HashRequest {
    pub plain_text: String,
    pub salt: String,
}

#[utoipa::path(
    post,
    path = "/api/nadeko/auth/hash",
    tags = ["nadeko.auth"],
    security(("ApiKeyAuth" = [])),
    request_body = HashRequest,
    responses(
        (status = 200, description = "Hash generated successfully", body = String),
        (status = 500, description = "Hashing failed")
    )
)]
pub async fn handle_hashing_password(Json(payload): Json<HashRequest>) -> impl IntoResponse {
    match security::hash_password(&payload.plain_text, &payload.salt) {
        Ok(encrypted) => (axum::http::StatusCode::OK, encrypted).into_response(),
        Err(e) => (axum::http::StatusCode::INTERNAL_SERVER_ERROR, e.to_string()).into_response(),
    }
}
