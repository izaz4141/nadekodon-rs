use anyhow::Result;
use std::sync::{Arc, atomic::Ordering};

use crate::utils::types::{DownloadState, WorkerEvent};

use crate::downloader::worker::DownloadWorker;

impl DownloadWorker {
    pub async fn pause(&self) -> Result<()> {
        self.paused.store(true, Ordering::SeqCst);
        self.sync_to_info().await;
        let mut info = self.info.lock().await;
        info.state = DownloadState::Paused;
        drop(info);
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
        drop(info);
        self.paused.store(false, Ordering::SeqCst);
        self.notify_resume.notify_waiters();
        self.sync_to_info().await;
        let mut info = self.info.lock().await;
        info.state = DownloadState::Cancelled;
        let id = info.id;
        let _ = self.event_tx.send(WorkerEvent::Cancelled(id)).await;
        Ok(())
    }
}
