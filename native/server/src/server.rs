extern crate nadekodon_core as core;
use core::app_context::AppContext;
use core::downloader;
use core::signals;
use core::utils;
use core::utils::logger;

use axum::{
    Router,
    body::Body,
    extract::{Json, Path, Query, State},
    http::{Request, StatusCode},
    middleware::{self, Next},
    response::IntoResponse,
    routing::{get, post},
};
use axum_extra::extract::{
    CookieJar,
    cookie::{Cookie, SameSite},
};
use nadekodon_core::utils::types::DMSettings;
use percent_encoding::percent_decode_str;
use reqwest::Url;
use serde::Deserialize;
use serde_json::{Value, json};
use std::collections::HashMap;
use std::env;
use std::net::SocketAddr;
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::{Arc, OnceLock};
use std::time::Duration;
use tokio::sync::Notify;
use tokio::sync::RwLock;
use uuid::Uuid;

static NADEKO_HOME: OnceLock<String> = OnceLock::new();
pub fn nadeko_home() -> &'static String {
    NADEKO_HOME
        .get_or_init(|| env::var("NADEKO_HOME").unwrap_or_else(|_| "/home/nadeko".to_string()))
}

#[derive(Debug, Clone)]
pub struct AppState {
    pub context: Arc<AppContext>,
    pub api_key: Arc<RwLock<String>>,
    pub username: Arc<RwLock<String>>,
    pub password: Arc<RwLock<String>>,
    pub config: Arc<RwLock<Value>>,
    pub restart_signal: Arc<Notify>,
    pub shutdown_signal: Arc<Notify>,
    pub shutdown_requested: Arc<AtomicBool>,
}
pub type SharedState = Arc<AppState>;

pub fn normalize_secret(s: &str) -> &str {
    let s = s.trim();

    if s.len() >= 2 {
        let b = s.as_bytes();
        if (b[0] == b'"' && b[s.len() - 1] == b'"') || (b[0] == b'\'' && b[s.len() - 1] == b'\'') {
            return &s[1..s.len() - 1];
        }
    }

    s
}

pub fn get_config_path() -> String {
    format!("{}/config/config.json", nadeko_home())
}

pub fn load_config() -> Value {
    let mut cfg = Value::Null;
    if let Ok(content) = std::fs::read_to_string("./assets/docs/default.json")
        && let Ok(mut v) = serde_json::from_str::<Value>(&content)
    {
        v["server_api_key"] = Value::String(Uuid::new_v4().to_string());
        let salt = utils::security::generate_salt();
        v["salt"] = Value::String(salt.clone());
        v["password"] = Value::String(utils::security::hash_password("admin", &salt).unwrap());
        cfg = v;
    }
    let path = get_config_path();
    logger::debug(&format!("Loading config from {}", path));
    if let Ok(content) = std::fs::read_to_string(&path)
        && let Ok(v) = serde_json::from_str(&content)
    {
        cfg = v;
    }
    save_config(&cfg);
    cfg
}

pub fn save_config(settings: &Value) {
    let path = get_config_path();
    let config_dir = format!("{}/config", nadeko_home());
    let _ = std::fs::create_dir_all(&config_dir);
    if let Ok(json_str) = serde_json::to_string_pretty(settings) {
        let _ = std::fs::write(path, json_str);
    }
}

async fn handle_status() -> impl IntoResponse {
    (StatusCode::OK, "Online")
}

pub async fn check_api_key(
    State(state): State<SharedState>,
    jar: CookieJar,
    req: Request<Body>,
    next: Next,
) -> Result<impl IntoResponse, StatusCode> {
    let api_key = state.api_key.read().await.clone();
    // Check header first
    if let Some(key) = req.headers().get("X-API-Key")
        && key.to_str().map(|k| k == api_key).unwrap_or(false)
    {
        return Ok(next.run(req).await);
    }

    // Check cookie
    if let Some(cookie) = jar.get("nadeko_api_key")
        && cookie.value() == api_key
    {
        return Ok(next.run(req).await);
    }

    Err(StatusCode::UNAUTHORIZED)
}

#[derive(Deserialize)]
struct LoginRequest {
    username: String,
    password: String,
}

async fn handle_login(
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
                    && utils::security::validate_password(&current_hash, &password).unwrap_or(false)
            }
        };
    }

    if !authorized {
        return (
            StatusCode::UNAUTHORIZED,
            Json(json!({ "error": "Invalid credentials" })),
        )
            .into_response();
    }

    let cookie = Cookie::build(("nadeko_api_key", state.api_key.read().await.clone()))
        .path("/")
        .secure(true)
        .http_only(true)
        .same_site(SameSite::Lax)
        .build();

    let jar = jar.add(cookie);

    (
        jar,
        Json(json!({
            "api_key": state.api_key.read().await.clone()
        })),
    )
        .into_response()
}

