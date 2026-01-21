use crate::server::SharedState;
use axum::{Json, extract::State, response::IntoResponse};
use nadekodon_core::signals;

pub async fn handle_query_url(
    State(state): State<SharedState>,
    Json(payload): Json<signals::QueryUrl>,
) -> impl IntoResponse {
    match nadekodon_core::downloader::query_url_info_internal(
        state.context.dm().await.client.clone(),
        payload,
    )
    .await
    {
        Ok(info) => Json(info).into_response(),
        Err(e) => (axum::http::StatusCode::INTERNAL_SERVER_ERROR, e.to_string()).into_response(),
    }
}
