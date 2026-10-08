use axum::{
    body::Bytes,
    extract::State,
    http::StatusCode,
    response::{IntoResponse, Response},
    Json,
};
use chrono::{TimeDelta, Utc};
use serde::Deserialize;
use serde_json::json;
use sqlx::FromRow;
use url::Url;

use crate::{auth::validation::random_secret, state::AppState};

use super::{no_store, with_cors, OAuthError};

const MAX_REDIRECT_URIS: usize = 10;
const MAX_REDIRECT_URI_LENGTH: usize = 2000;
const MAX_CLIENT_NAME_CHARS: usize = 100;
const METADATA_CACHE_MINUTES: i64 = 60;
const DEFAULT_CLIENT_NAME: &str = "MCP client";
const FORBIDDEN_SCHEMES: &[&str] = &[
    "javascript",
    "data",
    "file",
    "vbscript",
    "blob",
    "about",
    "filesystem",
    "view-source",
    "mailto",
    "ftp",
    "ws",
    "wss",
];

const KNOWN_APP_SCHEMES: &[&str] = &[
    "cursor",
    "vscode",
    "vscode-insiders",
    "windsurf",
    "zed",
    "kiro",
];

#[derive(Clone, Debug)]
pub struct ClientRecord {
    pub id: String,
    pub name: String,
    pub redirect_uris: Vec<String>,
}

#[derive(FromRow)]
struct ClientRow {
    id: String,
    client_name: String,
    redirect_uris: Vec<String>,
}

#[derive(Deserialize)]
struct RegistrationRequest {
    redirect_uris: Option<Vec<String>>,
    client_name: Option<String>,
    client_uri: Option<String>,
    token_endpoint_auth_method: Option<String>,
    grant_types: Option<Vec<String>>,
    response_types: Option<Vec<String>>,
    software_id: Option<String>,
    software_version: Option<String>,
}

#[derive(Deserialize)]
struct MetadataDocument {
    client_id: String,
    redirect_uris: Vec<String>,
    client_name: Option<String>,
    client_uri: Option<String>,
    token_endpoint_auth_method: Option<String>,
}

/// Checks a redirect URI against the allowed forms: `https`, loopback `http`, and
/// private-use schemes.
pub fn validate_redirect_uri(value: &str) -> Result<(), &'static str> {
    if value.len() > MAX_REDIRECT_URI_LENGTH || value.chars().any(char::is_control) {
        return Err("The redirect URI is too long or contains control characters.");
    }
    let url = Url::parse(value).map_err(|_| "The redirect URI is not an absolute URI.")?;
    if url.fragment().is_some() {
        return Err("The redirect URI must not contain a fragment.");
    }
    if !url.username().is_empty() || url.password().is_some() {
        return Err("The redirect URI must not contain credentials.");
    }
    match url.scheme() {
        "https" => {
            if url.host_str().is_none_or(str::is_empty) {
                return Err("The redirect URI must name a host.");
            }
            Ok(())
        }
        "http" => {
            if matches!(url.host_str(), Some("127.0.0.1" | "localhost" | "[::1]")) {
                Ok(())
            } else {
                Err("Plain http redirect URIs must use a loopback host.")
            }
        }
        scheme if FORBIDDEN_SCHEMES.contains(&scheme) => {
            Err("The redirect URI scheme is not allowed.")
        }
        // Private-use schemes must be reverse-domain names (RFC 8252) or a
        // known MCP client, so OS handlers such as `ms-msdt:` cannot be targets.
        scheme if scheme.contains('.') || KNOWN_APP_SCHEMES.contains(&scheme) => Ok(()),
        _ => Err("Private-use redirect URI schemes must be reverse-domain names."),
    }
}

pub fn sanitize_client_name(value: Option<&str>) -> String {
    let cleaned: String = value
        .unwrap_or_default()
        .chars()
        .filter(|character| !character.is_control())
        .take(MAX_CLIENT_NAME_CHARS)
        .collect();
    let trimmed = cleaned.trim();
    if trimmed.is_empty() {
        DEFAULT_CLIENT_NAME.to_owned()
    } else {
        trimmed.to_owned()
    }
}

fn optional_text(value: Option<String>, max: usize) -> Option<String> {
    value
        .map(|text| text.chars().filter(|c| !c.is_control()).take(max).collect())
        .filter(|text: &String| !text.trim().is_empty())
}

pub async fn register(State(state): State<AppState>, body: Bytes) -> Response {
    match register_client(&state, &body).await {
        Ok(response) => response,
        Err(error) => error.into_response(),
    }
}

