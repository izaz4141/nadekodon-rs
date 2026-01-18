use crate::server::SharedState;
use axum::{
    Form, Json, Router,
    extract::{Multipart, Query, State},
    http::StatusCode,
    response::IntoResponse,
    routing::{get, post},
};
use axum_extra::extract::cookie::{Cookie, CookieJar};
use nadekodon_core::utils::types::DownloadState;
use nadekodon_core::utils::{helper, logger, security};
use serde::{Deserialize, Serialize};
use std::collections::{HashMap, HashSet};
use std::path::PathBuf;

#[derive(Deserialize)]
struct AuthQuery {
    username: String,
    password: String,
}

pub fn get_router(state: SharedState) -> Router<SharedState> {
    let auth_router = Router::new()
        .route("/app/version", get(app_version))
        .route("/app/webapiVersion", get(webapi_version))
        .route("/app/preferences", get(preferences))
        .route("/torrents/add", post(torrents_add))
        .route("/torrents/info", get(torrents_info))
        .route("/torrents/properties", get(torrents_properties))
        .route("/torrents/files", get(torrents_files))
        .route("/torrents/delete", post(torrents_delete))
        .route("/torrents/setCategory", post(torrents_set_category))
        .route("/torrents/createCategory", post(torrents_create_category))
        .route("/torrents/categories", get(torrents_categories))
        .route("/torrents/setShareLimits", post(torrents_set_share_limits))
        .layer(axum::middleware::from_fn_with_state(state, auth_middleware));

    Router::new()
        .route("/auth/login", post(login))
        .merge(auth_router)
}

async fn login(
    State(state): State<SharedState>,
    jar: CookieJar,
    Form(auth): Form<AuthQuery>,
) -> impl IntoResponse {
    let current_username = state.username.read().await;
    let current_hash = state.password.read().await;

    if auth.username == *current_username
        && security::validate_password(&current_hash, &auth.password).unwrap_or(false)
    {
        let cookie = Cookie::build(("SID", state.api_key.read().await.clone()))
            .path("/")
            .http_only(true)
            .build();
        (jar.add(cookie), "Ok.").into_response()
    } else {
        (StatusCode::FORBIDDEN, "Fails.").into_response()
    }
}

async fn auth_middleware(
    State(state): State<SharedState>,
    jar: CookieJar,
    req: axum::http::Request<axum::body::Body>,
    next: axum::middleware::Next,
) -> impl IntoResponse {
    if let Some(cookie) = jar.get("SID") {
        if cookie.value() == state.api_key.read().await.clone() {
            return next.run(req).await;
        }
    }
    StatusCode::FORBIDDEN.into_response()
}

async fn app_version() -> &'static str {
    "v4.6.1"
}

async fn webapi_version() -> &'static str {
    "2.8.3"
}

