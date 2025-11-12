use anyhow::Result;
use futures::StreamExt;
use futures::future::join_all;
use indexmap::IndexMap;
use reqwest::header::{ACCEPT_RANGES, CONTENT_LENGTH, RANGE};
use std::{
    collections::HashSet, path::PathBuf, sync::{
        Arc, atomic::{AtomicBool, AtomicU8, AtomicU64, Ordering}
    }, time::{Duration, SystemTime, UNIX_EPOCH}
};
use tokio::{
    fs::File as TokioFile,
    io::{AsyncSeekExt, AsyncWriteExt, SeekFrom},
    sync::{mpsc, Mutex, Notify, RwLock},
    task::JoinHandle,
    time::{timeout, interval, Interval, Instant, sleep_until},
};
use uuid::Uuid;
use crate::utils::logger;
use rinf::RustSignal;

use crate::utils::{
    types::{
        HeadData, DownloadState, DownloadInfo,
        WorkerEvent, DMSettings,
    },
    helper::calc_speed,
    url::is_hls_url,
};
use crate::signals::{DownloadGlance, DownloadList};

const HISTORY_SAMPLE_INTERVAL_SECS: u64 = 1;
const MAX_HISTORY: usize = 15;

#[derive(Debug)]
pub struct DownloadWorker {
    info: Mutex<DownloadInfo>,
    client: reqwest::Client,
    settings: Arc<RwLock<DMSettings>>,
    paused: AtomicBool,
    started: AtomicBool,
    cancel: AtomicBool,
    threads: u64,
    speed_limit:AtomicU64,
    notify_resume: Notify,
    downloaded: AtomicU64,
    history: RwLock<Vec<(u128, u64)>>,
    handles: Mutex<Vec<JoinHandle<anyhow::Result<()>>>>,
    pub event_tx: mpsc::Sender<WorkerEvent>,
}

impl DownloadWorker {
    pub async fn new(
        id: Uuid,
        client: reqwest::Client,
        settings: Arc<RwLock<DMSettings>>,
        url: String,
        dest: PathBuf,
        event_tx: mpsc::Sender<WorkerEvent>,
    ) -> Arc<Self> {
        let speed_limit = settings.read().await.speed_limit;
        Arc::new(Self {
            info: Mutex::new(DownloadInfo {
                id,
                url: url.clone(),
                dest,
                total_size: None,
                downloaded: 0,
                state: DownloadState::Queued,
                history: Vec::new(),
            }),
            client: client,
            threads: settings.clone().read().await.download_threads as u64,
            settings: settings,
            paused: AtomicBool::new(false),
            started: AtomicBool::new(false),
            cancel: AtomicBool::new(false),
            speed_limit: AtomicU64::new(speed_limit),
            notify_resume: Notify::new(),
            downloaded: AtomicU64::new(0),
            history: RwLock::new(Vec::new()),
            handles: Mutex::new(Vec::new()),
            event_tx,
        })
    }

    pub async fn start(self: &Arc<Self>) -> Result<()> {
        if self.check_and_resume().await? {
            return Ok(());
        }
        self.started.store(true, Ordering::SeqCst);

        let threads = self.threads;
        let (url, dest) = self.extract_info().await;
        let head_data = self.fetch_head(&url).await?;

        let is_hls = is_hls_url(&url, &head_data.content_type);

        if is_hls {
            self.spawn_hls_download_task(&url, &dest).await?;
        } else {
            self.update_total_size(head_data.total_size).await;
            let is_single_thread = !head_data.accept_ranges || head_data.total_size.is_none() || threads <= 1;
            let size = head_data.total_size.unwrap_or(0);
            self.prepare_file(&dest, size, is_single_thread)?;
            self.spawn_download_tasks(&url, &dest, size, threads, is_single_thread, head_data.accept_ranges).await?;
        }

        self.spawn_sampler_and_monitor().await?;

        Ok(())
    }

