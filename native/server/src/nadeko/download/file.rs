use crate::server::SharedState;
use axum::{
    body::Body,
    extract::{Path, Request, State},
    http::{header, HeaderValue, StatusCode},
    response::IntoResponse,
};
use nadekodon_core::utils::{logger, types::DownloadState};
use serde::Deserialize;
use std::path::PathBuf;
use tower_http::services::fs::ServeFile;
use utoipa::{IntoParams, ToSchema};
use uuid::Uuid;

#[derive(Deserialize, ToSchema, IntoParams)]
#[into_params(parameter_in = Path)]
pub struct DownloadFilePath {
    pub id: String,
}

#[utoipa::path(
    get,
    path = "/api/nadeko/download/file/{id}",
    tags = ["nadeko.download"],
    security(("ApiKeyAuth" = [])),
    params(DownloadFilePath),
    responses(
        (status = 200, description = "File downloaded", body = Vec<u8>),
        (status = 206, description = "Partial content"),
        (status = 400, description = "Invalid ID"),
        (status = 403, description = "Download not completed"),
        (status = 404, description = "File not found")
    )
)]
pub async fn handle_download_file(
    State(state): State<SharedState>,
    Path(payload): Path<DownloadFilePath>,
    request: Request<Body>,
) -> impl IntoResponse {
    let uuid = match Uuid::parse_str(&payload.id) {
        Ok(u) => u,
        Err(_) => return (StatusCode::BAD_REQUEST, "Invalid ID").into_response(),
    };

    let dm = state.context.dm().await;
    let info = match dm.info(uuid).await {
        Ok(info) => info,
        Err(e) => {
            logger::error(&format!(
                "Failed to get download info for {}: {}",
                payload.id, e
            ));
            return (StatusCode::NOT_FOUND, "Download not found").into_response();
        }
    };

    if !matches!(
        info.state,
        DownloadState::Completed | DownloadState::Seeding
    ) {
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

    let (serve_path, filename) = if path.is_dir() {
        let (temp_file, temp_path) = match tempfile::NamedTempFile::new() {
            Ok(tf) => {
                let path = tf.path().to_path_buf();
                (tf, path)
            }
            Err(e) => {
                logger::error(&format!("Failed to create temp file: {}", e));
                return (
                    StatusCode::INTERNAL_SERVER_ERROR,
                    "Failed to create temp file",
                )
                    .into_response();
            }
        };

        let path_clone = path.clone();
        let zip_res = tokio::task::spawn_blocking(move || {
            use std::io::Seek;
            let mut file = temp_file.reopen()?;
            let mut zip = zip::ZipWriter::new(&mut file);
            let options = zip::write::SimpleFileOptions::default()
                .compression_method(zip::CompressionMethod::Stored);

            for entry in walkdir::WalkDir::new(&path_clone) {
                let entry = entry?;
                let entry_path = entry.path();
                let name = entry_path.strip_prefix(&path_clone).unwrap();

                if entry_path.is_file() {
                    zip.start_file(name.to_string_lossy(), options)?;
                    let mut f = std::fs::File::open(entry_path)?;
                    std::io::copy(&mut f, &mut zip)?;
                } else if !name.as_os_str().is_empty() {
                    zip.add_directory(name.to_string_lossy(), options)?;
                }
            }
            zip.finish()?;
            file.rewind()?;
            Ok::<tempfile::NamedTempFile, anyhow::Error>(temp_file)
        })
        .await;

        let _temp_file = match zip_res {
            Ok(Ok(tf)) => tf,
            Ok(Err(e)) => {
                logger::error(&format!("Failed to zip directory {:?}: {}", path, e));
                return (StatusCode::INTERNAL_SERVER_ERROR, "Failed to zip directory")
                    .into_response();
            }
            Err(e) => {
                logger::error(&format!("Zip task panicked for {:?}: {}", path, e));
                return (StatusCode::INTERNAL_SERVER_ERROR, "Internal server error")
                    .into_response();
            }
        };

        let dir_name = path
            .file_name()
            .and_then(|n| n.to_str())
            .unwrap_or("download");
        let zip_filename = format!("{}.zip", dir_name);
        (temp_path, zip_filename)
    } else {
        let filename = path
            .file_name()
            .and_then(|n| n.to_str())
            .unwrap_or("download")
            .to_string();
        (path, filename)
    };

    let mut svc = ServeFile::new(&serve_path);
    let res = match svc.try_call(request).await {
        Ok(res) => res,
        Err(e) => {
            logger::error(&format!("Failed to serve file {:?}: {}", serve_path, e));
            return (StatusCode::INTERNAL_SERVER_ERROR, "Failed to serve file").into_response();
        }
    };

    let mut res = res.map(Body::new);
    res.headers_mut().insert(
        header::CONTENT_DISPOSITION,
        HeaderValue::from_str(&format!("attachment; filename=\"{}\"", filename)).unwrap(),
    );

    res.into_response()
}