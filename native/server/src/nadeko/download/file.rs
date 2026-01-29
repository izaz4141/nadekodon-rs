use crate::server::SharedState;
use axum::{
    body::Body,
    extract::{Path, State},
    http::{HeaderMap, HeaderValue, StatusCode, header},
    response::IntoResponse,
};
use nadekodon_core::utils::{logger, types::DownloadState};
use std::path::PathBuf;
use tokio::fs::File;
use tokio::io::AsyncReadExt;
use uuid::Uuid;

pub async fn handle_download_file(
    State(state): State<SharedState>,
    Path(id): Path<String>,
) -> impl IntoResponse {
    let uuid = match Uuid::parse_str(&id) {
        Ok(u) => u,
        Err(_) => return (StatusCode::BAD_REQUEST, "Invalid ID").into_response(),
    };

    let dm = state.context.dm().await;
    let info = match dm.info(uuid).await {
        Ok(info) => info,
        Err(e) => {
            logger::error(&format!("Failed to get download info for {}: {}", id, e));
            return (StatusCode::NOT_FOUND, "Download not found").into_response();
        }
    };

    if !matches!(info.state, DownloadState::Completed | DownloadState::Seeding) {
        return (
            StatusCode::FORBIDDEN,
            "Download must be completed or seeding to download",
        )
            .into_response();
    }

    let path = PathBuf::from(&info.dest);
    if !path.exists() {
        return (StatusCode::NOT_FOUND, "File not found on disk").into_response();
    }

    let file = match File::open(&path).await {
        Ok(file) => file,
        Err(e) => {
            logger::error(&format!("Failed to open file {:?}: {}", path, e));
            return (StatusCode::INTERNAL_SERVER_ERROR, "Failed to open file").into_response();
        }
    };

    let stream = futures_util::stream::unfold(file, |mut file| async move {
        let mut buf = vec![0u8; 65536];
        match file.read(&mut buf).await {
            Ok(0) => None,
            Ok(n) => {
                buf.truncate(n);
                Some((Ok::<_, std::io::Error>(axum::body::Bytes::from(buf)), file))
            }
            Err(e) => Some((Err(e), file)),
        }
    });

    let body = Body::from_stream(stream);

    let filename = path
        .file_name()
        .and_then(|n| n.to_str())
        .unwrap_or("download");

    let mut headers = HeaderMap::new();
    headers.insert(
        header::CONTENT_TYPE,
        HeaderValue::from_static("application/octet-stream"),
    );
    headers.insert(
        header::CONTENT_DISPOSITION,
        HeaderValue::from_str(&format!("attachment; filename=\"{}\"", filename)).unwrap(),
    );

    (headers, body).into_response()
}
