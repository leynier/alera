use axum::{
    extract::{RawQuery, State},
    response::{IntoResponse, Redirect, Response},
};
use chrono::{TimeDelta, Utc};
use url::Url;
use uuid::Uuid;

use crate::{
    auth::validation::validate_code_challenge,
    mcp_models::{SCOPE_ADMIN, SCOPE_EXECUTE, SCOPE_READ},
    state::AppState,
};

use super::{
    clients::load_client,
    forms::FormFields,
    pages::{escape, provider_buttons, Page, PageError},
    AUTHORIZATION_REQUEST_MINUTES,
};

/// Where authorization errors go once the client and redirect URI are trusted.
pub struct ClientRedirect<'a> {
    pub redirect_uri: &'a str,
    pub state: Option<&'a str>,
    pub issuer: &'a str,
}

impl ClientRedirect<'_> {
    pub fn error(&self, error: &str, description: &str) -> Response {
        self.send(&[("error", error), ("error_description", description)])
    }

    pub fn send(&self, params: &[(&str, &str)]) -> Response {
        let Ok(mut url) = Url::parse(self.redirect_uri) else {
            return PageError::bad_request("The redirect URI is invalid.").into_response();
        };
        {
            let mut query = url.query_pairs_mut();
            for (name, value) in params {
                query.append_pair(name, value);
            }
            if let Some(state) = self.state {
                query.append_pair("state", state);
            }
            query.append_pair("iss", self.issuer);
        }
        Redirect::to(url.as_str()).into_response()
    }
}

/// Normalizes the requested scope. Unknown scopes are ignored, `mcp:read` is always
/// included, and an absent or empty scope requests `mcp:read` and `mcp:execute`.
/// `mcp:admin` is kept only when the client names it, and then also implies
/// `mcp:execute`; it is never added on its own, and consent still has to grant it.
pub fn requested_scopes(scope: Option<&str>) -> Vec<&'static str> {
    let requested: Vec<&str> = scope.unwrap_or_default().split_whitespace().collect();
    let admin = requested.contains(&SCOPE_ADMIN);
    let known = admin
        || requested
            .iter()
            .any(|value| *value == SCOPE_READ || *value == SCOPE_EXECUTE);
    let mut scopes = vec![SCOPE_READ];
    if !known || admin || requested.contains(&SCOPE_EXECUTE) {
        scopes.push(SCOPE_EXECUTE);
    }
    if admin {
        scopes.push(SCOPE_ADMIN);
    }
    scopes
}

pub async fn authorize(State(state): State<AppState>, RawQuery(query): RawQuery) -> Response {
    match authorize_request(&state, query.as_deref()).await {
        Ok(response) => response,
        Err(error) => error.into_response(),
    }
}

/// The edge forwards the authorization query as a form body, so Cloud Run
/// request logs never record the client's state.
pub async fn authorize_form(State(state): State<AppState>, body: String) -> Response {
    match authorize_request(&state, Some(&body)).await {
        Ok(response) => response,
        Err(error) => error.into_response(),
    }
}

