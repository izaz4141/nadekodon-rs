//! This `hub` crate is the
//! entry point of the Rust logic.
mod downloader;
mod signals;
mod utils;

use downloader::{
    cancel_download, delete_download, get_download_details, get_download_list,
    handle_init_torrent_persistence, handle_update_download_url, insert_download_worker,
    pause_download, query_url_info, resume_download, spawn_download_worker,
    spawn_progress_listener, start_download_manager,
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

    let shutdown_signal = std::sync::Arc::new(tokio::sync::Notify::new());
    let db_done_signal = std::sync::Arc::new(tokio::sync::Notify::new());

    let rclient = utils::url::build_browser_client().await;
    let dm = start_download_manager(rclient.clone()).await;

    spawn(utils::settings::update_settings(dm.clone()));
    spawn(handle_init_torrent_persistence(dm.clone()));
    spawn(utils::database::start_database_manager(
        dm.clone(),
        shutdown_signal.clone(),
        db_done_signal.clone(),
    ));
    spawn(utils::server::handle_api_key_generation());
    spawn(utils::server::start_server_listener(dm.clone()));
    spawn(query_url_info(rclient.clone()));
    spawn(spawn_download_worker(dm.clone()));
    spawn(spawn_progress_listener(dm.clone()));
    spawn(insert_download_worker(dm.clone()));
    spawn(get_download_list(dm.clone()));
    spawn(get_download_details(dm.clone()));
    spawn(pause_download(dm.clone()));
    spawn(resume_download(dm.clone()));
    spawn(cancel_download(dm.clone()));
    spawn(delete_download(dm.clone()));
    spawn(handle_update_download_url(dm.clone()));
    spawn(utils::ytdlp::handle_ytdl_query());
    spawn(utils::helper::handle_uuid_request());

    // Keep the main function running until Dart shutdown.
    dart_shutdown().await;

    // Signal database to save and exit
    shutdown_signal.notify_waiters();

    // Wait for database to finish saving (with timeout)
    let _ =
        tokio::time::timeout(std::time::Duration::from_secs(2), db_done_signal.notified()).await;
}
