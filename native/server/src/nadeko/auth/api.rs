use crate::security::create_jwt_response;
use crate::server::{SharedState, build_jwt_cookie, normalize_secret};
use axum::Json;
use axum::extract::State;
use axum::response::IntoResponse;
use axum_extra::extract::CookieJar;
use nadekodon_core::utils::encryption;
use serde::Serialize;
use serde_json::json;
use utoipa::ToSchema;
use uuid::Uuid;

#[derive(Serialize, ToSchema)]
pub struct ApiKeyResponse {
    pub api_key: String,
    pub access_token: String,
    pub csrf_token: String,
    pub expires_in: u64,
}

#[utoipa::path(
    get,
    path = "/api/nadeko/auth/generate-api",
    tags = ["nadeko.auth"],
    security(("ApiKeyAuth" = [])),
    responses(
        (status = 200, description = "API key generated successfully", body = ApiKeyResponse)
    )
)]
pub async fn handle_generate_api(
    State(state): State<SharedState>,
    jar: CookieJar,
) -> impl IntoResponse {
    let key = Uuid::new_v4().to_string();
    let master_key = state.master_key.read().await.clone();
    let encrypted_key = encryption::encrypt(&key, &master_key).unwrap_or_else(|_| key.clone());
    {
        let mut cfg = state.config.write().await;
        cfg["server_api_key"] = json!(encrypted_key);
        state.save_config(&cfg.clone());
    }
    *state.api_key.write().await = normalize_secret(&key).to_string();

    let username = state.username.read().await.clone();
    let jwt_response = create_jwt_response(&state, &username).await.unwrap();
    let jar = build_jwt_cookie(jar, &jwt_response);

    let json_response = ApiKeyResponse {
        api_key: state.api_key.read().await.clone(),
        access_token: jwt_response.access_token,
        csrf_token: jwt_response.csrf_token,
        expires_in: jwt_response.expires_in,
    };
    (jar, Json(json_response)).into_response()
}
