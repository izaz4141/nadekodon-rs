use nadekodon_core::downloader;
use nadekodon_core::signals;

use axum::{
    Router,
    body::Body,
    extract::{Json, Path, Query, State},
    http::{Request, StatusCode},
    middleware::{self, Next},
    response::IntoResponse,
    routing::{get, post},
};
use serde::Deserialize;
use serde_json::{Value, json};
use std::net::SocketAddr;
use std::sync::Arc;
use std::time::Duration;
use uuid::Uuid;

#[derive(Clone)]
pub struct AppState {
    pub dm: Arc<downloader::DownloadManager>,
    pub api_key: String,
    pub username: String,
    pub password: String,
    pub config: Arc<tokio::sync::RwLock<Value>>,
    pub restart_signal: Arc<tokio::sync::Notify>,
}

pub fn get_config_dir() -> String {
    std::env::var("NADEKO_HOME").unwrap_or_else(|_| ".".to_string())
}

pub fn get_config_path() -> String {
    format!("{}/config/config.json", get_config_dir())
}

pub fn load_config() -> Value {
    let path = get_config_path();
    if let Ok(content) = std::fs::read_to_string(&path) {
        if let Ok(v) = serde_json::from_str(&content) {
            return v;
        }
    }
    if let Ok(content) = std::fs::read_to_string("assets/docs/default.json") {
        if let Ok(v) = serde_json::from_str(&content) {
            return v;
        }
    }

    json!({
        "retreat_to_tray": true,
        "server_host": "127.0.0.1",
        "server_port": 8080,
        "server_api_key": "",
        "salt": "",
        "username": "",
        "password": "",
        "speed_limit": 0.0,
        "speed_mode": 0,
        "speed_schedule": [],
        "download_threads": 8,
        "concurrency_limit": 3,
        "download_timeout": 30,
        "download_retries": 5,
        "seeding_ratio": 1.0,
        "seeding_time": 30,
        "theme_mode": 0,
        "use_dynamic_color": true,
        "custom_color": 4294918273u32,
        "check_nightly": false
    })
}

pub fn save_config(settings: &Value) {
    let path = get_config_path();
    let config_dir = format!("{}/config", get_config_dir());
    let _ = std::fs::create_dir_all(&config_dir);
    if let Ok(json_str) = serde_json::to_string_pretty(settings) {
        let _ = std::fs::write(path, json_str);
    }
}

async fn handle_status() -> impl IntoResponse {
    (StatusCode::OK, "Online")
}

pub async fn check_api_key(
    State(api_key): State<String>,
    req: Request<Body>,
    next: Next,
) -> Result<impl IntoResponse, StatusCode> {
    match req.headers().get("X-API-Key") {
        Some(key) if key.to_str().map(|k| k == api_key).unwrap_or(false) => Ok(next.run(req).await),
        _ => Err(StatusCode::UNAUTHORIZED),
    }
}

async fn handle_get_download_list(
    State(state): State<AppState>,
    Query(query): Query<signals::GetDownloadList>,
) -> impl IntoResponse {
    let core_query = signals::GetDownloadList {
        anchor_id: query.anchor_id,
        before: query.before,
        after: query.after,
        statuses: query.statuses,
        tag: query.tag,
        search_query: query.search_query,
        sort_by: query.sort_by,
        ascending: query.ascending,
    };
    match downloader::get_download_list_internal(&state.dm, core_query).await {
        Ok(list) => Json(list).into_response(),
        Err(e) => (StatusCode::INTERNAL_SERVER_ERROR, e.to_string()).into_response(),
    }
}

async fn handle_get_download_details(
    State(state): State<AppState>,
    Path(id): Path<String>,
) -> impl IntoResponse {
    match downloader::get_download_details_internal(&state.dm, &id).await {
        Ok(Some(details)) => Json(details).into_response(),
        _ => StatusCode::NOT_FOUND.into_response(),
    }
}

