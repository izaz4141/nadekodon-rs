use crate::server::SharedState;
use axum::{
    extract::{Multipart, State},
    http::StatusCode,
    response::IntoResponse,
};
use nadekodon_core::utils::logger;
use std::path::PathBuf;

pub async fn torrents_add(
    State(state): State<SharedState>,
    mut multipart: Multipart,
) -> impl IntoResponse {
    let mut urls = Vec::new();
    let mut torrent_files = Vec::new();
    let mut savepath = None;
    let mut cookie = None;
    let mut category = None;

    // Parse multipart
    while let Ok(Some(field)) = multipart.next_field().await {
        let name = field.name().unwrap_or("").to_string();
        if name == "urls" {
            if let Ok(text) = field.text().await {
                for line in text.lines() {
                    let u = line.trim();
                    if !u.is_empty() {
                        urls.push(u.to_string());
                    }
                }
            }
        } else if name == "torrents" {
            if let Ok(bytes) = field.bytes().await {
                torrent_files.push(bytes.to_vec());
            }
        } else if name == "savepath" {
            if let Ok(text) = field.text().await {
                savepath = Some(text);
            }
        } else if name == "cookie" {
            if let Ok(text) = field.text().await {
                cookie = Some(text);
            }
        } else if name == "category" {
            if let Ok(text) = field.text().await {
                category = Some(text);
            }
        }
    }

    let default_save_dir = {
        let dm = state.context.dm().await;
        let settings = dm.settings.read().await;
        settings.download_dir.clone()
    };

    let dest_dir = if let Some(sp) = &savepath {
        PathBuf::from(sp)
    } else {
        PathBuf::from(default_save_dir)
    };

    // Process URLs
    for url in urls {
        let url_info = nadekodon_core::utils::url::get_url_info(
            state.context.dm().await.client.clone(),
            &url,
            cookie.clone(),
            None,
            None,
        )
        .await;

        let actual_url = match url_info {
            Ok(info) => info.url,
            Err(_) => url.clone(),
        };

        match state
            .context
            .dm()
            .await
            .add_download(
                actual_url.clone(),
                dest_dir.clone(),
                cookie.clone(),
                None,
                None,
                category.clone(),
            )
            .await
        {
            Ok(id) => logger::debug(&format!(
                "Added download via API: {} (ID: {}) category: {:?}",
                actual_url, id, category
            )),
            Err(e) => logger::error(&format!("Failed to add download via API: {}", e)),
        }
    }

    // Process Torrent Files
    for bytes in torrent_files {
        // Save to temp file
        let temp_hash = uuid::Uuid::new_v4().to_string();
        let temp_path = std::env::temp_dir().join(format!("{}.torrent", temp_hash));

        if let Err(e) = std::fs::write(&temp_path, bytes) {
            logger::error(&format!("Failed to save temp torrent file: {}", e));
            continue;
        }

        let torrent_url = temp_path.to_string_lossy().to_string();

        match state
            .context
            .dm()
            .await
            .add_download(
                torrent_url.clone(),
                dest_dir.clone(),
                None,
                None,
                None,
                category.clone(),
            )
            .await
        {
            Ok(id) => logger::debug(&format!(
                "Added torrent file via API: {} (ID: {}) category: {:?}",
                torrent_url, id, category
            )),
            Err(e) => logger::error(&format!("Failed to add torrent file via API: {}", e)),
        }
    }

    (StatusCode::OK, "Ok.")
}
