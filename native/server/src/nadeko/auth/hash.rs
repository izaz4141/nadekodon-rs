use crate::response::json_error;
use axum::{Json, response::IntoResponse};
use nadekodon_core::signals::{HashRequest, HashResponse};
use nadekodon_core::utils::security;

#[utoipa::path(
    post,
    path = "/api/nadeko/auth/hash",
    tags = ["nadeko.auth"],
    security(("ApiKeyAuth" = [])),
    request_body = HashRequest,
    responses(
        (status = 200, description = "Hash generated successfully", body = HashResponse),
        (status = 500, description = "Hashing failed")
    )
)]
pub async fn handle_hashing_password(Json(payload): Json<HashRequest>) -> impl IntoResponse {
    match security::hash_password(&payload.plain_text) {
        Ok(hash) => (
            axum::http::StatusCode::OK,
            Json(HashResponse {
                id: payload.id,
                hashed_text: Some(hash),
            }),
        )
            .into_response(),
        Err(e) => json_error(
            axum::http::StatusCode::INTERNAL_SERVER_ERROR,
            format!("Hashing failed: {}", e),
        )
        .into_response(),
    }
}