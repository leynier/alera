use axum::{
    body::{to_bytes, Body},
    http::{HeaderMap, Method, Request, StatusCode},
    Router,
};
use base64::{engine::general_purpose::URL_SAFE_NO_PAD, Engine};
use serde_json::{json, Value};
use sha2::{Digest, Sha256};
use tower::ServiceExt;
use url::Url;

pub const REDIRECT_URI: &str = "https://client.example/callback";
pub const RESOURCE: &str = "https://api.example.test/v1/mcp";
pub const VERIFIER: &str = "mcp-contract-verifier-with-enough-entropy-1234567890";

pub struct Reply {
    pub status: StatusCode,
    pub headers: HeaderMap,
    pub body: Vec<u8>,
}

impl Reply {
    pub fn json(&self) -> Value {
        serde_json::from_slice(&self.body).unwrap_or(Value::Null)
    }

    pub fn text(&self) -> String {
        String::from_utf8_lossy(&self.body).into_owned()
    }

    pub fn header(&self, name: &str) -> String {
        self.headers
            .get(name)
            .and_then(|value| value.to_str().ok())
            .unwrap_or_default()
            .to_owned()
    }

    pub fn location(&self) -> anyhow::Result<Url> {
        Ok(Url::parse(&self.header("location"))?)
    }

    pub fn error_code(&self) -> String {
        let value = self.json();
        value["error"]["code"]
            .as_str()
            .or_else(|| value["error"].as_str())
            .unwrap_or_default()
            .to_owned()
    }
}

pub fn query_value(url: &Url, name: &str) -> Option<String> {
    url.query_pairs()
        .find(|(key, _)| key == name)
        .map(|(_, value)| value.into_owned())
}

pub async fn send(
    app: &Router,
    method: Method,
    uri: &str,
    bearer: Option<&str>,
    content_type: Option<&str>,
    body: Vec<u8>,
) -> anyhow::Result<Reply> {
    let mut builder = Request::builder().method(method).uri(uri);
    if let Some(content_type) = content_type {
        builder = builder.header("content-type", content_type);
    }
    if let Some(bearer) = bearer {
        builder = builder.header("authorization", format!("Bearer {bearer}"));
    }
    let response = app.clone().oneshot(builder.body(Body::from(body))?).await?;
    let status = response.status();
    let headers = response.headers().clone();
    let body = to_bytes(response.into_body(), 1024 * 1024).await?.to_vec();
    Ok(Reply {
        status,
        headers,
        body,
    })
}

pub async fn get(app: &Router, uri: &str, bearer: Option<&str>) -> anyhow::Result<Reply> {
    send(app, Method::GET, uri, bearer, None, Vec::new()).await
}

pub async fn post_json(
    app: &Router,
    uri: &str,
    bearer: Option<&str>,
    body: Value,
) -> anyhow::Result<Reply> {
    send(
        app,
        Method::POST,
        uri,
        bearer,
        Some("application/json"),
        serde_json::to_vec(&body)?,
    )
    .await
}

pub async fn post_form(app: &Router, uri: &str, fields: &[(&str, &str)]) -> anyhow::Result<Reply> {
    let body = url::form_urlencoded::Serializer::new(String::new())
        .extend_pairs(fields)
        .finish();
    send(
        app,
        Method::POST,
        uri,
        None,
        Some("application/x-www-form-urlencoded"),
        body.into_bytes(),
    )
    .await
}

pub fn between(text: &str, start: &str, end: &str) -> anyhow::Result<String> {
    let from = text
        .find(start)
        .ok_or_else(|| anyhow::anyhow!("missing {start} in page"))?
        + start.len();
    let length = text[from..]
        .find(end)
        .ok_or_else(|| anyhow::anyhow!("missing end of {start}"))?;
    Ok(text[from..from + length].to_owned())
}

pub fn jwt_claims(token: &str) -> anyhow::Result<Value> {
    let segment = token
        .split('.')
        .nth(1)
        .ok_or_else(|| anyhow::anyhow!("malformed token"))?;
    Ok(serde_json::from_slice(&URL_SAFE_NO_PAD.decode(segment)?)?)
}

pub fn challenge() -> String {
    URL_SAFE_NO_PAD.encode(Sha256::digest(VERIFIER.as_bytes()))
}

