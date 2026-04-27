use axum::{
    body::Body,
    extract::State,
    http::{HeaderMap, Request, StatusCode},
    middleware::Next,
    response::IntoResponse,
};
use axum_extra::extract::CookieJar;
use jsonwebtoken::{
    Algorithm, DecodingKey, EncodingKey, Header, TokenData, Validation, decode, encode,
};
use serde::{Deserialize, Serialize};
use std::time::{SystemTime, UNIX_EPOCH};

use crate::server::SharedState;
use crate::server::secure_compare;

const JWT_ALGORITHM: Algorithm = Algorithm::HS256;
const JWT_EXPIRY_HOURS: u64 = 3;

#[derive(Serialize, Deserialize, Clone)]
pub struct JwtClaims {
    pub sub: String,
    pub exp: u64,
    pub csrf: String,
    pub iat: u64,
}

#[derive(Serialize, Deserialize)]
pub struct JwtResponse {
    pub access_token: String,
    pub csrf_token: String,
    pub expires_in: u64,
}

fn get_jwt_secret(state: &SharedState) -> Vec<u8> {
    state.master_key.blocking_read().as_bytes().to_vec()
}

fn get_current_timestamp() -> u64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap()
        .as_secs()
}

fn get_expiry_timestamp() -> u64 {
    get_current_timestamp() + (JWT_EXPIRY_HOURS * 3600)
}

fn create_csrf_token() -> String {
    use uuid::Uuid;
    Uuid::new_v4().to_string()
}

fn create_jwt_token(
    state: &SharedState,
    username: &str,
    csrf_token: &str,
) -> Result<String, jsonwebtoken::errors::Error> {
    let now = get_current_timestamp();
    let claims = JwtClaims {
        sub: username.to_string(),
        exp: get_expiry_timestamp(),
        csrf: csrf_token.to_string(),
        iat: now,
    };

    let header = Header::new(JWT_ALGORITHM);
    encode(
        &header,
        &claims,
        &EncodingKey::from_secret(&get_jwt_secret(state)),
    )
}

fn validate_jwt_token(
    state: &SharedState,
    token: &str,
) -> Result<TokenData<JwtClaims>, jsonwebtoken::errors::Error> {
    let mut validation = Validation::new(JWT_ALGORITHM);
    validation.validate_exp = true;

    decode::<JwtClaims>(
        token,
        &DecodingKey::from_secret(&get_jwt_secret(state)),
        &validation,
    )
}

fn is_token_expired(exp: u64) -> bool {
    get_current_timestamp() >= exp
}

pub fn create_jwt_response(
    state: &SharedState,
    username: &str,
) -> Result<JwtResponse, jsonwebtoken::errors::Error> {
    let csrf = create_csrf_token();
    let access_token = create_jwt_token(state, username, &csrf)?;
    let expires_in = JWT_EXPIRY_HOURS * 3600;

    Ok(JwtResponse {
        access_token,
        csrf_token: csrf,
        expires_in,
    })
}

pub fn validate_jwt_request(
    state: &SharedState,
    jar: &CookieJar,
    headers: &HeaderMap,
) -> Result<JwtClaims, String> {
    let jwt = jar.get("nadekodon_jwt");
    let csrf_header = headers
        .get("x-csrf-token")
        .and_then(|v| v.to_str().ok())
        .map(String::from);

    let token = jwt.ok_or("No JWT cookie")?;
    let csrf = csrf_header.ok_or("No CSRF header")?;

    let token_data = validate_jwt_token(state, token.value()).map_err(|e| e.to_string())?;
    let claims = token_data.claims;

    if is_token_expired(claims.exp) {
        return Err("Token expired".to_string());
    }

    if !secure_compare(&claims.csrf, &csrf) {
        return Err("CSRF token mismatch".to_string());
    }

    Ok(claims)
}

pub async fn check_api_key(
    State(state): State<SharedState>,
    req: Request<Body>,
    next: Next,
) -> Result<impl IntoResponse, StatusCode> {
    let api_key = state.api_key.read().await.clone();

    if let Some(key) = req.headers().get("X-API-Key")
        && key
            .to_str()
            .map(|k| secure_compare(k, &api_key))
            .unwrap_or(false)
    {
        return Ok(next.run(req).await);
    }

    Err(StatusCode::UNAUTHORIZED)
}
