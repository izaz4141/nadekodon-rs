use crate::signals::{ReportNewUuid, RequestNewUuid};
use rinf::{DartSignal, RustSignal};
use uuid::Uuid;

pub fn calc_speed(hist: Vec<(u128, u64)>) -> f64 {
    if hist.len() < 2 {
        return 0.0;
    }

    let (old_time, old_bytes) = hist.first().unwrap();
    let (new_time, new_bytes) = hist.last().unwrap();

    // elapsed time in seconds (timestamps are in milliseconds)
    let elapsed_secs = (*new_time - *old_time) as f64 / 1000.0;

    if elapsed_secs <= 0.0 {
        return 0.0;
    }

    let delta_bytes = *new_bytes as f64 - *old_bytes as f64;
    delta_bytes / elapsed_secs // bytes per second
}

pub fn fabricate_speed_history(current_bytes: u64, speed: u64) -> Vec<(u128, u64)> {
    let now = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .unwrap()
        .as_millis();

    let prev_bytes = if current_bytes > speed {
        current_bytes - speed
    } else {
        0
    };

    vec![(now - 1000, prev_bytes), (now, current_bytes)]
}

pub async fn handle_uuid_request() {
    let receiver = RequestNewUuid::get_dart_signal_receiver();
    while let Some(signal_pack) = receiver.recv().await {
        let message = signal_pack.message;
        let new_uuid = Uuid::new_v4().to_string();

        ReportNewUuid {
            request_id: message.request_id,
            new_uuid,
        }
        .send_signal_to_dart();
    }
}
