use anyhow::Result;
use librqbit::{AddTorrent, AddTorrentOptions, AddTorrentResponse, Session, SessionOptions};
use reqwest::{Client, Url, header};
use std::time::Duration;
use uuid::Uuid;

pub async fn build_browser_client() -> Client {
    let mut headers = header::HeaderMap::new();

    headers.insert(
        header::USER_AGENT,
        header::HeaderValue::from_static("Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/141.0.0.0 Safari/537.36"),
    );
    headers.insert(
        header::ACCEPT,
        header::HeaderValue::from_static(
            "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8",
        ),
    );
    headers.insert(
        header::ACCEPT_LANGUAGE,
        header::HeaderValue::from_static("en-US,en;q=0.9"),
    );
    headers.insert(
        header::ACCEPT_ENCODING,
        header::HeaderValue::from_static("gzip, deflate, br"),
    );

    Client::builder()
        .default_headers(headers)
        .redirect(reqwest::redirect::Policy::limited(10))
        // .connect_timeout(Duration::from_secs(60))
        // .timeout(Duration::from_secs(300))
        .pool_idle_timeout(None)
        .tcp_keepalive(Duration::from_secs(60))
        .build()
        .expect("Failed to build reqwest client")
}

#[derive(Debug, Clone)]
pub struct UrlInfo {
    pub url: String,
    pub name: String,
    pub total_size: Option<u64>,
    pub accept_ranges: bool,
    pub content_type: Option<String>,
}

pub async fn get_url_info(client: Client, url: &str) -> Result<UrlInfo> {
    if is_magnet_url(url) {
        let (name, total_size) = resolve_torrent_info(AddTorrent::from_url(url)).await?;

        return Ok(UrlInfo {
            url: url.to_string(),
            name,
            total_size,
            accept_ranges: true,
            content_type: Some("application/x-bittorrent".to_string()),
        });
    }

    // Send HEAD request
    let response = client.head(url).send().await?;

    // Extract total size
    let total_size = response
        .headers()
        .get(header::CONTENT_LENGTH)
        .and_then(|hv| hv.to_str().ok())
        .and_then(|s| s.parse::<u64>().ok());

    // Extract accept-ranges header
    let accept_ranges = response
        .headers()
        .get(header::ACCEPT_RANGES)
        .and_then(|hv| hv.to_str().ok())
        .map(|s| s.to_ascii_lowercase().contains("bytes"))
        .unwrap_or(false);

    // Extract content-type
    let content_type = response
        .headers()
        .get(header::CONTENT_TYPE)
        .and_then(|hv| hv.to_str().ok())
        .map(|s| s.to_string());

    if is_torrent_file(url, &content_type) {
        let bytes = client.get(url).send().await?.bytes().await?;
        let (name, total_size) = resolve_torrent_info(AddTorrent::from_bytes(bytes)).await?;

        return Ok(UrlInfo {
            url: url.to_string(),
            name,
            total_size,
            accept_ranges: true,
            content_type: Some("application/x-bittorrent".to_string()),
        });
    }

    // Extract filename from Content-Disposition or URL path
    let name = response
        .headers()
        .get(header::CONTENT_DISPOSITION)
        .and_then(|hv| hv.to_str().ok())
        .and_then(|cd| {
            cd.split(';').find_map(|part| {
                let trimmed = part.trim();
                if trimmed.starts_with("filename=") {
                    Some(
                        trimmed
                            .trim_start_matches("filename=")
                            .trim_matches('"')
                            .to_string(),
                    )
                } else {
                    None
                }
            })
        })
        .unwrap_or_else(|| {
            // fallback: extract from URL
            let parsed = Url::parse(url).ok();
            parsed
                .as_ref()
                .and_then(|u| {
                    u.path_segments()
                        .and_then(|segments| segments.last())
                        .map(|s| s.to_string())
                })
                .unwrap_or_else(|| "download.bin".to_string())
        });

    Ok(UrlInfo {
        url: url.to_string(),
        name,
        total_size,
        accept_ranges,
        content_type,
    })
}

