use crate::server::SharedState;
use axum::{
    Json,
    extract::{ConnectInfo, State},
    http::{HeaderMap, HeaderValue},
    response::IntoResponse,
};
use nadekodon_core::{signals::ServerStatus, utils::logger};
use std::net::SocketAddr;

#[utoipa::path(
    get,
    path = "/api/nadeko/system/status",
    tags = ["nadeko.system"],
    responses(
        (status = 200, description = "Server status", body = ServerStatus)
    )
)]
pub async fn handle_status(
    State(state): State<SharedState>,
    ConnectInfo(peer): ConnectInfo<SocketAddr>,
    headers: HeaderMap,
) -> impl IntoResponse {
    let client = headers
        .get("x-forwarded-for")
        .and_then(|v: &HeaderValue| v.to_str().ok())
        .map(|s| s.to_string())
        .unwrap_or_else(|| peer.to_string());
    logger::debug(&format!(
        "GET /api/nadeko/system/status peer={} client={:?} host={:?}",
        peer,
        client,
        headers
            .get("host")
            .and_then(|v| v.to_str().ok())
            .unwrap_or("<none>")
    ));

    let version = {
        let read = state.version.read().await;
        if let Some(v) = &*read {
            logger::debug(&format!("Version from cache: {}", v));
            v.clone()
        } else {
            drop(read);
            let mut v_str = "Unknown".to_string();
            let pubspec_path = "./assets/docs/pubspec.yaml";
            match std::fs::read_to_string(pubspec_path) {
                Ok(content) => {
                    let (v, b) = nadekodon_core::utils::version::parse_pubspec_version(&content);
                    if let Some(version_val) = v {
                        v_str = if let Some(build_val) = b {
                            format!("{}+{}", version_val, build_val)
                        } else {
                            version_val
                        };
                        logger::debug(&format!(
                            "Resolved version from {}: {}",
                            pubspec_path, v_str
                        ));
                    } else {
                        logger::warn(&format!(
                            "No version found in {}, serving \"Unknown\"",
                            pubspec_path
                        ));
                    }
                }
                Err(e) => {
                    logger::warn(&format!(
                        "Failed to read {}: {} (serving \"Unknown\")",
                        pubspec_path, e
                    ));
                }
            }
            {
                let mut write = state.version.write().await;
                *write = Some(v_str.clone());
            }
            v_str
        }
    };

    logger::debug(&format!(
        "Responding 200 to {}: status=Online version={}",
        client, version
    ));
    Json(ServerStatus {
        status: "Online".to_string(),
        version,
    })
}
