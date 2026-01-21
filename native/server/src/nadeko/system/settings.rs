use crate::server::{SharedState, nadeko_home, save_config};
use axum::{Json, extract::State, response::IntoResponse};
use nadekodon_core::utils::types::DMSettings;
use serde_json::Value;

pub async fn handle_get_settings(State(state): State<SharedState>) -> impl IntoResponse {
    let config = state.config.read().await.clone();
    Json(config)
}

pub async fn handle_update_settings(
    State(state): State<SharedState>,
    Json(new_config): Json<Value>,
) -> impl IntoResponse {
    let api_key = new_config["server_api_key"].clone().to_string();
    let username = new_config["username"].clone().to_string();
    let password = new_config["password"].clone().to_string();
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
    save_config(&new_config);
    *state.api_key.write().await = crate::server::normalize_secret(&api_key).to_string();
    *state.username.write().await = crate::server::normalize_secret(&username).to_string();
    *state.password.write().await = crate::server::normalize_secret(&password).to_string();
    *state.config.write().await = new_config;
    axum::http::StatusCode::OK
}
