use crate::server::SharedState;
use axum::{
    extract::{Form, Query, State},
    http::StatusCode,
    response::IntoResponse,
};
use nadekodon_core::utils::logger;
use serde::Deserialize;

#[derive(Deserialize, Debug)]
pub struct TorrentsDeleteQuery {
    hashes: Option<String>,
    #[serde(rename = "deleteFiles")]
    delete_files: Option<bool>,
}

pub async fn torrents_delete(
    State(state): State<SharedState>,
    query: Option<Query<TorrentsDeleteQuery>>,
    form: Option<Form<TorrentsDeleteQuery>>,
) -> impl IntoResponse {
    let form_data = form.map(|Form(f)| f);
    let query_data = query.map(|Query(q)| q);

    let hashes_opt = form_data
        .as_ref()
        .and_then(|d| d.hashes.clone())
        .or_else(|| query_data.as_ref().and_then(|d| d.hashes.clone()));

    let delete_files = form_data
        .as_ref()
        .and_then(|d| d.delete_files)
        .or_else(|| query_data.as_ref().and_then(|d| d.delete_files))
        .unwrap_or(false);

    let hashes_str = match hashes_opt {
        Some(h) => h,
        None => return (StatusCode::BAD_REQUEST, "Missing required field: hashes").into_response(),
    };

    let hashes: Vec<&str> = hashes_str.split('|').collect();

    let downloads = state
        .context
        .dm()
        .await
        .list_all()
        .await
        .unwrap_or_default();

    for hash in hashes {
        if hash.is_empty() {
            continue;
        }

        let target = downloads
            .iter()
            .find(|d| d.torrent_hash.as_deref() == Some(hash));

        if let Some(d) = target {
            if let Err(e) = state
                .context
                .dm()
                .await
                .delete_worker(d.id, delete_files)
                .await
            {
                logger::error(&format!("Failed to delete torrent {}: {}", hash, e));
            } else {
                logger::debug(&format!(
                    "Deleted torrent: {} (files: {})",
                    hash, delete_files
                ));
            }
        } else {
            logger::error(&format!("Torrent not found for deletion: {}", hash));
            return (StatusCode::NOT_FOUND, "Torrent not found").into_response();
        }
    }

    (StatusCode::OK, "Ok.").into_response()
}