async fn register_client(state: &AppState, body: &[u8]) -> Result<Response, OAuthError> {
    let request: RegistrationRequest = serde_json::from_slice(body).map_err(|_| {
        OAuthError::bad_request(
            "invalid_client_metadata",
            "The registration body must be a JSON object.",
        )
    })?;
    let redirect_uris = request.redirect_uris.unwrap_or_default();
    if redirect_uris.is_empty() || redirect_uris.len() > MAX_REDIRECT_URIS {
        return Err(OAuthError::bad_request(
            "invalid_redirect_uri",
            "Register between one and ten redirect URIs.",
        ));
    }
    for uri in &redirect_uris {
        validate_redirect_uri(uri)
            .map_err(|message| OAuthError::bad_request("invalid_redirect_uri", message))?;
    }
    if request
        .token_endpoint_auth_method
        .as_deref()
        .is_some_and(|method| method != "none")
    {
        return Err(OAuthError::bad_request(
            "invalid_client_metadata",
            "Only public clients with token_endpoint_auth_method none are supported.",
        ));
    }
    let grant_types = request
        .grant_types
        .unwrap_or_else(|| vec!["authorization_code".to_owned(), "refresh_token".to_owned()]);
    if grant_types.is_empty()
        || grant_types
            .iter()
            .any(|grant| grant != "authorization_code" && grant != "refresh_token")
    {
        return Err(OAuthError::bad_request(
            "invalid_client_metadata",
            "Only the authorization_code and refresh_token grants are supported.",
        ));
    }
    if request
        .response_types
        .as_ref()
        .is_some_and(|types| types.iter().any(|value| value != "code"))
    {
        return Err(OAuthError::bad_request(
            "invalid_client_metadata",
            "Only the code response type is supported.",
        ));
    }
    let client_id = random_secret("mcp_");
    let client_name = sanitize_client_name(request.client_name.as_deref());
    let now = Utc::now();
    sqlx::query(
        r#"
        INSERT INTO mcp_clients (
            id, kind, client_name, client_uri, redirect_uris, software_id,
            software_version, created_at, updated_at
        ) VALUES ($1, 'dynamic', $2, $3, $4, $5, $6, $7, $7)
        "#,
    )
    .bind(&client_id)
    .bind(&client_name)
    .bind(optional_text(request.client_uri, 2000))
    .bind(&redirect_uris)
    .bind(optional_text(request.software_id, 200))
    .bind(optional_text(request.software_version, 100))
    .bind(now)
    .execute(&state.pool)
    .await?;
    let body = json!({
        "client_id": client_id,
        "client_id_issued_at": now.timestamp(),
        "client_name": client_name,
        "redirect_uris": redirect_uris,
        "grant_types": grant_types,
        "response_types": ["code"],
        "token_endpoint_auth_method": "none",
        "scope": "mcp:read mcp:execute",
    });
    Ok(no_store(with_cors(
        (StatusCode::CREATED, Json(body)).into_response(),
    )))
}

/// Loads a registered client, fetching or refreshing a Client ID Metadata Document when
/// the id is an `https` URL. Errors are user-safe messages for the error page.
pub async fn load_client(state: &AppState, client_id: &str) -> Result<ClientRecord, String> {
    if client_id.is_empty() || client_id.len() > 2048 {
        return Err("The client_id is missing or invalid.".to_owned());
    }
    let cached = sqlx::query_as::<_, ClientRow>(
        r#"
        SELECT id, client_name, redirect_uris
        FROM mcp_clients
        WHERE id = $1
          AND (kind = 'dynamic' OR fetched_at > $2)
        "#,
    )
    .bind(client_id)
    .bind(Utc::now() - TimeDelta::minutes(METADATA_CACHE_MINUTES))
    .fetch_optional(&state.pool)
    .await
    .map_err(|error| {
        tracing::error!(error = %error, "load MCP client failed");
        "Alera could not load the client registration.".to_owned()
    })?;
    if let Some(row) = cached {
        return Ok(ClientRecord {
            id: row.id,
            name: row.client_name,
            redirect_uris: row.redirect_uris,
        });
    }
    if !client_id.starts_with("https://") {
        return Err("The client is not registered with Alera.".to_owned());
    }
    let record = fetch_metadata_document(state, client_id).await?;
    let now = Utc::now();
    sqlx::query(
        r#"
        INSERT INTO mcp_clients (
            id, kind, client_name, client_uri, redirect_uris, created_at, updated_at, fetched_at
        ) VALUES ($1, 'metadata_document', $2, $3, $4, $5, $5, $5)
        ON CONFLICT (id) DO UPDATE
        SET client_name = EXCLUDED.client_name, client_uri = EXCLUDED.client_uri,
            redirect_uris = EXCLUDED.redirect_uris, updated_at = EXCLUDED.updated_at,
            fetched_at = EXCLUDED.fetched_at
        WHERE mcp_clients.kind = 'metadata_document'
        "#,
    )
    .bind(&record.0.id)
    .bind(&record.0.name)
    .bind(record.1)
    .bind(&record.0.redirect_uris)
    .bind(now)
    .execute(&state.pool)
    .await
    .map_err(|error| {
        tracing::error!(error = %error, "store MCP client metadata failed");
        "Alera could not store the client registration.".to_owned()
    })?;
    Ok(record.0)
}

