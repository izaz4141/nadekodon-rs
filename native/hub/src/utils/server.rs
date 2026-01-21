extern crate nadekodon_core as core;
use core::app_context::AppContext;
use core::utils::security;
use nadekodon_server::{
    nadeko::create_nadeko_router,
    qbittorrent::get_router,
    server::{AppState, SharedState, check_api_key, run_server},
};
use tokio::sync::{Notify, RwLock};

use crate::signals::{NewApiKey, RequestAddDownload, RequestNewApiKey, StartServer};
use crate::utils::logger;
use axum::Router;
use axum::{
    Json, extract::State, http::StatusCode, middleware, response::IntoResponse, routing::post,
};
use rinf::{DartSignal, RustSignal};
use std::sync::Arc;
use std::sync::atomic::AtomicBool;
use uuid::Uuid;

pub async fn handle_api_key_generation() {
    let receiver = RequestNewApiKey::get_dart_signal_receiver();
    while let Some(_) = receiver.recv().await {
        let key = Uuid::new_v4().to_string();
        NewApiKey { key }.send_signal_to_dart();
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
    let receiver = StartServer::get_dart_signal_receiver();

    while let Some(signal_pack) = receiver.recv().await {
        let msg = signal_pack.message;
        logger::debug(&format!("Starting server on port {}", msg.port));

        if let Some((old_handle, old_notify)) = current_server.take() {
            old_notify.notify_one();
            let _ = old_handle.await;
        }

        let config_val = nadekodon_server::server::load_config();
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
            restart_signal: restart_signal.clone(),
            shutdown_signal: shutdown_signal.clone(),
            shutdown_requested: shutdown_requested.clone(),
        });
        let qbt_router = get_router(state.clone());
        let nadeko_router = create_nadeko_router(state.clone());
        let ext_router = Router::new()
            .route("/download/add", post(handle_add_download))
            .layer(middleware::from_fn_with_state(state.clone(), check_api_key))
            .with_state(state.clone());
        let router = Router::new()
            .nest("/api/v2", qbt_router)
            .nest("/api/nadeko", nadeko_router)
            .nest("/api/nadeko", ext_router)
            .with_state(state);

        let rs_clone = restart_signal.clone();
        let ss_clone = shutdown_signal.clone();
        let new_handle = tokio::spawn(async move {
            run_server(router, msg.port, rs_clone, ss_clone).await;
        });
        current_server = Some((new_handle, restart_signal));
    }
}
