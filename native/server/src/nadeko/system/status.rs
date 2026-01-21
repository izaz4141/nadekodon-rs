use axum::response::IntoResponse;

pub async fn handle_status() -> impl IntoResponse {
    (axum::http::StatusCode::OK, "Online")
}
