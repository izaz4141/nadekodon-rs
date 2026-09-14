use crate::response::json_error;
use crate::security::create_jwt_response;
use crate::server::{SharedState, build_jwt_cookie, normalize_secret};
use axum::{
    Json,
    extract::State,
    http::StatusCode,
    http::header::{HeaderMap, HeaderName},
    response::IntoResponse,
};
use axum_extra::extract::CookieJar;
use nadekodon_core::signals::{ChangeCredentialsRequest, ChangeCredentialsResponse};
use nadekodon_core::utils::{logger, security};

const X_PASSWORD: HeaderName = HeaderName::from_static("x-password");

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
        (status = 200, description = "Credentials changed successfully", body = ChangeCredentialsResponse),
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
        return json_error(StatusCode::UNAUTHORIZED, "Invalid current password").into_response();
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
            match security::hash_password(new_password) {
                Ok(hashed) => new_password_hash = hashed,
                Err(e) => {
                    logger::error(&format!("Failed to hash password: {}", e));
                    return json_error(StatusCode::INTERNAL_SERVER_ERROR, "Failed to hash password")
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

    let username = state.username.read().await.clone();
    let jwt_response = create_jwt_response(&state, &username).await.unwrap();
    let jar = build_jwt_cookie(jar, &jwt_response);

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
