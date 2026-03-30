use crate::server::SharedState;
use axum::{
    extract::{Query, State},
    response::IntoResponse,
};
use reqwest::Url;
use serde::Deserialize;
use utoipa::IntoParams;

#[derive(Deserialize, IntoParams)]
#[into_params(parameter_in = Query)]
pub struct ProxyImageQuery {
    pub url: String,
}

#[utoipa::path(
    get,
    path = "/api/nadeko/utils/img",
    tags = ["nadeko.utils"],
    security(("ApiKeyAuth" = [])),
    params(ProxyImageQuery),
    responses(
        (status = 200, description = "Proxied image", body = Vec<u8>),
        (status = 400, description = "Invalid request"),
        (status = 502, description = "Failed to fetch image")
    )
)]
pub async fn handle_proxy_image(
    State(state): State<SharedState>,
    Query(params): Query<ProxyImageQuery>,
) -> impl IntoResponse {
    let decoded_url = params.url;

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
