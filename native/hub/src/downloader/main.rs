use anyhow::Result;
use futures::StreamExt;
use futures::future::join_all;
use reqwest::header::{ACCEPT_RANGES, CONTENT_LENGTH, RANGE};
use std::{
    collections::{HashMap, HashSet},
    fs::File,
    path::PathBuf,
    sync::{
        atomic::{AtomicBool, AtomicU64, Ordering},
        Arc,
    },
    time::{Duration, SystemTime, UNIX_EPOCH},
};
use tokio::{
    fs::File as TokioFile,
    io::{AsyncSeekExt, AsyncWriteExt, SeekFrom},
    sync::{mpsc, Mutex, Notify, Semaphore},
    task::JoinHandle,
    time::{timeout, interval},
};
use uuid::Uuid;
use rinf::{debug_print};

use crate::utils;

const READ_TIMEOUT_SECS: u64 = 15;
const MAX_READ_TIMEOUTS: u8 = 3;
const SEGMENT_GET_RETRIES: u8 = 3;
const HISTORY_SAMPLE_INTERVAL_SECS: u64 = 1;
const MAX_HISTORY: usize = 15;

struct HeadData {
    total_size: Option<u64>,
    accept_ranges: bool,
}

#[derive(Clone, Debug)]
pub enum DownloadState {
    Queued,
    Running,
    Paused,
    Completed,
    Cancelled,
    Error(String),
}

#[derive(Clone, Debug)]
pub struct DownloadInfo {
    pub id: Uuid,
    pub url: String,
    pub dest: PathBuf,
    pub total_size: Option<u64>,
    pub downloaded: u64,                 // public snapshot value (read from worker's AtomicU64 when queried)
    pub threads: u8,
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

pub struct DownloadWorker {
    // metadata and mutable state (except downloaded/history which are stored separately)
    info: Mutex<DownloadInfo>, // used for url, dest, total_size, threads, state; downloaded/history are filled on info()
    client: reqwest::Client,
    paused: AtomicBool,
    cancel: AtomicBool,
    max_speed:AtomicU64,
    notify_resume: Notify,
    downloaded: AtomicU64,
    history: Mutex<Vec<(u128, u64)>>,
    handles: Mutex<Vec<JoinHandle<anyhow::Result<()>>>>,
    pub event_tx: mpsc::Sender<WorkerEvent>,
}

impl DownloadWorker {
    pub fn new(
        id: Uuid,
        url: String,
        dest: PathBuf,
        threads: u8,
        max_speed: u64,
        event_tx: mpsc::Sender<WorkerEvent>,
    ) -> Arc<Self> {
        Arc::new(Self {
            info: Mutex::new(DownloadInfo {
                id,
                url: url.clone(),
                dest,
                total_size: None,
                downloaded: 0,
                threads,
                state: DownloadState::Queued,
                history: Vec::new(),
            }),
            client: utils::url::build_browser_client(),
            paused: AtomicBool::new(false),
            cancel: AtomicBool::new(false),
            max_speed: AtomicU64::new(max_speed),
            notify_resume: Notify::new(),
            downloaded: AtomicU64::new(0),
            history: Mutex::new(Vec::new()),
            handles: Mutex::new(Vec::new()),
            event_tx,
        })
    }

    pub async fn start(self: &Arc<Self>) -> Result<()> {
        debug_print!("start() called");

        if self.check_and_resume().await? {
            return Ok(()); // resumed
        }

        let (url, dest, threads) = self.extract_info().await;
        let head_data = self.fetch_head(&url).await?;
        self.update_total_size(head_data.total_size).await;

        if !head_data.accept_ranges || head_data.total_size.is_none() || threads <= 1 {
            debug_print!("Falling back to single-thread mode");
            self.spawn_single_thread(&url, &dest).await;
            return Ok(());
        }

        let size = head_data.total_size.unwrap();
        self.prepare_file(&dest, size)?;
        self.spawn_segments(&url, &dest, size, threads).await?;
        self.spawn_sampler_and_monitor().await?;

        debug_print!("start() exiting normally");
        Ok(())
    }

