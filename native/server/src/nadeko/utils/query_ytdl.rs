use crate::response::json_error;
use axum::{extract::Json, response::IntoResponse};
use nadekodon_core::signals::{QueryYtdlRequest, QueryYtdlResponse};
use nadekodon_core::utils::ytdlp;

#[utoipa::path(
    post,
    path = "/api/nadeko/utils/query-ytdl",
    tags = ["nadeko.utils"],
    security(("ApiKeyAuth" = [])),
    request_body = QueryYtdlRequest,
    responses(
        (status = 200, description = "YouTubeDL info retrieved", body = QueryYtdlResponse),
        (status = 500, description = "Server error")
    )
)]
pub async fn handle_query_ytdl(Json(payload): Json<QueryYtdlRequest>) -> impl IntoResponse {
    match ytdlp::get_ytdl_info(&payload.url).await {
        Ok(mut info) => {
            info.id = payload.id;
            Json(info).into_response()
        }
        Err(e) => json_error(axum::http::StatusCode::INTERNAL_SERVER_ERROR, e).into_response(),
    }
}