    async fn check_and_resume(self: &Arc<Self>) -> Result<bool> {
        let was_paused = self.paused.load(Ordering::SeqCst);
        let has_started = self.started.load(Ordering::SeqCst);

        if was_paused && has_started {
            // This is a resume of an in-progress download
            let worker = Arc::clone(self);
            worker.resume().await?; // This sets paused to false
            return Ok(true);
        }

        // This is a fresh start (either brand new or from a queued-paused state)
        self.paused.store(false, Ordering::SeqCst); // Explicitly reset the flag

        let mut info = self.info.lock().await;
        match info.state {
            DownloadState::Completed => {
                let _ = self.event_tx.send(WorkerEvent::Completed(info.id)).await;
                Ok(true)
            }
            DownloadState::Running => Ok(true),
            _ => {
                info.state = DownloadState::Running;
                Ok(false)
            }
        }
    }

    async fn fetch_head(&self, url: &str) -> Result<HeadData> {
        let client = self.client.clone();
        let head = client.head(url).send().await?;
        let status = head.status();

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

        let content_type = head
            .headers()
            .get(reqwest::header::CONTENT_TYPE)
            .and_then(|v| v.to_str().ok())
            .map(|s| s.to_string());

        Ok(HeadData {
            total_size,
            accept_ranges,
            content_type,
        })
    }

    async fn update_total_size(&self, size: Option<u64>) {
        if let Some(s) = size {
            let mut info = self.info.lock().await;
            info.total_size = Some(s);
        }
    }

    async fn extract_info(&self) -> (String, std::path::PathBuf) {
        let info = self.info.lock().await;
        (info.url.clone(), info.dest.clone())
    }

    fn prepare_file(&self, dest: &std::path::Path, size: u64, is_single_thread: bool) -> Result<()> {
        let f = std::fs::File::create(dest)?;
        if !is_single_thread {f.set_len(size)?};
        Ok(())
    }

    async fn spawn_download_tasks(self: &Arc<Self>, url: &str, dest: &std::path::Path, size: u64, threads: u64, is_single_thread: bool, accept_ranges: bool) -> Result<()> {
        let client = self.client.clone();
        let mut handles = Vec::new();
        
        if is_single_thread {
            // For single-threaded, we use a single task covering the whole (potentially unknown) range
            let worker = Arc::clone(self);
            let url = url.to_string();
            let dest = dest.to_path_buf();
            let h = tokio::spawn(async move {
                worker.download_task(0, &client, &url, &dest, 0, size.saturating_sub(1), true, accept_ranges).await
            });
            handles.push(h);
        } else {
            // Multi-threaded segment logic
            let part_size = size / threads;
            for i in 0..threads {
                let start = i as u64 * part_size;
                let end = if i == threads - 1 { size - 1 } else { start + part_size - 1 };

                let client = client.clone();
                let worker = Arc::clone(self);
                let url = url.to_string();
                let dest = dest.to_path_buf();

                let h = tokio::spawn(async move {
                    worker.download_task(i, &client, &url, &dest, start, end, false, true).await
                });
                handles.push(h);
            }
        }

        let mut guard = self.handles.lock().await;
        *guard = handles;
        Ok(())
    }

