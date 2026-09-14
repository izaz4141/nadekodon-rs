use crate::response::{json_error, json_ok};
use crate::server::SharedState;
use axum::{
    extract::State,
    http::StatusCode,
    http::header::{HeaderMap, HeaderName},
    response::IntoResponse,
};
use nadekodon_core::utils::security;

const X_PASSWORD: HeaderName = HeaderName::from_static("x-password");

#[utoipa::path(
    post,
    path = "/api/nadeko/auth/verify-password",
    tags = ["nadeko.auth"],
    security(("ApiKeyAuth" = [])),
    responses(
        (status = 200, description = "Password verified successfully"),
        (status = 401, description = "Invalid password")
    )
)]
pub async fn handle_verify_password(
    State(state): State<SharedState>,
    headers: HeaderMap,
) -> impl IntoResponse {
    let current_hash = state.password.read().await;

    let password = headers
        .get(X_PASSWORD)
        .and_then(|v| v.to_str().ok())
        .unwrap_or_default();

    let is_valid = security::validate_password(&current_hash, password).unwrap_or(false);

    if is_valid {
        json_ok().into_response()
    } else {
        json_error(StatusCode::UNAUTHORIZED, "Invalid password").into_response()
    }
}