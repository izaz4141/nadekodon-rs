use crate::server::SharedState;
use axum::{extract::State, http::StatusCode, response::IntoResponse};
use futures_util::stream;
use http_body_util::BodyExt;
use librqbit::AddTorrent;
use multer::Multipart;
use nadekodon_core::utils::{logger, url::resolve_torrent_info};
use std::path::PathBuf;

pub struct TorrentsAddMultipart {
    pub urls: Vec<String>,
    pub torrents: Vec<Vec<u8>>,
    pub save_path: Option<String>,
    pub cookie: Option<String>,
    pub category: Option<String>,
    pub tags: Option<String>,
    pub skip_checking: Option<bool>,
    pub paused: Option<bool>,
    pub root_folder: Option<bool>,
    pub rename: Option<String>,
    pub up_limit: Option<i64>,
    pub dl_limit: Option<i64>,
    pub ratio_limit: Option<f64>,
    pub seeding_time_limit: Option<i64>,
    pub auto_tmm: Option<bool>,
    pub sequential_download: Option<bool>,
    pub first_last_piece_prio: Option<bool>,
}

fn extract_boundary(content_type: &str) -> Option<String> {
    if let Ok(ct) = content_type.parse::<mime::Mime>()
        && let Some(boundary) = ct.get_param("boundary")
    {
        return Some(boundary.as_str().to_string());
    }

    if let Some(start) = content_type.find("boundary=") {
        let after = &content_type[start + 9..];
        let end = after.find(';').unwrap_or(after.len());
        return Some(after[..end].trim().to_string());
    }

    None
}

fn is_urlencoded(content_type: &str) -> bool {
    content_type.starts_with("application/x-www-form-urlencoded")
}

fn parse_urlencoded_body(body: &str) -> TorrentsAddMultipart {
    fn decode(v: &str) -> String {
        percent_encoding::percent_decode_str(v)
            .decode_utf8_lossy()
            .into_owned()
    }

    fn parse_bool(v: Option<&str>) -> Option<bool> {
        v.map(|s| s.to_lowercase() == "true")
    }

    fn parse_i64(v: Option<&str>) -> Option<i64> {
        v.and_then(|s| s.parse().ok())
    }

    fn parse_f64(v: Option<&str>) -> Option<f64> {
        v.and_then(|s| s.parse().ok())
    }

    let mut urls = Vec::new();
    let mut save_path = None;
    let mut cookie = None;
    let mut category = None;
    let mut tags = None;
    let mut skip_checking = None;
    let mut paused = None;
    let mut root_folder = None;
    let mut rename = None;
    let mut up_limit = None;
    let mut dl_limit = None;
    let mut ratio_limit = None;
    let mut seeding_time_limit = None;
    let mut auto_tmm = None;
    let mut sequential_download = None;
    let mut first_last_piece_prio = None;

    for pair in body.split('&') {
        let mut parts = pair.splitn(2, '=');
        let key = parts.next().map(decode);
        let value = parts.next().map(decode);

        match key.as_deref() {
            Some("urls") => {
                if let Some(v) = value {
                    for line in v.lines() {
                        let u = line.trim();
                        if !u.is_empty() {
                            urls.push(u.to_string());
                        }
                    }
                }
            }
            Some("savepath") => save_path = value,
            Some("cookie") => cookie = value,
            Some("category") => category = value,
            Some("tags") => tags = value,
            Some("skip_checking") => skip_checking = parse_bool(value.as_deref()),
            Some("paused") => paused = parse_bool(value.as_deref()),
            Some("root_folder") => root_folder = parse_bool(value.as_deref()),
            Some("rename") => rename = value,
            Some("upLimit") => up_limit = parse_i64(value.as_deref()),
            Some("dlLimit") => dl_limit = parse_i64(value.as_deref()),
            Some("ratioLimit") => ratio_limit = parse_f64(value.as_deref()),
            Some("seedingTimeLimit") => seeding_time_limit = parse_i64(value.as_deref()),
            Some("autoTMM") => auto_tmm = parse_bool(value.as_deref()),
            Some("sequentialDownload") => sequential_download = parse_bool(value.as_deref()),
            Some("firstLastPiecePrio") => first_last_piece_prio = parse_bool(value.as_deref()),
            _ => {}
        }
    }

    TorrentsAddMultipart {
        urls,
        torrents: Vec::new(),
        save_path,
        cookie,
        category,
        tags,
        skip_checking,
        paused,
        root_folder,
        rename,
        up_limit,
        dl_limit,
        ratio_limit,
        seeding_time_limit,
        auto_tmm,
        sequential_download,
        first_last_piece_prio,
    }
}