    async fn download_task(
        self: &Arc<Self>,
        i: u64,
        client: &reqwest::Client,
        url: &str,
        dest: &std::path::Path,
        start: u64,
        end: u64,
        is_single_thread: bool,
        accept_ranges: bool,
    ) -> Result<()> {
        let worker = Arc::clone(self);

        let mut segment_progress = 0u64;
        let mut attempt = 1u8;
        
        let (download_timeout, download_retries) = {
            let s = self.settings.read().await;
            (s.download_timeout, s.download_retries)
        };

        loop {
            
            while self.paused.load(std::sync::atomic::Ordering::SeqCst) {
                self.notify_resume.notified().await;
            }
            if self.cancel.load(Ordering::SeqCst) {
                logger::debug(&format!("Segment {} canceled early", i));
                return Ok(());
            }


            let current_start = start + segment_progress;
            if current_start >= end {
                return Ok(());
            }

            let mut request_builder = client.get(url);
            if accept_ranges {
                let range = format!("bytes={}-{}", current_start, end);
                request_builder = request_builder.header(RANGE, &range);
            }
            let resp = match request_builder.send().await {
                Ok(r) => match r.error_for_status() {
                    Ok(v) => v,
                    Err(e) => return Err(anyhow::anyhow!("Segment {} bad status: {}", i, e)),
                },
                Err(e) => {
                    logger::error(&format!("Segment {} request failed: {:?}", i, e));
                    if attempt > download_retries {
                        self.cancel().await?;
                        return Err(anyhow::anyhow!("Segment {} request failed: {:?}", i, e))
                    }
                    attempt += 1;
                    continue;
                }
            };

            let mut file = TokioFile::options().write(true).open(dest).await?;
            if accept_ranges {
                file.seek(SeekFrom::Start(current_start)).await?;
            }
            let mut stream = resp.bytes_stream();

            while let Ok(next_chunk) = timeout(
                Duration::from_secs(download_timeout),
                stream.next(),
            ).await {
                while self.paused.load(Ordering::SeqCst) {
                    self.notify_resume.notified().await;
                }
                
                if self.cancel.load(Ordering::SeqCst) {
                    logger::debug(&format!("Segment {} cancelled", i));
                    return Ok(());
                }

                let next_chunk = match next_chunk {
                    Some(Ok(chunk)) => {
                        if chunk.is_empty() {
                            continue;
                        }
                        chunk
                    }

                    Some(Err(e)) => {
                        logger::error(&format!("Segment {}: stream error {:?}", i, e));
                        if attempt > download_retries {
                            self.cancel().await?;
                            return Err(anyhow::anyhow!("Segment {} stream error: {}", i, e));
                        }
                        if !accept_ranges {
                            self.downloaded.store(0, Ordering::SeqCst);
                        }
                        attempt += 1;
                        continue;
                    }

                    None => {
                        if is_single_thread || start + segment_progress >= end {
                            break;
                        }
                        if attempt > download_retries {
                            self.cancel().await?;
                            return Err(anyhow::anyhow!("Segment {}: stream ended unexpectedly", i));
                        }
                        if !accept_ranges {
                            self.downloaded.store(0, Ordering::SeqCst);
                        }
                        attempt += 1;
                        continue;
                    }
                };

                if let Err(e) = file.write_all(&next_chunk).await {
                    logger::error(&format!("Segment {}: file write error {:?}", i, e));
                    if attempt > download_retries {
                        self.cancel().await?;
                        return Err(anyhow::anyhow!("Segment {} file write failed: {}", i, e));
                    }
                    if !accept_ranges {
                        self.downloaded.store(0, Ordering::SeqCst);
                    }
                    attempt += 1;
                    continue;
                }

                let len = next_chunk.len() as u64;
                segment_progress += len;
                self.downloaded.fetch_add(len, Ordering::SeqCst);

                if start + segment_progress >= end {
                    break;
                }
                worker.limit_speed().await;
            }

            if is_single_thread || start + segment_progress >= end {
                return Ok(());
            }
        }
        // Err(anyhow::anyhow!("Segment {} failed after retries", i))
    }

    async fn spawn_hls_download_task(self: &Arc<Self>, url: &str, dest: &std::path::Path) -> Result<()> {
        logger::debug(&format!("Starting HLS download for {}", url));
        let client = self.client.clone();
        let worker = Arc::clone(self);

        let url = url.to_string();
        let dest = dest.to_path_buf();

        let h = tokio::spawn(async move {
            worker.download_hls_stream(&client, &url, &dest).await
        });

        let mut handles = self.handles.lock().await;
        handles.push(h);
        Ok(())
    }

