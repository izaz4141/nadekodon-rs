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
            let paths = [
                ("./version.json", true),
                ("./pubspec.yaml", false),
            ];
            for (path, is_json) in paths {
                if let Ok(content) = std::fs::read_to_string(path) {
                    let (v, b) = if is_json {
                        nadekodon_core::utils::version::parse_version_json(&content)
                    } else {
                        nadekodon_core::utils::version::parse_pubspec_version(&content)
                    };
                    if let Some(version_val) = v {
                        v_str = if let Some(build_val) = b {
                            format!("{}+{}", version_val, build_val)
                        } else {
                            version_val
                        };
                        break;
                    }
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
