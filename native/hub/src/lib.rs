//! This `hub` crate is the
//! entry point of the Rust logic.
mod signals;
mod downloader;
mod utils;

use downloader::{
    start_download_manager, spawn_download_worker,
    query_url_info,
    get_download_details, list_downloads,
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

    let dm = start_download_manager().await;
    spawn(query_url_info());
    spawn(spawn_download_worker(dm.clone()));
    spawn(list_downloads(dm.clone()));
    spawn(get_download_details(dm.clone()));
    spawn(pause_download(dm.clone()));
    spawn(resume_download(dm.clone()));
    spawn(cancel_download(dm.clone()));

    // Keep the main function running until Dart shutdown.
    dart_shutdown().await;
}


