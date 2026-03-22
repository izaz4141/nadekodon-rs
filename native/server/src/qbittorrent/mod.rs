mod add;
mod app;
mod categories;
mod delete;
mod files;
mod info;
mod misc;
mod properties;

use add::*;
use app::*;
use categories::*;
use delete::*;
use files::*;
use info::*;
use misc::*;
use properties::*;

use crate::server::{SharedState, auth_rate_limit_config, secure_compare};
use axum::{
    Form, Router,
    extract::State,
    http::StatusCode,
    response::IntoResponse,
    routing::{get, post},
};
use axum_extra::extract::cookie::{Cookie, CookieJar};
use nadekodon_core::utils::security;
use serde::Deserialize;
use tower_governor::GovernorLayer;

#[derive(Deserialize)]
struct AuthQuery {
    username: String,
    password: String,
}

pub fn get_router(state: SharedState) -> Router<SharedState> {
    let login_router = Router::new()
        .route("/auth/login", post(login))
        .layer(GovernorLayer::new(auth_rate_limit_config()));

    let auth_router = Router::new()
        .route("/app/version", get(app_version))
        .route("/app/webapiVersion", get(webapi_version))
        .route("/app/preferences", get(preferences))
        .route("/torrents/add", post(torrents_add))
        .route("/torrents/info", get(torrents_info))
        .route("/torrents/properties", get(torrents_properties))
        .route("/torrents/files", get(torrents_files))
        .route("/torrents/delete", post(torrents_delete))
        .route("/torrents/setCategory", post(torrents_set_category))
        .route("/torrents/createCategory", post(torrents_create_category))
        .route("/torrents/categories", get(torrents_categories))
        .route("/torrents/setShareLimits", post(torrents_set_share_limits))
        .route("/torrents/topPrio", post(torrents_top_prio))
        .route("/torrents/setForceStart", post(torrents_set_force_start))
        .layer(axum::middleware::from_fn_with_state(state, auth_middleware));

    Router::new().merge(login_router).merge(auth_router)
}

async fn login(
    State(state): State<SharedState>,
    jar: CookieJar,
    Form(auth): Form<AuthQuery>,
) -> impl IntoResponse {
    let current_username = state.username.read().await;
    let current_hash = state.password.read().await;

    if auth.username == *current_username
        && security::validate_password(&current_hash, &auth.password).unwrap_or(false)
    {
        let cookie = Cookie::build(("SID", state.api_key.read().await.clone()))
            .path("/")
            .http_only(true)
            .build();
        (jar.add(cookie), "Ok.").into_response()
    } else {
        (StatusCode::FORBIDDEN, "Fails.").into_response()
    }
}

async fn auth_middleware(
    State(state): State<SharedState>,
    jar: CookieJar,
    req: axum::http::Request<axum::body::Body>,
    next: axum::middleware::Next,
) -> impl IntoResponse {
    if let Some(cookie) = jar.get("SID")
        && secure_compare(cookie.value(), &state.api_key.read().await.clone())
    {
        return next.run(req).await;
    }
    StatusCode::FORBIDDEN.into_response()
}
