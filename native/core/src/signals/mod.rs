use serde::{Deserialize, Serialize};
use utoipa::ToSchema;

#[derive(Debug, Clone, Deserialize, ToSchema)]
pub struct UpdateSettings {
    pub download_dir: Option<String>,
    pub speed_limit: Option<u64>,
    pub download_threads: Option<u8>,
    pub concurrency_limit: Option<u8>,
    pub download_timeout: Option<u64>,
    pub download_retries: Option<u8>,
    pub seeding_ratio: Option<f32>,
    pub seeding_time: Option<u64>,
}

#[derive(Debug, Clone, Deserialize, ToSchema)]
pub struct QueryUrl {
    pub url: String,
    pub cookie: Option<String>,
    pub user_agent: Option<String>,
    pub referer: Option<String>,
}

#[derive(Debug, Clone, Deserialize, ToSchema)]
pub struct QueryYtdl {
    pub url: String,
}

#[derive(Debug, Clone, Serialize, ToSchema)]
pub struct UrlQueryOutput {
    pub url: String,
    pub name: String,
    pub total_size: Option<u64>,
    pub accept_ranges: bool,
    pub content_type: Option<String>,
    pub is_webpage: bool,
    pub error: bool,
}

#[derive(Debug, Clone, Serialize, ToSchema)]
pub struct YtdlQueryOutput {
    pub items: Vec<YtdlItem>,
    pub error: Option<String>,
}

#[derive(Debug, Clone, Serialize, ToSchema)]
pub struct YtdlItem {
    pub name: String,
    pub thumbnail: Option<String>,
    pub videos: Vec<YtdlFormat>,
    pub audios: Vec<YtdlFormat>,
}

#[derive(Debug, Clone, Serialize, Deserialize, ToSchema)]
pub struct YtdlFormat {
    pub format_id: String,
    pub ext: String,
    pub filesize: Option<u64>,
    pub url: String,
    pub vcodec: Option<String>,
    pub acodec: Option<String>,
    pub note: String,
}

#[derive(Debug, Clone, Deserialize, ToSchema)]
pub struct DoDownload {
    pub url: Option<String>,
    pub dest: String,
    pub video_format: Option<YtdlFormat>,
    pub audio_format: Option<YtdlFormat>,
    pub is_ytdl: bool,
    pub cookie: Option<String>,
    pub user_agent: Option<String>,
    pub referer: Option<String>,
}

#[derive(Debug, Clone, Deserialize, ToSchema)]
pub struct GetDownloadList {
    pub anchor_id: Option<String>,
    pub before: u32,
    pub after: u32,
    pub statuses: Vec<String>,
    pub tag: Option<i32>,
    pub search_query: Option<String>,
    pub sort_by: Option<i32>, // 0: Date, 1: Name, 2: Size, 3: Speed
    pub ascending: Option<bool>,
}

#[derive(Debug, Clone, Serialize, ToSchema)]
pub struct DownloadList {
    pub list: Vec<DownloadGlance>,
    pub total_count: u64,
    pub start_index: u64,
    pub tag: Option<i32>,
}

#[derive(Debug, Clone, Serialize, ToSchema)]
pub struct DownloadGlance {
    pub id: String,
    pub download_type: String,
    pub name: String,
    pub dest: String,
    pub total_size: Option<u64>,
    pub downloaded: u64,
    pub uploaded: u64,
    pub dspeed: f64,
    pub uspeed: Option<f64>,
    pub state: String,
    pub referer: Option<String>,
}

#[derive(Debug, Clone, Deserialize, ToSchema)]
pub struct GetDownloadDetails {
    pub id: String,
}

#[derive(Debug, Clone, Serialize, ToSchema)]
pub struct DownloadDetails {
    pub id: String,
    pub name: String,
    pub url: String,
    pub dest: String,
    pub total_size: Option<u64>,
    pub downloaded: u64,
    pub speed: f64,
    pub state: String,
    pub part_info: Vec<PartInfo>,
    pub uploaded: Option<u64>,
    pub upload_speed: Option<f64>,
    pub peers: Option<u64>,
    pub ratio: Option<f64>,
    pub eta: Option<String>,
    pub referer: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize, ToSchema)]
pub struct PartInfo {
    pub start: u64,
    pub end: u64,
    pub current: u64,
}

#[derive(Debug, Clone, Deserialize, ToSchema)]
pub struct PauseDownload {
    pub id: String,
}

#[derive(Debug, Clone, Deserialize, ToSchema)]
pub struct ResumeDownload {
    pub id: String,
}

#[derive(Deserialize, ToSchema)]
pub struct CancelDownload {
    pub id: String,
}

#[derive(Debug, Clone, Deserialize, ToSchema)]
pub struct DeleteDownload {
    pub id: String,
    pub delete_file: bool,
}

#[derive(Debug, Clone, Serialize)]
pub struct LogSignal {
    pub level: String,
    pub message: String,
}

#[derive(Debug, Clone, Deserialize)]
pub struct InitTorrentPersistence {
    pub path: String,
}

#[derive(Debug, Clone, Deserialize)]
pub struct InitDatabase {
    pub path: String,
}

#[derive(Debug, Clone, Deserialize, ToSchema)]
pub struct UpdateDownloadUrl {
    pub id: String,
    pub new_url: String,
}

#[derive(Debug, Clone, Serialize, ToSchema)]
pub struct RequestAddDownload {
    pub url: String,
    pub filename: Option<String>,
    pub user_agent: Option<String>,
    pub cookie: Option<String>,
    pub referer: Option<String>,
}

#[derive(Debug, Clone, Deserialize)]
pub struct StartServer {
    pub port: u16,
    pub api_key: String,
    pub username: String,
    pub password: String,
}

#[derive(Debug, Clone, Deserialize, ToSchema)]
pub struct RequestNewApiKey {
    pub master_key: Option<String>,
}

#[derive(Debug, Clone, Serialize, ToSchema)]
pub struct NewApiKey {
    pub encrypted_api_key: String,
    pub decrypted_api_key: String,
    pub master_key: String,
}

#[derive(Debug, Clone, Deserialize, ToSchema)]
pub struct DecryptRequest {
    pub encrypted_key: String,
    pub master_key: String,
}

#[derive(Debug, Clone, Serialize, ToSchema)]
pub struct DecryptResponse {
    pub decrypted_key: String,
}

#[derive(Debug, Clone, Deserialize, ToSchema)]
pub struct EncryptRequest {
    pub plain_key: String,
    pub master_key: Option<String>,
}

#[derive(Debug, Clone, Serialize, ToSchema)]
pub struct EncryptResponse {
    pub encrypted_key: String,
    pub master_key: String,
}

#[derive(Debug, Clone, Serialize)]
pub struct RequestFfmpeg {
    pub id: String,
    pub args: Vec<String>,
}

#[derive(Debug, Clone, Deserialize)]
pub struct FfmpegResult {
    pub id: String,
    pub success: bool,
    pub log: String,
}
