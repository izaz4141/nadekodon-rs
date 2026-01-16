use serde_json::Value;
use tokio::process::Command;

use crate::signals::{YtdlFormat, YtdlQueryOutput};

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
    let video_info: Value = serde_json::from_str(&json_str).map_err(|e| e.to_string())?;

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

    Ok(YtdlQueryOutput {
        name,
        thumbnail,
        videos,
        audios,
        error: None,
    })
}

pub async fn get_yt_dlp_version() -> String {
    let local = match Command::new("yt-dlp").arg("--version").output().await {
        Ok(output) if output.status.success() => {
            String::from_utf8_lossy(&output.stdout).trim().to_string()
        }
        _ => "Not found".to_string(),
    };

    if local == "Not found" {
        return local;
    }

    // Try to get latest version from GitHub API
    let latest = match get_latest_release("yt-dlp", "yt-dlp").await {
        Ok(v) => v,
        _ => return local,
    };

    format!("{} (Latest: {})", local, latest)
}

pub async fn get_ffmpeg_version() -> String {
    let local = match Command::new("ffmpeg").arg("-version").output().await {
        Ok(output) if output.status.success() => {
            let stdout = String::from_utf8_lossy(&output.stdout);
            let first_line = stdout.lines().next().unwrap_or_default();
            if let Some(version) = first_line
                .split("version ")
                .nth(1)
                .and_then(|s| s.split_whitespace().next())
            {
                version.to_string()
            } else {
                "Unknown".to_string()
            }
        }
        _ => "Not found".to_string(),
    };

    if local == "Not found" {
        return local;
    }

    // FFmpeg is harder to get latest version for via simple API, so we just return local for now
    // or try tags
    let latest = match get_latest_tag("FFmpeg", "FFmpeg").await {
        Ok(v) => v,
        _ => return local,
    };

    format!("{} (Latest: {})", local, latest)
}

async fn get_latest_release(owner: &str, repo: &str) -> Result<String, String> {
    let client = reqwest::Client::builder()
        .user_agent("nadekodon")
        .build()
        .map_err(|e| e.to_string())?;

    let url = format!("https://api.github.com/repos/{}/{}/releases/latest", owner, repo);
    let res = client.get(url).send().await.map_err(|e| e.to_string())?;
    let json: Value = res.json().await.map_err(|e| e.to_string())?;
    
    let tag = json["tag_name"].as_str().ok_or("No tag_name")?;
    Ok(tag.to_string())
}

async fn get_latest_tag(owner: &str, repo: &str) -> Result<String, String> {
    let client = reqwest::Client::builder()
        .user_agent("nadekodon")
        .build()
        .map_err(|e| e.to_string())?;

    let url = format!("https://api.github.com/repos/{}/{}/tags", owner, repo);
    let res = client.get(url).send().await.map_err(|e| e.to_string())?;
    let json: Value = res.json().await.map_err(|e| e.to_string())?;
    
    let tags = json.as_array().ok_or("Not an array")?;
    let tag = tags.first().and_then(|t| t["name"].as_str()).ok_or("No tags")?;
    Ok(tag.to_string())
}
