use indexmap::IndexMap;
use std::{
    collections::{HashMap, HashSet},
    path::PathBuf,
    sync::{
        Arc,
        atomic::{AtomicU8, Ordering},
    },
};
use tokio::sync::{Mutex, RwLock, broadcast, mpsc};
use tokio::task::JoinSet;

use crate::app_context::AppContext;
use crate::utils::logger;
use crate::utils::types::{DMSettings, DownloadState, WorkerEvent};
use librqbit::{Session, SessionOptions, SessionPersistenceConfig};

use crate::downloader::manager::DownloadManager;

impl DownloadManager {
    pub async fn new(
        client: reqwest::Client,
        settings: DMSettings,
        context: std::sync::Weak<AppContext>,
    ) -> Arc<Self> {
        let (tx, rx) = mpsc::channel::<WorkerEvent>(64);

        let torrent_session = Arc::new(tokio::sync::RwLock::new(None));

        let (broadcast_tx, _) = broadcast::channel(64);
        let dm = Arc::new(Self {
            client,
            settings: Arc::new(RwLock::new(settings)),
            workers: Arc::new(Mutex::new(IndexMap::new())),
            active: Arc::new(Mutex::new(HashSet::new())),
            concurrency: Arc::new(AtomicU8::new(0)),
            sender: tx.clone(),
            broadcast_tx,
            pending_deletions: Arc::new(Mutex::new(Vec::new())),
            torrent_session,
            categories: Arc::new(RwLock::new(HashMap::new())),
            context,
        });

        let dm_clone = dm.clone();
        tokio::spawn(async move {
            dm_clone.event_loop(rx).await;
        });

        let dm_clone2 = dm.clone();
        tokio::spawn(async move {
            dm_clone2.updater().await;
        });

        dm
    }

    pub async fn init_torrent_session(&self, persistence_path: PathBuf) {
        tokio::fs::create_dir_all(&persistence_path).await.ok();

        let session = Session::new_with_opts(
            persistence_path.clone(),
            SessionOptions {
                disable_dht: true,
                disable_dht_persistence: true,
                fastresume: false,
                persistence: Some(SessionPersistenceConfig::Json {
                    folder: Some(persistence_path),
                }),
                ..Default::default()
            },
        )
        .await
        .expect("Failed to initialize torrent session");

        // Pause all torrents on startup
        let handles_to_pause = session.with_torrents(|torrents| {
            torrents
                .filter_map(|(_, h)| {
                    if !h.is_paused() {
                        Some(h.clone())
                    } else {
                        None
                    }
                })
                .collect::<Vec<_>>()
        });
        for h in handles_to_pause {
            let _ = h.wait_until_initialized().await;
            let _ = session.pause(&h).await;
            logger::debug(&format!("Paused torrent: {}", h.info_hash().as_string()));
        }

        let mut session_guard = self.torrent_session.write().await;
        *session_guard = Some(session);

        logger::debug("Torrent session initialized with persistence");
    }

    pub async fn event_loop(self: &Arc<Self>, mut rx: mpsc::Receiver<WorkerEvent>) {
        while let Some(event) = rx.recv().await {
            self.handle_event(event).await;
        }
    }

    /// Called when a worker completes / cancels / errors
    async fn handle_event(self: &Arc<Self>, event: WorkerEvent) {
        match event {
            WorkerEvent::Completed(id) | WorkerEvent::Cancelled(id) | WorkerEvent::Error(id, _) => {
                self.active.lock().await.remove(&id);
                {
                    let conc = self.concurrency.load(Ordering::SeqCst);
                    if conc > 0 {
                        self.concurrency.store(conc - 1, Ordering::SeqCst);
                    };
                }

                logger::debug(&format!("Worker {:?} finished event: {:?}", id, event));
            }
            WorkerEvent::Stalled(id) => {
                {
                    let conc = self.concurrency.load(Ordering::SeqCst);
                    if conc > 0 {
                        self.concurrency.store(conc - 1, Ordering::SeqCst);
                    };
                }

                logger::debug(&format!("Worker {:?} stalled, slot released", id));
            }
        }
        let _ = self.broadcast_tx.send(event.clone());
        self.process_queue().await;
    }

    pub async fn process_queue(&self) {
        let limit = self.settings.read().await.concurrency_limit;
        let active_count = self.concurrency.load(Ordering::SeqCst);

        if active_count == limit {
            return;
        }
        if active_count > limit {
            let to_pause_count = active_count - limit;
            let workers_to_pause = {
                let candidates = {
                    let active = self.active.lock().await;
                    let workers = self.workers.lock().await;
                    active
                        .iter()
                        .filter_map(|id| workers.get(id).cloned().map(|w| (*id, w)))
                        .collect::<Vec<_>>()
                };

                let mut set = JoinSet::new();
                for (id, worker) in candidates {
                    set.spawn(async move {
                        let info = worker.info().await;
                        let is_stalled = matches!(info.state, DownloadState::Stalled);
                        if !is_stalled {
                            Some((id, worker))
                        } else {
                            None
                        }
                    });
                }

                let mut results = Vec::with_capacity(to_pause_count as usize);
                while let Some(res) = set.join_next().await {
                    if let Ok(Some(worker_data)) = res {
                        results.push(worker_data);
                    }
                }
                results
            };

            for (id, worker) in workers_to_pause {
                if self.concurrency.load(Ordering::SeqCst) <= limit {
                    return;
                }
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
        let queued_workers = workers_map
            .iter()
            .map(|(id, w)| (*id, w.clone()))
            .collect::<Vec<_>>();
        drop(workers_map);

        for (id, worker) in queued_workers {
            if to_start.len() >= slots as usize {
                break;
            }
            let info = worker.info().await;
            match info.state {
                DownloadState::Queued => to_start.push(id),
                DownloadState::Stalled => {
                    let current_active = self.concurrency.load(Ordering::SeqCst);
                    if current_active < limit {
                        self.concurrency.fetch_add(1, Ordering::SeqCst);
                        let _ = worker.resume().await;
                    }
                }
                _ => continue,
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
}
