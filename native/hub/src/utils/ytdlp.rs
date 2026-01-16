extern crate nadekodon_core as core;
use core::utils::ytdlp::get_ytdl_info;

use crate::signals::{QueryYtdl, YtdlFormat, YtdlQueryOutput};
use crate::utils::logger;

use rinf::{DartSignal, RustSignal};

pub async fn handle_ytdl_query() {
    let receiver = QueryYtdl::get_dart_signal_receiver();
    while let Some(signal) = receiver.recv().await {
        let url = signal.message.url;
        let result = get_ytdl_info(&url).await;
        let signal_to_send = match result {
            Ok(output) => {
                let videos: Vec<YtdlFormat> = output
                    .videos
                    .into_iter()
                    .map(|p| YtdlFormat {
                        format_id: p.format_id,
                        ext: p.ext,
                        filesize: p.filesize,
                        url: p.url,
                        vcodec: p.vcodec,
                        acodec: p.acodec,
                        note: p.note,
                    })
                    .collect();
                let audios: Vec<YtdlFormat> = output
                    .audios
                    .into_iter()
                    .map(|p| YtdlFormat {
                        format_id: p.format_id,
                        ext: p.ext,
                        filesize: p.filesize,
                        url: p.url,
                        vcodec: p.vcodec,
                        acodec: p.acodec,
                        note: p.note,
                    })
                    .collect();
                YtdlQueryOutput {
                    name: output.name,
                    thumbnail: output.thumbnail,
                    videos: videos,
                    audios: audios,
                    error: output.error,
                }
            }
            Err(e) => {
                logger::error(&format!("YT-DLP url not supported: {:?}", e));
                YtdlQueryOutput {
                    name: "".to_string(),
                    thumbnail: None,
                    videos: vec![],
                    audios: vec![],
                    error: Some(e),
                }
            }
        };
        signal_to_send.send_signal_to_dart();
    }
}
