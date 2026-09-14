use axum::{Json, http::StatusCode, response::IntoResponse};
use nadekodon_core::signals::{ErrorResponse, OkResponse};

pub fn json_ok() -> impl IntoResponse {
    Json(OkResponse::success())
}

pub fn json_error(status: StatusCode, msg: impl AsRef<str>) -> impl IntoResponse {
    (
        status,
        Json(ErrorResponse {
            error: msg.as_ref().to_string(),
        }),
    )
}