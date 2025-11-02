use serde::Deserialize;
use std::{
    collections::{HashMap, HashSet},
    path::PathBuf,
    sync::{
        atomic::{AtomicBool, AtomicU64, Ordering},
        Arc,
    },
};
use tokio::{
    sync::{mpsc, Mutex, Notify, Semaphore},
    task::JoinHandle,
};
use uuid::Uuid;

#[derive(Debug, Clone)]
pub struct DMSettings {
    pub speed_limit: u64,
    pub download_threads: u8,
    pub concurrency_limit: u8,
    pub download_timeout: u64,
    pub download_retries: u8,
}

#[derive(Debug, Clone)]
pub struct ServerSettings {
    pub port: Option<u16>,
}

#[derive(Debug)]
pub struct HeadData {
    pub total_size: Option<u64>,
    pub accept_ranges: bool,
}

#[derive(Debug, Clone)]
pub enum DownloadState {
    Queued,
    Running,
    Paused,
    Completed,
    Cancelled,
    Error(String),
}

#[derive(Debug, Clone)]
pub struct DownloadInfo {
    pub id: Uuid,
    pub url: String,
    pub dest: PathBuf,
    pub total_size: Option<u64>,
    pub downloaded: u64, 
    pub state: DownloadState,
    // history is a list of (timestamp_millis, downloaded_bytes) samples
    pub history: Vec<(u128, u64)>,
}

#[derive(Debug)]
pub enum WorkerEvent {
    Completed(Uuid),
    Error(Uuid, String),
    Cancelled(Uuid),
}