impl TorrentsAddMultipart {
    fn has_unsupported_fields(&self) -> bool {
        self.tags.is_some()
            || self.skip_checking.is_some()
            || self.paused.is_some()
            || self.root_folder.is_some()
            || self.rename.is_some()
            || self.up_limit.is_some()
            || self.dl_limit.is_some()
            || self.ratio_limit.is_some()
            || self.seeding_time_limit.is_some()
            || self.auto_tmm.is_some()
            || self.sequential_download.is_some()
            || self.first_last_piece_prio.is_some()
    }

    async fn parse_from_request(
        mut req: axum::http::Request<axum::body::Body>,
    ) -> Result<Self, String> {
        let content_type = req
            .headers()
            .get("content-type")
            .and_then(|v| v.to_str().ok())
            .unwrap_or("");

        if is_urlencoded(content_type) {
            let body = req
                .body_mut()
                .collect()
                .await
                .map_err(|e| format!("Failed to read body: {}", e))?
                .to_bytes();
            let body_str = String::from_utf8_lossy(&body);
            return Ok(parse_urlencoded_body(&body_str));
        }

        let boundary = match extract_boundary(content_type) {
            Some(b) => b,
            None => {
                let body = req
                    .body_mut()
                    .collect()
                    .await
                    .map_err(|e| format!("Failed to read body: {}", e))?
                    .to_bytes();
                let body_str = String::from_utf8_lossy(&body);
                logger::error(&format!("Received TorrentsAddRequest: {}", &body_str));
                logger::error(&format!("With headers: {:#?}", &req.headers()));
                return Err("Invalid or missing boundary".to_string());
            }
        };

        let body = req
            .body_mut()
            .collect()
            .await
            .map_err(|e| format!("Failed to read body: {}", e))?
            .to_bytes();

        let stream = stream::once(async move { Ok::<_, std::convert::Infallible>(body) });
        let mut multipart = Multipart::new(stream, &boundary);

        let mut result = TorrentsAddMultipart {
            urls: Vec::new(),
            torrents: Vec::new(),
            save_path: None,
            cookie: None,
            category: None,
            tags: None,
            skip_checking: None,
            paused: None,
            root_folder: None,
            rename: None,
            up_limit: None,
            dl_limit: None,
            ratio_limit: None,
            seeding_time_limit: None,
            auto_tmm: None,
            sequential_download: None,
            first_last_piece_prio: None,
        };

        while let Ok(Some(field)) = multipart.next_field().await {
            let name = field.name().unwrap_or("").to_string();
            match name.as_str() {
                "urls" => {
                    if let Ok(text) = field.text().await {
                        for line in text.lines() {
                            let u = line.trim();
                            if !u.is_empty() {
                                result.urls.push(u.to_string());
                            }
                        }
                    }
                }
                "torrents" => {
                    if let Ok(bytes) = field.bytes().await {
                        result.torrents.push(bytes.to_vec());
                    }
                }
                "savepath" => {
                    result.save_path = field.text().await.ok();
                }
                "cookie" => {
                    result.cookie = field.text().await.ok();
                }
                "category" => {
                    result.category = field.text().await.ok();
                }
                "tags" => {
                    if let Ok(text) = field.text().await {
                        result.tags = Some(text);
                    }
                }
                "skip_checking" => {
                    if let Ok(text) = field.text().await {
                        result.skip_checking = match text.to_lowercase().as_str() {
                            "true" => Some(true),
                            "false" => Some(false),
                            _ => None,
                        };
                    }
                }
                "paused" => {
                    if let Ok(text) = field.text().await {
                        result.paused = match text.to_lowercase().as_str() {
                            "true" => Some(true),
                            "false" => Some(false),
                            _ => None,
                        };
                    }
                }
                "root_folder" => {
                    if let Ok(text) = field.text().await {
                        result.root_folder = match text.to_lowercase().as_str() {
                            "true" => Some(true),
                            "false" => Some(false),
                            _ => None,
                        };
                    }
                }
                "rename" => {
                    result.rename = field.text().await.ok();
                }
                "upLimit" => {
                    if let Ok(text) = field.text().await {
                        result.up_limit = text.parse().ok();
                    }
                }
                "dlLimit" => {
                    if let Ok(text) = field.text().await {
                        result.dl_limit = text.parse().ok();
                    }
                }
                "ratioLimit" => {
                    if let Ok(text) = field.text().await {
                        result.ratio_limit = text.parse().ok();
                    }
                }
                "seedingTimeLimit" => {
                    if let Ok(text) = field.text().await {
                        result.seeding_time_limit = text.parse().ok();
                    }
                }
                "autoTMM" => {
                    if let Ok(text) = field.text().await {
                        result.auto_tmm = match text.to_lowercase().as_str() {
                            "true" => Some(true),
                            "false" => Some(false),
                            _ => None,
                        };
                    }
                }
                "sequentialDownload" => {
                    if let Ok(text) = field.text().await {
                        result.sequential_download = match text.to_lowercase().as_str() {
                            "true" => Some(true),
                            "false" => Some(false),
                            _ => None,
                        };
                    }
                }
                "firstLastPiecePrio" => {
                    if let Ok(text) = field.text().await {
                        result.first_last_piece_prio = match text.to_lowercase().as_str() {
                            "true" => Some(true),
                            "false" => Some(false),
                            _ => None,
                        };
                    }
                }
                _ => {}
            }
        }

        Ok(result)
    }
}