    async fn download_hls_stream(
        self: &Arc<Self>, 
        client: &reqwest::Client, 
        url: &str, 
        dest: &std::path::Path) -> Result<()> {
        // 1. Fetch master playlist
        let playlist_content = client.get(url).send().await?.text().await?;

        // 2. Parse playlist to find segments
        // For simplicity, assuming it's a media playlist, not a master playlist with variants.
        let base_url = {
            let mut url_parts = url.split('/').collect::<Vec<_>>();
            url_parts.pop();
            url_parts.join("/") + "/"
        };

        let mut segment_urls = Vec::new();
        for line in playlist_content.lines() {
            if !line.starts_with('#') && !line.is_empty() {
                if line.starts_with("http") {
                    segment_urls.push(line.to_string());
                } else {
                    segment_urls.push(format!("{}{}", base_url, line));
                }
            }
        }

        if segment_urls.is_empty() {
            return Err(anyhow::anyhow!("No segments found in HLS playlist"));
        }

        // Create a temporary directory for segments
        let temp_dir = dest.parent().unwrap().join(format!("temp_{}", self.info.lock().await.id));
        tokio::fs::create_dir_all(&temp_dir).await?;

        // 5. Download all segments
        let mut segment_paths = Vec::new();
        for (i, segment_url) in segment_urls.iter().enumerate() {
            if self.cancel.load(Ordering::SeqCst) {
                return Ok(());
            }
            while self.paused.load(Ordering::SeqCst) {
                self.notify_resume.notified().await;
            }

            let segment_path = temp_dir.join(format!("segment_{}.ts", i));
            let mut file = TokioFile::create(&segment_path).await?;
            
            let resp = client.get(segment_url).send().await?;
            let mut stream = resp.bytes_stream();

            while let Some(chunk) = stream.next().await {
                while self.paused.load(Ordering::SeqCst) {
                    self.notify_resume.notified().await;
                }
                if self.cancel.load(Ordering::SeqCst) {
                    logger::debug(&format!("Segment {} cancelled", i));
                    return Ok(());
                }

                let chunk = chunk?;
                file.write_all(&chunk).await?;
                self.downloaded.fetch_add(chunk.len() as u64, Ordering::SeqCst);
            }
            segment_paths.push(segment_path);
        }

        // 6. Concatenate segments using ffmpeg
        let list_path = temp_dir.join("mylist.txt");
        let mut list_file = TokioFile::create(&list_path).await?;
        for path in &segment_paths {
            let line = format!("file '{}'\n", path.to_str().unwrap());
            list_file.write_all(line.as_bytes()).await?;
        }
        list_file.flush().await?;

        let mut command = tokio::process::Command::new("ffmpeg");
        command.arg("-f").arg("concat")
               .arg("-safe").arg("0")
               .arg("-i").arg(&list_path)
               .arg("-c").arg("copy")
               .arg("-y")
               .arg(dest);

        match command.output().await {
            Ok(output) => {
                if !output.status.success() {
                    let stderr = String::from_utf8_lossy(&output.stderr);
                    return Err(anyhow::anyhow!("ffmpeg failed: {}", stderr));
                }
            }
            Err(e) => return Err(anyhow::anyhow!("ffmpeg execution failed: {}", e)),
        }

        // Clean up temp directory
        tokio::fs::remove_dir_all(&temp_dir).await?;

        Ok(())
    }

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
                while sampler_worker.paused.load(Ordering::SeqCst) {
                    sampler_worker.notify_resume.notified().await;
                    continue;
                }
                if sampler_worker.cancel.load(Ordering::SeqCst) {
                    break;
                }

