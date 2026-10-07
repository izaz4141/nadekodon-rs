use crate::response::{json_error, json_ok};
use crate::server::{SharedState, nadeko_home};
use axum::{
    Json,
    extract::State,
    http::StatusCode,
    response::IntoResponse,
};
use nadekodon_core::utils::logger;
use nadekodon_core::utils::config::{PRIVATE_CONFIG_KEYS, strip_keys};
use nadekodon_core::utils::types::DMSettings;
use serde::Serialize;
use serde_json::Value;
use utoipa::ToSchema;

#[derive(Serialize, ToSchema)]
pub struct SettingsResponse {
    #[serde(flatten)]
    pub settings: Value,
}

/// Config keys the settings endpoint may modify; credentials have dedicated
/// endpoints (`change-credentials`, `generate-api`).
const WRITABLE_SETTINGS: &[&str] = &[
    "download_folder",
    "speed_limit",
    "speed_mode",
    "speed_schedule",
    "download_threads",
    "concurrency_limit",
    "download_timeout",
    "download_retries",
    "seeding_ratio",
    "seeding_time",
    "stalled_time",
    "theme_mode",
    "use_dynamic_color",
    "custom_color",
    "check_nightly",
    "retreat_to_tray",
    "download_dir",
    "server_host",
    "server_port",
    "require_login",
    "accounts",
];

#[utoipa::path(
    get,
    path = "/api/nadeko/system/settings",
    tags = ["nadeko.system"],
    security(("ApiKeyAuth" = [])),
    responses(
        (status = 200, description = "Current settings", body = SettingsResponse)
    )
)]
pub async fn handle_get_settings(State(state): State<SharedState>) -> impl IntoResponse {
    let config = state.context.cfg().await;
    Json(strip_keys(&config.value, PRIVATE_CONFIG_KEYS))
}

#[utoipa::path(
    post,
    path = "/api/nadeko/system/settings",
    tags = ["nadeko.system"],
    security(("ApiKeyAuth" = [])),
    request_body = Value,
    responses(
        (status = 200, description = "Settings updated successfully")
    )
)]
pub async fn handle_update_settings(
    State(state): State<SharedState>,
    Json(new_config): Json<Value>,
) -> impl IntoResponse {
    let mut cfg = state.context.cfg().await.value.clone();
    for key in WRITABLE_SETTINGS {
        if let Some(v) = new_config.get(*key).filter(|v| !v.is_null()) {
            cfg[*key] = v.clone();
        }
    }

    let dm_settings = DMSettings {
        speed_limit: cfg["speed_limit"].as_u64().unwrap_or(0),
        concurrency_limit: cfg["concurrency_limit"].as_u64().unwrap_or(3) as u8,
        download_threads: cfg["download_threads"].as_u64().unwrap_or(4) as u8,
        download_timeout: cfg["download_timeout"].as_u64().unwrap_or(300),
        download_retries: cfg["download_retries"].as_u64().unwrap_or(3) as u8,
        seeding_ratio: cfg["seeding_ratio"].as_f64().unwrap_or(0.0) as f32,
        seeding_time: cfg["seeding_time"].as_u64().unwrap_or(0),
        download_dir: format!("{}/downloads", nadeko_home()),
        stalled_time: cfg["stalled_time"].as_u64().unwrap_or(30),
    };
    if let Err(e) = state.context.dm().await.update_settings(dm_settings).await {
        nadekodon_core::utils::logger::error(&format!("Error in updating DMSettings: {:?}", e));
    }

    if let Err(e) = state.context.save_config(&cfg).await {
        logger::error(&format!("Failed to save settings: {:?}", e));
        return json_error(StatusCode::INTERNAL_SERVER_ERROR, "Failed to save settings")
            .into_response();
    }

    json_ok().into_response()
}