#[derive(Serialize, Clone)]
pub struct PreferencesResponse {
    pub locale: String,
    pub create_subfolder_enabled: bool,
    pub start_paused_enabled: bool,
    pub auto_delete_mode: i32,
    pub preallocate_all: bool,
    pub incomplete_files_ext: bool,
    pub auto_tmm_enabled: bool,
    pub torrent_changed_tmm_enabled: bool,
    pub save_path_changed_tmm_enabled: bool,
    pub category_changed_tmm_enabled: bool,
    pub save_path: String,
    pub temp_path_enabled: bool,
    pub temp_path: String,
    pub scan_dirs: HashMap<String, String>,
    pub export_dir: String,
    pub export_dir_fin: String,
    pub mail_notification_enabled: bool,
    pub mail_notification_sender: String,
    pub mail_notification_email: String,
    pub mail_notification_smtp: String,
    pub mail_notification_ssl_enabled: bool,
    pub mail_notification_auth_enabled: bool,
    pub mail_notification_username: String,
    pub mail_notification_password: String,
    pub autorun_enabled: bool,
    pub autorun_program: String,
    pub queueing_enabled: bool,
    pub max_active_downloads: i32,
    pub max_active_torrents: i32,
    pub max_active_uploads: i32,
    pub dont_count_slow_torrents: bool,
    pub slow_torrent_dl_rate_threshold: i32,
    pub slow_torrent_ul_rate_threshold: i32,
    pub slow_torrent_inactive_timer: i32,
    pub max_ratio_enabled: bool,
    pub max_ratio: f64,
    pub max_ratio_act: i32,
    pub listen_port: i32,
    pub upnp: bool,
    pub random_port: bool,
    pub dl_limit: i32,
    pub up_limit: i32,
    pub max_connec: i32,
    pub max_connec_per_torrent: i32,
    pub max_uploads: i32,
    pub max_uploads_per_torrent: i32,
    pub stop_tracker_timeout: i32,
    pub enable_piece_extent_affinity: bool,
    pub bittorrent_protocol: i32,
    pub limit_utp_rate: bool,
    pub limit_tcp_overhead: bool,
    pub limit_lan_peers: bool,
    pub alt_dl_limit: i32,
    pub alt_up_limit: i32,
    pub scheduler_enabled: bool,
    pub schedule_from_hour: i32,
    pub schedule_from_min: i32,
    pub schedule_to_hour: i32,
    pub schedule_to_min: i32,
    pub scheduler_days: i32,
    pub dht: bool,
    pub pex: bool,
    pub lsd: bool,
    pub encryption: i32,
    pub anonymous_mode: bool,
    pub proxy_type: i32,
    pub proxy_ip: String,
    pub proxy_port: i32,
    pub proxy_peer_connections: bool,
    pub proxy_auth_enabled: bool,
    pub proxy_username: String,
    pub proxy_password: String,
    pub proxy_torrents_only: bool,
    pub ip_filter_enabled: bool,
    pub ip_filter_path: String,
    pub ip_filter_trackers: bool,
    pub web_ui_domain_list: String,
    pub web_ui_address: String,
    pub web_ui_port: i32,
    pub web_ui_upnp: bool,
    pub web_ui_username: String,
    pub web_ui_csrf_protection_enabled: bool,
    pub web_ui_clickjacking_protection_enabled: bool,
    pub web_ui_secure_cookie_enabled: bool,
    pub web_ui_max_auth_fail_count: i32,
    pub web_ui_ban_duration: i32,
    pub web_ui_session_timeout: i32,
    pub web_ui_host_header_validation_enabled: bool,
    pub bypass_local_auth: bool,
    pub bypass_auth_subnet_whitelist_enabled: bool,
    pub bypass_auth_subnet_whitelist: String,
    pub alternative_webui_enabled: bool,
    pub alternative_webui_path: String,
    pub use_https: bool,
    pub ssl_key: String,
    pub ssl_cert: String,
    pub web_ui_https_key_path: String,
    pub web_ui_https_cert_path: String,
    pub dyndns_enabled: bool,
    pub dyndns_service: i32,
    pub dyndns_username: String,
    pub dyndns_password: String,
    pub dyndns_domain: String,
    pub rss_refresh_interval: i32,
    pub rss_max_articles_per_feed: i32,
    pub rss_processing_enabled: bool,
    pub rss_auto_downloading_enabled: bool,
    pub rss_download_repack_proper_episodes: bool,
    pub rss_smart_episode_filters: String,
    pub add_trackers_enabled: bool,
    pub add_trackers: String,
    pub web_ui_use_custom_http_headers_enabled: bool,
    pub web_ui_custom_http_headers: String,
    pub max_seeding_time_enabled: bool,
    pub max_seeding_time: i32,
    pub announce_ip: String,
    pub announce_to_all_tiers: bool,
    pub announce_to_all_trackers: bool,
    pub async_io_threads: i32,
    #[serde(rename = "banned_IPs")]
    pub banned_ips: String,
    pub checking_memory_use: i32,
    pub current_interface_address: String,
    pub current_network_interface: String,
    pub disk_cache: i32,
    pub disk_cache_ttl: i32,
    pub embedded_tracker_port: i32,
    pub enable_coalesce_read_write: bool,
    pub enable_embedded_tracker: bool,
    pub enable_multi_connections_from_same_ip: bool,
    pub enable_os_cache: bool,
    pub enable_upload_suggestions: bool,
    pub file_pool_size: i32,
    pub outgoing_ports_max: i32,
    pub outgoing_ports_min: i32,
    pub recheck_completed_torrents: bool,
    pub resolve_peer_countries: bool,
    pub save_resume_data_interval: i32,
    pub send_buffer_low_watermark: i32,
    pub send_buffer_watermark: i32,
    pub send_buffer_watermark_factor: i32,
    pub socket_backlog_size: i32,
    pub upload_choking_algorithm: i32,
    pub upload_slots_behavior: i32,
    pub upnp_lease_duration: i32,
    pub utp_tcp_mixed_mode: i32,
}

