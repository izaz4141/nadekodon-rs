use crate::server::SharedState;
use axum::{
    extract::{Json, State},
    http::StatusCode,
    response::IntoResponse,
};
use axum_extra::extract::CookieJar;
use nadekodon_core::utils::security;
use serde::Deserialize;

#[derive(Deserialize)]
pub struct LoginRequest {
    username: String,
    password: String,
}

pub async fn handle_login(
    State(state): State<SharedState>,
    jar: CookieJar,
    Json(payload): Json<LoginRequest>,
) -> impl IntoResponse {
    let mut authorized = false;
    if let Some(cookie) = jar.get("nadeko_api_key")
        && cookie.value() == state.api_key.read().await.clone()
    {
        authorized = true;
    }
    if !authorized {
        authorized = match payload {
            LoginRequest { username, password } => {
                let current_username = state.username.read().await;
                let current_hash = state.password.read().await;

                username == *current_username
                    && security::validate_password(&current_hash, &password).unwrap_or(false)
            }
        };
    }

    if !authorized {
        return (
            StatusCode::UNAUTHORIZED,
            Json(serde_json::json!({ "error": "Invalid credentials" })),
        )
            .into_response();
    }

    let cookie = axum_extra::extract::cookie::Cookie::build((
        "nadeko_api_key",
        state.api_key.read().await.clone(),
    ))
    .path("/")
    .secure(true)
    .http_only(true)
    .same_site(axum_extra::extract::cookie::SameSite::Lax)
    .build();

    let jar = jar.add(cookie);

    (
        jar,
        Json(serde_json::json!({
            "api_key": state.api_key.read().await.clone()
        })),
    )
        .into_response()
}
