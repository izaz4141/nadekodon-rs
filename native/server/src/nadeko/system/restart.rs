use crate::server::SharedState;
use axum::extract::State;
use axum::response::IntoResponse;

pub async fn handle_restart(State(state): State<SharedState>) -> impl IntoResponse {
    state.restart_signal.notify_one();
    axum::http::StatusCode::OK
}