async fn preferences(State(state): State<SharedState>) -> Json<PreferencesResponse> {
    let dm = state.context.dm().await;
    let settings = dm.settings.read().await;

    Json(PreferencesResponse {
        locale: "en_GB".to_string(),
        create_subfolder_enabled: true,
        start_paused_enabled: false,
        auto_delete_mode: 0,
        preallocate_all: false,
        incomplete_files_ext: false,
        auto_tmm_enabled: false,
        torrent_changed_tmm_enabled: false,
        save_path_changed_tmm_enabled: false,
        category_changed_tmm_enabled: false,
        save_path: settings.download_dir.clone(),
        temp_path_enabled: false,
        temp_path: String::new(),
        scan_dirs: HashMap::new(),
        export_dir: String::new(),
        export_dir_fin: String::new(),
        mail_notification_enabled: false,
        mail_notification_sender: String::new(),
        mail_notification_email: String::new(),
        mail_notification_smtp: String::new(),
        mail_notification_ssl_enabled: false,
        mail_notification_auth_enabled: false,
        mail_notification_username: String::new(),
        mail_notification_password: String::new(),
        autorun_enabled: false,
        autorun_program: String::new(),
        queueing_enabled: true,
        max_active_downloads: settings.concurrency_limit as i32,
        max_active_torrents: settings.concurrency_limit as i32,
        max_active_uploads: settings.concurrency_limit as i32,
        dont_count_slow_torrents: false,
        slow_torrent_dl_rate_threshold: 0,
        slow_torrent_ul_rate_threshold: 0,
        slow_torrent_inactive_timer: 0,
        max_ratio_enabled: false,
        max_ratio: settings.seeding_ratio as f64,
        max_ratio_act: 0,
        listen_port: 0,
        upnp: false,
        random_port: true,
        dl_limit: settings.speed_limit as i32,
        up_limit: 0,
        max_connec: 0,
        max_connec_per_torrent: 0,
        max_uploads: 0,
        max_uploads_per_torrent: 0,
        stop_tracker_timeout: 60,
        enable_piece_extent_affinity: false,
        bittorrent_protocol: 0,
        limit_utp_rate: true,
        limit_tcp_overhead: false,
        limit_lan_peers: false,
        alt_dl_limit: 0,
        alt_up_limit: 0,
        scheduler_enabled: false,
        schedule_from_hour: 0,
        schedule_from_min: 0,
        schedule_to_hour: 0,
        schedule_to_min: 0,
        scheduler_days: 0,
        dht: true,
        pex: true,
        lsd: true,
        encryption: 0,
        anonymous_mode: false,
        proxy_type: -1,
        proxy_ip: String::new(),
        proxy_port: 0,
        proxy_peer_connections: false,
        proxy_auth_enabled: false,
        proxy_username: String::new(),
        proxy_password: String::new(),
        proxy_torrents_only: false,
        ip_filter_enabled: false,
        ip_filter_path: String::new(),
        ip_filter_trackers: false,
        web_ui_domain_list: "*".to_string(),
        web_ui_address: "0.0.0.0".to_string(),
        web_ui_port: 8080,
        web_ui_upnp: false,
        web_ui_username: "admin".to_string(),
        web_ui_csrf_protection_enabled: false,
        web_ui_clickjacking_protection_enabled: true,
        web_ui_secure_cookie_enabled: true,
        web_ui_max_auth_fail_count: 5,
        web_ui_ban_duration: 3600,
        web_ui_session_timeout: 3600,
        web_ui_host_header_validation_enabled: false,
        bypass_local_auth: false,
        bypass_auth_subnet_whitelist_enabled: false,
        bypass_auth_subnet_whitelist: String::new(),
        alternative_webui_enabled: false,
        alternative_webui_path: String::new(),
        use_https: false,
        ssl_key: String::new(),
        ssl_cert: String::new(),
        web_ui_https_key_path: String::new(),
        web_ui_https_cert_path: String::new(),
        dyndns_enabled: false,
        dyndns_service: 0,
        dyndns_username: String::new(),
        dyndns_password: String::new(),
        dyndns_domain: String::new(),
        rss_refresh_interval: 0,
        rss_max_articles_per_feed: 500,
        rss_processing_enabled: false,
        rss_auto_downloading_enabled: false,
        rss_download_repack_proper_episodes: false,
        rss_smart_episode_filters: String::new(),
        add_trackers_enabled: false,
        add_trackers: String::new(),
        web_ui_use_custom_http_headers_enabled: false,
        web_ui_custom_http_headers: String::new(),
        max_seeding_time_enabled: false,
        max_seeding_time: settings.seeding_time as i32,
        announce_ip: String::new(),
        announce_to_all_tiers: false,
        announce_to_all_trackers: false,
        async_io_threads: 0,
        banned_ips: String::new(),
        checking_memory_use: 0,
        current_interface_address: String::new(),
        current_network_interface: String::new(),
        disk_cache: 0,
        disk_cache_ttl: 0,
        embedded_tracker_port: 0,
        enable_coalesce_read_write: false,
        enable_embedded_tracker: false,
        enable_multi_connections_from_same_ip: false,
        enable_os_cache: true,
        enable_upload_suggestions: false,
        file_pool_size: 0,
        outgoing_ports_max: 0,
        outgoing_ports_min: 0,
        recheck_completed_torrents: false,
        resolve_peer_countries: false,
        save_resume_data_interval: 0,
        send_buffer_low_watermark: 0,
        send_buffer_watermark: 0,
        send_buffer_watermark_factor: 0,
        socket_backlog_size: 0,
        upload_choking_algorithm: 0,
        upload_slots_behavior: 0,
        upnp_lease_duration: 0,
        utp_tcp_mixed_mode: 0,
    })
}

