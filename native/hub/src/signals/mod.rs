use rinf::{DartSignal, RustSignal, SignalPiece};
use serde::{Deserialize, Serialize};

#[derive(Deserialize, DartSignal)]
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

#[derive(Deserialize, DartSignal)]
pub struct QueryUrl {
    pub url: String,
    pub cookie: Option<String>,
    pub user_agent: Option<String>,
    pub referer: Option<String>,
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
    pub items: Vec<YtdlItem>,
    pub error: Option<String>,
}

#[derive(Serialize, SignalPiece)]
pub struct YtdlItem {
    pub name: String,
    pub thumbnail: Option<String>,
    pub videos: Vec<YtdlFormat>,
    pub audios: Vec<YtdlFormat>,
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
    pub cookie: Option<String>,
    pub user_agent: Option<String>,
    pub referer: Option<String>,
}

#[derive(Deserialize, DartSignal)]
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

#[derive(Serialize, RustSignal)]
pub struct DownloadList {
    pub list: Vec<DownloadGlance>,
    pub total_count: u64,
    pub start_index: u64,
    pub tag: Option<i32>,
}
#[derive(Serialize, SignalPiece)]
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

#[derive(Deserialize, DartSignal)]
pub struct GetDownloadDetails {
    pub id: String,
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
    pub part_info: Vec<PartInfo>,
    pub uploaded: Option<u64>,
    pub upload_speed: Option<f64>,
    pub peers: Option<u64>,
    pub ratio: Option<f64>,
    pub eta: Option<String>,
    pub referer: Option<String>,
}

#[derive(Serialize, Deserialize, SignalPiece)]
pub struct PartInfo {
    pub start: u64,
    pub end: u64,
    pub current: u64,
}

#[derive(Deserialize, DartSignal)]
pub struct PauseDownload {
    pub id: String,
}

#[derive(Deserialize, DartSignal)]
pub struct ResumeDownload {
    pub id: String,
}

#[derive(Deserialize, DartSignal)]
pub struct CancelDownload {
    pub id: String,
}

#[derive(Deserialize, DartSignal)]
pub struct DeleteDownload {
    pub id: String,
    pub delete_file: bool,
}

#[derive(Serialize, RustSignal)]
pub struct LogSignal {
    pub level: String,
    pub message: String,
}

#[derive(Deserialize, DartSignal)]
pub struct InitTorrentPersistence {
    pub path: String,
}

#[derive(Deserialize, DartSignal)]
pub struct InitDatabase {
    pub path: String,
}

#[derive(Deserialize, DartSignal)]
pub struct UpdateDownloadUrl {
    pub id: String,
    pub new_url: String,
}

#[derive(Serialize, Deserialize, RustSignal)]
pub struct RequestAddDownload {
    pub url: String,
    pub filename: Option<String>,
    pub user_agent: Option<String>,
    pub cookie: Option<String>,
    pub referer: Option<String>,
}

#[derive(Deserialize, DartSignal)]
pub struct StartServer {
    pub port: u16,
    pub api_key: String,
    pub master_key: String,
    pub username: String,
    pub password: String,
    pub config_path: String,
}

#[derive(Deserialize, DartSignal)]
pub struct RequestNewApiKey {
    pub id: String,
    pub master_key: Option<String>,
}

#[derive(Serialize, RustSignal)]
pub struct NewApiKey {
    pub id: String,
    pub encrypted_api_key: String,
    pub decrypted_api_key: String,
    pub master_key: String,
}

#[derive(Deserialize, DartSignal)]
pub struct DecryptRequest {
    pub id: String,
    pub encrypted_key: String,
    pub master_key: String,
}

#[derive(Serialize, RustSignal)]
pub struct DecryptResponse {
    pub id: String,
    pub decrypted_key: String,
}

#[derive(Deserialize, DartSignal)]
pub struct EncryptRequest {
    pub id: String,
    pub plain_key: String,
    pub master_key: Option<String>,
}

#[derive(Serialize, RustSignal)]
pub struct EncryptResponse {
    pub id: String,
    pub encrypted_key: String,
    pub master_key: String,
}

// #[derive(Serialize, RustSignal)]
// pub struct RequestFfmpeg {
//     pub id: String,
//     pub args: Vec<String>,
// }

#[derive(Deserialize, DartSignal)]
pub struct FfmpegResult {
    pub id: String,
    // pub success: bool,
    // pub log: String,
}

#[derive(Deserialize, DartSignal)]
pub struct HashPassword {
    pub id: String,
    pub plain_text: String,
    pub salt: String,
}

#[derive(Serialize, RustSignal)]
pub struct HashingOutput {
    pub id: String,
    pub hashed_text: Option<String>,
}

#[derive(Deserialize, DartSignal)]
pub struct GenerateSalt {
    pub id: String,
}

#[derive(Serialize, RustSignal)]
pub struct SaltOutput {
    pub id: String,
    pub salt: String,
}

#[derive(Deserialize, DartSignal)]
pub struct Login {
    pub id: String,
    pub iuser: String,
    pub ipass: String,
    pub ruser: String,
    pub rpass: String,
}

#[derive(Serialize, RustSignal)]
pub struct LoginResult {
    pub id: String,
    pub success: bool,
}

#[derive(Deserialize, DartSignal)]
pub struct VerifyPassword {
    pub id: String,
    pub input: String,
    pub reference: String,
}

#[derive(Serialize, RustSignal)]
pub struct VerifyPasswordResult {
    pub id: String,
    pub success: bool,
}

#[derive(Deserialize, DartSignal)]
pub struct CreateTaggingRequest {
    pub id: String,
    pub name: String,
    pub description: String,
}

#[derive(Serialize, RustSignal)]
pub struct CreateTaggingResponse {
    pub id: String,
    pub success: String,
}

#[derive(Deserialize, DartSignal)]
pub struct PutTaggingRequest {
    pub id: String,
    pub name: String,
    pub tag: String,
}

#[derive(Serialize, RustSignal)]
pub struct PutTaggingResponse {
    pub id: String,
    pub success: String,
}
