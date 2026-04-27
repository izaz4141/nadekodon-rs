use crate::server::{SharedState, build_csrf_cookie, build_jwt_cookie, normalize_secret};
use crate::security::create_jwt_response;
use axum::{
    Json,
    extract::State,
    http::StatusCode,
    http::header::{HeaderMap, HeaderName},
    response::IntoResponse,
};
use axum_extra::extract::CookieJar;
use nadekodon_core::utils::{logger, security};
use serde::Deserialize;
use serde::Serialize;
use utoipa::ToSchema;

const X_PASSWORD: HeaderName = HeaderName::from_static("x-password");

#[derive(Deserialize, ToSchema)]
pub struct ChangeCredentialsRequest {
    pub new_username: Option<String>,
    pub new_password: Option<String>,
    pub server_port: Option<u16>,
}

#[derive(Serialize, ToSchema)]
pub struct ChangeCredentialsResponse {
    pub access_token: String,
    pub csrf_token: String,
    pub expires_in: u64,
}

#[utoipa::path(
    post,
    path = "/api/nadeko/auth/change-credentials",
    tags = ["nadeko.auth"],
    security(("ApiKeyAuth" = [])),
    params(
        ("X-Password" = String, Header, description = "Current password"),
    ),
    request_body = ChangeCredentialsRequest,
    responses(
        (status = 200, description = "Credentials changed successfully"),
        (status = 401, description = "Invalid current password"),
        (status = 500, description = "Server error")
    ),
)]
pub async fn handle_change_credentials(
    State(state): State<SharedState>,
    jar: CookieJar,
    headers: HeaderMap,
    Json(payload): Json<ChangeCredentialsRequest>,
) -> impl IntoResponse {
    let current_username = state.username.read().await;
    let current_hash = state.password.read().await.clone();

    let current_password = headers
        .get(X_PASSWORD)
        .and_then(|v| v.to_str().ok())
        .unwrap_or_default();

    let is_valid = security::validate_password(&current_hash, current_password).unwrap_or(false);

    if !is_valid {
        return (StatusCode::UNAUTHORIZED,).into_response();
    }

    let mut new_username = current_username.clone();
    let mut new_password_hash = current_hash.clone();

    if let Some(username) = &payload.new_username {
        if !username.is_empty() {
            new_username = normalize_secret(username).to_string();
        }
    }

    if let Some(new_password) = &payload.new_password {
        if !new_password.is_empty() {
            let salt = {
                let config = state.config.read().await;
                config["salt"].as_str().unwrap_or("").to_string()
            };
            match security::hash_password(new_password, &salt) {
                Ok(hashed) => new_password_hash = hashed,
                Err(e) => {
                    logger::error(&format!("Failed to hash password: {}", e));
                    return (StatusCode::INTERNAL_SERVER_ERROR,).into_response();
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

    let username = state.username.read().await.clone();
    let jwt_response = create_jwt_response(&state, &username).unwrap();
    let mut jar = jar.add(build_jwt_cookie(&jwt_response.access_token));
    jar = jar.add(build_csrf_cookie(&jwt_response.csrf_token));

    (
        StatusCode::OK,
        jar,
        axum::Json(ChangeCredentialsResponse {
            access_token: jwt_response.access_token,
            csrf_token: jwt_response.csrf_token,
            expires_in: jwt_response.expires_in,
        }),
    )
        .into_response()
}
