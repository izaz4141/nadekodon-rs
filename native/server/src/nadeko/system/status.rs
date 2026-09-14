use crate::server::SharedState;
use axum::{Json, extract::State, response::IntoResponse};
use nadekodon_core::signals::ServerStatus;

#[utoipa::path(
    get,
    path = "/api/nadeko/system/status",
    tags = ["nadeko.system"],
    responses(
        (status = 200, description = "Server status", body = ServerStatus)
    )
)]
pub async fn handle_status(State(state): State<SharedState>) -> impl IntoResponse {
    let version = {
        let read = state.version.read().await;
        if let Some(v) = &*read {
            v.clone()
        } else {
            drop(read);
            let mut v_str = "Unknown".to_string();
            if let Ok(content) = std::fs::read_to_string("./assets/docs/pubspec.yaml".to_string()) {
                let (v, b) = nadekodon_core::utils::version::parse_pubspec_version(&content);
                if let Some(version_val) = v {
                    v_str = if let Some(build_val) = b {
                        format!("{}+{}", version_val, build_val)
                    } else {
                        version_val
                    };
                }
            }
            {
                let mut write = state.version.write().await;
                *write = Some(v_str.clone());
            }
            v_str
        }
    };
    let res = ServerStatus {
        status: "Online".to_string(),
        version: version,
    };

    Json(res)
}