mod api;
mod hash;
mod login;
mod salt;

pub use api::*;
pub use hash::*;
pub use login::*;
pub use salt::*;

use crate::server::{SharedState, check_api_key};
use axum::middleware;
use axum::{
    Router,
    routing::{get, post},
};

pub fn create_auth_router(state: SharedState) -> Router<SharedState> {
    let public_router = Router::new()
        .route("/login", post(handle_login));

    let protected_router = Router::new()
        .route("/hash", post(handle_hashing_password))
        .route("/generate-salt", get(handle_generate_salt))
        .route("/generate-api", get(handle_generate_api))
        .layer(middleware::from_fn_with_state(state.clone(), check_api_key));

    public_router.merge(protected_router).with_state(state)
}
