pub mod compare;
pub mod current;
pub mod latest;

pub use compare::*;
pub use current::*;
pub use latest::*;

use crate::security::check_api_key;
use crate::server::SharedState;
use axum::middleware;
use axum::{
    Router,
    routing::{get, post},
};

pub fn create_version_router(state: SharedState) -> Router<SharedState> {
    Router::new()
        .route("/latest", get(handle_version_latest))
        .route("/current", get(handle_version_current))
        .route("/compare", post(handle_compare_versions))
        .layer(middleware::from_fn_with_state(state, check_api_key))
}
