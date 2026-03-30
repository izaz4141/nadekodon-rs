pub mod restart;
pub mod settings;
pub mod status;

pub use restart::*;
pub use settings::*;
pub use status::*;

use crate::server::{SharedState, check_api_key};
use axum::{
    Router, middleware,
    routing::{get, post},
};

pub fn create_system_router(state: SharedState) -> Router<SharedState> {
    Router::new()
        .route("/restart", post(handle_restart))
        .route(
            "/settings",
            get(handle_get_settings).post(handle_update_settings),
        )
        .layer(middleware::from_fn_with_state(state, check_api_key))
}
