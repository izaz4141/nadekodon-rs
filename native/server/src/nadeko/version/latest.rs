use crate::server::SharedState;
use axum::{
    extract::{Json, Query, State},
    response::IntoResponse,
};
use std::collections::HashMap;

pub async fn handle_version_latest(
    State(state): State<SharedState>,
    Query(params): Query<HashMap<String, String>>,
) -> impl IntoResponse {
    let repo_owner = match params.get("owner") {
        Some(v) => v.clone(),
        None => {
            return (
                axum::http::StatusCode::BAD_REQUEST,
                "Missing owner parameter".to_string(),
            )
                .into_response();
        }
    };
    let repo_name = match params.get("repo") {
        Some(v) => v.clone(),
        None => {
            return (
                axum::http::StatusCode::BAD_REQUEST,
                "Missing repo parameter".to_string(),
            )
                .into_response();
        }
    };
    let check_nightly = params.get("nightly").map(|v| v == "true").unwrap_or(false);
    let use_atom = params.get("atomic").map(|v| v == "true").unwrap_or(true);

    match nadekodon_core::utils::version::get_latest_version(
        &state.context.dm().await.client,
        &repo_owner,
        &repo_name,
        check_nightly,
        use_atom,
    )
    .await
    {
        Ok(info) => Json(info).into_response(),
        Err(e) => {
            nadekodon_core::utils::logger::error(&format!(
                "Error getting latest {}/{}: {:#?}",
                &repo_owner, &repo_name, &e
            ));
            (axum::http::StatusCode::BAD_REQUEST, e.to_string()).into_response()
        }
    }
}