async fn authorize_request(state: &AppState, query: Option<&str>) -> Result<Response, PageError> {
    let form = FormFields::parse_query(query);
    let trusted = |name: &str| {
        form.get(name)
            .map_err(|_| PageError::bad_request(format!("The {name} parameter is repeated.")))
    };
    let client_id = trusted("client_id")?
        .ok_or_else(|| PageError::bad_request("The client_id parameter is missing."))?;
    let client = load_client(state, client_id)
        .await
        .map_err(PageError::bad_request)?;
    let redirect_uri = trusted("redirect_uri")?
        .ok_or_else(|| PageError::bad_request("The redirect_uri parameter is missing."))?;
    if !client.redirect_uris.iter().any(|uri| uri == redirect_uri) {
        return Err(PageError::bad_request(
            "The redirect_uri does not match a URI registered for this client.",
        ));
    }
    let client_state = form.get("state").ok().flatten();
    // Every client registered itself, so a request error renders here instead
    // of redirecting: otherwise any registered URI becomes an open redirect.
    let fields = (
        form.get("state"),
        form.get("response_type"),
        form.get("code_challenge"),
        form.get("code_challenge_method"),
        form.get("scope"),
        form.get("resource"),
    );
    let (Ok(_), Ok(response_type), Ok(code_challenge), Ok(method), Ok(scope), Ok(resource)) =
        fields
    else {
        return Err(PageError::bad_request("A parameter is repeated."));
    };
    if response_type != Some("code") {
        return Err(PageError::bad_request(
            "Only the code response type is supported.",
        ));
    }
    let Some(code_challenge) = code_challenge else {
        return Err(PageError::bad_request("PKCE code_challenge is required."));
    };
    if method != Some("S256") || validate_code_challenge(code_challenge).is_err() {
        return Err(PageError::bad_request(
            "PKCE with code_challenge_method S256 is required.",
        ));
    }
    if resource.is_some_and(|value| value != state.config.mcp.resource) {
        return Err(PageError::bad_request(
            "The requested resource is not served by this authorization server.",
        ));
    }
    let scopes = requested_scopes(scope).join(" ");
    let id = Uuid::new_v4();
    let now = Utc::now();
    sqlx::query(
        r#"
        INSERT INTO mcp_authorization_requests (
            id, client_id, redirect_uri, state, code_challenge, scope, resource,
            created_at, expires_at
        ) VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9)
        "#,
    )
    .bind(id)
    .bind(&client.id)
    .bind(redirect_uri)
    .bind(client_state)
    .bind(code_challenge)
    .bind(&scopes)
    .bind(resource)
    .bind(now)
    .bind(now + TimeDelta::minutes(AUTHORIZATION_REQUEST_MINUTES))
    .execute(&state.pool)
    .await?;
    let body = format!(
        "<h1>Sign in to Alera</h1>\
<p><strong>{}</strong> wants to use your Alera runtimes over MCP.</p>\
<p class=\"muted\">After you sign in you can choose which runtimes it may use. You will then return to {}.</p>{}",
        escape(&client.name),
        escape(&redirect_host(redirect_uri)),
        provider_buttons("request", &id.to_string()),
    );
    Ok(Page::new("Sign in to Alera", body).into_response())
}

/// A short label for where a redirect URI returns: its host, or its scheme for
/// private-use schemes without a host.
pub fn redirect_host(redirect_uri: &str) -> String {
    match Url::parse(redirect_uri) {
        Ok(url) => match url.host_str() {
            Some(host) if !host.is_empty() => host.to_owned(),
            _ => url.scheme().to_owned(),
        },
        Err(_) => redirect_uri.to_owned(),
    }
}

#[cfg(test)]
mod tests {
    use super::{redirect_host, requested_scopes, ClientRedirect};

    #[test]
    fn scope_defaults_and_normalization() {
        assert_eq!(requested_scopes(None), vec!["mcp:read", "mcp:execute"]);
        assert_eq!(requested_scopes(Some("")), vec!["mcp:read", "mcp:execute"]);
        assert_eq!(requested_scopes(Some("mcp:read")), vec!["mcp:read"]);
        assert_eq!(
            requested_scopes(Some("offline_access mcp:read")),
            vec!["mcp:read"]
        );
        assert_eq!(
            requested_scopes(Some("mcp:execute")),
            vec!["mcp:read", "mcp:execute"]
        );
        assert_eq!(
            requested_scopes(Some("openid profile")),
            vec!["mcp:read", "mcp:execute"]
        );
    }

    #[test]
    fn admin_is_kept_only_when_requested() {
        for scope in [
            None,
            Some(""),
            Some("mcp:read"),
            Some("mcp:execute"),
            Some("mcp:read mcp:execute"),
            Some("admin mcp:admins openid"),
        ] {
            assert!(!requested_scopes(scope).contains(&"mcp:admin"), "{scope:?}");
        }
        assert_eq!(
            requested_scopes(Some("mcp:admin")),
            vec!["mcp:read", "mcp:execute", "mcp:admin"]
        );
        assert_eq!(
            requested_scopes(Some("mcp:read mcp:admin")),
            vec!["mcp:read", "mcp:execute", "mcp:admin"]
        );
        assert_eq!(
            requested_scopes(Some("mcp:read mcp:execute mcp:admin")),
            vec!["mcp:read", "mcp:execute", "mcp:admin"]
        );
    }

    #[test]
    fn redirects_carry_state_and_issuer() {
        let redirect = ClientRedirect {
            redirect_uri: "https://client.example/cb?keep=1",
            state: Some("s 1"),
            issuer: "https://api.alera.build",
        };
        let response = redirect.send(&[("code", "abc")]);
        let location = response
            .headers()
            .get("location")
            .and_then(|value| value.to_str().ok())
            .unwrap_or_default();
        assert_eq!(
            location,
            "https://client.example/cb?keep=1&code=abc&state=s+1&iss=https%3A%2F%2Fapi.alera.build"
        );
        assert_eq!(
            redirect_host("cursor://anysphere.cursor-retrieval/cb"),
            "anysphere.cursor-retrieval"
        );
        assert_eq!(redirect_host("com.example:/cb"), "com.example");
    }
}