                tokio::select! {
                    _ = samp.tick() => {
                        let snapshot = sampler_worker.downloaded.load(Ordering::SeqCst);
                        let ts = SystemTime::now().duration_since(UNIX_EPOCH).unwrap().as_millis();
                        sampler_worker.history.write().await.push((ts, snapshot));
                        let hist_len = sampler_worker.history.read().await.len();
                        if hist_len > MAX_HISTORY { 
                            let remove = hist_len - MAX_HISTORY; 
                            sampler_worker.history.write().await.drain(0..remove);
                        }
                    }
                    _ = stop_flag.notified() => {
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
            let results = join_all(handles).await;
            stop_flag.notify_waiters();
            
            for (i, res) in results.into_iter().enumerate() {
                match res {
                    Ok(Ok(())) => {},
                    Ok(Err(e)) => {
                        let err_str = format!("Monitor: segment {} failed {:?}", i, e);
                        logger::error(&err_str);
                        let mut info = monitor_worker.info.lock().await;
                        info.state = DownloadState::Error(err_str.clone());
                        let id = info.id;
                        let _ = monitor_worker.event_tx.send(WorkerEvent::Error(id,err_str)).await;
                        return;
                    }
                    Err(e) => {
                        let err_str = format!("Monitor: join error {:?}", &e);
                        logger::error(&err_str);
                        let mut info = monitor_worker.info.lock().await;
                        info.state = DownloadState::Error(err_str.clone());
                        let id = info.id;
                        let _ = monitor_worker.event_tx.send(WorkerEvent::Error(id,err_str)).await;
                        return;
                    }
                }
            }
            if !monitor_worker.cancel.load(Ordering::SeqCst) {
                let mut info = monitor_worker.info.lock().await;
                info.state = DownloadState::Completed;
                let id = info.id;
                let _ = monitor_worker.event_tx.send(WorkerEvent::Completed(id)).await;
            }
        });

        Ok(())
    }

    async fn change_speed_limit(self: &Arc<Self>, limit: u64) {
        self.speed_limit.store(limit, Ordering::SeqCst);
    }

    async fn limit_speed(self: &Arc<Self>) {
        let limit = self.speed_limit.load(Ordering::SeqCst) as f64;
        if limit > 0.0 {
            let speed = calc_speed(self.history.read().await.to_vec());
            let sleep_dur = (speed/limit) - 1.0;

            if sleep_dur > 0.0 {
                sleep_until(Instant::now() + Duration::from_secs_f64(sleep_dur)).await;
            }
        }
    }


    pub async fn pause(&self) -> Result<()> {
        self.paused.store(true, Ordering::SeqCst);
        let mut info = self.info.lock().await;
        info.state = DownloadState::Paused;
        info.downloaded = self.downloaded.load(Ordering::SeqCst);
        info.history = self.history.read().await.clone();
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
        info.history = self.history.read().await.clone();
        let id = info.id;
        let _ = self.event_tx.send(WorkerEvent::Cancelled(id)).await;
        Ok(())
    }

    pub async fn snapshot_info(&self) -> DownloadInfo {
        let meta = self.info.lock().await;
        let mut snapshot = meta.clone();
        let d = self.downloaded.load(Ordering::SeqCst);
        snapshot.downloaded = d;
        let hist = self.history.read().await;
        snapshot.history = hist.clone();
        snapshot
    }
    pub async fn info(&self) -> DownloadInfo {
        self.snapshot_info().await
    }
}

#[derive(Debug)]
pub struct DownloadManager {
    client: reqwest::Client,
    pub settings: Arc<RwLock<DMSettings>>,
    workers: Arc<Mutex<IndexMap<Uuid, Arc<DownloadWorker>>>>,
    active: Arc<Mutex<HashSet<Uuid>>>,
    concurrency: Arc<AtomicU8>,
    sender: mpsc::Sender<WorkerEvent>,
}

