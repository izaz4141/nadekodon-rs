use axum::response::IntoResponse;
use nadekodon_core::utils::security;

pub async fn handle_generate_salt() -> impl IntoResponse {
    security::generate_salt()
}
