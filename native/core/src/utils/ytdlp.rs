use anyhow::Context;
use serde_json::Value;
use std::process::Stdio;
use tokio::process::Command;

use crate::signals::{YtdlFormat, YtdlQueryOutput, YtdlSearchResult};

pub async fn get_ytdl_info(url: &str) -> Result<YtdlQueryOutput, String> {
    let output = Command::new("yt-dlp")
        .arg("--dump-json")
        .arg(url)
        .output()
        .await
        .map_err(|e| e.to_string())?;

    if !output.status.success() {
        return Err(String::from_utf8_lossy(&output.stderr).to_string());
    }

    let json_str = String::from_utf8(output.stdout).map_err(|e| e.to_string())?;

    let mut items = Vec::new();
    let mut has_items = false;

    for item_result in serde_json::Deserializer::from_str(&json_str).into_iter::<Value>() {
        let video_info = item_result.map_err(|e| e.to_string())?;
        has_items = true;

        let name = video_info["title"].as_str().unwrap_or_default().to_string();
        let thumbnail = video_info["thumbnail"].as_str().map(|s| s.to_string());
        let mut videos = Vec::new();
        let mut audios = Vec::new();

        if let Some(formats) = video_info["formats"].as_array() {
            for format in formats {
                let filesize = format["filesize"].as_u64();
                let ytdl_format = YtdlFormat {
                    format_id: format["format_id"].as_str().unwrap_or_default().to_string(),
                    ext: format["ext"].as_str().unwrap_or_default().to_string(),
                    filesize,
                    url: format["url"].as_str().unwrap_or_default().to_string(),
                    vcodec: format["vcodec"].as_str().map(|s| s.to_string()),
                    acodec: format["acodec"].as_str().map(|s| s.to_string()),
                    note: format["format_note"]
                        .as_str()
                        .unwrap_or_default()
                        .to_string(),
                };

                if format["vcodec"].as_str() != Some("none") {
                    videos.push(ytdl_format);
                } else if format["acodec"].as_str() != Some("none") {
                    audios.push(ytdl_format);
                }
            }
        }

        items.push(crate::signals::YtdlItem {
            name,
            thumbnail,
            videos,
            audios,
        });
    }

    if !has_items {
        return Err("No JSON data found in yt-dlp output".to_string());
    }

    Ok(YtdlQueryOutput { items, error: None })
}

pub async fn search(query: &str) -> anyhow::Result<Vec<YtdlSearchResult>> {
    let output = Command::new("yt-dlp")
        .arg("--dump-json")
        .arg("--no-download")
        .arg("--flat-playlist")
        .arg("--ignore-errors")
        .arg(format!("ytsearch10:{query}"))
        .stdout(Stdio::piped())
        .stderr(Stdio::piped())
        .output()
        .await
        .context("Failed to execute yt-dlp for search")?;

    if !output.status.success() {
        let stderr = String::from_utf8_lossy(&output.stderr);
        anyhow::bail!("yt-dlp search failed: {stderr}");
    }

    let stdout = String::from_utf8(output.stdout).context("Invalid UTF-8 from yt-dlp")?;
    let mut results = Vec::new();

    for line in stdout.lines() {
        if line.trim().is_empty() {
            continue;
        }
        if let Ok(v) = serde_json::from_str::<Value>(line) {
            results.push(YtdlSearchResult {
                id: v["id"].as_str().unwrap_or_default().to_string(),
                title: v["title"].as_str().unwrap_or_default().to_string(),
                url: v["webpage_url"]
                    .as_str()
                    .or_else(|| v["url"].as_str())
                    .unwrap_or_default()
                    .to_string(),
                thumbnail: v["thumbnails"]
                    .as_array()
                    .and_then(|arr| arr.first().or_else(|| arr.last()))
                    .and_then(|t| t["url"].as_str())
                    .map(|s| s.to_string()),
                duration: v["duration"].as_f64(),
                channel: v["channel"]
                    .as_str()
                    .or_else(|| v["uploader"].as_str())
                    .map(|s| s.to_string()),
                webpage_url: v["webpage_url"].as_str().map(|s| s.to_string()),
            });
        }
    }

    Ok(results)
}