async fn torrents_add(
    State(state): State<SharedState>,
    mut multipart: Multipart,
) -> impl IntoResponse {
    let mut urls = Vec::new();
    let mut torrent_files = Vec::new();
    let mut savepath = None;
    let mut cookie = None;
    let mut category = None;

    // Parse multipart
    while let Ok(Some(field)) = multipart.next_field().await {
        let name = field.name().unwrap_or("").to_string();
        if name == "urls" {
            if let Ok(text) = field.text().await {
                for line in text.lines() {
                    let u = line.trim();
                    if !u.is_empty() {
                        urls.push(u.to_string());
                    }
                }
            }
        } else if name == "torrents" {
            if let Ok(bytes) = field.bytes().await {
                torrent_files.push(bytes.to_vec());
            }
        } else if name == "savepath" {
            if let Ok(text) = field.text().await {
                savepath = Some(text);
            }
        } else if name == "cookie" {
            if let Ok(text) = field.text().await {
                cookie = Some(text);
            }
        } else if name == "category" {
            if let Ok(text) = field.text().await {
                category = Some(text);
            }
        }
    }

    let default_save_dir = {
        let dm = state.context.dm().await;
        let settings = dm.settings.read().await;
        settings.download_dir.clone()
    };

    let dest_dir = if let Some(sp) = &savepath {
        PathBuf::from(sp)
    } else {
        PathBuf::from(default_save_dir)
    };

    // Process URLs
    for url in urls {
        let url_info = nadekodon_core::utils::url::get_url_info(
            state.context.dm().await.client.clone(),
            &url,
            cookie.clone(),
            None,
            None,
        )
        .await;

        let actual_url = match url_info {
            Ok(info) => info.url,
            Err(_) => url.clone(),
        };

        match state
            .context
            .dm()
            .await
            .add_download(
                actual_url.clone(),
                dest_dir.clone(),
                cookie.clone(),
                None,
                None,
                category.clone(),
            )
            .await
        {
            Ok(id) => logger::debug(&format!(
                "Added download via API: {} (ID: {}) category: {:?}",
                actual_url, id, category
            )),
            Err(e) => logger::error(&format!("Failed to add download via API: {}", e)),
        }
    }

    // Process Torrent Files
    for bytes in torrent_files {
        // Save to temp file
        let temp_hash = uuid::Uuid::new_v4().to_string();
        let temp_path = std::env::temp_dir().join(format!("{}.torrent", temp_hash));

        if let Err(e) = std::fs::write(&temp_path, bytes) {
            logger::error(&format!("Failed to save temp torrent file: {}", e));
            continue;
        }

        let torrent_url = temp_path.to_string_lossy().to_string();

        match state
            .context
            .dm()
            .await
            .add_download(
                torrent_url.clone(),
                dest_dir.clone(),
                None,
                None,
                None,
                category.clone(),
            )
            .await
        {
            Ok(id) => logger::debug(&format!(
                "Added torrent file via API: {} (ID: {}) category: {:?}",
                torrent_url, id, category
            )),
            Err(e) => logger::error(&format!("Failed to add torrent file via API: {}", e)),
        }
    }

    (StatusCode::OK, "Ok.")
}

