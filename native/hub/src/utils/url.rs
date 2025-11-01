use std::time::Duration;
use anyhow::Result;
use reqwest::{
    Client, Url,
    header
};

pub fn build_browser_client() -> Client {
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
        .connect_timeout(Duration::from_secs(60))
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

pub async fn get_url_info(url: &str) -> Result<UrlInfo> {
    let client = build_browser_client();
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

    // Extract filename from Content-Disposition or URL path
    let name = response
        .headers()
        .get(header::CONTENT_DISPOSITION)
        .and_then(|hv| hv.to_str().ok())
        .and_then(|cd| {
            cd.split(';')
                .find_map(|part| {
                    let trimmed = part.trim();
                    if trimmed.starts_with("filename=") {
                        Some(trimmed.trim_start_matches("filename=").trim_matches('"').to_string())
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
