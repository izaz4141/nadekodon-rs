extern crate nadekodon_core as core;
use core::downloader::DownloadManager;
use core::utils::security;
use nadekodon_server::{
    qbittorrent::get_router,
    server::{AppState, check_api_key, create_nadeko_router, run_server},
};

use crate::signals::{NewApiKey, RequestAddDownload, RequestNewApiKey, StartServer};
use crate::utils::logger;
use axum::Router;
use axum::{
    Json, extract::State, http::StatusCode, middleware, response::IntoResponse, routing::post,
};
use rinf::{DartSignal, RustSignal};
use std::sync::Arc;
use uuid::Uuid;

pub async fn handle_api_key_generation() {
    let receiver = RequestNewApiKey::get_dart_signal_receiver();
    while let Some(_) = receiver.recv().await {
        let key = Uuid::new_v4().to_string();
        NewApiKey { key }.send_signal_to_dart();
    }
}

async fn handle_add_download(
    State(_state): State<AppState>,
    Json(payload): Json<RequestAddDownload>,
) -> impl IntoResponse {
    payload.send_signal_to_dart();
    (StatusCode::OK, "Download request sent".to_string())
}

pub async fn start_server_listener(dm: Arc<DownloadManager>) {
    let mut current_server: Option<(tokio::task::JoinHandle<()>, Arc<tokio::sync::Notify>)> = None;
    let receiver = StartServer::get_dart_signal_receiver();

    while let Some(signal_pack) = receiver.recv().await {
        let msg = signal_pack.message;
        logger::debug(&format!("Starting server on port {}", msg.port));

        if let Some((old_handle, old_notify)) = current_server.take() {
            old_notify.notify_one();
            let _ = old_handle.await; // Wait for the port to be released
        }

        let config_val = nadekodon_server::server::load_config();
        let salt = config_val["salt"].as_str().unwrap_or("");

        let password = if msg.password.contains("\"iv\":") && msg.password.contains("\"data\":") {
            match security::decrypt_password(&msg.password, salt) {
                Ok(decrypted) => decrypted,
                Err(e) => {
                    logger::error(&format!("Failed to decrypt password: {}", e));
                    msg.password
                },
            }
        } else {
            msg.password
        };

        let config = Arc::new(tokio::sync::RwLock::new(config_val));
        let restart_signal = Arc::new(tokio::sync::Notify::new());
        let state = AppState {
            dm: dm.clone(),
            api_key: msg.api_key,
            username: msg.username,
            password,
            config,
            restart_signal: restart_signal.clone(),
        };

        let qbt_router = get_router(state.clone());
        let nadeko_router = create_nadeko_router(state.clone());
        let ext_router = Router::new()
            .route("/add-download", post(handle_add_download))
            .layer(middleware::from_fn_with_state(
                state.api_key.clone(),
                check_api_key,
            ))
            .with_state(state.clone());
        let router = Router::new()
            .nest("/api/v2", qbt_router)
            .nest("/api/nadeko", nadeko_router)
            .nest("/api/nadeko", ext_router)
            .with_state(state);

        let rs_clone = restart_signal.clone();
        let new_handle = tokio::spawn(async move {
            run_server(router, msg.port, rs_clone).await;
        });
        current_server = Some((new_handle, restart_signal));
    }
}