    // ───────────────────────────────
    // STEP 1: Resume or init
    // ───────────────────────────────
    async fn check_and_resume(self: &Arc<Self>) -> Result<bool> {
        let was_paused = self.paused.load(std::sync::atomic::Ordering::SeqCst);
        if was_paused {
            debug_print!("Resuming paused worker...");
            let worker = Arc::clone(self);
            worker.resume().await?;
            return Ok(true);
        }

        let mut info = self.info.lock().await;
        match info.state {
            DownloadState::Completed => {
                let _ = self.event_tx.send(WorkerEvent::Completed(info.id)).await;
                Ok(true)
            }
            DownloadState::Running => Ok(true),
            _ => {
                info.state = DownloadState::Running;
                debug_print!("Set state to Running");
                Ok(false)
            }
        }
    }

    async fn fetch_head(&self, url: &str) -> Result<HeadData> {
        let client = self.client.clone();
        debug_print!("HEAD {}", url);
        let head = client.head(url).send().await?;
        let status = head.status();
        debug_print!("HEAD status: {:?}", status);

        let total_size = head
            .headers()
            .get(CONTENT_LENGTH)
            .and_then(|hv| hv.to_str().ok())
            .and_then(|s| s.parse::<u64>().ok());

        let accept_ranges = head
            .headers()
            .get(ACCEPT_RANGES)
            .and_then(|hv| hv.to_str().ok())
            .map(|s| s.to_ascii_lowercase().contains("bytes"))
            .unwrap_or(false);

        debug_print!("total_size={:?}, accept_ranges={}", total_size, accept_ranges);

        Ok(HeadData {
            total_size,
            accept_ranges,
        })
    }

    async fn update_total_size(&self, size: Option<u64>) {
        if let Some(s) = size {
            let mut info = self.info.lock().await;
            info.total_size = Some(s);
        }
    }

    // ───────────────────────────────
    // STEP 3: Extract info
    // ───────────────────────────────
    async fn extract_info(&self) -> (String, std::path::PathBuf, u8) {
        let info = self.info.lock().await;
        (info.url.clone(), info.dest.clone(), info.threads)
    }

    // ───────────────────────────────
    // STEP 4: File preparation
    // ───────────────────────────────
    fn prepare_file(&self, dest: &std::path::Path, size: u64) -> Result<()> {
        debug_print!("Creating file {:?} size {}", dest.display(), size);
        let mut f = std::fs::File::create(dest)?;
        f.set_len(size)?;
        Ok(())
    }

    // ───────────────────────────────
    // STEP 5: Spawn segment workers
    // ───────────────────────────────
    async fn spawn_segments(self: &Arc<Self>, url: &str, dest: &std::path::Path, size: u64, threads: u8) -> Result<()> {
        let client = self.client.clone();
        let part_size = size / threads as u64;
        debug_print!("Spawning {} segments (part_size={})", threads, part_size);

        let mut handles = Vec::new();

        for i in 0..threads {
            let start = i as u64 * part_size;
            let end = if i == threads - 1 { size - 1 } else { start + part_size - 1 };

            let client = client.clone();
            let worker = Arc::clone(self);
            let url = url.to_string();
            let dest = dest.to_path_buf();

            let h = tokio::spawn(async move {
                worker.segment_download(i, &client, &url, &dest, start, end).await
            });
            handles.push(h);
        }

        let mut guard = self.handles.lock().await;
        *guard = handles;
        Ok(())
    }

    // ───────────────────────────────
    // STEP 6: Segment download logic
    // ───────────────────────────────
    async fn segment_download(
        &self,
        i: u8,
        client: &reqwest::Client,
        url: &str,
        dest: &std::path::Path,
        start: u64,
        end: u64,
    ) -> Result<()> {

        let mut segment_progress = 0u64;
        for attempt in 1..=SEGMENT_GET_RETRIES {
            debug_print!("Segment {} attempt {}", i, attempt);

            if self.cancel.load(std::sync::atomic::Ordering::SeqCst) {
                debug_print!("Segment {} canceled early", i);
                return Ok(());
            }

            while self.paused.load(std::sync::atomic::Ordering::SeqCst) {
                debug_print!("Segment {} paused before request", i);
                self.notify_resume.notified().await;
            }

            let current_start = start + segment_progress;
            if current_start > end {
                debug_print!("Segment {} already complete", i);
                return Ok(());
            }

            let range = format!("bytes={}-{}", current_start, end);
            let resp = match client.get(url).header(RANGE, &range).send().await {
                Ok(r) => match r.error_for_status() {
                    Ok(v) => v,
                    Err(e) => return Err(anyhow::anyhow!("Segment {} bad status: {}", i, e)),
                },
                Err(e) => {
                    debug_print!("Segment {} request failed: {:?}", i, e);
                    continue;
                }
            };

            let mut file = TokioFile::options().write(true).open(dest).await?;
            file.seek(SeekFrom::Start(current_start)).await?;
            let mut stream = resp.bytes_stream();

            while let Ok(chunk_res) = timeout(Duration::from_secs(READ_TIMEOUT_SECS), stream.next()).await {
                while self.paused.load(Ordering::SeqCst) {
                    self.notify_resume.notified().await;
                }
                if self.cancel.load(Ordering::SeqCst) {
                    return Ok(());
                }
                match chunk_res {
                    Some(Ok(chunk)) => {
                        file.write_all(&chunk).await?;
                        segment_progress += chunk.len() as u64;
                        self.downloaded.fetch_add(chunk.len() as u64, std::sync::atomic::Ordering::SeqCst);
                        if start + segment_progress > end {
                            break;
                        }
                    }
                    _ => break,
                }
            }

            if start + segment_progress >= end {
                debug_print!("Segment {} completed fully", i);
                return Ok(());
            }
        }
        Err(anyhow::anyhow!("Segment {} failed after retries", i))
    }

