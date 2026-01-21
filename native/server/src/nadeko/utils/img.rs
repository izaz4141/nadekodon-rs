use crate::server::SharedState;
use axum::{
    extract::{Query, State},
    response::IntoResponse,
};
use percent_encoding::percent_decode_str;
use reqwest::Url;
use std::collections::HashMap;

pub async fn handle_proxy_image(
    State(state): State<SharedState>,
    Query(params): Query<HashMap<String, String>>,
) -> impl IntoResponse {
    let encoded_url = match params.get("url") {
        Some(url) => url.clone(),
        None => {
            return (axum::http::StatusCode::BAD_REQUEST, "Missing url parameter").into_response();
        }
    };

    let decoded_url = match percent_decode_str(&encoded_url).decode_utf8() {
        Ok(url) => url.into_owned(),
        Err(_) => {
            return (axum::http::StatusCode::BAD_REQUEST, "Invalid URL encoding").into_response();
        }
    };

    let parsed_url = match Url::parse(&decoded_url) {
        Ok(url) => url,
        Err(_) => return (axum::http::StatusCode::BAD_REQUEST, "Invalid URL").into_response(),
    };

    if parsed_url.scheme() != "http" && parsed_url.scheme() != "https" {
        return (
            axum::http::StatusCode::BAD_REQUEST,
            "Only HTTP/HTTPS URLs allowed",
        )
            .into_response();
    }
    let client = &state.context.dm().await.client.clone();
    let info = match nadekodon_core::utils::url::get_url_info(
        client.clone(),
        parsed_url.as_str(),
        None,
        None,
        None,
    )
    .await
    {
        Ok(i) => i,
        Err(_) => {
            return (axum::http::StatusCode::BAD_REQUEST, "Cant reach image url").into_response();
        }
    };
    let content_type = match info.content_type {
        Some(ct) => ct,
        None => {
            return (
                axum::http::StatusCode::BAD_REQUEST,
                "Cant determine content type",
            )
                .into_response();
        }
    };
    let response = match client.get(parsed_url).send().await {
        Ok(resp) => resp,
        Err(_) => {
            return (axum::http::StatusCode::BAD_GATEWAY, "Failed to fetch image").into_response();
        }
    };

    if !response.status().is_success() {
        return (
            axum::http::StatusCode::from_u16(response.status().as_u16())
                .unwrap_or(axum::http::StatusCode::BAD_GATEWAY),
            "Failed to fetch image",
        )
            .into_response();
    }

    if !content_type.starts_with("image/") {
        return (
            axum::http::StatusCode::BAD_REQUEST,
            "URL must point to an image",
        )
            .into_response();
    }

    let bytes = match response.bytes().await {
        Ok(b) => b,
        Err(_) => {
            return (axum::http::StatusCode::BAD_GATEWAY, "Failed to read image").into_response();
        }
    };

    (
        [
            (reqwest::header::CONTENT_TYPE, content_type),
            (
                reqwest::header::CACHE_CONTROL,
                "public, max-age=3600".to_string(),
            ),
            (
                reqwest::header::ACCESS_CONTROL_ALLOW_ORIGIN,
                "*".to_string(),
            ),
        ],
        bytes,
    )
        .into_response()
}