async fn handle_do_download(
    State(state): State<AppState>,
    Json(payload): Json<signals::DoDownload>,
) -> impl IntoResponse {
    match downloader::spawn_download_worker_internal(&state.dm, payload).await {
        Ok(_) => (StatusCode::OK, "Download added".to_string()),
        Err(e) => (StatusCode::INTERNAL_SERVER_ERROR, e.to_string()),
    }
}

#[derive(Deserialize)]
struct IdRequest {
    id: String,
}

async fn handle_pause_download(
    State(state): State<AppState>,
    Json(payload): Json<IdRequest>,
) -> impl IntoResponse {
    if let Ok(id) = Uuid::parse_str(&payload.id) {
        let _ = state.dm.pause(id).await;
        StatusCode::OK
    } else {
        StatusCode::BAD_REQUEST
    }
}

async fn handle_resume_download(
    State(state): State<AppState>,
    Json(payload): Json<IdRequest>,
) -> impl IntoResponse {
    if let Ok(id) = Uuid::parse_str(&payload.id) {
        let _ = state.dm.resume(id).await;
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
    State(state): State<AppState>,
    Json(payload): Json<UpdateUrlRequest>,
) -> impl IntoResponse {
    if let Ok(id) = Uuid::parse_str(&payload.id) {
        let _ = state.dm.update_download_url(id, payload.new_url).await;
        StatusCode::OK
    } else {
        StatusCode::BAD_REQUEST
    }
}

async fn handle_cancel_download(
    State(state): State<AppState>,
    Json(payload): Json<IdRequest>,
) -> impl IntoResponse {
    if let Ok(id) = Uuid::parse_str(&payload.id) {
        let _ = state.dm.cancel(id).await;
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
    State(state): State<AppState>,
    Json(payload): Json<DeleteDownloadRequest>,
) -> impl IntoResponse {
    if let Ok(id) = Uuid::parse_str(&payload.id) {
        let _ = state.dm.delete_worker(id, payload.delete_file).await;
        StatusCode::OK
    } else {
        StatusCode::BAD_REQUEST
    }
}

async fn handle_restart(
    State(state): State<AppState>,
) -> impl IntoResponse {
    state.restart_signal.notify_one();
    StatusCode::OK
}

async fn handle_query_url(
    State(state): State<AppState>,
    Json(payload): Json<signals::QueryUrl>,
) -> impl IntoResponse {
    match downloader::query_url_info_internal(state.dm.client.clone(), payload).await {
        Ok(info) => Json(info).into_response(),
        Err(e) => (StatusCode::INTERNAL_SERVER_ERROR, e.to_string()).into_response(),
    }
}

async fn handle_query_ytdl(
    Json(payload): Json<signals::QueryYtdl>,
) -> impl IntoResponse {
    match nadekodon_core::utils::ytdlp::get_ytdl_info(&payload.url).await {
        Ok(info) => Json(info).into_response(),
        Err(e) => (StatusCode::INTERNAL_SERVER_ERROR, e).into_response(),
    }
}

#[derive(Deserialize)]
struct EncryptRequest {
    plain_text: String,
    salt: String,
}

#[derive(Deserialize)]
struct DecryptRequest {
    stored: String,
    salt: String,
}

async fn handle_encrypt_password(
    Json(payload): Json<EncryptRequest>,
) -> impl IntoResponse {
    match nadekodon_core::utils::security::encrypt_password(&payload.plain_text, &payload.salt) {
        Ok(encrypted) => (StatusCode::OK, encrypted).into_response(),
        Err(e) => (StatusCode::INTERNAL_SERVER_ERROR, e.to_string()).into_response(),
    }
}

async fn handle_decrypt_password(
    Json(payload): Json<DecryptRequest>,
) -> impl IntoResponse {
    match nadekodon_core::utils::security::decrypt_password(&payload.stored, &payload.salt) {
        Some(decrypted) => (StatusCode::OK, decrypted).into_response(),
        None => (StatusCode::BAD_REQUEST, "Decryption failed".to_string()).into_response(),
    }
}

async fn handle_generate_salt() -> impl IntoResponse {
    nadekodon_core::utils::security::generate_salt()
}

async fn handle_get_deps_version() -> impl IntoResponse {
    let ytdlp = nadekodon_core::utils::ytdlp::get_yt_dlp_version().await;
    let ffmpeg = nadekodon_core::utils::ytdlp::get_ffmpeg_version().await;
    Json(json!({
        "ytdlp": ytdlp,
        "ffmpeg": ffmpeg,
    }))
}

async fn handle_get_settings(State(state): State<AppState>) -> impl IntoResponse {
    let config = state.config.read().await.clone();
    Json(config)
}

async fn handle_update_settings(
    State(state): State<AppState>,
    Json(new_config): Json<Value>,
) -> impl IntoResponse {
    *state.config.write().await = new_config.clone();
    save_config(&new_config);
    StatusCode::OK
}

pub fn create_nadeko_router(state: AppState) -> Router<AppState> {
    Router::new()
        .route("/status", get(handle_status))
        .route("/list", get(handle_get_download_list))
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
        .route("/encrypt", post(handle_encrypt_password))
        .route("/decrypt", post(handle_decrypt_password))
        .route("/generate-salt", get(handle_generate_salt))
        .route("/deps-version", get(handle_get_deps_version))
        .layer(middleware::from_fn_with_state(
            state.api_key.clone(),
            check_api_key,
        ))
        .with_state(state)
}

pub fn create_router(state: AppState) -> Router {
    let qbt_router = crate::qbittorrent::get_router(state.clone());
    let nadeko_router = create_nadeko_router(state.clone());

    Router::new()
        .nest("/api/v2", qbt_router)
        .nest("/api/nadeko", nadeko_router)
        .with_state(state)
}

pub async fn run_server(router: Router, port: u16, restart_signal: Arc<tokio::sync::Notify>) {
    let addr = SocketAddr::from(([0, 0, 0, 0], port));
    nadekodon_core::utils::logger::debug(&format!("HTTP server listening on {}", addr));
    match tokio::net::TcpListener::bind(addr).await {
        Ok(listener) => {
            if let Err(e) = axum::serve(listener, router)
                .with_graceful_shutdown(async move {
                    restart_signal.notified().await;
                })
                .await
            {
                nadekodon_core::utils::logger::error(&format!("HTTP server error: {}", e));
            }
        }
        Err(e) => {
            nadekodon_core::utils::logger::error(&format!("Failed to bind HTTP server: {}", e))
        }
    }
}

pub async fn run_server_loop(
    dm: Arc<downloader::DownloadManager>,
    mut port: u16,
    api_key: String,
    username: String,
    password: String,
) {
    loop {
        let config_val = load_config();
        
        let salt = config_val["salt"].as_str().unwrap_or("");
        
        let current_password = if password.contains("\"iv\":") && password.contains("\"data\":") {
            nadekodon_core::utils::security::decrypt_password(&password, salt).unwrap_or(password.clone())
        } else {
            password.clone()
        };

        if let Some(p) = config_val["server_port"].as_u64() {
            port = p as u16;
        }

        let restart_signal = Arc::new(tokio::sync::Notify::new());

        let config = Arc::new(tokio::sync::RwLock::new(config_val));
        let state = AppState {
            dm: dm.clone(),
            api_key: api_key.clone(),
            username: username.clone(),
            password: current_password,
            config,
            restart_signal: restart_signal.clone(),
        };

        let router = create_router(state);
        run_server(router, port, restart_signal).await;
        
        nadekodon_core::utils::logger::debug("Restarting HTTP server...");
        tokio::time::sleep(Duration::from_secs(1)).await;
    }
}
