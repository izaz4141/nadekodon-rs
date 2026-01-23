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
    hashes: String,
    #[serde(rename = "deleteFiles")]
    delete_files: Option<bool>,
}

pub async fn torrents_delete(
    State(state): State<SharedState>,
    query: Option<Query<TorrentsDeleteQuery>>,
    form: Option<Form<TorrentsDeleteQuery>>,
) -> impl IntoResponse {
    let params = if let Some(Form(p)) = form {
        p
    } else if let Some(Query(p)) = query {
        p
    } else {
        return (StatusCode::BAD_REQUEST, "Missing required parameters").into_response();
    };

    let hashes: Vec<&str> = params.hashes.split('|').collect();
    let delete_files = params.delete_files.unwrap_or(false);

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
