use crate::response::json_error;
use axum::{extract::Json, response::IntoResponse};
use nadekodon_core::signals::{SearchYtdlRequest, SearchYtdlResponse};
use nadekodon_core::utils::ytdlp;

#[utoipa::path(
    post,
    path = "/api/nadeko/utils/search-ytdl",
    tags = ["nadeko.utils"],
    security(("ApiKeyAuth" = [])),
    request_body = SearchYtdlRequest,
    responses(
        (status = 200, description = "YouTubeDL search results", body = SearchYtdlResponse),
        (status = 500, description = "Server error")
    )
)]
pub async fn handle_search_ytdl(Json(payload): Json<SearchYtdlRequest>) -> impl IntoResponse {
    match ytdlp::search(&payload.query).await {
        Ok(results) => Json(SearchYtdlResponse {
            id: payload.id,
            results,
            error: None,
        })
        .into_response(),
        Err(e) => json_error(axum::http::StatusCode::INTERNAL_SERVER_ERROR, e.to_string())
            .into_response(),
    }
}
