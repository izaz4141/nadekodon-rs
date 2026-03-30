use crate::server::SharedState;
use axum::{
    body::Body,
    extract::{Path, State},
    http::{HeaderMap, HeaderValue, StatusCode, header},
    response::IntoResponse,
};
use nadekodon_core::utils::{logger, types::DownloadState};
use serde::Deserialize;
use std::path::PathBuf;
use tokio::fs::File;
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
        (status = 400, description = "Invalid ID"),
        (status = 403, description = "Download not completed"),
        (status = 404, description = "File not found")
    )
)]
pub async fn handle_download_file(
    State(state): State<SharedState>,
    Path(payload): Path<DownloadFilePath>,
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

    if path.is_dir() {
        let (temp_file, _temp_path) = match tempfile::NamedTempFile::new() {
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
            Ok::<std::fs::File, anyhow::Error>(file)
        })
        .await;

        let std_file = match zip_res {
            Ok(Ok(file)) => file,
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

        let content_length = match std_file.metadata() {
            Ok(m) => m.len(),
            Err(e) => {
                logger::error(&format!("Failed to get metadata for zipped file: {}", e));
                return (StatusCode::INTERNAL_SERVER_ERROR, "Failed to get metadata")
                    .into_response();
            }
        };

        let file = tokio::fs::File::from_std(std_file);

        let stream = tokio_util::io::ReaderStream::new(file);
        let body = Body::from_stream(stream);

        let filename = path
            .file_name()
            .and_then(|n| n.to_str())
            .unwrap_or("download");
        let zip_filename = format!("{}.zip", filename);

        let mut headers = HeaderMap::new();
        headers.insert(
            header::CONTENT_TYPE,
            HeaderValue::from_static("application/zip"),
        );
        headers.insert(
            header::CONTENT_DISPOSITION,
            HeaderValue::from_str(&format!("attachment; filename=\"{}\"", zip_filename)).unwrap(),
        );
        headers.insert(
            header::CONTENT_LENGTH,
            HeaderValue::from_str(&content_length.to_string()).unwrap(),
        );

        (headers, body).into_response()
    } else {
        let file = match File::open(&path).await {
            Ok(file) => file,
            Err(e) => {
                logger::error(&format!("Failed to open file {:?}: {}", path, e));
                return (StatusCode::INTERNAL_SERVER_ERROR, "Failed to open file").into_response();
            }
        };

        let content_length = match file.metadata().await {
            Ok(m) => m.len(),
            Err(e) => {
                logger::error(&format!(
                    "Failed to get metadata for file {:?}: {}",
                    path, e
                ));
                return (StatusCode::INTERNAL_SERVER_ERROR, "Failed to get metadata")
                    .into_response();
            }
        };

        let stream = tokio_util::io::ReaderStream::new(file);
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
        headers.insert(
            header::CONTENT_LENGTH,
            HeaderValue::from_str(&content_length.to_string()).unwrap(),
        );

        (headers, body).into_response()
    }
}
