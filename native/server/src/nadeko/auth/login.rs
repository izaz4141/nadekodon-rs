use crate::security::{create_jwt_response, validate_jwt_request};
use crate::server::{SharedState, build_jwt_cookie};
use axum::{
    extract::State,
    http::{HeaderMap, StatusCode},
    response::IntoResponse,
};
use axum_extra::{TypedHeader, extract::CookieJar};
use headers::{Authorization, authorization::Basic};
use nadekodon_core::utils::security;
use serde::Serialize;
use utoipa::ToSchema;

#[derive(Serialize, ToSchema)]
pub struct LoginResponse {
    pub api_key: String,
    pub access_token: String,
    pub csrf_token: String,
    pub expires_in: u64,
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
    headers: HeaderMap,
    TypedHeader(Authorization(auth)): TypedHeader<Authorization<Basic>>,
) -> impl IntoResponse {
    let mut authorized = false;

    if validate_jwt_request(&state, &jar, &headers).await.is_ok() {
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

    let username = state.username.read().await.clone();
    let api_key = state.api_key.read().await.clone();
    let jwt_response = create_jwt_response(&state, &username).await.unwrap();
    let jar = build_jwt_cookie(jar, &jwt_response);

    (
        jar,
        axum::Json(LoginResponse {
            api_key,
            access_token: jwt_response.access_token,
            csrf_token: jwt_response.csrf_token,
            expires_in: jwt_response.expires_in,
        }),
    )
        .into_response()
}
