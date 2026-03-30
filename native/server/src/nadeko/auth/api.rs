use crate::server::{SharedState, build_api_cookie, normalize_secret};
use axum::Json;
use axum::extract::State;
use axum::response::IntoResponse;
use axum_extra::extract::CookieJar;
use serde::Serialize;
use serde_json::json;
use utoipa::ToSchema;
use uuid::Uuid;

#[derive(Serialize, ToSchema)]
pub struct ApiKeyResponse {
    pub api_key: String,
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
    let jar = jar.add(build_api_cookie(&key));
    {
        let mut cfg = state.config.write().await;
        cfg["server_api_key"] = json!(key.clone());
        state.save_config(&cfg.clone());
    }
    *state.api_key.write().await = normalize_secret(&key).to_string();
    let json_response = ApiKeyResponse {
        api_key: state.api_key.read().await.clone(),
    };
    (jar, Json(json_response)).into_response()
}
