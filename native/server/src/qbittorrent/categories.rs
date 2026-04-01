use crate::server::SharedState;
use axum::{Form, Json, extract::State, http::StatusCode, response::IntoResponse};
use nadekodon_core::utils::logger;
use serde::{Deserialize, Serialize};
use std::collections::HashMap;
use std::path::PathBuf;
use utoipa::ToSchema;

#[derive(Deserialize, Debug, ToSchema)]
pub struct TorrentsSetCategoryForm {
    pub hashes: String,
    pub category: String,
}

#[utoipa::path(
    post,
    path = "/api/qbittorrent/torrents/setCategory",
    tag = "qbit.torrents",
    security(("SIDCookie" = [])),
    request_body = TorrentsSetCategoryForm,
    responses(
        (status = 200, description = "Category set"),
        (status = 400, description = "Failed to set category"),
        (status = 404, description = "Torrent not found")
    )
)]
pub async fn torrents_set_category(
    State(state): State<SharedState>,
    Form(query): Form<TorrentsSetCategoryForm>,
) -> impl IntoResponse {
    let downloads = state
        .context
        .dm()
        .await
        .list_all()
        .await
        .unwrap_or_default();

    if query.hashes == "all" {
        for d in downloads {
            if d.torrent_hash.is_none() {
                continue;
            }
            if let Some(worker) = state.context.dm().await.get_worker(d.id).await {
                if query.category.is_empty() {
                    worker.clear_category().await;
                } else if let Err(e) = worker.set_category(query.category.clone()).await {
                    logger::error(&format!("Failed to set category: {:?}", e));
                    return (
                        StatusCode::BAD_REQUEST,
                        format!("Failed to set category: {:?}", e),
                    )
                        .into_response();
                }
            }
        }
    } else {
        let hashes: Vec<&str> = query.hashes.split('|').collect();
        for hash in hashes {
            if hash.is_empty() {
                continue;
            }

            let target = downloads
                .iter()
                .find(|d| d.torrent_hash.as_deref() == Some(hash));

            match target {
                Some(d) => {
                    if let Some(worker) = state.context.dm().await.get_worker(d.id).await {
                        if query.category.is_empty() {
                            worker.clear_category().await;
                        } else if let Err(e) = worker.set_category(query.category.clone()).await {
                            logger::error(&format!("Failed to set category: {:?}", e));
                            return (
                                StatusCode::BAD_REQUEST,
                                format!("Failed to set category: {:?}", e),
                            )
                                .into_response();
                        }
                    }
                }
                None => {
                    return (StatusCode::NOT_FOUND, "Torrent not found").into_response();
                }
            }
        }
    }

    (StatusCode::OK, "Ok.").into_response()
}

#[derive(Deserialize, Debug, ToSchema)]
pub struct TorrentsCreateCategoryForm {
    pub category: String,
    #[serde(rename = "savePath")]
    pub save_path: Option<String>,
}

#[utoipa::path(
    post,
    path = "/api/qbittorrent/torrents/createCategory",
    tag = "qbit.torrents",
    security(("SIDCookie" = [])),
    request_body = TorrentsCreateCategoryForm,
    responses(
        (status = 200, description = "Category created"),
        (status = 400, description = "Invalid category name"),
        (status = 409, description = "Category already exists")
    )
)]
pub async fn torrents_create_category(
    State(state): State<SharedState>,
    Form(query): Form<TorrentsCreateCategoryForm>,
) -> impl IntoResponse {
    if query.category.is_empty() {
        return (StatusCode::BAD_REQUEST, "Category name is empty").into_response();
    }

    let save_path = query.save_path.map(PathBuf::from);

    match state
        .context
        .dm()
        .await
        .create_category(query.category, save_path)
        .await
    {
        Ok(()) => (StatusCode::OK, "Ok.").into_response(),
        Err("Category already exists") => {
            (StatusCode::CONFLICT, "Category already exists").into_response()
        }
        Err(_) => (StatusCode::BAD_REQUEST, "Invalid category name").into_response(),
    }
}

#[derive(Serialize, ToSchema)]
pub struct CategoryResponse {
    name: String,
    #[serde(rename = "savePath")]
    save_path: Option<String>,
}

#[utoipa::path(
    get,
    path = "/api/qbittorrent/torrents/categories",
    tag = "qbit.torrents",
    security(("SIDCookie" = [])),
    responses(
        (status = 200, description = "List of categories", body = HashMap<String, CategoryResponse>)
    )
)]
pub async fn torrents_categories(State(state): State<SharedState>) -> impl IntoResponse {
    let categories = state.context.dm().await.categories.read().await.clone();

    let response: HashMap<String, CategoryResponse> = categories
        .into_iter()
        .map(|(name, info)| {
            (
                name.clone(),
                CategoryResponse {
                    name,
                    save_path: info.save_path.map(|p| p.to_string_lossy().to_string()),
                },
            )
        })
        .collect();

    Json(response).into_response()
}
