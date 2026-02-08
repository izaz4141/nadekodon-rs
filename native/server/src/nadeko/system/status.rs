use crate::server::SharedState;
use axum::{extract::State, response::IntoResponse, Json};
use serde_json::json;

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

    let mut res = json!({
        "status": "Online",
    });
    if version != "Unknown" {
        res["version"] = json!(version);
    }

    Json(res)
}