#[derive(Deserialize, Debug)]
struct TorrentsInfoQuery {
    filter: Option<String>,
    category: Option<String>,
    tag: Option<String>,
    sort: Option<String>,
    reverse: Option<bool>,
    limit: Option<usize>,
    offset: Option<isize>,
    hashes: Option<String>,
}
#[derive(Serialize, Clone)]
struct TorrentsInfoResponse {
    added_on: u64,
    amount_left: u64,
    category: String,
    completed: u64,
    completion_on: i64,
    content_path: String,
    dl_limit: i64,
    dlspeed: u64,
    downloaded: u64,
    eta: i64,
    hash: String,
    last_activity: u64,
    name: String,
    progress: f64,
    ratio: f64,
    save_path: String,
    size: u64,
    state: String,
    tags: String,
    total_size: u64,
    up_limit: i64,
    uploaded: u64,
    upspeed: u64,
}
async fn torrents_info(
    State(state): State<SharedState>,
    Query(query): Query<TorrentsInfoQuery>,
) -> impl IntoResponse {
    let downloads = state
        .context
        .dm()
        .await
        .list_all()
        .await
        .unwrap_or_default();

    // 1. Filtering
    let filtered: Vec<_> = downloads
        .into_iter()
        .filter(|d| d.torrent_hash.is_some())
        .filter(|d| {
            // Filter by hashes
            if let Some(hashes_str) = &query.hashes {
                let hashes: Vec<&str> = hashes_str.split('|').collect();
                let d_hash = d.torrent_hash.as_ref().unwrap(); // Safe because of filter above
                if !hashes.contains(&d_hash.as_str()) {
                    return false;
                }
            }

            // Filter by state
            if let Some(filter) = &query.filter {
                let match_filter = match filter.as_str() {
                    "all" => true,
                    "downloading" => {
                        matches!(d.state, DownloadState::Running)
                    }
                    "seeding" => matches!(d.state, DownloadState::Seeding),
                    "completed" => {
                        matches!(d.state, DownloadState::Completed)
                    }
                    "paused" => matches!(d.state, DownloadState::Paused),
                    "active" => matches!(d.state, DownloadState::Running | DownloadState::Seeding),
                    "inactive" => matches!(
                        d.state,
                        DownloadState::Paused | DownloadState::Queued | DownloadState::Completed
                    ),
                    "resumed" => !matches!(d.state, DownloadState::Paused),
                    "stalled" => false, // We don't have "stalled" state yet
                    "errored" => matches!(d.state, DownloadState::Error(_)),
                    _ => true,
                };
                if !match_filter {
                    return false;
                }
            }

            // Filter by category
            if let Some(cat) = &query.category {
                if cat.is_empty() {
                    if d.category.is_some() {
                        return false;
                    }
                } else {
                    if d.category.as_deref() != Some(cat) {
                        return false;
                    }
                }
            }

            // Filter by tag
            if let Some(tag) = &query.tag {
                if tag.is_empty() {
                    // Assuming no tags yet
                } else {
                    return false; // No tags implemented
                }
            }

            true
        })
        .collect();

    // 2. Mapping
    let mut info_futures = Vec::new();
    for d in filtered {
        info_futures.push(async move {
            let hash = d.torrent_hash.clone().unwrap_or_else(|| d.id.to_string());
            let total_size = d.total_size.unwrap_or(0);
            let downloaded = d.downloaded;
            let progress = if total_size > 0 {
                downloaded as f64 / total_size as f64
            } else if downloaded > 0 {
                1.0
            } else {
                0.0
            };

            let amount_left = total_size.saturating_sub(downloaded);
            let dlspeed = helper::calc_speed(d.history.clone()) as u64;
            let upspeed = d.uspeed.unwrap_or(0.0) as u64;

            let eta = if dlspeed > 0 && amount_left > 0 {
                (amount_left / dlspeed) as i64
            } else if amount_left == 0 {
                0
            } else {
                8640000 // Placeholder for unknown ETA
            };

            let qbt_state = match d.state {
                DownloadState::Queued => "queuedDL",
                DownloadState::Running => "downloading",
                DownloadState::Paused => "pausedDL",
                DownloadState::Completed => "uploading",
                DownloadState::Seeding => "uploading",
                DownloadState::Cancelled => "error",
                DownloadState::Error(_) => "error",
            };

            let last_activity = d.updated_at / 1000;
            let completion_on =
                if matches!(d.state, DownloadState::Completed | DownloadState::Seeding) {
                    (d.updated_at / 1000) as i64
                } else {
                    -1
                };

            let mut content_path = d.dest.to_string_lossy().to_string();
            if d.dest.is_dir() {
                if let Ok(mut entries) = tokio::fs::read_dir(&d.dest).await {
                    let mut first_entry = None;
                    let mut count = 0;
                    while let Ok(Some(entry)) = entries.next_entry().await {
                        count += 1;
                        if count == 1 {
                            first_entry = Some(entry.path());
                        } else {
                            break;
                        }
                    }
                    if count == 1 {
                        if let Some(path) = first_entry {
                            content_path = path.to_string_lossy().to_string();
                        }
                    }
                }
            }

            TorrentsInfoResponse {
                added_on: d.added_at / 1000,
                amount_left,
                category: d.category.unwrap_or_default(),
                completed: downloaded,
                completion_on,
                content_path,
                dl_limit: -1, // Not exposed per-torrent in settings yet
                dlspeed,
                downloaded,
                eta,
                hash,
                last_activity,
                name: d
                    .dest
                    .file_name()
                    .map(|s| s.to_string_lossy().to_string())
                    .unwrap_or(d.url),
                progress,
                ratio: if downloaded > 0 {
                    d.uploaded as f64 / downloaded as f64
                } else {
                    0.0
                },
                save_path: d
                    .dest
                    .parent()
                    .map(|p| p.to_string_lossy().to_string())
                    .unwrap_or_default(),
                size: total_size,
                state: qbt_state.to_string(),
                tags: "".to_string(),
                total_size,
                up_limit: -1,
                uploaded: d.uploaded,
                upspeed,
            }
        });
    }
    let mut info_list: Vec<TorrentsInfoResponse> = futures::future::join_all(info_futures).await;

    // 3. Sorting
    if let Some(sort_key) = &query.sort {
        info_list.sort_by(|a, b| {
            let cmp = match sort_key.as_str() {
                "name" => a.name.cmp(&b.name),
                "size" => a.size.cmp(&b.size),
                "progress" => a
                    .progress
                    .partial_cmp(&b.progress)
                    .unwrap_or(std::cmp::Ordering::Equal),
                "dlspeed" => a.dlspeed.cmp(&b.dlspeed),
                "upspeed" => a.upspeed.cmp(&b.upspeed),
                "added_on" => a.added_on.cmp(&b.added_on),
                "completion_on" => a.completion_on.cmp(&b.completion_on),
                "ratio" => a
                    .ratio
                    .partial_cmp(&b.ratio)
                    .unwrap_or(std::cmp::Ordering::Equal),
                "amount_left" => a.amount_left.cmp(&b.amount_left),
                _ => a.added_on.cmp(&b.added_on),
            };
            if query.reverse.unwrap_or(false) {
                cmp.reverse()
            } else {
                cmp
            }
        });
    }

    // 4. Pagination
    let offset = query.offset.unwrap_or(0);
    let start = if offset >= 0 {
        offset as usize
    } else {
        info_list.len().saturating_sub(offset.abs() as usize)
    };

    let end = if let Some(limit) = query.limit {
        (start + limit).min(info_list.len())
    } else {
        info_list.len()
    };

    let paged_list = if start < info_list.len() {
        info_list[start..end].to_vec()
    } else {
        Vec::new()
    };

    Json(paged_list)
}