async fn handle_get_download_list(
    State(state): State<SharedState>,
    Json(payload): Json<signals::GetDownloadList>,
) -> impl IntoResponse {
    match downloader::get_download_list_internal(&state.context.dm().await, payload).await {
        Ok(list) => Json(list).into_response(),
        Err(e) => (StatusCode::INTERNAL_SERVER_ERROR, e.to_string()).into_response(),
    }
}

async fn handle_get_download_details(
    State(state): State<SharedState>,
    Path(id): Path<String>,
) -> impl IntoResponse {
    match downloader::get_download_details_internal(&state.context.dm().await, &id).await {
        Ok(Some(details)) => Json(details).into_response(),
        _ => StatusCode::NOT_FOUND.into_response(),
    }
}

async fn handle_do_download(
    State(state): State<SharedState>,
    Json(payload): Json<signals::DoDownload>,
) -> impl IntoResponse {
    match downloader::spawn_download_worker_internal(&state.context.dm().await, payload).await {
        Ok(_) => (StatusCode::OK, "Download added".to_string()),
        Err(e) => (StatusCode::INTERNAL_SERVER_ERROR, e.to_string()),
    }
}

#[derive(Deserialize)]
struct IdRequest {
    id: String,
}

async fn handle_pause_download(
    State(state): State<SharedState>,
    Json(payload): Json<IdRequest>,
) -> impl IntoResponse {
    if let Ok(id) = Uuid::parse_str(&payload.id) {
        let _ = state.context.dm().await.pause(id).await;
        StatusCode::OK
    } else {
        StatusCode::BAD_REQUEST
    }
}

async fn handle_resume_download(
    State(state): State<SharedState>,
    Json(payload): Json<IdRequest>,
) -> impl IntoResponse {
    if let Ok(id) = Uuid::parse_str(&payload.id) {
        let _ = state.context.dm().await.resume(id).await;
        StatusCode::OK
    } else {
        StatusCode::BAD_REQUEST
    }
}

#[derive(Deserialize)]
struct UpdateUrlRequest {
    id: String,
    new_url: String,
}

async fn handle_update_url(
    State(state): State<SharedState>,
    Json(payload): Json<UpdateUrlRequest>,
) -> impl IntoResponse {
    if let Ok(id) = Uuid::parse_str(&payload.id) {
        let _ = state
            .context
            .dm()
            .await
            .update_download_url(id, payload.new_url)
            .await;
        StatusCode::OK
    } else {
        StatusCode::BAD_REQUEST
    }
}

async fn handle_cancel_download(
    State(state): State<SharedState>,
    Json(payload): Json<IdRequest>,
) -> impl IntoResponse {
    if let Ok(id) = Uuid::parse_str(&payload.id) {
        let _ = state.context.dm().await.cancel(id).await;
        StatusCode::OK
    } else {
        StatusCode::BAD_REQUEST
    }
}

#[derive(Deserialize)]
struct DeleteDownloadRequest {
    id: String,
    delete_file: bool,
}

async fn handle_delete_download(
    State(state): State<SharedState>,
    Json(payload): Json<DeleteDownloadRequest>,
) -> impl IntoResponse {
    if let Ok(id) = Uuid::parse_str(&payload.id) {
        let _ = state
            .context
            .dm()
            .await
            .delete_worker(id, payload.delete_file)
            .await;
        StatusCode::OK
    } else {
        StatusCode::BAD_REQUEST
    }
}

async fn handle_restart(State(state): State<SharedState>) -> impl IntoResponse {
    state.restart_signal.notify_one();
    StatusCode::OK
}

async fn handle_query_url(
    State(state): State<SharedState>,
    Json(payload): Json<signals::QueryUrl>,
) -> impl IntoResponse {
    match downloader::query_url_info_internal(state.context.dm().await.client.clone(), payload)
        .await
    {
        Ok(info) => Json(info).into_response(),
        Err(e) => (StatusCode::INTERNAL_SERVER_ERROR, e.to_string()).into_response(),
    }
}

async fn handle_query_ytdl(Json(payload): Json<signals::QueryYtdl>) -> impl IntoResponse {
    match utils::ytdlp::get_ytdl_info(&payload.url).await {
        Ok(info) => Json(info).into_response(),
        Err(e) => (StatusCode::INTERNAL_SERVER_ERROR, e).into_response(),
    }
}

