mod auth;
mod download;
mod system;
mod utils;
mod version;

pub use auth::*;
pub use download::*;
pub use system::*;
pub use utils::*;
pub use version::*;

use crate::server::SharedState;
use axum::Router;

pub fn create_nadeko_router(state: SharedState) -> Router<SharedState> {
    let auth_router = create_auth_router(state.clone());
    let download_router = create_download_router(state.clone());
    let system_router = create_system_router(state.clone());
    let utils_router = create_utils_router(state.clone());
    let version_router = create_version_router(state.clone());

    Router::new()
        .nest("/auth", auth_router)
        .nest("/download", download_router)
        .nest("/system", system_router)
        .nest("/utils", utils_router)
        .nest("/version", version_router)
        .with_state(state)
}
