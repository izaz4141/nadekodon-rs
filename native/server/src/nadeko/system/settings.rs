use crate::server::{SharedState, nadeko_home, normalize_secret};
use axum::{Json, extract::State, response::IntoResponse};
use nadekodon_core::utils::types::DMSettings;
use serde::Serialize;
use serde_json::Value;
use utoipa::ToSchema;

#[derive(Serialize, ToSchema)]
pub struct SettingsResponse {
    #[serde(flatten)]
    pub settings: Value,
}

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
    let config = state.config.read().await.clone();
    let mut settings = config;
    if let Value::Object(map) = &mut settings {
        map.remove("require_login");
        map.remove("username");
        map.remove("password");
        map.remove("salt");
    }
    Json(settings)
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
    let dm_settings = DMSettings {
        speed_limit: new_config["speed_limit"].as_u64().unwrap_or(0),
        concurrency_limit: new_config["concurrency_limit"].as_u64().unwrap_or(3) as u8,
        download_threads: new_config["download_threads"].as_u64().unwrap_or(4) as u8,
        download_timeout: new_config["download_timeout"].as_u64().unwrap_or(300),
        download_retries: new_config["download_retries"].as_u64().unwrap_or(3) as u8,
        seeding_ratio: new_config["seeding_ratio"].as_f64().unwrap_or(0.0) as f32,
        seeding_time: new_config["seeding_time"].as_u64().unwrap_or(0),
        download_dir: format!("{}/downloads", nadeko_home()),
    };
    if let Err(e) = state.context.dm().await.update_settings(dm_settings).await {
        nadekodon_core::utils::logger::error(&format!("Error in updating DMSettings: {:?}", e));
    }

    let mut cfg = state.config.write().await;
    if let Some(v) = new_config.get("server_api_key").filter(|v| !v.is_null()) {
        cfg["server_api_key"] = v.clone();
        *state.api_key.write().await = normalize_secret(&v.as_str().unwrap_or("")).to_string();
    }
    if let Some(v) = new_config.get("download_folder").filter(|v| !v.is_null()) {
        cfg["download_folder"] = v.clone();
    }
    if let Some(v) = new_config.get("speed_limit").filter(|v| !v.is_null()) {
        cfg["speed_limit"] = v.clone();
    }
    if let Some(v) = new_config.get("speed_mode").filter(|v| !v.is_null()) {
        cfg["speed_mode"] = v.clone();
    }
    if let Some(v) = new_config.get("speed_schedule").filter(|v| !v.is_null()) {
        cfg["speed_schedule"] = v.clone();
    }
    if let Some(v) = new_config.get("download_threads").filter(|v| !v.is_null()) {
        cfg["download_threads"] = v.clone();
    }
    if let Some(v) = new_config.get("concurrency_limit").filter(|v| !v.is_null()) {
        cfg["concurrency_limit"] = v.clone();
    }
    if let Some(v) = new_config.get("download_timeout").filter(|v| !v.is_null()) {
        cfg["download_timeout"] = v.clone();
    }
    if let Some(v) = new_config.get("download_retries").filter(|v| !v.is_null()) {
        cfg["download_retries"] = v.clone();
    }
    if let Some(v) = new_config.get("seeding_ratio").filter(|v| !v.is_null()) {
        cfg["seeding_ratio"] = v.clone();
    }
    if let Some(v) = new_config.get("seeding_time").filter(|v| !v.is_null()) {
        cfg["seeding_time"] = v.clone();
    }
    if let Some(v) = new_config.get("theme_mode").filter(|v| !v.is_null()) {
        cfg["theme_mode"] = v.clone();
    }
    if let Some(v) = new_config.get("use_dynamic_color").filter(|v| !v.is_null()) {
        cfg["use_dynamic_color"] = v.clone();
    }
    if let Some(v) = new_config.get("custom_color").filter(|v| !v.is_null()) {
        cfg["custom_color"] = v.clone();
    }
    if let Some(v) = new_config.get("check_nightly").filter(|v| !v.is_null()) {
        cfg["check_nightly"] = v.clone();
    }
    if let Some(v) = new_config.get("retreat_to_tray").filter(|v| !v.is_null()) {
        cfg["retreat_to_tray"] = v.clone();
    }
    if let Some(v) = new_config.get("download_dir").filter(|v| !v.is_null()) {
        cfg["download_dir"] = v.clone();
    }

    let cfg_clone = cfg.clone();
    drop(cfg);

    state.save_config(&cfg_clone);
    *state.config.write().await = cfg_clone;

    axum::http::StatusCode::OK
}
