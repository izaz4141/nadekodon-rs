use axum::{extract::Json, response::IntoResponse};
use nadekodon_core::signals::{QueryYtdl, YtdlQueryOutput};
use nadekodon_core::utils::ytdlp;

#[utoipa::path(
    post,
    path = "/api/nadeko/utils/query-ytdl",
    tags = ["nadeko.utils"],
    security(("ApiKeyAuth" = [])),
    request_body = QueryYtdl,
    responses(
        (status = 200, description = "YouTubeDL info retrieved", body = YtdlQueryOutput),
        (status = 500, description = "Server error")
    )
)]
pub async fn handle_query_ytdl(Json(payload): Json<QueryYtdl>) -> impl IntoResponse {
    match ytdlp::get_ytdl_info(&payload.url).await {
        Ok(info) => Json(info).into_response(),
        Err(e) => (axum::http::StatusCode::INTERNAL_SERVER_ERROR, e).into_response(),
    }
}