/// Registers the runtime's relay identity and reports its MCP and Remote Access settings.
pub async fn report_runtime(
    app: &Router,
    token: &str,
    runtime_id: &str,
    mcp_access: &str,
    mobile_access: bool,
) -> anyhow::Result<Value> {
    let identity = post_json(
        app,
        "/v1/relay/identity",
        Some(token),
        json!({"publicKey": URL_SAFE_NO_PAD.encode([5_u8; 32]), "keyVersion": 1}),
    )
    .await?;
    anyhow::ensure!(identity.status == StatusCode::OK, "{}", identity.text());
    let grant = post_json(
        app,
        "/v1/relay/grants",
        Some(token),
        json!({"runtimeId": runtime_id, "mcpAccess": mcp_access, "mobileAccess": mobile_access}),
    )
    .await?;
    anyhow::ensure!(grant.status == StatusCode::OK, "{}", grant.text());
    jwt_claims(grant.json()["grant"].as_str().unwrap_or_default())
}

pub async fn register_client(app: &Router, name: &str) -> anyhow::Result<String> {
    let reply = post_json(
        app,
        "/oauth/register",
        None,
        json!({
            "redirect_uris": [REDIRECT_URI],
            "client_name": name,
            "token_endpoint_auth_method": "none",
            "grant_types": ["authorization_code", "refresh_token"],
        }),
    )
    .await?;
    anyhow::ensure!(reply.status == StatusCode::CREATED, "{}", reply.text());
    Ok(reply.json()["client_id"]
        .as_str()
        .unwrap_or_default()
        .to_owned())
}

pub fn authorize_uri(client_id: &str, scope: &str) -> String {
    let query = url::form_urlencoded::Serializer::new(String::new())
        .append_pair("response_type", "code")
        .append_pair("client_id", client_id)
        .append_pair("redirect_uri", REDIRECT_URI)
        .append_pair("state", "client-state")
        .append_pair("code_challenge", &challenge())
        .append_pair("code_challenge_method", "S256")
        .append_pair("scope", scope)
        .append_pair("resource", RESOURCE)
        .finish();
    format!("/oauth/authorize?{query}")
}

/// Drives authorize, provider login, and callback; returns the consent page and its fields.
pub async fn reach_consent(
    app: &Router,
    client_id: &str,
    scope: &str,
) -> anyhow::Result<(Reply, String, String)> {
    let sign_in = get(app, &authorize_uri(client_id, scope), None).await?;
    anyhow::ensure!(sign_in.status == StatusCode::OK, "{}", sign_in.text());
    let request = between(&sign_in.text(), "/oauth/login?request=", "&amp;")?;
    let login = get(
        app,
        &format!("/oauth/login?request={request}&provider=google"),
        None,
    )
    .await?;
    anyhow::ensure!(login.status.is_redirection(), "{}", login.text());
    let provider = login.location()?;
    anyhow::ensure!(
        query_value(&provider, "redirect_uri").as_deref()
            == Some("https://api.example.test/oauth/callback")
    );
    let state = query_value(&provider, "state").unwrap_or_default();
    let consent = get(
        app,
        &format!("/oauth/callback?state={state}&code=provider-code-for-contract"),
        None,
    )
    .await?;
    anyhow::ensure!(consent.status == StatusCode::OK, "{}", consent.text());
    let token = between(&consent.text(), "name=\"consent_token\" value=\"", "\"")?;
    Ok((consent, request, token))
}

pub async fn exchange_code(app: &Router, client_id: &str, code: &str) -> anyhow::Result<Reply> {
    post_form(
        app,
        "/oauth/token",
        &[
            ("grant_type", "authorization_code"),
            ("code", code),
            ("code_verifier", VERIFIER),
            ("client_id", client_id),
            ("redirect_uri", REDIRECT_URI),
            ("resource", RESOURCE),
        ],
    )
    .await
}

/// Runs the whole browser flow and returns `(access_token, refresh_token, code)`.
pub async fn authorize_runtimes(
    app: &Router,
    client_id: &str,
    runtimes: &[&str],
    all_runtimes: bool,
) -> anyhow::Result<(String, String, String)> {
    let (_, request, token) = reach_consent(app, client_id, "mcp:read mcp:execute").await?;
    let mut fields = vec![
        ("request", request.as_str()),
        ("consent_token", token.as_str()),
        ("execute", "1"),
        ("action", "approve"),
    ];
    for runtime in runtimes {
        fields.push(("runtime", runtime));
    }
    if all_runtimes {
        fields.push(("all_runtimes", "1"));
    }
    let approved = post_form(app, "/oauth/consent", &fields).await?;
    anyhow::ensure!(
        approved.status == StatusCode::SEE_OTHER,
        "{}",
        approved.text()
    );
    let code = query_value(&approved.location()?, "code").unwrap_or_default();
    let tokens = exchange_code(app, client_id, &code).await?;
    anyhow::ensure!(tokens.status == StatusCode::OK, "{}", tokens.text());
    let value = tokens.json();
    Ok((
        value["access_token"]
            .as_str()
            .unwrap_or_default()
            .to_owned(),
        value["refresh_token"]
            .as_str()
            .unwrap_or_default()
            .to_owned(),
        code,
    ))
}
