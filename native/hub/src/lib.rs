//! This `hub` crate is the
//! entry point of the Rust logic.
mod downloader;
mod signals;
mod utils;

extern crate nadekodon_core as ncore;

use ncore::app_context::AppContext;
use ncore::utils as cutils;
use ncore::utils::types::DMSettings;
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

    let rclient = cutils::url::build_browser_client().await;

    let settings = DMSettings {
        speed_limit: 0,
        concurrency_limit: 3,
        download_threads: 8,
        download_timeout: 30,
        download_retries: 5,
        seeding_ratio: 1.0,
        seeding_time: 30,
        download_dir: "Downloads".to_string(),
    };

    let context = AppContext::new(rclient.clone(), settings, shutdown_signal.clone()).await;
    let dm = context.dm().await;

    spawn(utils::settings::update_settings(dm.clone()));
    spawn(downloader::handle_init_torrent_persistence(dm.clone()));
    spawn(utils::database::start_database_manager(
        context.clone(),
        db_done_signal.clone(),
    ));
    spawn(utils::server::handle_api_key_generation());
    spawn(utils::server::start_server_listener(context.clone()));
    spawn(downloader::query_url_info(rclient.clone()));
    spawn(downloader::spawn_download_worker(dm.clone()));
    spawn(downloader::get_download_list(dm.clone()));
    spawn(downloader::get_download_details(dm.clone()));
    spawn(downloader::pause_download(dm.clone()));
    spawn(downloader::resume_download(dm.clone()));
    spawn(downloader::cancel_download(dm.clone()));
    spawn(downloader::delete_download(dm.clone()));
    spawn(downloader::handle_update_download_url(dm.clone()));
    spawn(utils::ytdlp::handle_ytdl_query());
    spawn(downloader::handle_ffmpeg_results());
    spawn(utils::security::handle_password_security());

    // Keep the main function running until Dart shutdown.
    dart_shutdown().await;

    // Signal database to save and exit
    shutdown_signal.notify_waiters();

    // Wait for database to finish saving (with timeout)
    let _ =
        tokio::time::timeout(std::time::Duration::from_secs(2), db_done_signal.notified()).await;
}