#[derive(Deserialize, Debug)]
struct TorrentsPropertiesQuery {
    hash: String,
}

#[derive(Serialize, Clone)]
pub struct TorrentsPropertiesResponse {
    pub save_path: String,
    pub creation_date: i64,
    pub piece_size: i64,
    pub comment: String,
    pub total_wasted: i64,
    pub total_uploaded: i64,
    pub total_uploaded_session: i64,
    pub total_downloaded: i64,
    pub total_downloaded_session: i64,
    pub up_limit: i64,
    pub dl_limit: i64,
    pub time_elapsed: i64,
    pub seeding_time: i64,
    pub nb_connections: i32,
    pub nb_connections_limit: i32,
    pub share_ratio: f64,
    pub addition_date: i64,
    pub completion_date: i64,
    pub created_by: String,
    pub dl_speed_avg: i64,
    pub dl_speed: i64,
    pub eta: i64,
    pub last_seen: i64,
    pub peers: i32,
    pub peers_total: i32,
    pub pieces_have: i32,
    pub pieces_num: i32,
    pub reannounce: i64,
    pub seeds: i32,
    pub seeds_total: i32,
    pub total_size: i64,
    pub up_speed_avg: i64,
    pub up_speed: i64,
    #[serde(rename = "isPrivate")] // qBittorrent uses camelCase for this specific field
    pub is_private: bool,
}
async fn torrents_properties(
    State(state): State<SharedState>,
    Query(query): Query<TorrentsPropertiesQuery>,
) -> impl IntoResponse {
    let downloads = state
        .context
        .dm()
        .await
        .list_all()
        .await
        .unwrap_or_default();

    // Find the specific torrent by hash
    let target_torrent = downloads
        .into_iter()
        .find(|d| d.torrent_hash.as_deref() == Some(&query.hash));

    match target_torrent {
        Some(d) => {
            let amount_left = d.total_size.unwrap_or(0).saturating_sub(d.downloaded) as i64;
            let dlspeed = helper::calc_speed(d.history.clone()) as i64;
            let upspeed = d.uspeed.unwrap_or(0.0) as i64;

            let eta = if dlspeed > 0 && amount_left > 0 {
                (amount_left / dlspeed) as i64
            } else if amount_left == 0 {
                0
            } else {
                -1
            };
            let resp = TorrentsPropertiesResponse {
                save_path: d.dest.to_string_lossy().into_owned(),
                addition_date: (d.added_at / 1000) as i64,
                total_size: d.total_size.unwrap_or(0) as i64,
                creation_date: (d.added_at / 1000) as i64,
                piece_size: -1,
                comment: "".to_string(),
                total_wasted: 0,
                total_uploaded: d.uploaded as i64,
                total_uploaded_session: 0,
                total_downloaded: d.downloaded as i64,
                total_downloaded_session: 0,
                up_limit: -1,
                dl_limit: -1,
                time_elapsed: 0,
                seeding_time: 0,
                nb_connections: 0,
                nb_connections_limit: -1,
                share_ratio: 0.0,
                completion_date: -1,
                created_by: "".to_string(),
                dl_speed_avg: dlspeed.clone(),
                dl_speed: dlspeed,
                eta: eta,
                last_seen: (d.updated_at / 1000) as i64,
                peers: 0,
                peers_total: 0,
                pieces_have: 0,
                pieces_num: 0,
                reannounce: 0,
                seeds: 0,
                seeds_total: 0,
                up_speed_avg: upspeed.clone(),
                up_speed: upspeed,
                is_private: false,
            };
            Json(resp).into_response()
        }
        None => (StatusCode::NOT_FOUND, "Torrent hash was not found").into_response(),
    }
}