#[derive(Deserialize)]
struct HashRequest {
    plain_text: String,
    salt: String,
}

async fn handle_hashing_password(Json(payload): Json<HashRequest>) -> impl IntoResponse {
    match utils::security::hash_password(&payload.plain_text, &payload.salt) {
        Ok(encrypted) => (StatusCode::OK, encrypted).into_response(),
        Err(e) => (StatusCode::INTERNAL_SERVER_ERROR, e.to_string()).into_response(),
    }
}

async fn handle_generate_salt() -> impl IntoResponse {
    utils::security::generate_salt()
}

async fn handle_get_deps_version() -> impl IntoResponse {
    let ytdlp = utils::ytdlp::get_yt_dlp_version().await;
    let ffmpeg = utils::ytdlp::get_ffmpeg_version().await;
    Json(json!({
        "ytdlp": ytdlp,
        "ffmpeg": ffmpeg,
    }))
}

async fn handle_generate_api(
    State(state): State<SharedState>,
    jar: CookieJar,
) -> impl IntoResponse {
    let key = Uuid::new_v4().to_string();
    let cookie = Cookie::build(("nadeko_api_key", key.clone()))
        .path("/")
        .secure(true)
        .http_only(true)
        .same_site(SameSite::Lax)
        .build();

    let jar = jar.add(cookie);
    {
        let mut cfg = state.config.write().await;
        cfg["server_api_key"] = Value::String(key.clone());
    }
    *state.api_key.write().await = normalize_secret(&key).to_string();
    (
        jar,
        Json(json!({
            "api_key": state.api_key.read().await.clone()
        })),
    )
        .into_response()
}

async fn handle_get_settings(State(state): State<SharedState>) -> impl IntoResponse {
    let config = state.config.read().await.clone();
    Json(config)
}

async fn handle_update_settings(
    State(state): State<SharedState>,
    Json(new_config): Json<Value>,
) -> impl IntoResponse {
    let api_key = new_config["server_api_key"].clone().to_string();
    let username = new_config["username"].clone().to_string();
    let password = new_config["password"].clone().to_string();
    let dm_settings = DMSettings {
        speed_limit: new_config["speed_limit"].as_u64().unwrap_or(0),
        concurrency_limit: new_config["concurrency_limit"].as_u64().unwrap_or(3) as u8,
        download_threads: new_config["download_threads"].as_u64().unwrap_or(4) as u8,
        download_timeout: new_config["download_timeout"].as_u64().unwrap_or(300),
        download_retries: new_config["download_retries"].as_u64().unwrap_or(3) as u8,
        seeding_ratio: new_config["seeding_ratio"].as_f64().unwrap_or(0.0) as f32,
        seeding_time: new_config["seeding_time"].as_u64().unwrap_or(0),
        download_dir: format!("{}/downloads", nadeko_home()),
    };
    if let Err(e) = state.context.dm().await.update_settings(dm_settings).await {
        logger::error(&format!("Error in updating DMSettings: {:?}", e));
    }
    save_config(&new_config);
    *state.api_key.write().await = normalize_secret(&api_key).to_string();
    *state.username.write().await = normalize_secret(&username).to_string();
    *state.password.write().await = normalize_secret(&password).to_string();
    *state.config.write().await = new_config;
    StatusCode::OK
}

