use crate::server::SharedState;
use axum::{Json, extract::State, response::IntoResponse};
use nadekodon_core::signals::{EncryptRequest, EncryptResponse};
use nadekodon_core::utils::encryption;

#[utoipa::path(
    post,
    path = "/api/nadeko/auth/encrypt",
    tags = ["nadeko.auth"],
    security(("ApiKeyAuth" = [])),
    request_body = EncryptRequest,
    responses(
        (status = 200, description = "Text encrypted successfully", body = EncryptResponse),
        (status = 500, description = "Encryption Failed")
    )
)]
pub async fn handle_encrypt(
    State(state): State<SharedState>,
    Json(req): Json<EncryptRequest>,
) -> impl IntoResponse {
    let master_key = state.master_key.read().await.clone();
    let encrypted_text = match encryption::encrypt(&req.plain_key, &master_key) {
        Ok(encrypted) => encrypted,
        Err(e) => {
            nadekodon_core::utils::logger::error(&format!("Unable to encrypt text: {:#}", &e));
            return (axum::http::StatusCode::INTERNAL_SERVER_ERROR,).into_response();
        }
    };
    Json(EncryptResponse {
        encrypted_key: encrypted_text,
        master_key,
    })
    .into_response()
}
