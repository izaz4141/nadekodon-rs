mod cancel;
mod delete;
mod details;
mod r#do;
mod file;
mod list;
mod pause;
mod resume;
mod update_url;

pub use cancel::handle_cancel_download;
pub use delete::*;
pub use details::*;
pub use r#do::handle_do_download;
pub use file::handle_download_file;
pub use list::*;
pub use pause::handle_pause_download;
pub use resume::*;
pub use update_url::*;

use crate::server::{SharedState, check_api_key};
use axum::middleware;
use axum::{
    Router,
    routing::{get, post},
};

pub fn create_download_router(state: SharedState) -> Router<SharedState> {
    Router::new()
        .route("/list", post(handle_get_download_list))
        .route("/details/{id}", get(handle_get_download_details))
        .route("/do", post(handle_do_download))
        .route("/pause", post(handle_pause_download))
        .route("/resume", post(handle_resume_download))
        .route("/cancel", post(handle_cancel_download))
        .route("/delete", post(handle_delete_download))
        .route("/update-url", post(handle_update_url))
        .route("/file/{id}", get(handle_download_file))
        .layer(middleware::from_fn_with_state(state, check_api_key))
}
