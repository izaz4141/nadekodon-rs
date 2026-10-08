pub const HISTORY_SAMPLE_INTERVAL_SECS: u64 = 1;
pub const MAX_HISTORY: usize = 15;

/// Caps `add_torrent` so a peerless magnet can't block a worker forever.
pub const TORRENT_ADD_TIMEOUT_SECS: u64 = 60;
