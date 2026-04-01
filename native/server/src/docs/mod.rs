pub mod security;

use axum::Router;
use utoipa::OpenApi;
use utoipa_swagger_ui::SwaggerUi;

use crate::server::SharedState;

use security::SecurityModifier;

#[derive(OpenApi)]
#[openapi(
    paths(
        crate::nadeko::auth::login::handle_login,
        crate::nadeko::auth::hash::handle_hashing_password,
        crate::nadeko::auth::salt::handle_generate_salt,
        crate::nadeko::auth::api::handle_generate_api,
        crate::nadeko::auth::change_credentials::handle_change_credentials,
        crate::nadeko::auth::verify_password::handle_verify_password,
        crate::nadeko::download::list::handle_get_download_list,
        crate::nadeko::download::details::handle_get_download_details,
        crate::nadeko::download::create::handle_create_download,
        crate::nadeko::download::pause::handle_pause_download,
        crate::nadeko::download::resume::handle_resume_download,
        crate::nadeko::download::cancel::handle_cancel_download,
        crate::nadeko::download::delete::handle_delete_download,
        crate::nadeko::download::update_url::handle_update_url,
        crate::nadeko::download::file::handle_download_file,
        crate::nadeko::system::status::handle_status,
        crate::nadeko::system::restart::handle_restart,
        crate::nadeko::system::settings::handle_get_settings,
        crate::nadeko::system::settings::handle_update_settings,
        crate::nadeko::utils::query_url::handle_query_url,
        crate::nadeko::utils::query_ytdl::handle_query_ytdl,
        crate::nadeko::utils::img::handle_proxy_image,
        crate::nadeko::version::latest::handle_version_latest,
        crate::nadeko::version::current::handle_version_current,
        crate::nadeko::version::compare::handle_compare_versions,
        crate::qbittorrent::auth_login,
        crate::qbittorrent::app::app_version,
        crate::qbittorrent::app::app_webapi_version,
        crate::qbittorrent::app::app_preferences,
        crate::qbittorrent::add::torrents_add,
        crate::qbittorrent::info::torrents_info,
        crate::qbittorrent::properties::torrents_properties,
        crate::qbittorrent::files::torrents_files,
        crate::qbittorrent::delete::torrents_delete,
        crate::qbittorrent::categories::torrents_set_category,
        crate::qbittorrent::categories::torrents_create_category,
        crate::qbittorrent::categories::torrents_categories,
        crate::qbittorrent::misc::torrents_set_share_limits,
        crate::qbittorrent::misc::torrents_top_prio,
        crate::qbittorrent::misc::torrents_set_force_start,
    ),
    components(
        schemas(
            crate::nadeko::auth::hash::HashRequest,
            crate::nadeko::auth::api::ApiKeyResponse,
            crate::nadeko::auth::change_credentials::ChangeCredentialsRequest,
            crate::nadeko::download::pause::IdRequest,
            crate::nadeko::download::resume::IdRequest,
            crate::nadeko::download::cancel::IdRequest,
            crate::nadeko::download::delete::DeleteDownloadRequest,
            crate::nadeko::download::update_url::UpdateUrlRequest,
            crate::nadeko::download::file::DownloadFilePath,
            crate::nadeko::download::details::DownloadDetailsPath,
            crate::nadeko::system::status::StatusResponse,
            crate::nadeko::system::settings::SettingsResponse,
            crate::nadeko::version::current::VersionCurrentResponse,
            crate::nadeko::version::compare::CompareVersionsRequest,
            crate::nadeko::version::compare::CompareVersionsResponse,
            nadekodon_core::signals::DoDownload,
            nadekodon_core::signals::GetDownloadList,
            nadekodon_core::signals::DownloadList,
            nadekodon_core::signals::DownloadGlance,
            nadekodon_core::signals::GetDownloadDetails,
            nadekodon_core::signals::DownloadDetails,
            nadekodon_core::signals::PauseDownload,
            nadekodon_core::signals::ResumeDownload,
            nadekodon_core::signals::CancelDownload,
            nadekodon_core::signals::DeleteDownload,
            nadekodon_core::signals::UpdateDownloadUrl,
            nadekodon_core::signals::QueryUrl,
            nadekodon_core::signals::QueryYtdl,
            nadekodon_core::signals::UrlQueryOutput,
            nadekodon_core::signals::YtdlQueryOutput,
            nadekodon_core::signals::YtdlItem,
            nadekodon_core::signals::YtdlFormat,
            nadekodon_core::signals::PartInfo,
            crate::qbittorrent::AuthQuery,
            crate::qbittorrent::app::PreferencesResponse,
            crate::qbittorrent::add::TorrentsAddMultipart,
            crate::qbittorrent::info::TorrentsInfoResponse,
            crate::qbittorrent::properties::TorrentsPropertiesResponse,
            crate::qbittorrent::files::TorrentFileResponse,
            crate::qbittorrent::delete::TorrentsDeleteQuery,
            crate::qbittorrent::categories::TorrentsSetCategoryForm,
            crate::qbittorrent::categories::TorrentsCreateCategoryForm,
            crate::qbittorrent::categories::CategoryResponse,
            crate::qbittorrent::misc::TorrentsSetShareLimitsForm,
            crate::qbittorrent::misc::TorrentsTopPrioForm,
            crate::qbittorrent::misc::TorrentsSetForceStartForm,
        )
    ),
    modifiers(&SecurityModifier),
    security(
        ("BasicAuth" = []),
        ("ApiKeyAuth" = []),
        ("SIDCookie" = [])
    )
)]
pub struct ApiDoc;

pub fn create_docs_router(_state: SharedState) -> Router<SharedState> {
    let api = ApiDoc::openapi();

    Router::new().merge(SwaggerUi::new("/api/docs").url("/api/openapi.json", api.clone()))
}