impl DownloadManager {
    pub fn new(client: reqwest::Client, settings: DMSettings) -> Arc<Self> {
        let (tx, mut rx) = mpsc::channel::<WorkerEvent>(64);
        let mgr = Arc::new(Self {
            client,
            settings: Arc::new(RwLock::new(settings)),
            workers: Arc::new(Mutex::new(IndexMap::new())),
            active: Arc::new(Mutex::new(HashSet::new())),
            concurrency: Arc::new(AtomicU8::new(0)),
            sender: tx.clone(),
        });

        let mgr1 = Arc::clone(&mgr);
        let mgr2 = mgr1.clone();

        // event loop
        tokio::spawn(async move {
            while let Some(event) = rx.recv().await {
                mgr1.handle_event(event).await;
            }
        });

        // updater
        tokio::spawn(async move {
            mgr2.updater().await;
        });

        mgr
    }

    /// Called when a worker completes / cancels / errors
    async fn handle_event(self: &Arc<Self>, event: WorkerEvent) {
        match event {
            WorkerEvent::Completed(id)
            | WorkerEvent::Cancelled(id)
            | WorkerEvent::Error(id, _) => {
                self.active.lock().await.remove(&id);
                {
                    let conc = self.concurrency.load(Ordering::SeqCst).clone();
                    if conc > 0 {
                        self.concurrency.store(conc-1, Ordering::SeqCst);
                    };
                }

                logger::debug(&format!("Worker {:?} finished event: {:?}", id, event));
            }
        }
        self.process_queue().await;
    }

    pub async fn process_queue(&self) {
        let limit = self.settings.read().await.concurrency_limit.clone();
        let active_count = self.concurrency.load(Ordering::SeqCst).clone();

        if active_count == limit {
            return;
        }
        if active_count > limit {
            let to_pause_count = active_count - limit;
            let workers_to_pause = {
                let active = self.active.lock().await;
                let workers = self.workers.lock().await;
                active.iter()
                    .take(to_pause_count as usize)
                    .map(|id| (*id, workers.get(id).cloned()))
                    .filter_map(|(id, w_opt)| w_opt.map(|w| (id, w)))
                    .collect::<Vec<_>>()
            };

            for (id, worker) in workers_to_pause {
                if worker.pause().await.is_ok() {
                    worker.info.lock().await.state = DownloadState::Queued;
                    if self.active.lock().await.remove(&id) {
                        self.concurrency.fetch_sub(1, Ordering::SeqCst);
                    }
                }
            }
            return;
        }

        let slots = limit - active_count;
        let mut to_start = Vec::new();
        let workers_map = self.workers.lock().await;
        let queued_workers = workers_map.iter()
            .map(|(id, w)| (*id, w.clone()))
            .collect::<Vec<_>>();
        drop(workers_map);

        for (id, worker) in queued_workers {
            if to_start.len() >= slots as usize {
                break;
            }
            let info = worker.info().await;
            if matches!(info.state, DownloadState::Queued) {
                to_start.push(id);
            }
        }
        
        for id in to_start {
            // It's possible another task already started a worker, so we check again.
            let current_active = self.concurrency.load(Ordering::SeqCst);
            if current_active < limit {
                self.concurrency.fetch_add(1, Ordering::SeqCst);
                let _ = self.start(id).await;
            } else {
                break;
            }
        }
    }

    pub async fn add_download(&self, url: String, dest: PathBuf) -> Result<Uuid> {
        let id = Uuid::new_v4();
        let worker = DownloadWorker::new(
            id, self.client.clone(), self.settings.clone(), url, dest, self.sender.clone()
        ).await;
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
        
        {
            self.active.lock().await.insert(id);
        }
        
        let w = Arc::clone(&worker);
        
        tokio::spawn(async move {
            let _ = w.start().await;
        });
        Ok(())
    }

