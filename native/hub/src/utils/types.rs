use serde::{Deserialize, Serialize};
use std::path::PathBuf;
use uuid::Uuid;

#[derive(Debug, Clone)]
pub struct DMSettings {
    pub speed_limit: u64,
    pub download_threads: u8,
    pub concurrency_limit: u8,
    pub download_timeout: u64,
    pub download_retries: u8,
    pub seeding_ratio: f32,
    pub seeding_time: u64,
}

#[derive(Debug)]
pub struct HeadData {
    pub total_size: Option<u64>,
    pub accept_ranges: bool,
    pub content_type: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub enum DownloadType {
    Normal,
    Torrent,
    HLS,
}

impl Default for DownloadType {
    fn default() -> Self {
        Self::Normal
    }
}

#[derive(Debug, Clone)]
pub enum DownloadState {
    Queued,
    Running,
    Paused,
    Completed,
    Seeding,
    Cancelled,
    Error(String),
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct PartInfo {
    pub start: u64,
    pub end: u64,
    pub current: u64,
}

#[derive(Debug, Clone)]
pub struct DownloadInfo {
    pub id: Uuid,
    pub url: String,
    pub dest: PathBuf,
    pub total_size: Option<u64>,
    pub downloaded: u64,
    pub uploaded: u64,
    pub state: DownloadState,
    pub history: Vec<(u128, u64)>,
    pub parts: Vec<PartInfo>,
    pub added_at: u64,
    pub updated_at: u64,
    pub download_type: DownloadType,
    pub torrent_hash: Option<String>,
}

#[derive(Debug, Clone)]
pub enum WorkerEvent {
    Completed(Uuid),
    Error(Uuid, String),
    Cancelled(Uuid),
}
