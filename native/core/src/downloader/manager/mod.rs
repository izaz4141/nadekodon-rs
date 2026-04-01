use indexmap::IndexMap;
use std::{
    collections::{HashMap, HashSet},
    sync::{Arc, atomic::AtomicU8},
};
use tokio::sync::{Mutex, RwLock, broadcast, mpsc};
use uuid::Uuid;

use crate::app_context::AppContext;
use crate::utils::types::{CategoryInfo, DMSettings, WorkerEvent};
use librqbit::Session;

pub mod categories;
pub mod controls;
pub mod core;
pub mod downloads;
pub mod queries;
pub mod settings;
pub mod state;
use crate::downloader::worker::DownloadWorker;

pub struct DownloadManager {
    pub client: reqwest::Client,
    pub settings: Arc<RwLock<DMSettings>>,
    workers: Arc<Mutex<IndexMap<Uuid, Arc<DownloadWorker>>>>,
    active: Arc<Mutex<HashSet<Uuid>>>,
    concurrency: Arc<AtomicU8>,
    sender: mpsc::Sender<WorkerEvent>,
    pub broadcast_tx: broadcast::Sender<WorkerEvent>,
    pending_deletions: Arc<Mutex<Vec<Uuid>>>,
    pub torrent_session: Arc<tokio::sync::RwLock<Option<Arc<Session>>>>,
    pub categories: Arc<RwLock<HashMap<String, CategoryInfo>>>,
    context: std::sync::Weak<AppContext>,
}

impl std::fmt::Debug for DownloadManager {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.debug_struct("DownloadManager")
            .field("settings", &self.settings)
            .field("workers", &self.workers)
            .field("active", &self.active)
            .field("concurrency", &self.concurrency)
            .finish()
    }
}

impl DownloadManager {
    pub fn subscribe(&self) -> broadcast::Receiver<WorkerEvent> {
        self.broadcast_tx.subscribe()
    }
}
