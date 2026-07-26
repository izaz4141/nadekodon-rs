use axum::{extract::Json, response::IntoResponse};
use nadekodon_core::signals::{SearchYtdl, YtdlSearchOutput};
use nadekodon_core::utils::ytdlp;

#[utoipa::path(
    post,
    path = "/api/nadeko/utils/search-ytdl",
    tags = ["nadeko.utils"],
    security(("ApiKeyAuth" = [])),
    request_body = SearchYtdl,
    responses(
        (status = 200, description = "YouTubeDL search results", body = YtdlSearchOutput),
        (status = 500, description = "Server error")
    )
)]
pub async fn handle_search_ytdl(Json(payload): Json<SearchYtdl>) -> impl IntoResponse {
    match ytdlp::search(&payload.query).await {
        Ok(results) => Json(YtdlSearchOutput {
            results,
            error: None,
        })
        .into_response(),
        Err(e) => (axum::http::StatusCode::INTERNAL_SERVER_ERROR, e.to_string()).into_response(),
    }
}
