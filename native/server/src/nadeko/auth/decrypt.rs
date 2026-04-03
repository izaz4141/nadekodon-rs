use crate::server::{SharedState, get_master_key};
use axum::{Json, extract::State, response::IntoResponse};
use nadekodon_core::signals::{DecryptRequest, DecryptResponse};
use nadekodon_core::utils::encryption;

#[utoipa::path(
    post,
    path = "/api/nadeko/auth/decrypt",
    tags = ["nadeko.auth"],
    security(("ApiKeyAuth" = [])),
    request_body = DecryptRequest,
    responses(
        (status = 200, description = "Key decrypted successfully", body = DecryptResponse),
        (status = 500, description = "Decryption failed"),
    )
)]
pub async fn handle_decrypt(
    State(_state): State<SharedState>,
    Json(req): Json<DecryptRequest>,
) -> impl IntoResponse {
    let master_key = get_master_key();
    let decrypted_key = match encryption::decrypt(&req.encrypted_key, &master_key) {
        Ok(key) => key,
        Err(e) => {
            nadekodon_core::utils::logger::error(&format!("Unable to decrypt key: {:#}", &e));
            return (axum::http::StatusCode::INTERNAL_SERVER_ERROR,).into_response();
        }
    };
    Json(DecryptResponse { decrypted_key }).into_response()
}
