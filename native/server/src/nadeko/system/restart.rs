use crate::response::json_ok;
use crate::server::SharedState;
use axum::extract::State;
use axum::response::IntoResponse;
use std::sync::atomic::Ordering;

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
    // Tell long-lived streams to stop before shutting the server down so the
    // graceful shutdown does not have to wait for their lifetime cap.
    state.restart_requested.store(true, Ordering::SeqCst);
    state.restart_signal.notify_one();
    json_ok().into_response()
}