#[derive(Deserialize, Debug)]
struct TorrentsFilesQuery {
    hash: String,
    indexes: Option<String>,
}
#[derive(Serialize)]
pub struct TorrentFileResponse {
    pub index: usize,
    pub name: String,
    pub size: u64,
    pub progress: f32,
    pub priority: i32,
    pub is_seed: bool,
    pub piece_range: [usize; 2],
    pub availability: f32,
}
async fn torrents_files(
    State(state): State<SharedState>,
    Query(query): Query<TorrentsFilesQuery>,
) -> impl IntoResponse {
    let dm = state.context.dm().await;
    let session_guard = dm.torrent_session.read().await;
    let session = match session_guard.as_ref() {
        Some(s) => s,
        None => {
            return (StatusCode::INTERNAL_SERVER_ERROR, "Session not initialized").into_response();
        }
    };
    let tid = match query.hash.parse() {
        Ok(i) => i,
        _ => return (StatusCode::BAD_REQUEST, "Problem with hash").into_response(),
    };

    let handle = match session.get(librqbit::api::TorrentIdOrHash::Hash(tid)) {
        Some(h) => h,
        None => return (StatusCode::NOT_FOUND, "Torrent not found").into_response(),
    };

    let metadata_guard = handle.metadata.load();
    let info = match metadata_guard.as_ref() {
        Some(i) => i,
        None => {
            return (StatusCode::INTERNAL_SERVER_ERROR, "Metadata not available").into_response();
        }
    };

    let stats = handle.stats();

    let target_indexes: Option<HashSet<usize>> = query
        .indexes
        .as_ref()
        .map(|idx_str| idx_str.split('|').filter_map(|s| s.parse().ok()).collect());

    let files: Vec<TorrentFileResponse> = info
        .file_infos
        .iter()
        .enumerate()
        .filter(|(i, _)| match &target_indexes {
            Some(indexes) => indexes.contains(i),
            None => true,
        })
        .map(|(idx, file)| {
            let file_progress = stats.file_progress.get(idx).copied().unwrap_or(0);
            let progress = if file.len > 0 {
                file_progress as f64 / file.len as f64
            } else {
                0.0
            };
            let piece_range = file.piece_range_usize();

            TorrentFileResponse {
                index: idx,
                name: file.relative_filename.to_string_lossy().to_string(),
                size: file.len,
                progress: progress as f32,
                priority: 0,
                is_seed: stats.finished,
                piece_range: [piece_range.start, piece_range.end.saturating_sub(1)],
                availability: if stats.finished { 1.0 } else { progress as f32 },
            }
        })
        .collect();

    Json(files).into_response()
}

#[derive(Deserialize, Debug)]
struct TorrentsDeleteQuery {
    hashes: String,
    #[serde(rename = "deleteFiles")]
    delete_files: Option<bool>,
}
async fn torrents_delete(
    State(state): State<SharedState>,
    Query(query): Query<TorrentsDeleteQuery>,
) -> impl IntoResponse {
    let hashes: Vec<&str> = query.hashes.split('|').collect();
    let delete_files = query.delete_files.unwrap_or(false);

    let downloads = state
        .context
        .dm()
        .await
        .list_all()
        .await
        .unwrap_or_default();

    for hash in hashes {
        if hash.is_empty() {
            continue;
        }

        let target = downloads
            .iter()
            .find(|d| d.torrent_hash.as_deref() == Some(hash));

        if let Some(d) = target {
            if let Err(e) = state
                .context
                .dm()
                .await
                .delete_worker(d.id, delete_files)
                .await
            {
                logger::error(&format!("Failed to delete torrent {}: {}", hash, e));
            } else {
                logger::debug(&format!(
                    "Deleted torrent: {} (files: {})",
                    hash, delete_files
                ));
            }
        } else {
            logger::error(&format!("Torrent not found for deletion: {}", hash));
            return (StatusCode::NOT_FOUND, "Torrent not found").into_response();
        }
    }

    (StatusCode::OK, "Ok.").into_response()
}

