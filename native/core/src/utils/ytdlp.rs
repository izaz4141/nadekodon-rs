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
