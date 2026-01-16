use std::sync::Arc;
use std::path::PathBuf;
use std::env;
use tokio::sync::{Notify, RwLock};
use uuid::Uuid;

extern crate nadekodon_core as core;
use core::downloader::DownloadManager;
use core::utils::{types::DMSettings, logger};
use core::utils::database::{start_database_manager};

use nadekodon_server::server;
use nadekodon_server::server::nadeko_home;

#[tokio::main]
async fn main() {
    logger::debug("Initializing Nadeko~don Server...");
    let cwd = env::current_dir().expect("failed to get current dir");
    logger::debug(&format!("{}", cwd.display()));


    let initial_config = server::load_config();
    let mut api_key = initial_config["server_api_key"]
        .as_str()
        .map(|s| s.to_string())
        .unwrap_or_else(|| Uuid::new_v4().to_string());
    
    // Helper to get string from config
    let get_str = |key: &str| initial_config[key].as_str().unwrap_or("").to_string();
    
    let mut username = get_str("username");
    let mut password = get_str("password");
    let salt = get_str("salt");

    // Decrypt password if it looks encrypted (contains "iv" and "data") 
    // or just try to decrypt it regardless since our decrypt handles fallback
    if !password.is_empty() {
        if let Ok(decrypted) = core::utils::security::decrypt_password(&password, &salt) {
            password = decrypted;
        }
    }

    // Environment variables override
    if let Ok(env_user) = std::env::var("NADEKO_USERNAME") {
        username = env_user;
    }
    if let Ok(env_pass) = std::env::var("NADEKO_PASSWORD") {
        password = env_pass;
    }
    if let Ok(env_key) = std::env::var("NADEKO_SERVER_API_KEY") {
        api_key = env_key;
    }

    let client = core::utils::url::build_browser_client().await;

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

    let dm = DownloadManager::new(client, settings).await;
    dm.init_torrent_session(PathBuf::from(format!("{}/config/torrent_data", nadeko_home()))).await;
    let dm_clone = dm.clone();
    tokio::spawn(async move {
        let shutdown_signal = Arc::new(Notify::new());
        let db_done_signal = Arc::new(Notify::new());
        let db_path = PathBuf::from(format!("{}/config/nadekodon.db", nadeko_home()));
        start_database_manager(dm_clone, shutdown_signal, db_done_signal, db_path)
    });

    let state = server::AppState {
        config: Arc::new(RwLock::new(initial_config)),
        api_key: api_key.clone(),
        username: username.clone(),
        password: password.clone(),
        dm,
        restart_signal: Arc::new(tokio::sync::Notify::new()),
    };

    let port: u16 = std::env::var("NADEKO_SERVER_PORT")
        .unwrap_or_else(|_| "8080".to_string())
        .parse()
        .unwrap_or(8080);

    // Use the run_server_loop function from core
    nadekodon_server::server::run_server_loop(
        state.dm.clone(),
        port,
        state.api_key.clone(),
        state.username.clone(),
        state.password.clone(),
    )
    .await;
}
