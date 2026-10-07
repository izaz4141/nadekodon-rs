extern crate nadekodon_core as ncore;
use ncore::app_context::AppContext;
use ncore::utils;

use crate::security::JwtResponse;

use axum::{Router, routing::get};
use axum_extra::extract::{
    CookieJar,
    cookie::{Cookie, SameSite},
};
use governor::{clock::QuantaInstant, middleware::NoOpMiddleware};
use std::env;
use std::net::SocketAddr;
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::{Arc, OnceLock};
use std::time::Duration;
use subtle::ConstantTimeEq;
use time::Duration as TimeDuration;
use tokio::sync::{Notify, RwLock};
use tower_governor::{
    GovernorLayer,
    governor::{GovernorConfig, GovernorConfigBuilder},
    key_extractor::SmartIpKeyExtractor,
};

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
    pub restart_signal: Arc<Notify>,
    pub shutdown_signal: Arc<Notify>,
    pub shutdown_requested: Arc<AtomicBool>,
    pub version: Arc<RwLock<Option<String>>>,
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

pub fn secure_compare(a: &str, b: &str) -> bool {
    a.as_bytes().ct_eq(b.as_bytes()).into()
}

/// Default credentials used when none are configured.
pub const DEFAULT_USERNAME: &str = "admin";
pub const DEFAULT_PASSWORD: &str = "admin";

/// Falls back to [`DEFAULT_USERNAME`] when no username is configured.
pub fn resolve_username(raw: &str) -> String {
    if raw.is_empty() {
        DEFAULT_USERNAME.to_string()
    } else {
        raw.to_string()
    }
}

/// Resolves a configured password (plaintext or argon2 hash); falls back to
/// [`DEFAULT_PASSWORD`] when missing or a hash of the empty string.
pub fn resolve_password(raw: &str) -> String {
    let hashes_empty =
        utils::security::is_valid_hash(raw) && utils::security::validate_password(raw, "")
            .unwrap_or(false);
    if raw.is_empty() || hashes_empty {
        DEFAULT_PASSWORD.to_string()
    } else {
        raw.to_string()
    }
}

/// Resolves the configured API key; empty, sample, or still-encrypted
/// (`NDK:`) values are treated as unset.
pub fn resolve_api_key(raw: &str) -> Option<String> {
    if raw.is_empty()
        || raw == ncore::utils::config::SAMPLE_API_KEY
        || raw.starts_with("NDK:")
    {
        None
    } else {
        Some(raw.to_string())
    }
}

pub fn build_jwt_cookie(jar: CookieJar, jwt: &JwtResponse) -> CookieJar {
    let jwt_token = Cookie::build(("nadekodon_jwt", jwt.access_token.clone()))
        .path("/")
        .secure(true)
        .http_only(true)
        .same_site(SameSite::Lax)
        .max_age(TimeDuration::seconds(jwt.expires_in as i64))
        .build();
    let csrf_token = Cookie::build(("nadekodon_csrf", jwt.csrf_token.clone()))
        .path("/")
        .secure(true)
        .same_site(SameSite::Lax)
        .max_age(TimeDuration::seconds(jwt.expires_in as i64))
        .build();
    jar.add(jwt_token).add(csrf_token)
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

pub fn create_router(
    state: SharedState,
    governor_conf: GovernorConfig<SmartIpKeyExtractor, NoOpMiddleware<QuantaInstant>>,
) -> Router {
    let qbt_router = crate::qbittorrent::get_router(state.clone());
    let nadeko_router = crate::nadeko::create_nadeko_router(state.clone());
    let docs_router = crate::docs::create_docs_router(state.clone());

    Router::new()
        .nest("/api/v2", qbt_router)
        .nest("/api/nadeko", nadeko_router)
        .merge(docs_router)
        .layer(GovernorLayer::new(governor_conf))
        .route(
            "/api/nadeko/system/status",
            get(crate::nadeko::system::handle_status),
        )
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

pub async fn run_server_loop(state: SharedState) {
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
            let config = state.context.cfg().await;
            config.value["server_port"].as_u64().unwrap_or(8080) as u16
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