    // ───────────────────────────────
    // STEP 7: Sampler + Monitor
    // ───────────────────────────────
    async fn spawn_sampler_and_monitor(self: &Arc<Self>) -> Result<()> {
        let stop_flag = Arc::new(Notify::new());
        let stop_clone = stop_flag.clone();

        self.spawn_sampler(stop_flag);
        self.spawn_monitor(stop_clone).await?;
        Ok(())
    }

    fn spawn_sampler(self: &Arc<Self>, stop_flag: Arc<Notify>) {
        let sampler_worker = Arc::clone(self);
        tokio::spawn(async move {
            let mut samp = interval(Duration::from_secs(HISTORY_SAMPLE_INTERVAL_SECS));
            loop {
                if sampler_worker.paused.load(std::sync::atomic::Ordering::SeqCst) {
                    sampler_worker.notify_resume.notified().await;
                    continue;
                }
                if sampler_worker.cancel.load(std::sync::atomic::Ordering::SeqCst) {
                    debug_print!("Sampler exiting (cancel)");
                    break;
                }

                tokio::select! {
                    _ = samp.tick() => {
                        let snapshot = sampler_worker.downloaded.load(std::sync::atomic::Ordering::SeqCst);
                        let ts = SystemTime::now().duration_since(UNIX_EPOCH).unwrap().as_millis();
                        let mut hist = sampler_worker.history.lock().await;
                        hist.push((ts, snapshot));
                        if hist.len() > MAX_HISTORY { 
                            let remove = hist.len() - MAX_HISTORY; 
                            hist.drain(0..remove);
                        }
                        debug_print!("Sampler sampling history");
                    }
                    _ = stop_flag.notified() => {
                        debug_print!("Sampler stopping on signal");
                        break;
                    }
                }
            }
        });
    }

    async fn spawn_monitor(self: &Arc<Self>, stop_flag: Arc<Notify>) -> Result<()> {
        let monitor_worker = Arc::clone(self);
        let handles = {
            let mut guard = monitor_worker.handles.lock().await;
            std::mem::take(&mut *guard)
        };

        tokio::spawn(async move {
            debug_print!("Monitor started with {} segments", handles.len());
            let results = join_all(handles).await;

            for (i, res) in results.into_iter().enumerate() {
                match res {
                    Ok(Ok(())) => debug_print!("Monitor: segment {} OK", i),
                    Ok(Err(e)) => {
                        debug_print!("Monitor: segment {} failed {:?}", i, e);
                        stop_flag.notify_waiters();
                        return;
                    }
                    Err(e) => {
                        debug_print!("Monitor: join error {:?}", e);
                        stop_flag.notify_waiters();
                        return;
                    }
                }
            }

            stop_flag.notify_waiters();
            let mut info = monitor_worker.info.lock().await;
            info.state = DownloadState::Completed;
            let id = info.id;
            let _ = monitor_worker.event_tx.send(WorkerEvent::Completed(id)).await;
        });

        Ok(())
    }

    // ───────────────────────────────
    // SINGLE-THREAD FALLBACK
    // ───────────────────────────────
    async fn spawn_single_thread(self: &Arc<Self>, url: &str, dest: &std::path::Path) {
        let worker = Arc::clone(self);
        let url = url.to_string();
        let dest = dest.to_path_buf();
        let h = tokio::spawn(async move { worker.single_thread_download(&url, &dest).await });
        self.handles.lock().await.push(h);
    }

