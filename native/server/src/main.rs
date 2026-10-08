use serde_json::Value;
use std::path::PathBuf;
use std::sync::Arc;
use std::sync::atomic::{AtomicBool, Ordering};
use tokio::sync::RwLock;

use uuid::Uuid;

extern crate nadekodon_core as ncore;
use ncore::app_context::AppContext;
use ncore::utils::{config, logger, security, types::DMSettings};

use nadekodon_server::server;
use nadekodon_server::server::{
    DEFAULT_PASSWORD, DEFAULT_USERNAME, nadeko_home, normalize_secret, resolve_password,
    resolve_username,
};

#[tokio::main]
async fn main() {
    logger::debug("Initializing Nadeko~don Server...");

    let config_path = server::get_config_path();
    let master_key =
        std::env::var("NADEKO_SERVER_MASTER_KEY").expect("NADEKO_SERVER_MASTER_KEY is not set");

    // Bootstrap the config first: DM settings below derive from it.
    logger::debug(&format!("Loading config from {}", config_path));
    let preloaded = match config::load_or_bootstrap(config_path.clone(), master_key.clone()).await {
        Ok((cfg, true)) => {
            logger::info("No config found, created a default one");
            cfg
        }
        Ok((cfg, false)) => cfg,
        Err(e) => {
            logger::error(&format!("Failed to load or create the config: {:?}", e));
            return;
        }
    };
    let mut initial_config = preloaded.value.clone();
    logger::debug(&format!(
        "Config loaded (on-disk server_port: {})",
        preloaded.value["server_port"]
    ));

    let mut api_key = initial_config["server_api_key"]
        .as_str()
        .and_then(server::resolve_api_key)
        .unwrap_or_else(|| Uuid::new_v4().to_string());

    logger::debug("Resolving credentials and API key...");

    let get_str = |key: &str| initial_config[key].as_str().unwrap_or("").to_string();

    let mut username = get_str("username");
    let mut password = get_str("password");

    // Blank env values are treated as unset.
    if let Ok(env_user) = std::env::var("NADEKO_USERNAME")
        && !env_user.trim().is_empty()
    {
        username = env_user;
    }
    if let Ok(env_pass) = std::env::var("NADEKO_PASSWORD")
        && !env_pass.trim().is_empty()
    {
        password = env_pass;
    }
    if let Ok(env_key) = std::env::var("NADEKO_SERVER_API_KEY")
        && !env_key.trim().is_empty()
    {
        api_key = env_key;
    }
    username = normalize_secret(&username).to_string();
    password = normalize_secret(&password).to_string();

    // Empty credentials fall back to admin:admin.
    let had_username = username.clone();
    let had_password = password.clone();
    username = resolve_username(&username);
    password = resolve_password(&password);
    if username != had_username {
        logger::warn(&format!(
            "No username configured, falling back to the default \"{}\"",
            DEFAULT_USERNAME
        ));
    }
    if password != had_password {
        logger::warn(&format!(
            "No usable password configured, falling back to the default \"{}\" password",
            DEFAULT_PASSWORD
        ));
    }

    api_key = normalize_secret(&api_key).to_string();
    if api_key.is_empty() {
        api_key = Uuid::new_v4().to_string();
        logger::warn("No server API key configured, generated a new one");
    }
    password = if security::is_valid_hash(&password) {
        password
    } else {
        match security::hash_password(&password) {
            Ok(v) => v,
            Err(e) => {
                logger::error(&format!("Error when hashing password: {:?}", e));
                password
            }
        }
    };

    logger::debug("Building HTTP client...");
    let client = ncore::utils::url::build_browser_client().await;
    logger::debug("HTTP client built");

    let settings = DMSettings {
        speed_limit: initial_config["speed_limit"].as_u64().unwrap_or(0),
        concurrency_limit: initial_config["concurrency_limit"].as_u64().unwrap_or(3) as u8,
        download_threads: initial_config["download_threads"].as_u64().unwrap_or(4) as u8,
        download_timeout: initial_config["download_timeout"].as_u64().unwrap_or(300),
        download_retries: initial_config["download_retries"].as_u64().unwrap_or(3) as u8,
        seeding_ratio: initial_config["seeding_ratio"].as_f64().unwrap_or(0.0) as f32,
        seeding_time: initial_config["seeding_time"].as_u64().unwrap_or(0),
        stalled_time: initial_config["stalled_time"].as_u64().unwrap_or(30),
        download_dir: format!("{}/downloads", nadeko_home()),
    };

    let shutdown_signal = Arc::new(tokio::sync::Notify::new());
    let db_done_signal = Arc::new(tokio::sync::Notify::new());

    logger::debug("Creating app context...");
    let context = AppContext::new(client, settings, shutdown_signal).await;
    context.set_master_key(master_key).await;
    logger::debug("App context created, initializing config...");
    if let Err(e) = context.init_config(config_path).await {
        logger::error(&format!("Failed to initialize the config: {:?}", e));
        return;
    }
    logger::debug("Config initialized");

    let dm = context.dm().await;
    logger::debug("Initializing torrent session...");
    dm.init_torrent_session(PathBuf::from(format!(
        "{}/config/torrent_data",
        nadeko_home()
    )))
    .await;
    logger::debug("Torrent session initialized");

    let db_path = PathBuf::from(format!("{}/config/nadekodon.db", nadeko_home()));

    logger::debug("Starting database manager...");
    let context_clone = context.clone();
    tokio::spawn(async move {
        if let Err(e) = context_clone
            .start_database_manager(db_path, db_done_signal)
            .await
        {
            logger::error(&format!("Failed to start database manager: {:?}", e));
        } else {
            logger::debug("Database manager started");
        }
    });

    let port: u16 = std::env::var("NADEKO_SERVER_PORT")
        .unwrap_or_else(|_| "8080".to_string())
        .parse()
        .unwrap_or(8080);
    logger::debug(&format!("Resolved NADEKO_SERVER_PORT: {}", port));

    initial_config["download_folder"] = Value::String(format!("{}/downloads", nadeko_home()));
    initial_config["server_api_key"] = Value::String(api_key.clone());
    initial_config["server_port"] = Value::Number(port.into());
    initial_config["username"] = Value::String(username.clone());
    initial_config["password"] = {
        if security::is_valid_hash(&password) {
            Value::String(password.clone())
        } else {
            match security::hash_password(&password) {
                Ok(v) => Value::String(v),
                Err(e) => {
                    logger::error(&format!("Error when hashing password: {:?}", e));
                    Value::String(password.clone())
                }
            }
        }
    };

    // Persist so disk matches what the server is actually using.
    match context.save_config(&initial_config).await {
        Ok(()) => logger::debug("Config saved"),
        Err(e) => logger::error(&format!("Failed to save the config: {:?}", e)),
    }

    let state = Arc::new(server::AppState {
        api_key: Arc::new(RwLock::new(api_key)),
        username: Arc::new(RwLock::new(username)),
        password: Arc::new(RwLock::new(password)),
        context,
        restart_signal: Arc::new(tokio::sync::Notify::new()),
        shutdown_signal: Arc::new(tokio::sync::Notify::new()),
        shutdown_requested: Arc::new(AtomicBool::new(false)),
        version: Arc::new(RwLock::new(None)),
    });

    let state_clone = state.clone();
    tokio::spawn(async move {
        tokio::signal::ctrl_c().await.ok();
        logger::debug("Shutdown signal received...");
        state_clone.shutdown_signal.notify_waiters();
        state_clone.shutdown_requested.store(true, Ordering::SeqCst);
    });

    logger::debug("Startup sequence complete, entering server loop");
    server::run_server_loop(state).await;
}
