use crate::server::{SharedState, build_api_cookie, normalize_secret};
use axum::{Json, extract::State, http::StatusCode, response::IntoResponse};
use axum_extra::extract::CookieJar;
use nadekodon_core::utils::security;
use serde::Deserialize;

#[derive(Deserialize)]
pub struct ChangeCredentialsRequest {
    current_password: String,
    new_username: Option<String>,
    new_password: Option<String>,
    server_port: Option<u16>,
}

pub async fn handle_change_credentials(
    State(state): State<SharedState>,
    jar: CookieJar,
    Json(payload): Json<ChangeCredentialsRequest>,
) -> impl IntoResponse {
    let current_username = state.username.read().await;
    let current_hash = state.password.read().await.clone();

    let is_valid =
        security::validate_password(&current_hash, &payload.current_password).unwrap_or(false);

    if !is_valid {
        return (
            StatusCode::UNAUTHORIZED,
            Json(serde_json::json!({ "error": "Current password is incorrect" })),
        )
            .into_response();
    }

    let mut new_username = current_username.clone();
    let mut new_password_hash = current_hash.clone();

    if let Some(username) = &payload.new_username {
        if !username.is_empty() {
            new_username = normalize_secret(username).to_string();
        }
    }

    if let Some(password) = &payload.new_password {
        if !password.is_empty() {
            let salt = {
                let config = state.config.read().await;
                config["salt"].as_str().unwrap_or("").to_string()
            };
            match security::hash_password(password, &salt) {
                Ok(hashed) => new_password_hash = hashed,
                Err(e) => {
                    return (
                        StatusCode::INTERNAL_SERVER_ERROR,
                        Json(serde_json::json!({ "error": format!("Failed to hash password: {}", e) })),
                    )
                        .into_response();
                }
            }
        }
    }

    let mut cfg = state.config.write().await;
    cfg["username"] = serde_json::json!(new_username);
    cfg["password"] = serde_json::json!(new_password_hash);

    if let Some(server_port) = payload.server_port {
        cfg["server_port"] = serde_json::json!(server_port);
    }

    let cfg_clone = cfg.clone();
    drop(cfg);

    state.save_config(&cfg_clone);

    *state.username.write().await = new_username;
    *state.password.write().await = new_password_hash;

    let jar = jar.add(build_api_cookie(&state.api_key.read().await));

    (
        jar,
        Json(serde_json::json!({ "success": true, "message": "Credentials updated successfully" })),
    )
        .into_response()
}
