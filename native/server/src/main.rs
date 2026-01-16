use serde_json::Value;
use std::sync::Arc;
use tokio::sync::RwLock;
use uuid::Uuid;

use nadekodon_core::downloader::DownloadManager;
use nadekodon_core::utils::types::DMSettings;
use nadekodon_server::server;

#[tokio::main]
async fn main() {
    println!("Initializing Nadeko~don Server...");

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
        if let Some(decrypted) = nadekodon_core::utils::security::decrypt_password(&password, &salt) {
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

    // Also check for Server Port env var here or let run_server_loop handle it? 
    // main.rs handles port logic below.

    let client = reqwest::Client::builder()
        .build()
        .expect("Failed to create HTTP client");

    let settings = DMSettings {
        speed_limit: 0,
        concurrency_limit: 3,
        download_threads: 4,
        download_timeout: 300,
        download_retries: 3,
        seeding_ratio: 0.0,
        seeding_time: 0,
        download_dir: "Downloads".to_string(),
    };

    let dm = DownloadManager::new(client, settings).await;

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
