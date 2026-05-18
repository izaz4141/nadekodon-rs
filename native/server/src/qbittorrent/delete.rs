use crate::server::SharedState;
use axum::{
    extract::{Form, State},
    http::StatusCode,
    response::IntoResponse,
};
use nadekodon_core::utils::logger;
use serde::{Deserialize, Serialize};
use utoipa::ToSchema;

// Not Actually Query, but form (because arr stack sent form to this route)
#[derive(Deserialize, Debug, Serialize, ToSchema)]
pub struct TorrentsDeleteQuery {
    pub hashes: Option<String>,
    #[serde(rename = "deleteFiles")]
    pub delete_files: Option<bool>,
}

#[utoipa::path(
    post,
    path = "/api/v2/torrents/delete",
    tag = "qbit.torrents",
    security(("SIDCookie" = [])),
    request_body = TorrentsDeleteQuery,
    responses(
        (status = 200, description = "Torrent deleted"),
        (status = 400, description = "Missing required field"),
        (status = 404, description = "Torrent not found")
    )
)]
pub async fn torrents_delete(
    State(state): State<SharedState>,
    Form(form): Form<TorrentsDeleteQuery>,
) -> impl IntoResponse {
    let hashes_opt = form.hashes.clone();
    let delete_files = form.delete_files.unwrap_or(false);

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
