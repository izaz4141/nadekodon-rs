use time::{OffsetDateTime};


#[inline]
pub fn now_unix() -> i64 {
    OffsetDateTime::now_utc().unix_timestamp()
}

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
