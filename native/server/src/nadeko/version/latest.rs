use crate::server::SharedState;
use axum::{
    extract::{Json, Query, State},
    response::IntoResponse,
};
use nadekodon_core::utils::version::VersionInfo;
use serde::Deserialize;
use utoipa::IntoParams;

#[derive(Deserialize, IntoParams)]
#[into_params(parameter_in = Query)]
pub struct VersionLatestQuery {
    pub owner: String,
    pub repo: String,
    #[serde(default)]
    pub nightly: bool,
    #[serde(default = "default_true")]
    pub atomic: bool,
}

fn default_true() -> bool {
    true
}

#[utoipa::path(
    get,
    path = "/api/nadeko/version/latest",
    tags = ["nadeko.version"],
    security(("ApiKeyAuth" = [])),
    params(VersionLatestQuery),
    responses(
        (status = 200, description = "Latest version info", body = VersionInfo),
        (status = 400, description = "Invalid request")
    )
)]
pub async fn handle_version_latest(
    State(state): State<SharedState>,
    Query(params): Query<VersionLatestQuery>,
) -> impl IntoResponse {
    let repo_owner = params.owner;
    let repo_name = params.repo;
    let check_nightly = params.nightly;
    let use_atom = params.atomic;

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
