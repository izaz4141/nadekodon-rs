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

#[derive(Serialize, RustSignal)]
pub struct SampleNumberOutput {
  pub current_number: i32,
}

#[derive(Deserialize, DartSignal)]
pub struct QueryUrl {
    pub url: String,
}
#[derive(Serialize, RustSignal)]
pub struct UrlQueryOutput {
    pub url: String,
    pub name: String,
    pub total_size: Option<u64>,
    pub accept_ranges: bool,
    pub content_type: Option<String>,
    pub is_webpage: bool,
    pub error: bool,
}

#[derive(Deserialize, DartSignal)]
pub struct DoDownload {
    pub url: String,
    pub dest: String,
}

#[derive(Deserialize, DartSignal)]
pub struct GetDownloadList {}

#[derive(Serialize, RustSignal)]
pub struct DownloadList {
    pub list: Vec<DownloadGlance>
}
#[derive(Serialize, SignalPiece)]
pub struct DownloadGlance {
    pub id: String,
    pub name: String,
    pub total_size: Option<u64>,
    pub downloaded: u64,
    pub speed: f64,
    pub state: String,
}

#[derive(Deserialize, DartSignal)]
pub struct GetDownloadDetails {
    pub id: String
}

#[derive(Serialize, RustSignal)]
pub struct DownloadDetails {
    pub id: String,
    pub name: String,
    pub url: String,
    pub dest: String,
    pub total_size: Option<u64>,
    pub downloaded: u64,
    pub speed: f64,
    pub threads: u8,
    pub state: String,
}

#[derive(Deserialize, DartSignal)]
pub struct PauseDownload {
    pub id: String
}

#[derive(Deserialize, DartSignal)]
pub struct ResumeDownload {
    pub id: String
}

#[derive(Deserialize, DartSignal)]
pub struct CancelDownload {
    pub id: String
}