use anyhow::Result;
use std::{
    path::PathBuf,
    sync::{
        Arc,
        atomic::{AtomicBool, AtomicU64},
    },
    time::{SystemTime, UNIX_EPOCH},
};
use tokio::sync::{Mutex, Notify, RwLock, mpsc};
use uuid::Uuid;

use crate::utils::types::{DMSettings, DownloadInfo, DownloadState, DownloadType, WorkerEvent};
use librqbit::Session;

use crate::downloader::manager::DownloadManager;
use crate::downloader::worker::DownloadWorker;

impl DownloadWorker {
    pub async fn new(
        id: Uuid,
        client: reqwest::Client,
        settings: Arc<RwLock<DMSettings>>,
        url: String,
        dest: PathBuf,
        event_tx: mpsc::Sender<WorkerEvent>,
        torrent_session: Arc<tokio::sync::RwLock<Option<Arc<Session>>>>,
        cookie: Option<String>,
        user_agent: Option<String>,
        referer: Option<String>,
        category: Option<String>,
        dm: std::sync::Weak<DownloadManager>,
    ) -> Result<Arc<Self>, &'static str> {
        let speed_limit = settings.read().await.speed_limit;

        if let Some(ref cat) = category {
            let dm_ref = dm.upgrade().ok_or("DownloadManager dropped")?;
            dm_ref.create_category(cat.clone(), None).await?;
        }

        let worker = Arc::new(Self {
            info: Mutex::new(DownloadInfo {
                id,
                url: url.clone(),
                dest,
                total_size: None,
                downloaded: 0,
                uploaded: 0,
                uspeed: None,
                state: DownloadState::Queued,
                history: Vec::new(),
                parts: Vec::new(),
                added_at: SystemTime::now()
                    .duration_since(UNIX_EPOCH)
                    .unwrap()
                    .as_millis() as u64,
                updated_at: SystemTime::now()
                    .duration_since(UNIX_EPOCH)
                    .unwrap()
                    .as_millis() as u64,
                download_type: DownloadType::Normal,
                torrent_hash: None,
                referer,
                category,
                seeding_ratio_override: None,
                seeding_time_override: None,
            }),
            client,
            threads: settings.clone().read().await.download_threads as u64,
            settings,
            paused: AtomicBool::new(false),
            started: AtomicBool::new(false),
            cancel: AtomicBool::new(false),
            speed_limit: AtomicU64::new(speed_limit),
            notify_resume: Notify::new(),
            downloaded: AtomicU64::new(0),
            uploaded: AtomicU64::new(0),
            seeding_start: AtomicU64::new(0),
            history: RwLock::new(Vec::new()),
            handles: Mutex::new(Vec::new()),
            part_progress: RwLock::new(Vec::new()),
            event_tx,
            torrent_session,
            cookie,
            user_agent,
            dm,
        });

        Ok(worker)
    }

    pub async fn from_info(
        info: DownloadInfo,
        client: reqwest::Client,
        settings: Arc<RwLock<DMSettings>>,
        event_tx: mpsc::Sender<WorkerEvent>,
        torrent_session: Arc<tokio::sync::RwLock<Option<Arc<Session>>>>,
        dm: std::sync::Weak<DownloadManager>,
    ) -> Result<Arc<Self>, &'static str> {
        let speed_limit = settings.read().await.speed_limit;

        if let Some(ref cat) = info.category {
            let dm_ref = dm.upgrade().ok_or("DownloadManager dropped")?;
            dm_ref.create_category(cat.clone(), None).await?;
        }

        let downloaded = info.downloaded;
        let uploaded = info.uploaded;
        let mut parts_progress = Vec::new();
        for part in &info.parts {
            parts_progress.push(Arc::new(AtomicU64::new(part.current)));
        }

        // Reset state to Paused if it was Running or Queued, to avoid auto-start issues
        let mut safe_info = info.clone();
        match safe_info.state {
            DownloadState::Running | DownloadState::Queued | DownloadState::Seeding => {
                safe_info.state = DownloadState::Paused;
            }
            _ => {}
        }

        let is_paused = matches!(safe_info.state, DownloadState::Paused);

        let worker = Arc::new(Self {
            info: Mutex::new(safe_info.clone()),
            client,
            threads: settings.clone().read().await.download_threads as u64,
            settings,
            paused: AtomicBool::new(is_paused),
            started: AtomicBool::new(false),
            cancel: AtomicBool::new(false),
            speed_limit: AtomicU64::new(speed_limit),
            notify_resume: Notify::new(),
            downloaded: AtomicU64::new(downloaded),
            uploaded: AtomicU64::new(uploaded),
            seeding_start: AtomicU64::new(0),
            history: RwLock::new(safe_info.history),
            handles: Mutex::new(Vec::new()),
            part_progress: RwLock::new(parts_progress),
            event_tx,
            torrent_session,
            cookie: None,
            user_agent: None,
            dm,
        });

        Ok(worker)
    }
}