#[derive(Deserialize, Debug)]
struct TorrentsSetCategoryForm {
    hashes: String,
    category: String,
}
async fn torrents_set_category(
    State(state): State<SharedState>,
    Form(query): Form<TorrentsSetCategoryForm>,
) -> impl IntoResponse {
    let downloads = state
        .context
        .dm()
        .await
        .list_all()
        .await
        .unwrap_or_default();

    if query.hashes == "all" {
        for d in downloads {
            if d.torrent_hash.is_none() {
                continue;
            }
            if let Some(worker) = state.context.dm().await.get_worker(d.id).await {
                if query.category.is_empty() {
                    worker.clear_category().await;
                } else {
                    if let Err(e) = worker.set_category(query.category.clone()).await {
                        logger::error(&format!("Failed to set category: {:?}", e));
                        return (
                            StatusCode::BAD_REQUEST,
                            format!("Failed to set category: {:?}", e),
                        )
                            .into_response();
                    }
                }
            }
        }
    } else {
        let hashes: Vec<&str> = query.hashes.split('|').collect();
        for hash in hashes {
            if hash.is_empty() {
                continue;
            }

            let target = downloads
                .iter()
                .find(|d| d.torrent_hash.as_deref() == Some(hash));

            match target {
                Some(d) => {
                    if let Some(worker) = state.context.dm().await.get_worker(d.id).await {
                        if query.category.is_empty() {
                            worker.clear_category().await;
                        } else {
                            if let Err(e) = worker.set_category(query.category.clone()).await {
                                logger::error(&format!("Failed to set category: {:?}", e));
                                return (
                                    StatusCode::BAD_REQUEST,
                                    format!("Failed to set category: {:?}", e),
                                )
                                    .into_response();
                            }
                        }
                    }
                }
                None => {
                    return (StatusCode::NOT_FOUND, "Torrent not found").into_response();
                }
            }
        }
    }

    (StatusCode::OK, "Ok.").into_response()
}

#[derive(Deserialize, Debug)]
struct TorrentsCreateCategoryForm {
    category: String,
    #[serde(rename = "savePath")]
    save_path: Option<String>,
}

async fn torrents_create_category(
    State(state): State<SharedState>,
    Form(query): Form<TorrentsCreateCategoryForm>,
) -> impl IntoResponse {
    if query.category.is_empty() {
        return (StatusCode::BAD_REQUEST, "Category name is empty").into_response();
    }

    let save_path = query.save_path.map(PathBuf::from);

    match state
        .context
        .dm()
        .await
        .create_category(query.category, save_path)
        .await
    {
        Ok(()) => (StatusCode::OK, "Ok.").into_response(),
        Err("Category already exists") => {
            (StatusCode::CONFLICT, "Category already exists").into_response()
        }
        Err(_) => (StatusCode::BAD_REQUEST, "Invalid category name").into_response(),
    }
}

#[derive(Serialize)]
struct CategoryResponse {
    name: String,
    #[serde(rename = "savePath")]
    save_path: Option<String>,
}

async fn torrents_categories(State(state): State<SharedState>) -> impl IntoResponse {
    let categories = state.context.dm().await.categories.read().await.clone();

    let response: HashMap<String, CategoryResponse> = categories
        .into_iter()
        .map(|(name, info)| {
            (
                name.clone(),
                CategoryResponse {
                    name,
                    save_path: info.save_path.map(|p| p.to_string_lossy().to_string()),
                },
            )
        })
        .collect();

    Json(response).into_response()
}

#[derive(Deserialize)]
struct TorrentsSetShareLimitsForm {
    hashes: String,
    #[serde(rename = "ratioLimit")]
    ratio_limit: Option<f32>,
    #[serde(rename = "seedingTimeLimit")]
    seeding_time_limit: Option<i64>,
    #[serde(rename = "inactiveSeedingTimeLimit")]
    _inactive_seeding_time_limit: Option<i64>,
}

async fn torrents_set_share_limits(
    State(state): State<SharedState>,
    Form(query): Form<TorrentsSetShareLimitsForm>,
) -> impl IntoResponse {
    let hashes: Vec<&str> = if query.hashes == "all" {
        Vec::new()
    } else {
        query.hashes.split('|').collect()
    };

    let ratio = match query.ratio_limit {
        Some(-2.0) => None,
        Some(-1.0) => Some(f32::MAX),
        Some(v) => Some(v),
        None => None,
    };

    let time = match query.seeding_time_limit {
        Some(-2) => None,
        Some(-1) => Some(u64::MAX),
        Some(v) => Some(v as u64),
        None => None,
    };

    let torrents = state
        .context
        .dm()
        .await
        .list_torrents(if hashes.is_empty() {
            None
        } else {
            Some(hashes)
        })
        .await;

    for info in torrents {
        if let Some(worker) = state.context.dm().await.get_worker(info.id).await {
            worker.set_seeding_limits(ratio, time).await;
        }
    }

    (StatusCode::OK, "Ok.").into_response()
}
