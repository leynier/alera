pub mod authorize;
pub mod cimd;
pub mod client_assertion;
pub mod client_authentication;
pub mod client_jwks;
pub mod clients;
pub mod consent;
pub mod forms;
pub mod grants;
pub mod login;
pub mod metadata;
pub mod pages;
pub mod token;

use axum::{
    http::{header, HeaderValue, StatusCode},
    response::{IntoResponse, Response},
    routing::{delete, get, post, put},
    Json, Router,
};
use serde_json::json;

use crate::{device_auth, error::ApiError, mcp_gateway, runtimes, state::AppState};

pub const AUTHORIZATION_REQUEST_MINUTES: i64 = 10;

/// Routes for Remote MCP. With MCP disabled the OAuth server and gateway routes are absent
/// (404), while device sign-in and grant management stay available.
pub fn router(mcp_enabled: bool) -> Router<AppState> {
    let mut router = Router::new()
        .route("/oauth/login", get(login::start))
        .route(
            "/oauth/callback",
            get(login::callback).post(login::callback_form),
        )
        .route("/oauth/consent", post(consent::submit))
        .route(
            "/device",
            get(device_auth::page).post(device_auth::page_form),
        )
        .route("/v1/auth/device", post(device_auth::start))
        .route("/v1/auth/device/token", post(device_auth::token))
        .route("/v1/mcp/grants", get(grants::list))
        .route("/v1/mcp/grants/{id}", delete(grants::revoke))
        .route("/v1/runtime/name", put(runtimes::rename_runtime))
        .route(
            "/v1/runtime/capabilities",
            put(runtimes::report_capabilities),
        );
    if mcp_enabled {
        router = router
            .route(
                "/.well-known/oauth-authorization-server",
                get(metadata::authorization_server).options(preflight),
            )
            .route(
                "/.well-known/oauth-protected-resource",
                get(metadata::protected_resource).options(preflight),
            )
            .route(
                "/.well-known/oauth-protected-resource/v1/mcp",
                get(metadata::protected_resource).options(preflight),
            )
            .route(
                "/oauth/register",
                post(clients::register).options(preflight),
            )
            .route(
                "/oauth/authorize",
                get(authorize::authorize).post(authorize::authorize_form),
            )
            .route("/oauth/token", post(token::token).options(preflight))
            .route("/oauth/revoke", post(token::revoke).options(preflight))
            .route("/v1/mcp/runtimes", get(mcp_gateway::list_runtimes))
            .route("/v1/mcp/calls", post(mcp_gateway::create_call))
            .route(
                "/v1/mcp/calls/{id}/outcome",
                post(mcp_gateway::complete_call),
            );
    }
    router
}

/// Adds the CORS headers browser-based MCP clients need on the public OAuth endpoints.
pub fn with_cors(mut response: Response) -> Response {
    let headers = response.headers_mut();
    headers.insert(
        header::ACCESS_CONTROL_ALLOW_ORIGIN,
        HeaderValue::from_static("*"),
    );
    headers.insert(
        header::ACCESS_CONTROL_EXPOSE_HEADERS,
        HeaderValue::from_static("WWW-Authenticate"),
    );
    response
}

async fn preflight() -> Response {
    let mut response = with_cors(StatusCode::NO_CONTENT.into_response());
    let headers = response.headers_mut();
    headers.insert(
        header::ACCESS_CONTROL_ALLOW_METHODS,
        HeaderValue::from_static("GET, POST, OPTIONS"),
    );
    headers.insert(
        header::ACCESS_CONTROL_ALLOW_HEADERS,
        HeaderValue::from_static("Authorization, Content-Type, MCP-Protocol-Version"),
    );
    headers.insert(
        header::ACCESS_CONTROL_MAX_AGE,
        HeaderValue::from_static("86400"),
    );
    response
}

/// An RFC 6749 style error: `{ error, error_description }` with `Cache-Control: no-store`.
#[derive(Debug)]
pub struct OAuthError {
    pub status: StatusCode,
    pub error: &'static str,
    pub description: String,
}

impl OAuthError {
    pub fn new(status: StatusCode, error: &'static str, description: impl Into<String>) -> Self {
        Self {
            status,
            error,
            description: description.into(),
        }
    }

    pub fn bad_request(error: &'static str, description: impl Into<String>) -> Self {
        Self::new(StatusCode::BAD_REQUEST, error, description)
    }

    pub fn invalid_request(description: impl Into<String>) -> Self {
        Self::bad_request("invalid_request", description)
    }

    pub fn invalid_grant(description: impl Into<String>) -> Self {
        Self::bad_request("invalid_grant", description)
    }

    pub fn invalid_client(description: impl Into<String>) -> Self {
        Self::new(StatusCode::UNAUTHORIZED, "invalid_client", description)
    }

    fn server_error() -> Self {
        Self::new(
            StatusCode::INTERNAL_SERVER_ERROR,
            "server_error",
            "The authorization server could not complete the request.",
        )
    }
}

impl From<sqlx::Error> for OAuthError {
    fn from(error: sqlx::Error) -> Self {
        tracing::error!(error = %error, "database operation failed");
        Self::server_error()
    }
}

impl From<ApiError> for OAuthError {
    fn from(error: ApiError) -> Self {
        match error {
            ApiError::Request { message, .. } => Self::invalid_grant(message),
            other => {
                tracing::error!(error = %other, "authorization server failure");
                Self::server_error()
            }
        }
    }
}

impl IntoResponse for OAuthError {
    fn into_response(self) -> Response {
        let body = Json(json!({
            "error": self.error,
            "error_description": self.description,
        }));
        no_store(with_cors((self.status, body).into_response()))
    }
}

pub fn no_store(mut response: Response) -> Response {
    let headers = response.headers_mut();
    headers.insert(header::CACHE_CONTROL, HeaderValue::from_static("no-store"));
    headers.insert(header::PRAGMA, HeaderValue::from_static("no-cache"));
    response
}
