use rinf::{DartSignal, RustSignal, SignalPiece};
use serde::{Deserialize, Serialize};



#[derive(Deserialize, DartSignal)]
pub struct UpdateSettings {
    pub server_port: Option<u16>,
    pub speed_limit: Option<u64>,
    pub download_threads: Option<u8>,
    pub concurrency_limit: Option<u8>,
    pub download_timeout: Option<u64>,
    pub download_retries: Option<u8>,
}

#[derive(Deserialize, DartSignal)]
pub struct QueryUrl {
    pub url: String,
}

#[derive(Deserialize, DartSignal)]
pub struct QueryYtdl {
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

#[derive(Serialize, RustSignal)]
pub struct YtdlQueryOutput {
    pub name: String,
    pub thumbnail: Option<String>,
    pub videos: Vec<YtdlFormat>,
    pub audios: Vec<YtdlFormat>,
    pub error: Option<String>,
}

#[derive(Serialize, Deserialize, SignalPiece)]
pub struct YtdlFormat {
    pub format_id: String,
    pub ext: String,
    pub filesize: Option<u64>,
    pub url: String,
    pub vcodec: Option<String>,
    pub acodec: Option<String>,
    pub note: String,
}

#[derive(Deserialize, DartSignal)]
pub struct DoDownload {
    pub url: Option<String>,
    pub dest: String,
    pub video_format: Option<YtdlFormat>,
    pub audio_format: Option<YtdlFormat>,
    pub is_ytdl: bool,
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

#[derive(Serialize, RustSignal)]
pub struct LogSignal {
    pub level: String,
    pub message: String,
}