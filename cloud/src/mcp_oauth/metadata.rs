use axum::{extract::State, response::Response, Json};
use serde_json::{json, Value};

use crate::{
    mcp_models::{SCOPE_EXECUTE, SCOPE_READ},
    state::AppState,
};

use super::with_cors;

pub async fn authorization_server(State(state): State<AppState>) -> Response {
    with_cors(axum::response::IntoResponse::into_response(Json(
        authorization_server_document(&state),
    )))
}

pub async fn protected_resource(State(state): State<AppState>) -> Response {
    with_cors(axum::response::IntoResponse::into_response(Json(
        protected_resource_document(&state),
    )))
}

pub fn authorization_server_document(state: &AppState) -> Value {
    let config = &state.config;
    json!({
        "issuer": config.issuer,
        "authorization_endpoint": config.public_url("/oauth/authorize"),
        "token_endpoint": config.public_url("/oauth/token"),
        "registration_endpoint": config.public_url("/oauth/register"),
        "revocation_endpoint": config.public_url("/oauth/revoke"),
        "jwks_uri": config.public_url("/.well-known/jwks.json"),
        "response_types_supported": ["code"],
        "response_modes_supported": ["query"],
        "grant_types_supported": ["authorization_code", "refresh_token"],
        "token_endpoint_auth_methods_supported": ["none"],
        "revocation_endpoint_auth_methods_supported": ["none"],
        "code_challenge_methods_supported": ["S256"],
        "scopes_supported": [SCOPE_READ, SCOPE_EXECUTE],
        "client_id_metadata_document_supported": true,
        "authorization_response_iss_parameter_supported": true,
    })
}

pub fn protected_resource_document(state: &AppState) -> Value {
    json!({
        "resource": state.config.mcp.resource,
        "authorization_servers": [state.config.issuer],
        "scopes_supported": [SCOPE_READ, SCOPE_EXECUTE],
        "bearer_methods_supported": ["header"],
        "resource_name": "Alera",
    })
}
