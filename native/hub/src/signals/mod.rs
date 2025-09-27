use rinf::{DartSignal, RustSignal, SignalPiece};
use serde::{Deserialize, Serialize};

/// To send data from Dart to Rust, use `DartSignal`.
#[derive(Deserialize, DartSignal)]
pub struct SmallText {
    pub text: String,
}

/// To send data from Rust to Dart, use `RustSignal`.
#[derive(Serialize, RustSignal)]
pub struct SmallNumber {
    pub number: i32,
}

/// A signal can be nested inside another signal.
#[derive(Serialize, RustSignal)]
pub struct BigBool {
    pub member: bool,
    pub nested: SmallBool,
}

/// To nest a signal inside other signal, use `SignalPiece`.
#[derive(Serialize, SignalPiece)]
pub struct SmallBool(pub bool);

#[derive(Deserialize, DartSignal)]
pub struct DoDownload {
    pub url: String,
    pub path: String,
}

#[derive(Serialize, RustSignal, Clone)]
pub struct DownloadProgress {
    pub id: String,        // download ID
    pub downloaded: u64,   // total downloaded bytes so far
    pub total: Option<u64>, // total size if known, None if unknown
    pub speed: u64,        // bytes/sec, computed over short window
    pub finished: bool,    // true when download completes
}