async fn fetch_metadata_document(
    state: &AppState,
    client_id: &str,
) -> Result<(ClientRecord, Option<String>), String> {
    let url = Url::parse(client_id).map_err(|_| "The client_id URL is invalid.".to_owned())?;
    if url.as_str() != client_id
        || url.scheme() != "https"
        || url.fragment().is_some()
        || !url.username().is_empty()
        || url.password().is_some()
        || url.path() == "/"
    {
        return Err("The client_id URL is not a valid metadata document URL.".to_owned());
    }
    let body = state.client_metadata.fetch(&url).await.map_err(|error| {
        tracing::warn!(error = %error, "client metadata document fetch failed");
        "The client metadata document could not be loaded.".to_owned()
    })?;
    parse_metadata_document(client_id, &body)
}

pub fn parse_metadata_document(
    client_id: &str,
    body: &[u8],
) -> Result<(ClientRecord, Option<String>), String> {
    let document: MetadataDocument = serde_json::from_slice(body)
        .map_err(|_| "The client metadata document is not valid JSON metadata.".to_owned())?;
    if document.client_id != client_id {
        return Err("The client metadata document names a different client_id.".to_owned());
    }
    if document.redirect_uris.is_empty() || document.redirect_uris.len() > MAX_REDIRECT_URIS {
        return Err("The client metadata document has no usable redirect URIs.".to_owned());
    }
    for uri in &document.redirect_uris {
        validate_redirect_uri(uri).map_err(ToOwned::to_owned)?;
    }
    if document
        .token_endpoint_auth_method
        .as_deref()
        .is_some_and(|method| method != "none")
    {
        return Err("Only public MCP clients are supported.".to_owned());
    }
    Ok((
        ClientRecord {
            id: client_id.to_owned(),
            name: sanitize_client_name(document.client_name.as_deref()),
            redirect_uris: document.redirect_uris,
        },
        optional_text(document.client_uri, 2000),
    ))
}

#[cfg(test)]
mod tests {
    use super::{parse_metadata_document, sanitize_client_name, validate_redirect_uri};

    #[test]
    fn accepts_https_loopback_and_private_use_redirects() {
        for uri in [
            "https://claude.ai/api/mcp/auth_callback",
            "http://127.0.0.1:33418/callback",
            "http://localhost:6274/oauth/callback",
            "http://[::1]:8080/cb",
            "cursor://anysphere.cursor-retrieval/oauth/user-alera/callback",
            "com.example.app:/oauth2redirect",
        ] {
            assert!(validate_redirect_uri(uri).is_ok(), "{uri} must be accepted");
        }
    }

    #[test]
    fn rejects_dangerous_redirects() {
        for uri in [
            "javascript:alert(1)",
            "data:text/html,hi",
            "file:///etc/passwd",
            "vbscript:msgbox",
            "http://example.com/callback",
            "http://192.168.1.2/callback",
            "ms-msdt:/id",
            "search-ms:query=x",
            "https://claude.ai/cb#fragment",
            "https://user:pass@claude.ai/cb",
            "not a uri",
        ] {
            assert!(
                validate_redirect_uri(uri).is_err(),
                "{uri} must be rejected"
            );
        }
    }

    #[test]
    fn metadata_document_must_name_itself() {
        let id = "https://client.example/metadata.json";
        let valid = format!(
            r#"{{"client_id":"{id}","client_name":"Example","redirect_uris":["https://client.example/cb"]}}"#
        );
        let parsed = parse_metadata_document(id, valid.as_bytes());
        assert!(parsed.is_ok());
        let other = r#"{"client_id":"https://evil.example/m.json","redirect_uris":["https://client.example/cb"]}"#;
        assert!(parse_metadata_document(id, other.as_bytes()).is_err());
        let bad_redirect = format!(r#"{{"client_id":"{id}","redirect_uris":["javascript:x"]}}"#);
        assert!(parse_metadata_document(id, bad_redirect.as_bytes()).is_err());
    }

    #[test]
    fn client_names_are_bounded() {
        assert_eq!(sanitize_client_name(None), "MCP client");
        assert_eq!(sanitize_client_name(Some("  Claude\n ")), "Claude");
        assert_eq!(sanitize_client_name(Some(&"x".repeat(300))).len(), 100);
    }
}
