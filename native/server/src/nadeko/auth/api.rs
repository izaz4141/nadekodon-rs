use crate::server::{SharedState, normalize_secret};
use axum::Json;
use axum::extract::State;
use axum::response::IntoResponse;
use axum_extra::extract::CookieJar;
use axum_extra::extract::cookie::SameSite;
use serde_json::json;
use uuid::Uuid;

pub async fn handle_generate_api(
    State(state): State<SharedState>,
    jar: CookieJar,
) -> impl IntoResponse {
    let key = Uuid::new_v4().to_string();
    let cookie = axum_extra::extract::cookie::Cookie::build(("nadeko_api_key", key.clone()))
        .path("/")
        .secure(true)
        .http_only(true)
        .same_site(SameSite::Lax)
        .build();

    let jar = jar.add(cookie);
    {
        let mut cfg = state.config.write().await;
        cfg["server_api_key"] = json!(key.clone());
    }
    *state.api_key.write().await = normalize_secret(&key).to_string();
    let json_response = json!({
        "api_key": state.api_key.read().await.clone()
    });
    (jar, Json(json_response)).into_response()
}