pub fn is_hls_url(url: &str, content_type: &Option<String>) -> bool {
    url.ends_with(".m3u8")
        || match content_type {
            Some(ct) => {
                let ct_lower = ct.to_ascii_lowercase();
                ct_lower.contains("application/vnd.apple.mpegurl")
                    || ct_lower.contains("application/x-mpegurl")
            }
            None => false,
        }
}

pub fn is_magnet_url(url: &str) -> bool {
    url.starts_with("magnet:")
}

pub fn is_torrent_file(url: &str, content_type: &Option<String>) -> bool {
    url.ends_with(".torrent")
        || match content_type {
            Some(ct) => ct.to_ascii_lowercase() == "application/x-bittorrent",
            None => false,
        }
}

async fn resolve_torrent_info<'a>(add_torrent: AddTorrent<'a>) -> Result<(String, Option<u64>)> {
    // Create a temporary directory for the session
    let temp_dir = std::env::temp_dir().join(format!("nadekodon_torrent_{}", Uuid::new_v4()));
    tokio::fs::create_dir_all(&temp_dir).await?;

    // Initialize a temporary session
    let session = Session::new_with_opts(
        temp_dir.clone(),
        SessionOptions {
            disable_dht: true,
            disable_dht_persistence: true,
            persistence: None,
            ..Default::default()
        },
    )
    .await
    .map_err(|e| anyhow::anyhow!("Failed to create temp session: {}", e))?;

    let add_result = session
        .add_torrent(
            add_torrent,
            Some(AddTorrentOptions {
                overwrite: true,
                list_only: true,
                ..Default::default()
            }),
        )
        .await;

    let (name, total_size, torrent_id) = match add_result {
        Ok(AddTorrentResponse::ListOnly(response)) => {
            let info = response.info;
            let name = info
                .name
                .map(|b| String::from_utf8_lossy(&b).to_string())
                .unwrap_or_else(|| "unknown".to_string());
            let size: u64 = if let Some(len) = info.length {
                len
            } else if let Some(files) = info.files {
                files.iter().map(|f| f.length).sum()
            } else {
                0
            };
            (name, Some(size), None)
        }
        Ok(AddTorrentResponse::Added(id, handle))
        | Ok(AddTorrentResponse::AlreadyManaged(id, handle)) => {
            // Wait for metadata (timeout after 30 seconds)
            let timeout_duration = Duration::from_secs(30);
            let start_time = std::time::Instant::now();

            let mut found_name = "torrent_fetching".to_string();
            let mut found_size = None;

            while start_time.elapsed() < timeout_duration {
                if let Some(metadata) = handle.metadata.load().as_ref() {
                    found_name = metadata
                        .name
                        .clone()
                        .unwrap_or_else(|| "unknown".to_string());
                    let size: u64 = if let Some(len) = metadata.info.length {
                        len
                    } else if let Some(files) = &metadata.info.files {
                        files.iter().map(|f| f.length).sum()
                    } else {
                        0
                    };
                    found_size = Some(size);
                    break;
                }
                tokio::time::sleep(Duration::from_millis(500)).await;
            }

            // Note: For AddTorrent::from_bytes, we expect metadata to be available immediately or very quickly.
            // For magnet links, it might take time.

            (
                found_name,
                found_size,
                Some(librqbit::api::TorrentIdOrHash::Id(id)),
            )
        }
        Err(e) => {
            let _ = tokio::fs::remove_dir_all(&temp_dir).await;
            return Err(anyhow::anyhow!("Failed to query torrent info: {}", e));
        }
    };

    // Cleanup
    if let Some(id) = torrent_id {
        let _ = session.delete(id, true).await;
    }
    session.stop().await;
    let _ = tokio::fs::remove_dir_all(&temp_dir).await;

    Ok((name, total_size))
}
