use crate::server::{SharedState, build_api_cookie, secure_compare};
use axum::{extract::State, http::StatusCode, response::IntoResponse};
use axum_extra::{TypedHeader, extract::CookieJar};
use headers::{Authorization, authorization::Basic};
use nadekodon_core::utils::security;
use serde::Serialize;
use utoipa::ToSchema;

#[derive(Serialize, ToSchema)]
pub struct LoginResponse {
    pub api_key: String,
}

#[utoipa::path(
    post,
    path = "/api/nadeko/auth/login",
    tags = ["nadeko.auth"],
    security(("BasicAuth" = [])),
    responses(
        (status = 200, description = "Login successful", body = LoginResponse),
        (status = 401, description = "Invalid credentials")
    )
)]
pub async fn handle_login(
    State(state): State<SharedState>,
    jar: CookieJar,
    TypedHeader(Authorization(auth)): TypedHeader<Authorization<Basic>>,
) -> impl IntoResponse {
    let mut authorized = false;
    if let Some(cookie) = jar.get("nadeko_api_key")
        && secure_compare(cookie.value(), &state.api_key.read().await.clone())
    {
        authorized = true;
    }
    if !authorized {
        let username = auth.username();
        let password = auth.password();
        let current_username = state.username.read().await;
        let current_hash = state.password.read().await;

        authorized = username == *current_username
            && security::validate_password(&current_hash, &password).unwrap_or(false);
    }

    if !authorized {
        return (StatusCode::UNAUTHORIZED,).into_response();
    }

    let jar = jar.add(build_api_cookie(&state.api_key.read().await));

    (
        jar,
        axum::Json(LoginResponse {
            api_key: state.api_key.read().await.clone(),
        }),
    )
        .into_response()
}
