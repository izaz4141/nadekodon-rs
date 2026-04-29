pub mod img;
pub mod query_url;
pub mod query_ytdl;

pub use img::*;
pub use query_url::*;
pub use query_ytdl::*;

use crate::security::check_api_key;
use crate::server::SharedState;
use axum::middleware;
use axum::{
    Router,
    routing::{get, post},
};

pub fn create_utils_router(state: SharedState) -> Router<SharedState> {
    Router::new()
        .route("/query-url", post(handle_query_url))
        .route("/query-ytdl", post(handle_query_ytdl))
        .route("/img", get(handle_proxy_image))
        .layer(middleware::from_fn_with_state(state, check_api_key))
}
