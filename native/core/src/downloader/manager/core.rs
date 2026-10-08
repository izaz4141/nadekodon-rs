use indexmap::IndexMap;
use std::{
    collections::{HashMap, HashSet},
    path::{Path, PathBuf},
    sync::{
        Arc,
        atomic::{AtomicU8, Ordering},
    },
    time::{Duration, SystemTime, UNIX_EPOCH},
};
use tokio::sync::{Mutex, RwLock, broadcast, mpsc};

use crate::app_context::AppContext;
use crate::utils::logger;
use crate::utils::types::{DMSettings, DownloadState, WorkerEvent};
use librqbit::{Session, SessionOptions, SessionPersistenceConfig};

use crate::downloader::manager::DownloadManager;

/// Drops `session.json` entries whose `.torrent` file is missing — librqbit
/// restores those as magnets and hangs startup on `resolve_magnet`.
///
/// Returns `(remaining, skipped_hashes)`.
async fn prune_unrestorable_torrents(
    persistence_dir: &Path,
) -> anyhow::Result<(usize, HashSet<String>)> {
    let empty = || HashSet::new();
    let session_file = persistence_dir.join("session.json");
    let contents = match tokio::fs::read_to_string(&session_file).await {
        Ok(c) => c,
        Err(e) if e.kind() == std::io::ErrorKind::NotFound => return Ok((0, empty())),
        Err(e) => {
            logger::warn(&format!(
                "Could not read {} for pre-clean: {}",
                session_file.display(),
                e
            ));
            return Ok((0, empty()));
        }
    };

    let mut root: serde_json::Value = match serde_json::from_str(&contents) {
        Ok(v) => v,
        Err(e) => {
            logger::warn(&format!(
                "session.json is malformed ({}); leaving it untouched",
                e
            ));
            return Ok((0, empty()));
        }
    };

    let torrents = match root.get_mut("torrents").and_then(|v| v.as_object_mut()) {
        Some(map) => map,
        None => {
            logger::warn("session.json has no \"torrents\" object; leaving it untouched");
            return Ok((0, empty()));
        }
    };

    // Compute restorability first (can't await inside `retain`).
    let mut restorable = HashSet::new();
    let mut skipped_hash_set = HashSet::new();
    let mut skipped: Vec<(String, String)> = Vec::new();
    for (id, entry) in torrents.iter() {
        let hash = entry
            .get("info_hash")
            .and_then(|h| h.as_str())
            .unwrap_or("")
            .to_string();
        let is_restorable = if hash.is_empty() {
            false
        } else {
            let file = persistence_dir.join(format!("{}.torrent", hash));
            match tokio::fs::metadata(&file).await {
                Ok(m) => m.len() > 0,
                Err(_) => false,
            }
        };
        if is_restorable {
            restorable.insert(id.clone());
        } else {
            skipped.push((id.clone(), hash.clone()));
            skipped_hash_set.insert(hash);
        }
    }

    if skipped.is_empty() {
        return Ok((torrents.len(), empty()));
    }

    for (id, hash) in &skipped {
        logger::warn(&format!(
            "Skipping torrent {} ({}): no restorable .torrent file; removing from session.json",
            id, hash
        ));
    }

    // Back the original up before touching it.
    let ts = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap_or_default()
        .as_secs();
    let backup_path = persistence_dir.join(format!("session.json.bak-{}", ts));
    match tokio::fs::copy(&session_file, &backup_path).await {
        Ok(_) => logger::info(&format!(
            "Backed up session.json to {}",
            backup_path.display()
        )),
        Err(e) => logger::warn(&format!(
            "Failed to back up session.json to {}: {}",
            backup_path.display(),
            e
        )),
    }

    torrents.retain(|id, _| restorable.contains(id));
    let remaining = torrents.len();

    let new_contents = serde_json::to_string_pretty(&root)?;
    let tmp_path = persistence_dir.join("session.json.tmp");
    tokio::fs::write(&tmp_path, &new_contents).await?;
    tokio::fs::rename(&tmp_path, &session_file).await?;
    logger::info(&format!(
        "Pruned {} unrestorable torrent(s) from session.json ({} remain)",
        skipped.len(),
        remaining
    ));

    Ok((remaining, skipped_hash_set))
}

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
            pruned_torrent_hashes: Arc::new(RwLock::new(None)),
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

        // Prune unrestorable entries (no local .torrent) so restore can't hang.
        let pruned_hashes = match prune_unrestorable_torrents(&persistence_path).await {
            Ok((kept, skipped_hashes)) => {
                logger::debug(&format!(
                    "Persistence pre-check: {} torrent(s) restorable, {} skipped",
                    kept,
                    skipped_hashes.len()
                ));
                skipped_hashes
            }
            Err(e) => {
                logger::warn(&format!("Persistence pre-check failed: {:?}", e));
                HashSet::new()
            }
        };

        // Publish early so the DB manager can drop their rows without waiting.
        *self.pruned_torrent_hashes.write().await = Some(pruned_hashes);

        let session = match tokio::time::timeout(
            Duration::from_secs(60),
            Session::new_with_opts(
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
            ),
        )
        .await
        {
            Ok(Ok(s)) => s,
            Ok(Err(e)) => {
                logger::error(&format!(
                    "Failed to initialize torrent session: {:#}",
                    e
                ));
                logger::error(
                    "Torrent session unavailable; torrent operations will report \
                     'Torrent session not initialized'",
                );
                return;
            }
            Err(_) => {
                logger::error(
                    "Torrent session initialization timed out after 60s; \
                     leaving torrent session unavailable instead of hanging startup",
                );
                return;
            }
        };

        let restored_count = session.with_torrents(|torrents| torrents.count());
        logger::debug(&format!("Restored {} torrent(s) from persistence", restored_count));

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
        logger::debug(&format!(
            "Pausing {} still-active torrent(s)",
            handles_to_pause.len()
        ));
        for h in handles_to_pause {
            let hash = h.info_hash().as_string();
            logger::debug(&format!("Pausing torrent {}...", hash));
            match tokio::time::timeout(Duration::from_secs(30), async {
                let _ = h.wait_until_initialized().await;
                session.pause(&h).await
            })
            .await
            {
                Ok(Ok(_)) => logger::debug(&format!("Paused torrent: {}", hash)),
                Ok(Err(e)) => {
                    logger::warn(&format!("Failed to pause torrent {}: {:#}", hash, e))
                }
                Err(_) => logger::warn(&format!(
                    "Timed out pausing torrent {} after 30s; continuing startup",
                    hash
                )),
            }
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
            WorkerEvent::Completed(id)
            | WorkerEvent::Error(id, _)
            | WorkerEvent::Cancelled(id)
            | WorkerEvent::SeedingStarted(id)
            | WorkerEvent::Stalled(id) => {
                if self.active.lock().await.remove(&id) {
                    let conc = self.concurrency.load(Ordering::SeqCst);
                    if conc > 0 {
                        self.concurrency.store(conc - 1, Ordering::SeqCst);
                    };
                }

                logger::debug(&format!("Worker {:?} finished event: {:?}", id, event));
            }
            WorkerEvent::ProgressResumed(id) => {
                logger::debug(&format!(
                    "Worker {:?} progress resumed, re-checking queue",
                    id
                ));
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
            let candidates = {
                let active = self.active.lock().await;
                let workers = self.workers.lock().await;
                active
                    .iter()
                    .filter_map(|id| workers.get(id).cloned().map(|w| (*id, w)))
                    .take(to_pause_count as usize)
                    .collect::<Vec<_>>()
            };

            for (id, worker) in candidates {
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
                DownloadState::StalledDL | DownloadState::StalledUP => {
                    if self.concurrency.load(Ordering::SeqCst) < limit
                        && !worker.stalled.load(Ordering::SeqCst)
                    {
                        self.active.lock().await.insert(id);
                        self.concurrency.fetch_add(1, Ordering::SeqCst);
                        let _ = worker.resume().await;
                    }
                }
                _ => continue,
            }
        }

        for id in to_start {
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
