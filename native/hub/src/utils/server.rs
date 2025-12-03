use crate::signals::{NewApiKey, RequestAddDownload, RequestNewApiKey, StartServer};
use crate::utils::logger;
use crate::{downloader::main::DownloadManager, utils::types::WorkerEvent};
use axum::{
    Router,
    extract::{
        State,
        ws::{Message, WebSocket, WebSocketUpgrade},
    },
    response::IntoResponse,
    routing::any,
};
use futures::{sink::SinkExt, stream::StreamExt};
use rinf::{DartSignal, RustSignal};
use serde::{Deserialize, Serialize};
use std::{net::SocketAddr, sync::Arc};
use uuid::Uuid;

#[derive(Clone)]
struct AppState {
    dm: Arc<DownloadManager>,
    api_key: String,
}

#[derive(Deserialize, Debug)]
#[serde(tag = "type")]
enum ClientMessage {
    #[serde(rename = "download")]
    Download {
        url: String,
        filename: Option<String>,
        cookie: Option<String>,
        user_agent: Option<String>,
    },
    #[serde(rename = "ping")]
    Ping,
}

#[derive(Serialize, Debug)]
#[serde(tag = "type")]
enum ServerMessage {
    #[serde(rename = "event")]
    Event {
        event: String,
        id: String,
        data: Option<String>,
    },
    #[serde(rename = "pong")]
    Pong,
}

pub async fn start_server_listener(dm: Arc<DownloadManager>) {
    let receiver = StartServer::get_dart_signal_receiver();
    let mut server_handle: Option<tokio::task::JoinHandle<()>> = None;

    while let Some(signal_pack) = receiver.recv().await {
        let msg = signal_pack.message;
        let port = msg.port;
        let api_key = msg.api_key;
        let dm_clone = dm.clone();

        if let Some(handle) = server_handle {
            handle.abort();
            logger::debug("Aborted previous WebSocket server");
        }

        server_handle = Some(tokio::spawn(async move {
            run_server_loop(dm_clone, port, api_key).await;
        }));
    }
}

pub async fn handle_api_key_generation() {
    let receiver = RequestNewApiKey::get_dart_signal_receiver();
    while let Some(_) = receiver.recv().await {
        let key = Uuid::new_v4().to_string();
        NewApiKey { key }.send_signal_to_dart();
    }
}

async fn run_server_loop(dm: Arc<DownloadManager>, port: u16, api_key: String) {
    let state = AppState { dm, api_key };

    let app = Router::new()
        .route("/ws", any(ws_handler))
        .with_state(state);

    let addr = SocketAddr::from(([127, 0, 0, 1], port));
    logger::debug(&format!("WebSocket server listening on {}", addr));
    match tokio::net::TcpListener::bind(addr).await {
        Ok(listener) => {
            if let Err(e) = axum::serve(listener, app).await {
                logger::error(&format!("WebSocket server error: {}", e));
            }
        }
        Err(e) => logger::error(&format!("Failed to bind WebSocket server: {}", e)),
    }
}

async fn ws_handler(
    ws: WebSocketUpgrade,
    axum::extract::Query(params): axum::extract::Query<std::collections::HashMap<String, String>>,
    State(state): State<AppState>,
) -> impl IntoResponse {
    if let Some(provided_key) = params.get("key") {
        if provided_key != &state.api_key {
            return (axum::http::StatusCode::UNAUTHORIZED, "Invalid API Key").into_response();
        }
    } else {
        return (axum::http::StatusCode::UNAUTHORIZED, "Missing API Key").into_response();
    }
    ws.on_upgrade(|socket| handle_socket(socket, state))
}

async fn handle_socket(socket: WebSocket, state: AppState) {
    let (mut sender, mut receiver) = socket.split();
    let mut rx = state.dm.broadcast_tx.subscribe();

    loop {
        tokio::select! {
            // Receive broadcast events from DownloadManager
            event = rx.recv() => {
                if let Ok(event) = event {
                    let msg = match event {
                        WorkerEvent::Completed(id) => ServerMessage::Event {
                            event: "completed".to_string(),
                            id: id.to_string(),
                            data: None,
                        },
                        WorkerEvent::Cancelled(id) => ServerMessage::Event {
                            event: "cancelled".to_string(),
                            id: id.to_string(),
                            data: None,
                        },
                        WorkerEvent::Error(id, err) => ServerMessage::Event {
                            event: "error".to_string(),
                            id: id.to_string(),
                            data: Some(err),
                        },
                    };

                    if let Ok(json) = serde_json::to_string(&msg) {
                        if sender.send(Message::Text(json)).await.is_err() {
                            break;
                        }
                    }
                }
            }
            // Receive messages from client
            client_msg = receiver.next() => {
                match client_msg {
                    Some(Ok(Message::Text(text))) => {
                        if let Ok(client_msg) = serde_json::from_str::<ClientMessage>(&text) {
                            match client_msg {
                                ClientMessage::Download { url, filename, cookie, user_agent } => {
                                    let signal = RequestAddDownload {
                                        url,
                                        filename,
                                        cookie,
                                        user_agent,
                                    };
                                    signal.send_signal_to_dart();
                                    logger::debug("Sent RequestAddDownload signal to Dart");
                                }
                                ClientMessage::Ping => {
                                    let pong = ServerMessage::Pong;
                                    if let Ok(json) = serde_json::to_string(&pong) {
                                        if sender.send(Message::Text(json)).await.is_err() {
                                            break;
                                        }
                                    }
                                }
                            }
                        }
                    }
                    Some(Ok(_)) => {
                        // Ignore other message types
                    }
                    _ => {
                        // Connection closed or error
                        break;
                    }
                }
            }
        }
    }
}
