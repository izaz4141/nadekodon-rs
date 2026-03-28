use serde_json::Value;
use std::path::PathBuf;
use std::sync::Arc;
use std::sync::atomic::{AtomicBool, Ordering};
use tokio::sync::RwLock;

use uuid::Uuid;

extern crate nadekodon_core as ncore;
use ncore::app_context::AppContext;
use ncore::utils::security;
use ncore::utils::{logger, types::DMSettings};

use nadekodon_server::server;
use nadekodon_server::server::{nadeko_home, normalize_secret};

#[tokio::main]
async fn main() {
    logger::debug("Initializing Nadeko~don Server...");

    let config_path = server::get_config_path();
    let mut initial_config = server::load_config(&config_path);
    let mut api_key = initial_config["server_api_key"]
        .as_str()
        .map(|s| s.to_string())
        .unwrap_or_else(|| Uuid::new_v4().to_string());

    let get_str = |key: &str| initial_config[key].as_str().unwrap_or("").to_string();

    let mut username = get_str("username");
    let mut password = get_str("password");
    let salt = get_str("salt");

    if let Ok(env_user) = std::env::var("NADEKO_USERNAME") {
        username = env_user;
    }
    if let Ok(env_pass) = std::env::var("NADEKO_PASSWORD") {
        password = env_pass;
    }
    if let Ok(env_key) = std::env::var("NADEKO_SERVER_API_KEY") {
        api_key = env_key;
    }
    username = normalize_secret(&username).to_string();
    password = normalize_secret(&password).to_string();
    password = if security::is_valid_hash(&password) {
        password
    } else {
        match security::hash_password(&password, &salt) {
            Ok(v) => v,
            Err(e) => {
                logger::error(&format!("Error when hashing password: {:?}", e));
                password
            }
        }
    };
    api_key = normalize_secret(&api_key).to_string();

    let client = ncore::utils::url::build_browser_client().await;

    let settings = DMSettings {
        speed_limit: initial_config["speed_limit"].as_u64().unwrap_or(0),
        concurrency_limit: initial_config["concurrency_limit"].as_u64().unwrap_or(3) as u8,
        download_threads: initial_config["download_threads"].as_u64().unwrap_or(4) as u8,
        download_timeout: initial_config["download_timeout"].as_u64().unwrap_or(300),
        download_retries: initial_config["download_retries"].as_u64().unwrap_or(3) as u8,
        seeding_ratio: initial_config["seeding_ratio"].as_f64().unwrap_or(0.0) as f32,
        seeding_time: initial_config["seeding_time"].as_u64().unwrap_or(0),
        download_dir: format!("{}/downloads", nadeko_home()),
    };

    let shutdown_signal = Arc::new(tokio::sync::Notify::new());
    let db_done_signal = Arc::new(tokio::sync::Notify::new());

    let context = AppContext::new(client, settings, shutdown_signal).await;
    let dm = context.dm().await;
    dm.init_torrent_session(PathBuf::from(format!(
        "{}/config/torrent_data",
        nadeko_home()
    )))
    .await;

    let db_path = PathBuf::from(format!("{}/config/nadekodon.db", nadeko_home()));

    let context_clone = context.clone();
    tokio::spawn(async move {
        if let Err(e) = context_clone
            .start_database_manager(db_path, db_done_signal)
            .await
        {
            logger::error(&format!("Failed to start database manager: {:?}", e));
        }
    });

    let port: u16 = std::env::var("NADEKO_SERVER_PORT")
        .unwrap_or_else(|_| "8080".to_string())
        .parse()
        .unwrap_or(8080);

    initial_config["download_folder"] = Value::String(format!("{}/downloads", nadeko_home()));
    initial_config["server_api_key"] = Value::String(api_key.clone());
    initial_config["server_port"] = Value::Number(port.into());
    initial_config["username"] = Value::String(username.clone());
    initial_config["password"] = {
        if security::is_valid_hash(&password) {
            Value::String(password.clone())
        } else {
            match security::hash_password(&password, &salt) {
                Ok(v) => Value::String(v),
                Err(e) => {
                    logger::error(&format!("Error when hashing password: {:?}", e));
                    Value::String(password.clone())
                }
            }
        }
    };

    let state = Arc::new(server::AppState {
        config: Arc::new(RwLock::new(initial_config.clone())),
        config_path,
        api_key: Arc::new(RwLock::new(api_key)),
        username: Arc::new(RwLock::new(username)),
        password: Arc::new(RwLock::new(password)),
        context,
        restart_signal: Arc::new(tokio::sync::Notify::new()),
        shutdown_signal: Arc::new(tokio::sync::Notify::new()),
        shutdown_requested: Arc::new(AtomicBool::new(false)),
        version: Arc::new(RwLock::new(None)),
    });

    state.save_config(&initial_config);

    let state_clone = state.clone();
    tokio::spawn(async move {
        tokio::signal::ctrl_c().await.ok();
        logger::debug("Shutdown signal received...");
        state_clone.shutdown_signal.notify_waiters();
        state_clone.shutdown_requested.store(true, Ordering::SeqCst);
    });

    server::run_server_loop(state).await;
}
