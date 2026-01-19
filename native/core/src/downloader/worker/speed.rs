use std::{
    sync::{Arc, atomic::Ordering},
    time::Duration,
};
use tokio::time::{Instant, sleep_until};

use crate::utils::helper::calc_speed;

use crate::downloader::worker::DownloadWorker;

impl DownloadWorker {
    pub async fn change_speed_limit(self: &Arc<Self>, limit: u64) {
        self.speed_limit.store(limit, Ordering::SeqCst);
    }

    pub async fn limit_speed(self: &Arc<Self>) {
        let limit = self.speed_limit.load(Ordering::SeqCst) as f64;
        if limit > 0.0 {
            let speed = calc_speed(self.history.read().await.to_vec());
            let sleep_dur = (speed / limit) - 1.0;

            if sleep_dur > 0.0 {
                tokio::select! {
                    _ = sleep_until(Instant::now() + Duration::from_secs_f64(sleep_dur)) => {},
                    _ = self.notify_resume.notified() => {},
                }
            }
        }
    }
}
