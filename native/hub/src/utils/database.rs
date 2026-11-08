use crate::signals::{InitDatabaseRequest, InitDatabaseResponse};
use crate::utils::{logger, tagging::handle_tagging};

extern crate nadekodon_core as core;
use core::app_context::AppContext;
use rinf::{DartSignal, RustSignal};
use std::path::PathBuf;
use std::sync::Arc;
use tokio::{spawn, sync::Notify};

pub async fn start_database_manager(context: Arc<AppContext>, db_done_signal: Arc<Notify>) {
    spawn(handle_tagging());
    let receiver = InitDatabaseRequest::get_dart_signal_receiver();
    while let Some(signal_pack) = receiver.recv().await {
        let message = signal_pack.message;
        let path = message.path;
        let db_path = PathBuf::from(path);
        if let Some(parent) = db_path.parent() {
            unsafe {
                std::env::set_var("NADEKO_HOME", parent);
            }
        }

        // Initialize before reporting success so Dart cannot act while the
        // database is missing.
        let success = match context.init_database(db_path, db_done_signal.clone()).await {
            Ok(db) => {
                spawn(async move {
                    db.run_loop().await;
                });
                logger::debug("Database manager started");
                true
            }
            Err(e) => {
                logger::error(&format!("Failed to start database manager: {:?}", e));
                false
            }
        };

        InitDatabaseResponse {
            id: message.id,
            success,
        }
        .send_signal_to_dart();
    }
}