    pub async fn pause(&self, id: Uuid) -> Result<()> {
        let w = { self.workers.lock().await.get(&id).cloned() };
        match w {
            Some(worker) => {
                worker.pause().await?;
                if self.active.lock().await.remove(&id) {
                    if self.concurrency.load(Ordering::SeqCst) > 0 {
                        self.concurrency.fetch_sub(1, Ordering::SeqCst);
                    }
                }
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
                            return Ok(());
                        }
                        _ => {
                            info.state = DownloadState::Queued;
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
        let w = { self.workers.lock().await.get(&id).cloned() };
        match w {
            Some(worker) => {
                worker.cancel().await?;
                self.active.lock().await.remove(&id);
                let conc = self.concurrency.load(Ordering::SeqCst).clone();
                if conc > 0 {
                    self.concurrency.store(conc-1, Ordering::SeqCst);
                };
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

    pub async fn send_list(&self, mut interval: Interval) {
        loop {
            interval.tick().await;

            match self.list_all().await {
                Ok(list) => {
                    let mut download_list = Vec::new();
                    let list_ref = list.clone();
                    for info in list {
                        let state_str = match &info.state {
                            DownloadState::Queued => "Queued".to_string(),
                            DownloadState::Running => "Running".to_string(),
                            DownloadState::Paused => "Paused".to_string(),
                            DownloadState::Completed => "Completed".to_string(),
                            DownloadState::Cancelled => "Cancelled".to_string(),
                            DownloadState::Error(_) => "Error".to_string(),
                        };
                        let speed = calc_speed(info.history);
                        let glance = DownloadGlance {
                            id: info.id.to_string(),
                            name: info.dest
                                .file_name()
                                .and_then(|s| s.to_str())
                                .unwrap_or("")
                                .to_string(),
                            total_size: info.total_size,
                            downloaded: info.downloaded,
                            speed: speed,
                            state: state_str.clone(),
                        };
                        download_list.push(glance);
                    }
                    DownloadList { list: download_list }.send_signal_to_dart();
                }
                Err(e) => {
                    logger::error(&format!("Failed to get download details: {:?}", e));
                }
            }
        }
    }

    pub async fn recalculate_speed_limits(&self, mut interval: Interval) {
        loop {
            interval.tick().await;
            let global_limit = self.settings.read().await.speed_limit;
            if global_limit == 0 {
                continue;
            }

            let worker_refs = {
                let active = self.active.lock().await;
                let workers = self.workers.lock().await;
                active.iter()
                    .filter_map(|id| workers.get(id).cloned())
                    .collect::<Vec<_>>()
            };

            let histories = join_all(worker_refs.iter().map(|w| async {
                w.history.read().await.clone()
            })).await;

            let mut worker_speeds = Vec::new();
            let mut total_speed = 0u64;

            for (i, w) in worker_refs.iter().enumerate() {
                let s = calc_speed(histories[i].clone()) as u64;
                total_speed += s;
                worker_speeds.push((w.clone(), s));
            }

            if total_speed == 0 {
                let even_limit = global_limit / worker_speeds.len().max(1) as u64;
                for (w, _) in worker_speeds {
                    w.change_speed_limit(even_limit).await;
                }
                continue;
            }

            for (w, speed) in worker_speeds {
                let share = ((speed as f64 / total_speed as f64) * global_limit as f64) as u64;
                w.change_speed_limit(share.max((global_limit as f64 * 0.05) as u64)).await;
            }
        }
    }

    pub async fn updater(self: &Arc<Self>) {
        let mut interval1 = interval(Duration::from_secs(1));
        let mut interval2 = interval(Duration::from_secs(1));
        let mgr1 = self.clone();
        let mgr2 = self.clone();

        tokio::spawn( async move {
            mgr1.send_list(interval1).await;
        });

        tokio::spawn( async move {
            mgr2.recalculate_speed_limits(interval2).await;
        });
    }

    pub async fn update_settings(&self, new: DMSettings) -> Result<()> {
        let concurrency_changed;
        {
            let mut settings = self.settings.write().await;
            concurrency_changed = settings.concurrency_limit != new.concurrency_limit;

            settings.speed_limit = new.speed_limit;
            settings.download_threads = new.download_threads;
            settings.concurrency_limit = new.concurrency_limit;
            settings.download_timeout = new.download_timeout;
            settings.download_retries = new.download_retries;
        }

        if concurrency_changed {
            self.process_queue().await;
        }

        Ok(())
    }
}