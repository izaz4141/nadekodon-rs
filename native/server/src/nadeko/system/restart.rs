use crate::server::SharedState;
use axum::extract::State;
use axum::response::IntoResponse;

#[utoipa::path(
    post,
    path = "/api/nadeko/system/restart",
    tags = ["nadeko.system"],
    security(("ApiKeyAuth" = [])),
    responses(
        (status = 200, description = "Server restart initiated")
    )
)]
pub async fn handle_restart(State(state): State<SharedState>) -> impl IntoResponse {
    state.restart_signal.notify_one();
    axum::http::StatusCode::OK
}