    async fn single_thread_download(&self, url: &str, dest: &PathBuf) -> Result<()> {
        let resp = self.client.get(url).send().await?;
        let mut stream = resp.bytes_stream();
        let mut f = TokioFile::create(dest).await?;

        while let Some(chunk_res) = stream.next().await {
            let chunk = chunk_res?;
            
            while self.paused.load(Ordering::SeqCst) {
                self.notify_resume.notified().await;
            }
            if self.cancel.load(Ordering::SeqCst) {
                return Ok(());
            }

            f.write_all(&chunk).await?;
            let added = chunk.len() as u64;
            let new_total = self.downloaded.fetch_add(added, Ordering::SeqCst) + added;

            // append history sample
            let ts = SystemTime::now()
                .duration_since(UNIX_EPOCH)
                .unwrap_or_default()
                .as_millis();
            {
                let mut hist = self.history.lock().await;
                hist.push((ts, new_total));
                let len = hist.len();
                if len > MAX_HISTORY {
                    let remove = len - MAX_HISTORY;
                    // drain will remove the oldest `remove` entries
                    hist.drain(0..remove);
                }
            }
        }

        let mut info = self.info.lock().await;
        info.state = DownloadState::Completed;
        info.downloaded = self.downloaded.load(Ordering::SeqCst);
        let hist = self.history.lock().await;
        info.history = hist.clone();
        let _ = self.event_tx.send(WorkerEvent::Completed(info.id)).await;
        Ok(())
    }

    pub async fn pause(&self) -> Result<()> {
        self.paused.store(true, Ordering::SeqCst);
        let mut info = self.info.lock().await;
        info.state = DownloadState::Paused;
        info.downloaded = self.downloaded.load(Ordering::SeqCst);
        info.history = self.history.lock().await.clone();
        Ok(())
    }

    pub async fn resume(self: &Arc<Self>) -> Result<()> {
        self.paused.store(false, Ordering::SeqCst);
        self.notify_resume.notify_waiters();
        {
            let mut info = self.info.lock().await;
            info.state = DownloadState::Running;
        }
        Ok(())
    }

    pub async fn cancel(&self) -> Result<()> {
        self.cancel.store(true, Ordering::SeqCst);
        let mut handles = self.handles.lock().await;
        for h in handles.drain(..) {
            h.abort();
        }
        let mut info = self.info.lock().await;
        info.state = DownloadState::Cancelled;
        self.paused.store(false, Ordering::SeqCst);
        self.notify_resume.notify_waiters();
        info.downloaded = self.downloaded.load(Ordering::SeqCst);
        info.history = self.history.lock().await.clone();
        let id = info.id;
        let _ = self.event_tx.send(WorkerEvent::Cancelled(id)).await;
        Ok(())
    }

    /// Build a public snapshot DownloadInfo combining the metadata (info mutex)
    /// with the atomic downloaded counter and history.
    pub async fn snapshot_info(&self) -> DownloadInfo {
        let meta = self.info.lock().await;
        let mut snapshot = meta.clone(); // clone url/dest/total_size/threads/state
        // override downloaded and history with authoritative values
        let d = self.downloaded.load(Ordering::SeqCst);
        snapshot.downloaded = d;
        let hist = self.history.lock().await;
        snapshot.history = hist.clone();
        snapshot
    }
    /// Query public snapshot info for this worker.
    /// This constructs a DownloadInfo snapshot using metadata + atomic downloaded + history.
    pub async fn info(&self) -> DownloadInfo {
        self.snapshot_info().await
    }
}

pub struct DownloadManager {
    workers: Arc<Mutex<HashMap<Uuid, Arc<DownloadWorker>>>>,
    active: Arc<Mutex<HashSet<Uuid>>>,
    semaphore: Arc<Semaphore>,
    sender: mpsc::Sender<WorkerEvent>,
}

impl DownloadManager {
    pub fn new(max_concurrency: usize) -> Arc<Self> {
        let (tx, mut rx) = mpsc::channel::<WorkerEvent>(64);
        let mgr = Arc::new(Self {
            workers: Arc::new(Mutex::new(HashMap::new())),
            active: Arc::new(Mutex::new(HashSet::new())),
            semaphore: Arc::new(Semaphore::new(max_concurrency)),
            sender: tx.clone(),
        });

        let mgr_clone = Arc::clone(&mgr);
        tokio::spawn(async move {
            while let Some(event) = rx.recv().await {
                mgr_clone.handle_event(event).await;
            }
        });

        mgr
    }

