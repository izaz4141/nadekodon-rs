use utoipa::Modify;
use utoipa::openapi::security::{ApiKey, ApiKeyValue, Http, HttpAuthScheme, SecurityScheme};

pub struct SecurityModifier;

impl Modify for SecurityModifier {
    fn modify(&self, openapi: &mut utoipa::openapi::OpenApi) {
        let components = openapi
            .components
            .get_or_insert_with(utoipa::openapi::Components::new);

        components.add_security_scheme(
            "BasicAuth",
            SecurityScheme::Http(Http::new(HttpAuthScheme::Basic)),
        );

        components.add_security_scheme(
            "ApiKeyAuth",
            SecurityScheme::ApiKey(ApiKey::Header(ApiKeyValue::with_description(
                "X-API-Key",
                "API key authentication. Accepts X-API-Key header or nadeko_api_key cookie",
            ))),
        );

        components.add_security_scheme(
            "SIDCookie",
            SecurityScheme::ApiKey(ApiKey::Cookie(ApiKeyValue::with_description(
                "SID",
                "Session cookie for qbittorrent api route",
            ))),
        );
    }
}
