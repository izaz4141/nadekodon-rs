extern crate nadekodon_core as core;
use core::app_context::AppContext;
use core::utils;
use core::utils::logger;

use axum::{
    Router,
    body::Body,
    extract::State,
    http::{Request, StatusCode},
    middleware::Next,
    response::IntoResponse,
};
use axum_extra::extract::CookieJar;
use serde_json::Value;
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

pub async fn check_api_key(
    State(state): State<SharedState>,
    jar: CookieJar,
    req: Request<Body>,
    next: Next,
) -> Result<impl IntoResponse, StatusCode> {
    let api_key = state.api_key.read().await.clone();
    if let Some(key) = req.headers().get("X-API-Key")
        && key.to_str().map(|k| k == api_key).unwrap_or(false)
    {
        return Ok(next.run(req).await);
    }

    if let Some(cookie) = jar.get("nadeko_api_key")
        && cookie.value() == api_key
    {
        return Ok(next.run(req).await);
    }

    Err(StatusCode::UNAUTHORIZED)
}

pub fn create_router(state: SharedState) -> Router {
    let qbt_router = crate::qbittorrent::get_router(state.clone());
    let nadeko_router = crate::nadeko::create_nadeko_router(state.clone());

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
