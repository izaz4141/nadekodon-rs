use crate::signals::InitDatabase;
use crate::utils::{logger, tagging::handle_tagging};

extern crate nadekodon_core as core;
use core::app_context::AppContext;
use rinf::DartSignal;
use std::path::PathBuf;
use std::sync::Arc;
use tokio::{spawn, sync::Notify};

pub async fn start_database_manager(context: Arc<AppContext>, db_done_signal: Arc<Notify>) {
    spawn(handle_tagging());
    let receiver = InitDatabase::get_dart_signal_receiver();
    while let Some(signal_pack) = receiver.recv().await {
        let path = signal_pack.message.path;
        let db_path = PathBuf::from(path);
        if let Some(parent) = db_path.parent() {
            unsafe {
                std::env::set_var("NADEKO_HOME", parent);
            }
        }

        let context_clone = context.clone();
        let db_signal = db_done_signal.clone();

        tokio::spawn(async move {
            if let Err(e) = context_clone
                .start_database_manager(db_path, db_signal)
                .await
            {
                logger::error(&format!("Failed to start database manager: {:?}", e));
            }
        });
    }
}
