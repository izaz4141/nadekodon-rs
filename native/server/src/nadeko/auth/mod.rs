mod api;
mod change_credentials;
mod hash;
mod login;
mod salt;
mod verify_password;

pub use api::*;
pub use change_credentials::*;
pub use hash::*;
pub use login::*;
pub use salt::*;
pub use verify_password::*;

use crate::server::{SharedState, auth_rate_limit_config, check_api_key};
use axum::middleware;
use axum::{
    Router,
    routing::{get, post},
};
use tower_governor::GovernorLayer;

pub fn create_auth_router(state: SharedState) -> Router<SharedState> {
    let public_router = Router::new()
        .route("/login", post(handle_login))
        .layer(GovernorLayer::new(auth_rate_limit_config()));

    let protected_router = Router::new()
        .route("/hash", post(handle_hashing_password))
        .route("/generate-salt", get(handle_generate_salt))
        .route("/generate-api", get(handle_generate_api))
        .route("/change-credentials", post(handle_change_credentials))
        .route("/verify-password", post(handle_verify_password))
        .layer(middleware::from_fn_with_state(state.clone(), check_api_key))
        .layer(GovernorLayer::new(auth_rate_limit_config()));

    public_router.merge(protected_router).with_state(state)
}
