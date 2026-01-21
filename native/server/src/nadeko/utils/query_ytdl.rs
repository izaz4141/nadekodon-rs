use axum::{extract::Json, response::IntoResponse};
use nadekodon_core::signals;
use nadekodon_core::utils::ytdlp;

pub async fn handle_query_ytdl(Json(payload): Json<signals::QueryYtdl>) -> impl IntoResponse {
    match ytdlp::get_ytdl_info(&payload.url).await {
        Ok(info) => Json(info).into_response(),
        Err(e) => (axum::http::StatusCode::INTERNAL_SERVER_ERROR, e).into_response(),
    }
}
