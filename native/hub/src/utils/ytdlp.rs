use rinf::{DartSignal, RustSignal};
use serde_json::Value;
use tokio::process::Command;

use crate::utils::logger;

use crate::signals::{QueryYtdl, YtdlQueryOutput, YtdlFormat};

async fn get_ytdl_info(ytdlp_path: &str, url: &str) -> Result<YtdlQueryOutput, String> {
    let output = Command::new(&ytdlp_path)
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
                note: format["format_note"].as_str().unwrap_or_default().to_string(),
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

pub async fn handle_ytdl_query() {
    let mut receiver = QueryYtdl::get_dart_signal_receiver();
    while let Some(signal) = receiver.recv().await {
        let url = signal.message.url;
        let ytdlp_path = signal.message.ytdlp_path;
        let result = get_ytdl_info(&ytdlp_path, &url).await;
        let signal_to_send = match result {
            Ok(output) => {
                logger::debug(&format!("YT-DLP url queried OK!"));
                output
            },
            Err(e) => {
                logger::error(&format!("YT-DLP url not supported: {:?}", e));
                YtdlQueryOutput {
                    name: "".to_string(),
                    thumbnail: None,
                    videos: vec![],
                    audios: vec![],
                    error: Some(e),
                }
            },
        };
        signal_to_send.send_signal_to_dart();
    }
}