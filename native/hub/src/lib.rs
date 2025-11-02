//! This `hub` crate is the
//! entry point of the Rust logic.
mod signals;
mod downloader;
mod utils;

use downloader::{
    start_download_manager, spawn_download_worker,
    query_url_info, get_download_details,
    pause_download, resume_download, cancel_download
};
use rinf::{dart_shutdown, write_interface};
use tokio::spawn;



// Uncomment below to target the web.
// use tokio_with_wasm::alias as tokio;

write_interface!();

// You can go with any async library, not just `tokio`.
#[tokio::main(flavor = "current_thread")]
async fn main() {
    // Spawn concurrent tasks.
    // Always use non-blocking async functions like `tokio::fs::File::open`.
    // If you must use blocking code, use `tokio::task::spawn_blocking`
    // or the equivalent provided by your async library.

    let rclient = utils::url::build_browser_client().await;
    let dm = start_download_manager(rclient.clone()).await;
    spawn(utils::settings::update_settings(dm.clone()));
    spawn(query_url_info(rclient.clone()));
    spawn(spawn_download_worker(dm.clone()));
    spawn(get_download_details(dm.clone()));
    spawn(pause_download(dm.clone()));
    spawn(resume_download(dm.clone()));
    spawn(cancel_download(dm.clone()));

    // Keep the main function running until Dart shutdown.
    dart_shutdown().await;
}


