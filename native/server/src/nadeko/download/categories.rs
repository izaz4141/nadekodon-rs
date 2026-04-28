use crate::server::SharedState;
use axum::{extract::State, response::IntoResponse, Json};
use nadekodon_core::signals::{CategoryDisplay, CategoriesOutput, UpdateCategories};
use std::path::PathBuf;

#[utoipa::path(
    get,
    path = "/api/nadeko/download/categories",
    tags = ["nadeko.download"],
    security(("ApiKeyAuth" = [])),
    responses(
        (status = 200, description = "Categories list", body = CategoriesOutput),
        (status = 500, description = "Server error")
    )
)]
pub async fn handle_get_categories(
    State(state): State<SharedState>,
) -> impl IntoResponse {
    let dm = state.context.dm().await;
    let categories = dm.list_categories().await;
    let category_list: Vec<CategoryDisplay> = categories
        .into_iter()
        .map(|c| CategoryDisplay {
            name: c.name,
            save_path: c.save_path.map(|p| p.to_string_lossy().to_string()),
        })
        .collect();
    Json(CategoriesOutput { categories: category_list })
}

#[utoipa::path(
    post,
    path = "/api/nadeko/download/categories",
    tags = ["nadeko.download"],
    security(("ApiKeyAuth" = [])),
    request_body = UpdateCategories,
    responses(
        (status = 200, description = "Categories updated"),
        (status = 500, description = "Server error")
    )
)]
pub async fn handle_update_categories(
    State(state): State<SharedState>,
    Json(payload): Json<UpdateCategories>,
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
        Ok(_) => (axum::http::StatusCode::OK, "Categories updated".to_string()),
        Err(e) => (axum::http::StatusCode::INTERNAL_SERVER_ERROR, e.to_string()),
    }
}