async fn handle_proxy_image(
    State(state): State<SharedState>,
    Query(params): Query<HashMap<String, String>>,
) -> impl IntoResponse {
    let encoded_url = match params.get("url") {
        Some(url) => url.clone(),
        None => return (StatusCode::BAD_REQUEST, "Missing url parameter").into_response(),
    };

    let decoded_url = match percent_decode_str(&encoded_url).decode_utf8() {
        Ok(url) => url.into_owned(),
        Err(_) => return (StatusCode::BAD_REQUEST, "Invalid URL encoding").into_response(),
    };

    let parsed_url = match Url::parse(&decoded_url) {
        Ok(url) => url,
        Err(_) => return (StatusCode::BAD_REQUEST, "Invalid URL").into_response(),
    };

    if parsed_url.scheme() != "http" && parsed_url.scheme() != "https" {
        return (StatusCode::BAD_REQUEST, "Only HTTP/HTTPS URLs allowed").into_response();
    }
    let client = &state.context.dm().await.client.clone();
    let info = match utils::url::get_url_info(client.clone(), parsed_url.as_str(), None, None, None)
        .await
    {
        Ok(i) => i,
        Err(_) => return (StatusCode::BAD_REQUEST, "Cant reach image url").into_response(),
    };
    let content_type = match info.content_type {
        Some(ct) => ct,
        None => return (StatusCode::BAD_REQUEST, "Cant determine content type").into_response(),
    };
    let response = match client.get(parsed_url).send().await {
        Ok(resp) => resp,
        Err(_) => return (StatusCode::BAD_GATEWAY, "Failed to fetch image").into_response(),
    };

    if !response.status().is_success() {
        return (
            StatusCode::from_u16(response.status().as_u16()).unwrap_or(StatusCode::BAD_GATEWAY),
            "Failed to fetch image",
        )
            .into_response();
    }

    if !content_type.starts_with("image/") {
        return (StatusCode::BAD_REQUEST, "URL must point to an image").into_response();
    }

    let bytes = match response.bytes().await {
        Ok(b) => b,
        Err(_) => return (StatusCode::BAD_GATEWAY, "Failed to read image").into_response(),
    };

    (
        [
            (reqwest::header::CONTENT_TYPE, content_type),
            (
                reqwest::header::CACHE_CONTROL,
                "public, max-age=3600".to_string(),
            ),
            (
                reqwest::header::ACCESS_CONTROL_ALLOW_ORIGIN,
                "*".to_string(),
            ),
        ],
        bytes,
    )
        .into_response()
}

pub fn create_nadeko_router(state: SharedState) -> Router<SharedState> {
    let protected_routes = Router::new()
        .route("/status", get(handle_status))
        .route("/list", post(handle_get_download_list))
        .route("/details/:id", get(handle_get_download_details))
        .route("/do-download", post(handle_do_download))
        .route("/pause", post(handle_pause_download))
        .route("/resume", post(handle_resume_download))
        .route("/cancel", post(handle_cancel_download))
        .route("/delete", post(handle_delete_download))
        .route("/update-url", post(handle_update_url))
        .route("/query-url", post(handle_query_url))
        .route("/query-ytdl", post(handle_query_ytdl))
        .route("/restart", post(handle_restart))
        .route(
            "/settings",
            get(handle_get_settings).post(handle_update_settings),
        )
        .route("/hash", post(handle_hashing_password))
        .route("/generate-salt", get(handle_generate_salt))
        .route("/generate-api", get(handle_generate_api))
        .route("/deps-version", get(handle_get_deps_version))
        .route("/img", get(handle_proxy_image))
        .layer(middleware::from_fn_with_state(state.clone(), check_api_key));

    let public_routes = Router::new().route("/login", post(handle_login));

    Router::new()
        .merge(protected_routes)
        .merge(public_routes)
        .with_state(state)
}

pub fn create_router(state: SharedState) -> Router {
    let qbt_router = crate::qbittorrent::get_router(state.clone());
    let nadeko_router = create_nadeko_router(state.clone());

    Router::new()
        .nest("/api/v2", qbt_router)
        .nest("/api/nadeko", nadeko_router)
        .with_state(state)
}

pub async fn run_server(
    router: Router,
    port: u16,
    restart_signal: Arc<Notify>,
    shutdown_signal: Arc<Notify>,
) {
    let addr = SocketAddr::from(([0, 0, 0, 0], port));
    utils::logger::debug(&format!("HTTP server listening on {}", addr));
    match tokio::net::TcpListener::bind(addr).await {
        Ok(listener) => {
            tokio::select! {
                _ = axum::serve(listener, router)
                    .with_graceful_shutdown(async move {
                        restart_signal.notified().await;
                    }) => {}
                _ = shutdown_signal.notified() => {
                    utils::logger::debug("Shutdown signal received, stopping HTTP server...");
                }
            }
        }
        Err(e) => utils::logger::error(&format!("Failed to bind HTTP server: {}", e)),
    }
}

pub async fn run_server_loop(state: SharedState) {
    loop {
        let port = {
            let config = state.config.read().await.clone();
            config["server_port"].as_u64().unwrap_or(8080) as u16
        };
        let restart_signal = state.restart_signal.clone();
        let shutdown_signal = state.shutdown_signal.clone();

        let router = create_router(state.clone());
        run_server(router, port, restart_signal, shutdown_signal).await;

        if state.shutdown_requested.load(Ordering::SeqCst) {
            utils::logger::debug("Shutting down application...");
            state.context.shutdown().await;
            break;
        }

        utils::logger::debug("Restarting HTTP server...");
        tokio::time::sleep(Duration::from_secs(1)).await;
    }
}
