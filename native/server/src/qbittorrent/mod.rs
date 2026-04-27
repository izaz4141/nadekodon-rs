pub mod add;
pub mod app;
pub mod categories;
pub mod delete;
pub mod files;
pub mod info;
pub mod misc;
pub mod properties;

pub use add::{TorrentsAddMultipart, torrents_add};
pub use app::{PreferencesResponse, app_preferences, app_version, app_webapi_version};
pub use categories::{
    CategoryResponse, TorrentsCreateCategoryForm, TorrentsSetCategoryForm, torrents_categories,
    torrents_create_category, torrents_set_category,
};
pub use delete::{TorrentsDeleteQuery, torrents_delete};
pub use files::{TorrentFileResponse, TorrentsFilesQuery, torrents_files};
pub use info::{TorrentsInfoQuery, TorrentsInfoResponse, torrents_info};
pub use misc::{
    TorrentsSetForceStartForm, TorrentsSetShareLimitsForm, TorrentsTopPrioForm,
    torrents_set_force_start, torrents_set_share_limits, torrents_top_prio,
};
pub use properties::{TorrentsPropertiesQuery, TorrentsPropertiesResponse, torrents_properties};

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
use utoipa::ToSchema;

pub fn get_router(state: SharedState) -> Router<SharedState> {
    let login_router = Router::new()
        .route("/auth/login", post(auth_login))
        .layer(GovernorLayer::new(auth_rate_limit_config()));

    let auth_router = Router::new()
        .route("/app/version", get(app_version))
        .route("/app/webapiVersion", get(app_webapi_version))
        .route("/app/preferences", get(app_preferences))
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

#[derive(Deserialize, ToSchema)]
pub struct AuthQuery {
    pub username: String,
    pub password: String,
}

#[utoipa::path(
    post,
    path = "/api/qbittorrent/auth/login",
    tag = "qbit.auth",
    request_body = AuthQuery,
    responses(
        (status = 200, description = "Login successful"),
        (status = 403, description = "Invalid credentials")
    )
)]
pub async fn auth_login(
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
            .secure(true)
            .http_only(true)
            .same_site(axum_extra::extract::cookie::SameSite::Strict)
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
