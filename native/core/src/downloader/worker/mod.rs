use std::sync::{
    Arc,
    atomic::{AtomicBool, AtomicU64},
};
use tokio::{
    sync::{Mutex, Notify, RwLock, mpsc},
    task::JoinHandle,
};

use crate::utils::types::{DMSettings, DownloadInfo, WorkerEvent};
use librqbit::Session;

pub mod control;
pub mod hls;
pub mod http;
pub mod info;
pub mod init;
pub mod monitor;
pub mod speed;
pub mod start;
pub mod torrent;
use crate::downloader::manager::DownloadManager;

pub struct DownloadWorker {
    pub(crate) info: Mutex<DownloadInfo>,
    client: reqwest::Client,
    settings: Arc<RwLock<DMSettings>>,
    paused: AtomicBool,
    pub(crate) started: AtomicBool,
    cancel: AtomicBool,
    pub(crate) stalled: AtomicBool,
    threads: u64,
    speed_limit: AtomicU64,
    notify_resume: Notify,
    downloaded: AtomicU64,
    uploaded: AtomicU64,
    pub(crate) seeding_start: AtomicU64,
    pub(crate) history: RwLock<Vec<(u128, u64)>>,
    pub(crate) last_progress: AtomicU64,
    pub torrent_session: Arc<tokio::sync::RwLock<Option<Arc<Session>>>>,
    handles: Mutex<Vec<JoinHandle<anyhow::Result<()>>>>,
    part_progress: RwLock<Vec<Arc<AtomicU64>>>,
    pub event_tx: mpsc::Sender<WorkerEvent>,
    cookie: Option<String>,
    user_agent: Option<String>,
    dm: std::sync::Weak<DownloadManager>,
}

impl std::fmt::Debug for DownloadWorker {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.debug_struct("DownloadWorker")
            .field("info", &self.info)
            .field("paused", &self.paused)
            .field("started", &self.started)
            .field("cancel", &self.cancel)
            .field("stalled", &self.stalled)
            .field("threads", &self.threads)
            .field("speed_limit", &self.speed_limit)
            .field("downloaded", &self.downloaded)
            .field("uploaded", &self.uploaded)
            .finish()
    }
}
