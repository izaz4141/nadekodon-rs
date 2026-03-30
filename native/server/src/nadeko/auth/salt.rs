use axum::response::IntoResponse;
use nadekodon_core::utils::security;

#[utoipa::path(
    get,
    path = "/api/nadeko/auth/generate-salt",
    tags = ["nadeko.auth"],
    security(("ApiKeyAuth" = [])),
    responses(
        (status = 200, description = "Salt generated successfully", body = String)
    )
)]
pub async fn handle_generate_salt() -> impl IntoResponse {
    security::generate_salt()
}
