extern crate nadekodon_core as core;

use core::app_context::AppContext;
use core::utils;
use core::utils::logger;
use subtle::ConstantTimeEq;

use axum::{
    Router,
    body::Body,
    extract::State,
    http::{Request, StatusCode},
    middleware::Next,
    response::IntoResponse,
};
use axum_extra::extract::{CookieJar, cookie::Cookie};
use governor::{clock::QuantaInstant, middleware::NoOpMiddleware};
use serde_json::Value;
use std::env;
use std::net::SocketAddr;
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::{Arc, OnceLock};
use std::time::Duration;
use time::Duration as TimeDuration;
use tokio::sync::{Notify, RwLock};
use tower_governor::{
    GovernorLayer,
    governor::{GovernorConfig, GovernorConfigBuilder},
    key_extractor::SmartIpKeyExtractor,
};
use tower_http::trace::TraceLayer;
use tracing_appender::non_blocking::WorkerGuard;
use uuid::Uuid;

static NADEKO_HOME: OnceLock<String> = OnceLock::new();
pub fn nadeko_home() -> &'static String {
    NADEKO_HOME
        .get_or_init(|| env::var("NADEKO_HOME").unwrap_or_else(|_| "/home/nadeko".to_string()))
}

pub fn get_logs_dir() -> String {
    format!("{}/logs", nadeko_home())
}

#[derive(Debug, Clone)]
pub struct AppState {
    pub context: Arc<AppContext>,
    pub api_key: Arc<RwLock<String>>,
    pub username: Arc<RwLock<String>>,
    pub password: Arc<RwLock<String>>,
    pub config: Arc<RwLock<Value>>,
    pub config_path: String,
    pub restart_signal: Arc<Notify>,
    pub shutdown_signal: Arc<Notify>,
    pub shutdown_requested: Arc<AtomicBool>,
    pub version: Arc<RwLock<Option<String>>>,
}
pub type SharedState = Arc<AppState>;

impl AppState {
    pub fn save_config(&self, settings: &Value) {
        if let Some(parent) = std::path::Path::new(&self.config_path).parent() {
            let _ = std::fs::create_dir_all(parent);
        }
        if let Ok(json_str) = serde_json::to_string_pretty(settings) {
            let _ = std::fs::write(&self.config_path, json_str);
        }
    }
}

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

pub fn secure_compare(a: &str, b: &str) -> bool {
    a.as_bytes().ct_eq(b.as_bytes()).into()
}

pub fn build_api_cookie(key: &str) -> Cookie<'static> {
    Cookie::build(("nadeko_api_key", key.to_string()))
        .path("/")
        .secure(true)
        .http_only(true)
        .same_site(axum_extra::extract::cookie::SameSite::Strict)
        .max_age(TimeDuration::days(30))
        .build()
}

pub fn get_config_path() -> String {
    format!("{}/config/config.json", nadeko_home())
}

pub fn auth_rate_limit_config() -> GovernorConfig<SmartIpKeyExtractor, NoOpMiddleware<QuantaInstant>>
{
    GovernorConfigBuilder::default()
        .per_second(30)
        .burst_size(5)
        .key_extractor(SmartIpKeyExtractor)
        .finish()
        .unwrap()
}

pub fn global_rate_limit_config()
-> GovernorConfig<SmartIpKeyExtractor, NoOpMiddleware<QuantaInstant>> {
    GovernorConfigBuilder::default()
        .per_millisecond(200)
        .burst_size(20)
        .key_extractor(SmartIpKeyExtractor)
        .finish()
        .unwrap()
}

pub fn load_config(path: &str) -> Value {
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
    logger::debug(&format!("Loading config from {}", path));
    if let Ok(content) = std::fs::read_to_string(path)
        && let Ok(v) = serde_json::from_str(&content)
    {
        cfg = v;
    }
    cfg
}

pub async fn check_api_key(
    State(state): State<SharedState>,
    jar: CookieJar,
    req: Request<Body>,
    next: Next,
) -> Result<impl IntoResponse, StatusCode> {
    let api_key = state.api_key.read().await.clone();
    if let Some(key) = req.headers().get("X-API-Key")
        && key
            .to_str()
            .map(|k| secure_compare(k, &api_key))
            .unwrap_or(false)
    {
        return Ok(next.run(req).await);
    }

    if let Some(cookie) = jar.get("nadeko_api_key")
        && secure_compare(cookie.value(), &api_key)
    {
        return Ok(next.run(req).await);
    }

    Err(StatusCode::UNAUTHORIZED)
}

pub fn create_router(
    state: SharedState,
    governor_conf: GovernorConfig<SmartIpKeyExtractor, NoOpMiddleware<QuantaInstant>>,
) -> Router {
    let qbt_router = crate::qbittorrent::get_router(state.clone());
    let nadeko_router = crate::nadeko::create_nadeko_router(state.clone());

    Router::new()
        .nest("/api/v2", qbt_router)
        .nest("/api/nadeko", nadeko_router)
        .layer(TraceLayer::new_for_http())
        .layer(GovernorLayer::new(governor_conf))
        .with_state(state)
}

pub async fn run_server(
    router: Router,
    port: u16,
    restart_signal: Arc<Notify>,
    shutdown_signal: Arc<Notify>,
) {
    let host = env::var("NADEKO_SERVER_HOST").unwrap_or_else(|_| "127.0.0.1".to_string());
    let addr: SocketAddr = match host.parse() {
        Ok(ip) => SocketAddr::new(ip, port),
        Err(_) => SocketAddr::from(([127, 0, 0, 1], port)),
    };
    utils::logger::debug(&format!("HTTP server listening on {}", addr));
    match tokio::net::TcpListener::bind(addr).await {
        Ok(listener) => {
            tokio::select! {
                _ = axum::serve(listener, router.into_make_service_with_connect_info::<SocketAddr>())
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

pub async fn run_server_loop(state: SharedState, _guard: WorkerGuard) {
    loop {
        let governor_conf = global_rate_limit_config();
        let governor_limiter = governor_conf.limiter().clone();

        let cleanup_handle = tokio::spawn(async move {
            loop {
                tokio::time::sleep(Duration::from_secs(60)).await;
                // logger::debug(&format!(
                //     "Rate limiting storage size: {}",
                //     governor_limiter.len()
                // ));
                governor_limiter.retain_recent();
            }
        });

        let port = {
            let config = state.config.read().await.clone();
            config["server_port"].as_u64().unwrap_or(8080) as u16
        };
        let restart_signal = state.restart_signal.clone();
        let shutdown_signal = state.shutdown_signal.clone();

        let router = create_router(state.clone(), governor_conf);
        run_server(router, port, restart_signal, shutdown_signal).await;

        cleanup_handle.abort();

        if state.shutdown_requested.load(Ordering::SeqCst) {
            utils::logger::debug("Shutting down application...");
            state.context.shutdown().await;
            break;
        }

        utils::logger::debug("Restarting HTTP server...");
        tokio::time::sleep(Duration::from_secs(1)).await;
    }
}
