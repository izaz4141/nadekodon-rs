extern crate nadekodon_core as ncore;
use nadekodon_core::utils::encryption;
use nadekodon_server::{
    docs::create_docs_router,
    nadeko::{create_nadeko_router, system::handle_status},
    qbittorrent::get_router,
    server::{
        AppState, SharedState, check_api_key, global_rate_limit_config, load_config, run_server,
    },
};
use ncore::app_context::AppContext;
use ncore::utils::security;

use crate::signals::{
    DecryptRequest, DecryptResponse, EncryptRequest, EncryptResponse, NewApiKey,
    RequestAddDownload, RequestNewApiKey, StartServer,
};
use crate::utils::logger;
use axum::Router;
use axum::{
    Json,
    extract::State,
    http::StatusCode,
    middleware,
    response::IntoResponse,
    routing::{get, post},
};
use rinf::{DartSignal, RustSignal};
use std::sync::Arc;
use std::sync::atomic::AtomicBool;
use std::time::Duration;
use tokio::{
    spawn,
    sync::{Notify, RwLock},
};
use tower_governor::GovernorLayer;
use uuid::Uuid;

pub async fn handle_api_key_generation() {
    let receiver = RequestNewApiKey::get_dart_signal_receiver();
    while let Some(signal_pack) = receiver.recv().await {
        let msg = signal_pack.message;
        let master_key = match &msg.master_key {
            Some(key) if encryption::is_valid_master_key(key) => key.clone(),
            _ => {
                logger::warn("Invalid master key provided, generating new one");
                encryption::generate_master_key()
            }
        };
        let api_key = Uuid::new_v4().to_string();
        let encrypted_api_key = match encryption::encrypt(&api_key, &master_key) {
            Ok(encrypted) => encrypted,
            Err(e) => {
                logger::error(&format!("Encryption failed: {}", e));
                NewApiKey {
                    id: msg.id,
                    encrypted_api_key: String::new(),
                    decrypted_api_key: String::new(),
                    master_key: String::new(),
                }
                .send_signal_to_dart();
                continue;
            }
        };
        NewApiKey {
            id: msg.id,
            encrypted_api_key,
            decrypted_api_key: api_key,
            master_key,
        }
        .send_signal_to_dart();
    }
}

pub async fn handle_decrypt_request() {
    let receiver = DecryptRequest::get_dart_signal_receiver();
    while let Some(signal_pack) = receiver.recv().await {
        let msg = signal_pack.message;
        let decrypted_key = match encryption::decrypt(&msg.encrypted_key, &msg.master_key) {
            Ok(key) => key,
            Err(e) => {
                logger::error(&format!("Decryption failed: {}", e));
                String::new()
            }
        };
        DecryptResponse {
            id: msg.id,
            decrypted_key,
        }
        .send_signal_to_dart();
    }
}

pub async fn handle_encrypt_request() {
    let receiver = EncryptRequest::get_dart_signal_receiver();
    while let Some(signal_pack) = receiver.recv().await {
        let msg = signal_pack.message;
        let master_key = msg
            .master_key
            .unwrap_or_else(encryption::generate_master_key);
        let encrypted_key = match encryption::encrypt(&msg.plain_key, &master_key) {
            Ok(encrypted) => encrypted,
            Err(e) => {
                logger::error(&format!("Encryption failed: {}", e));
                EncryptResponse {
                    id: msg.id,
                    encrypted_key: String::new(),
                    master_key: String::new(),
                }
                .send_signal_to_dart();
                continue;
            }
        };
        EncryptResponse {
            id: msg.id,
            encrypted_key,
            master_key,
        }
        .send_signal_to_dart();
    }
}

async fn handle_add_download(
    State(_state): State<SharedState>,
    Json(payload): Json<RequestAddDownload>,
) -> impl IntoResponse {
    payload.send_signal_to_dart();
    (StatusCode::OK, "Download request sent".to_string())
}

pub async fn start_server_listener(context: Arc<AppContext>) {
    let mut current_server: Option<(tokio::task::JoinHandle<()>, Arc<tokio::sync::Notify>)> = None;
    let mut cleanup_handle: Option<tokio::task::JoinHandle<()>> = None;
    let receiver = StartServer::get_dart_signal_receiver();

    while let Some(signal_pack) = receiver.recv().await {
        let msg = signal_pack.message;
        logger::debug(&format!("Starting server on port {}", msg.port));

        if let Some(handle) = cleanup_handle.take() {
            handle.abort();
        }

        if let Some((old_handle, old_notify)) = current_server.take() {
            old_notify.notify_one();
            let _ = old_handle.await;
        }

        let config_path = msg.config_path;
        let config_val = load_config(&config_path);
        let salt = config_val["salt"]
            .as_str()
            .map(|s| s.to_string())
            .unwrap_or_else(security::generate_salt);

        let password = if security::is_valid_hash(&msg.password) {
            msg.password
        } else {
            match security::hash_password(&msg.password, &salt) {
                Ok(v) => v,
                Err(e) => {
                    logger::error(&format!("Error when hashing password: {:?}", e));
                    msg.password
                }
            }
        };

        let config = Arc::new(RwLock::new(config_val));
        let restart_signal = Arc::new(Notify::new());
        let shutdown_signal = Arc::new(Notify::new());
        let shutdown_requested = Arc::new(AtomicBool::new(false));

        let state = Arc::new(AppState {
            context: context.clone(),
            api_key: Arc::new(RwLock::new(msg.api_key)),
            username: Arc::new(RwLock::new(msg.username)),
            password: Arc::new(RwLock::new(password)),
            config,
            config_path,
            restart_signal: restart_signal.clone(),
            shutdown_signal: shutdown_signal.clone(),
            shutdown_requested: shutdown_requested.clone(),
            version: Arc::new(RwLock::new(None)),
        });

        let governor_conf = global_rate_limit_config();
        let governor_limiter = governor_conf.limiter().clone();

        cleanup_handle = Some(spawn(async move {
            loop {
                tokio::time::sleep(Duration::from_secs(60)).await;
                // logger::debug(&format!(
                //     "Rate limiting storage size: {}",
                //     governor_limiter.len()
                // ));
                governor_limiter.retain_recent();
            }
        }));

        let qbt_router = get_router(state.clone());
        let nadeko_router = create_nadeko_router(state.clone());
        let docs_router = create_docs_router(state.clone());
        let ext_router = Router::new()
            .route("/api/nadeko/download/add", post(handle_add_download))
            .layer(middleware::from_fn_with_state(state.clone(), check_api_key))
            .with_state(state.clone());
        let router = Router::new()
            .nest("/api/v2", qbt_router)
            .nest("/api/nadeko", nadeko_router)
            .merge(ext_router)
            .merge(docs_router)
            .layer(GovernorLayer::new(governor_conf))
            .route("/api/nadeko/system/status", get(handle_status))
            .with_state(state);

        let rs_clone = restart_signal.clone();
        let ss_clone = shutdown_signal.clone();
        let new_handle = spawn(async move {
            run_server(router, msg.port, rs_clone, ss_clone).await;
        });
        current_server = Some((new_handle, restart_signal));
    }
}