    async fn handle_event(self: &Arc<Self>, event: WorkerEvent) {
        match event {
            WorkerEvent::Completed(id) => {
                self.active.lock().await.remove(&id);
                debug_print!("Worker {:?} completed", id);
            }
            WorkerEvent::Cancelled(id) => {
                self.active.lock().await.remove(&id);
                debug_print!("Worker {:?} cancelled", id);
            }
            WorkerEvent::Error(id, err) => {
                self.active.lock().await.remove(&id);
                debug_print!("Worker {:?} errored: {}", id, err);
            }
        }
        self.process_queue().await;
    }

    pub async fn process_queue(&self) {
        let allowed = self.semaphore.available_permits();
        if allowed == 0 {
            return;
        }

        let active_count = self.active.lock().await.len();
        let remaining = allowed.saturating_sub(active_count);

        if remaining == 0 {
            return;
        }

        let workers = self.workers.lock().await;
        let mut to_start = Vec::new();
        for (id, w) in workers.iter() {
            let info = w.info().await;
            if matches!(info.state, DownloadState::Queued) {
                to_start.push(*id);
            }
            if to_start.len() >= remaining {
                break;
            }
        }
        drop(workers);

        for id in to_start {
            let _ = self.start(id).await;
        }
    }

    pub async fn add_download(&self, url: String, dest: PathBuf, threads: u8, max_speed: u64) -> Result<Uuid> {
        let id = Uuid::new_v4();
        let worker = DownloadWorker::new(
            id, url, dest, threads, max_speed, self.sender.clone()
        );
        self.workers.lock().await.insert(id, worker);
        self.process_queue().await;
        Ok(id)
    }

    pub async fn start(&self, id: Uuid) -> Result<()> {
        let worker_opt = { self.workers.lock().await.get(&id).cloned() };
        let worker = match worker_opt {
            Some(w) => w,
            None => return Err(anyhow::anyhow!("Worker not found")),
        };

        let sem = self.semaphore.clone();
        let permit = sem.acquire_owned().await.unwrap();
        {
            self.active.lock().await.insert(id);
        }

        let w = Arc::clone(&worker);
        tokio::spawn(async move {
            let _permit = permit; // keep permit alive while active
            if let Err(e) = w.start().await {
                let mut info = w.info.lock().await;
                info.state = DownloadState::Error(format!("{:?}", e));
                let _ = w
                    .event_tx
                    .send(WorkerEvent::Error(info.id, e.to_string()))
                    .await;
            }
        });
        Ok(())
    }

    pub async fn pause(&self, id: Uuid) -> Result<()> {
        let w = { self.workers.lock().await.get(&id).cloned() };
        match w {
            Some(worker) => {
                worker.pause().await?;
                self.active.lock().await.remove(&id);
                self.process_queue().await;
                Ok(())
            }
            None => Err(anyhow::anyhow!("Worker not found")),
        }
    }

    pub async fn resume(&self, id: Uuid) -> Result<()> {
        let w = { self.workers.lock().await.get(&id).cloned() };
        match w {
            Some(worker) => {
                {
                    let mut info = worker.info.lock().await;
                    match info.state {
                        DownloadState::Completed | DownloadState::Running => {
                            debug_print!("Already completed or running, skipping");
                            return Ok(());
                        }
                        _ => {
                            info.state = DownloadState::Queued;
                            debug_print!("Set state to Queued");
                        }
                    }
                }
                self.process_queue().await;
                Ok(())
            }
            None => Err(anyhow::anyhow!("Worker not found")),
        }
    }

    pub async fn cancel(&self, id: Uuid) -> Result<()> {
        let w = { self.workers.lock().await.remove(&id) };
        match w {
            Some(worker) => {
                worker.cancel().await?;
                self.active.lock().await.remove(&id);
                self.process_queue().await;
                Ok(())
            }
            None => Err(anyhow::anyhow!("Worker not found")),
        }
    }

    pub async fn info(&self, id: Uuid) -> Result<DownloadInfo> {
        let w = {
            let map = self.workers.lock().await;
            map.get(&id).cloned()
        };
        match w {
            Some(worker) => Ok(worker.info().await),
            None => Err(anyhow::anyhow!("Worker not found")),
        }
    }

    pub async fn list_all(&self) -> Result<Vec<DownloadInfo>> {
        let map = self.workers.lock().await;
        let mut out = Vec::new();
        for w in map.values() {
            out.push(w.info().await);
        }
        Ok(out)
    }
}