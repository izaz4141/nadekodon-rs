extern crate nadekodon_core as core;
use core::utils::ytdlp::{get_ytdl_info, search};

use crate::signals::{
    QueryYtdlRequest, SearchYtdlRequest, YtdlFormat, QueryYtdlResponse, SearchYtdlResponse, YtdlSearchResult,
};
use crate::utils::logger;

use rinf::{DartSignal, RustSignal};

pub async fn handle_ytdl_query() {
    let receiver = QueryYtdlRequest::get_dart_signal_receiver();
    while let Some(signal) = receiver.recv().await {
        let id = signal.message.id;
        let url = signal.message.url;
        let result = get_ytdl_info(&url).await;
        let signal_to_send = match result {
            Ok(output) => {
                let items: Vec<crate::signals::YtdlItem> = output
                    .items
                    .into_iter()
                    .map(|item| {
                        let videos: Vec<YtdlFormat> = item
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
                        let audios: Vec<YtdlFormat> = item
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

                        crate::signals::YtdlItem {
                            name: item.name,
                            thumbnail: item.thumbnail,
                            videos,
                            audios,
                        }
                    })
                    .collect();

                QueryYtdlResponse {
                    id: id.clone(),
                    items,
                    error: output.error,
                }
            }
            Err(e) => {
                logger::error(&format!("YT-DLP url not supported: {:?}", e));
                QueryYtdlResponse {
                    id,
                    items: vec![],
                    error: Some(e),
                }
            }
        };
        signal_to_send.send_signal_to_dart();
    }
}

pub async fn handle_ytdl_search() {
    let receiver = SearchYtdlRequest::get_dart_signal_receiver();
    while let Some(signal) = receiver.recv().await {
        let id = signal.message.id;
        let query = signal.message.query;
        let result = search(&query).await;
        let signal_to_send = match result {
            Ok(results) => {
                let items: Vec<YtdlSearchResult> = results
                    .into_iter()
                    .map(|r| YtdlSearchResult {
                        id: r.id,
                        title: r.title,
                        url: r.url,
                        thumbnail: r.thumbnail,
                        duration: r.duration,
                        channel: r.channel,
                        webpage_url: r.webpage_url,
                    })
                    .collect();
                SearchYtdlResponse {
                    id: id.clone(),
                    results: items,
                    error: None,
                }
            }
            Err(e) => {
                logger::error(&format!("YT-DLP search failed: {:?}", e));
                SearchYtdlResponse {
                    id,
                    results: vec![],
                    error: Some(e.to_string()),
                }
            }
        };
        signal_to_send.send_signal_to_dart();
    }
}
