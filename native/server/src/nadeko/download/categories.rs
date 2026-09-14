use crate::response::{json_error, json_ok};
use crate::server::SharedState;
use axum::{Json, extract::Query, extract::State, response::IntoResponse};
use nadekodon_core::signals::{GetCategoriesResponse, CategoryDisplay, UpdateCategoriesRequest};
use std::collections::HashMap;
use std::path::PathBuf;

#[utoipa::path(
    get,
    path = "/api/nadeko/download/categories",
    tags = ["nadeko.download"],
    security(("ApiKeyAuth" = [])),
    params(("id" = String, Query, description = "Request correlation id")),
    responses(
        (status = 200, description = "Categories list", body = GetCategoriesResponse),
        (status = 500, description = "Server error")
    )
)]
pub async fn handle_get_categories(
    State(state): State<SharedState>,
    Query(params): Query<HashMap<String, String>>,
) -> impl IntoResponse {
    let id = params.get("id").cloned().unwrap_or_default();
    let dm = state.context.dm().await;
    let categories = dm.list_categories().await;
    let category_list: Vec<CategoryDisplay> = categories
        .into_iter()
        .map(|c| CategoryDisplay {
            name: c.name,
            save_path: c.save_path.map(|p| p.to_string_lossy().to_string()),
        })
        .collect();
    Json(GetCategoriesResponse {
        id,
        categories: category_list,
    })
}

#[utoipa::path(
    post,
    path = "/api/nadeko/download/categories",
    tags = ["nadeko.download"],
    security(("ApiKeyAuth" = [])),
    request_body = UpdateCategoriesRequest,
    responses(
        (status = 200, description = "Categories updated"),
        (status = 500, description = "Server error")
    )
)]
pub async fn handle_update_categories(
    State(state): State<SharedState>,
    Json(payload): Json<UpdateCategoriesRequest>,
) -> impl IntoResponse {
    let dm = state.context.dm().await;
    let category_infos: Vec<nadekodon_core::utils::types::CategoryInfo> = payload
        .categories
        .into_iter()
        .map(|c| nadekodon_core::utils::types::CategoryInfo {
            name: c.name,
            save_path: c.save_path.map(PathBuf::from),
        })
        .collect();
    match dm.update_categories(category_infos).await {
        Ok(_) => json_ok().into_response(),
        Err(e) => json_error(axum::http::StatusCode::INTERNAL_SERVER_ERROR, e.to_string())
            .into_response(),
    }
}