pub async fn torrents_add(
    State(state): State<SharedState>,
    req: axum::http::Request<axum::body::Body>,
) -> impl IntoResponse {
    let multipart_data = match TorrentsAddMultipart::parse_from_request(req).await {
        Ok(data) => data,
        Err(e) => {
            logger::error(&format!("Failed to parse multipart: {}", e));
            return (StatusCode::BAD_REQUEST, "Invalid multipart data");
        }
    };

    let urls = multipart_data.urls.clone();
    let torrent_files = multipart_data.torrents.clone();
    let savepath = multipart_data.save_path.clone();
    let cookie = multipart_data.cookie.clone();
    let category = multipart_data.category.clone();

    if multipart_data.has_unsupported_fields() {
        if multipart_data.tags.is_some() {
            logger::debug("tags field ignored (not implemented)");
        }
        if multipart_data.skip_checking.is_some() {
            logger::debug("skip_checking field ignored (not implemented)");
        }
        if multipart_data.paused.is_some() {
            logger::debug("paused field ignored (not implemented)");
        }
        if multipart_data.root_folder.is_some() {
            logger::debug("root_folder field ignored (not implemented)");
        }
        if multipart_data.rename.is_some() {
            logger::debug("rename field ignored (not implemented)");
        }
        if multipart_data.up_limit.is_some() {
            logger::debug("up_limit field ignored (not implemented)");
        }
        if multipart_data.dl_limit.is_some() {
            logger::debug("dl_limit field ignored (not implemented)");
        }
        if multipart_data.ratio_limit.is_some() {
            logger::debug("ratio_limit field ignored (not implemented)");
        }
        if multipart_data.seeding_time_limit.is_some() {
            logger::debug("seeding_time_limit field ignored (not implemented)");
        }
        if multipart_data.auto_tmm.is_some() {
            logger::debug("auto_tmm field ignored (not implemented)");
        }
        if multipart_data.sequential_download.is_some() {
            logger::debug("sequential_download field ignored (not implemented)");
        }
        if multipart_data.first_last_piece_prio.is_some() {
            logger::debug("first_last_piece_prio field ignored (not implemented)");
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

    for url in urls {
        let url_info = match nadekodon_core::utils::url::get_url_info(
            state.context.dm().await.client.clone(),
            &url,
            cookie.clone(),
            None,
            None,
        )
        .await
        {
            Ok(info) => info,
            Err(_) => {
                return (StatusCode::BAD_REQUEST, "Invalid torrent url");
            }
        };

        let torrent_dest_dir: PathBuf = dest_dir.join(&url_info.name);

        match state
            .context
            .dm()
            .await
            .add_download(
                url_info.url.clone(),
                torrent_dest_dir,
                cookie.clone(),
                None,
                None,
                category.clone(),
            )
            .await
        {
            Ok(id) => logger::debug(&format!(
                "Added download via API: {} (ID: {}) category: {:?}",
                url_info.url, id, category
            )),
            Err(e) => logger::error(&format!("Failed to add download via API: {}", e)),
        }
    }

    for bytes in torrent_files {
        let temp_hash = uuid::Uuid::new_v4().to_string();
        let temp_path = std::env::temp_dir().join(format!("{}.torrent", temp_hash));

        if let Err(e) = std::fs::write(&temp_path, &bytes) {
            logger::error(&format!("Failed to save temp torrent file: {}", e));
            continue;
        }
        let (name, _) = match resolve_torrent_info(AddTorrent::from_bytes(bytes)).await {
            Ok((n, t)) => (n, t),
            Err(e) => {
                logger::error(&format!(
                    "Fail to get torrent info from bytes in /torrents/add {:#?}",
                    e
                ));
                return (StatusCode::BAD_REQUEST, "Invalid torrent bytes");
            }
        };
        let torrent_url = temp_path.to_string_lossy().to_string();
        let torrent_dest_dir: PathBuf = dest_dir.join(&name);

        match state
            .context
            .dm()
            .await
            .add_download(
                torrent_url.clone(),
                torrent_dest_dir.clone(),
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
