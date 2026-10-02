use base64::{engine::general_purpose::URL_SAFE_NO_PAD, Engine};
use jsonwebtoken::{decode, decode_header, jwk::JwkSet, Algorithm, DecodingKey, Validation};
use serde::Deserialize;
use serde_json::Value;
use sha2::{Digest, Sha256};
use tokio::io::{AsyncReadExt, AsyncWriteExt};
use tokio::net::TcpListener;
use url::Url;

use super::chatgpt_credentials::{Account, Tokens};
use crate::terminal_host::diagnostics::redaction::register_secret;
use crate::terminal_host::host_error::{HostError, HostResult};

pub(super) const ISSUER: &str = "https://auth.openai.com";
pub(super) const RESOURCE: &str = "https://api.openai.com/v1";
const SCOPE: &str = "openid profile email offline_access resource.invoke chatgpt.tokens.use.direct";

pub(super) fn client() -> HostResult<reqwest::Client> {
    reqwest::Client::builder()
        .timeout(std::time::Duration::from_secs(30))
        .redirect(reqwest::redirect::Policy::none())
        .build()
        .map_err(|_| HostError::state("ChatGPT connection could not be created."))
}

fn random_value() -> String {
    URL_SAFE_NO_PAD.encode(rand::random::<[u8; 32]>())
}

pub(super) struct Attempt {
    pub listener: TcpListener,
    pub redirect: String,
    pub state: String,
    pub nonce: String,
    pub verifier: String,
    pub account: Option<Account>,
    pub issued_registration: std::sync::Arc<std::sync::Mutex<Option<String>>>,
}

impl Attempt {
    pub async fn prepare(host_id: &str, account: Option<Account>) -> HostResult<(Self, String)> {
        let listener = TcpListener::bind((std::net::Ipv4Addr::LOCALHOST, 0))
            .await
            .map_err(|_| HostError::state("ChatGPT sign-in callback could not be opened."))?;
        let port = listener
            .local_addr()
            .map_err(|_| HostError::state("ChatGPT callback is unavailable."))?
            .port();
        let attempt = Self {
            listener,
            redirect: format!("http://127.0.0.1:{port}/auth/callback"),
            state: random_value(),
            nonce: random_value(),
            verifier: random_value(),
            account,
            issued_registration: Default::default(),
        };
        let mut url = Url::parse(&format!("{ISSUER}/api/accounts/authorize")).unwrap();
        {
            let mut query = url.query_pairs_mut();
            query.extend_pairs([
                (
                    "client_id",
                    attempt
                        .account
                        .as_ref()
                        .map(|a| a.client_id.as_str())
                        .unwrap_or("dynamic_agent_client"),
                ),
                ("ext_agent_host_id", host_id),
                ("response_type", "code"),
                ("redirect_uri", &attempt.redirect),
                ("scope", SCOPE),
                ("resource", RESOURCE),
                ("state", &attempt.state),
                ("nonce", &attempt.nonce),
                ("code_challenge_method", "S256"),
                (
                    "code_challenge",
                    &URL_SAFE_NO_PAD.encode(Sha256::digest(attempt.verifier.as_bytes())),
                ),
            ]);
            if let Some(account) = &attempt.account {
                if !account.email.is_empty() {
                    query.append_pair("login_hint", &account.email);
                }
                if let Some(tokens) = &account.tokens {
                    query.append_pair("id_token_hint", &tokens.id_token);
                    if !tokens.can_infer() {
                        query.append_pair("prompt", "consent");
                    }
                }
            } else {
                query.append_pair("agent_name_hint", "Alera");
            }
        }
        register_secret(&attempt.state);
        register_secret(&attempt.verifier);
        register_secret(url.as_str());
        Ok((attempt, url.to_string()))
    }

    pub async fn finish(self) -> HostResult<Account> {
        loop {
            let (mut socket, _) = self
                .listener
                .accept()
                .await
                .map_err(|_| HostError::state("ChatGPT sign-in callback failed."))?;
            let mut request = Vec::new();
            let read = async {
                let mut bytes = [0u8; 2048];
                while request.len() < 16 * 1024 {
                    let count = socket.read(&mut bytes).await?;
                    if count == 0 {
                        break;
                    }
                    request.extend_from_slice(&bytes[..count]);
                    if request.windows(4).any(|value| value == b"\r\n\r\n") {
                        break;
                    }
                }
                Ok::<_, std::io::Error>(())
            };
            if !matches!(
                tokio::time::timeout(std::time::Duration::from_secs(2), read).await,
                Ok(Ok(()))
            ) {
                continue;
            }
            let request = String::from_utf8_lossy(&request);
            let mut parts = request
                .lines()
                .next()
                .unwrap_or_default()
                .split_whitespace();
            let method = parts.next();
            let target = parts.next().unwrap_or_default();
            let Ok(url) = Url::parse(&format!("http://127.0.0.1{target}")) else {
                continue;
            };
            if method != Some("GET") || url.path() != "/auth/callback" {
                let _ = socket
                    .write_all(
                        b"HTTP/1.1 404 Not Found\r\nContent-Length: 0\r\nConnection: close\r\n\r\n",
                    )
                    .await;
                continue;
            }
            let callback = validate_callback(
                &url,
                &self.state,
                self.account.as_ref().map(|a| a.client_id.as_str()),
            );
            let message = if callback.is_ok() {
                "Return to Alera to finish connecting ChatGPT."
            } else {
                "ChatGPT sign-in could not be verified. Return to Alera."
            };
            let response = format!("HTTP/1.1 200 OK\r\nContent-Type: text/plain\r\nCache-Control: no-store\r\nConnection: close\r\nContent-Length: {}\r\n\r\n{message}", message.len());
            let _ = socket.write_all(response.as_bytes()).await;
            let (code, client_id) = callback?;
            if self.account.is_none() {
                *self.issued_registration.lock().unwrap() = Some(client_id.clone());
            }
            register_secret(&code);
            let value = token_request(&[
                ("grant_type", "authorization_code"),
                ("client_id", &client_id),
                ("code", &code),
                ("code_verifier", &self.verifier),
                ("redirect_uri", &self.redirect),
                ("resource", RESOURCE),
            ])
            .await?;
            let tokens = parse_tokens(&value, None)?;
            let claims = verify_identity(&tokens.id_token, &client_id, Some(&self.nonce)).await?;
            if self
                .account
                .as_ref()
                .is_some_and(|account| !account.subject.is_empty() && account.subject != claims.sub)
            {
                return Err(HostError::state(
                    "ChatGPT returned a different account. Add it as a new account.",
                ));
            }
            return Ok(Account {
                client_id,
                subject: claims.sub,
                email: claims.email.unwrap_or_default(),
                tokens: Some(tokens),
            });
        }
    }
}

pub(super) fn validate_callback(
    url: &Url,
    state: &str,
    existing: Option<&str>,
) -> HostResult<(String, String)> {
    let mut params = std::collections::HashMap::new();
    for (key, value) in url.query_pairs() {
        if params.insert(key.to_string(), value.to_string()).is_some() {
            return Err(HostError::state(
                "ChatGPT callback has duplicate parameters.",
            ));
        }
    }
    if params.get("state").map(String::as_str) != Some(state) {
        return Err(HostError::state("ChatGPT sign-in state did not match."));
    }
    if params.contains_key("error") {
        return Err(HostError::state("ChatGPT sign-in was declined or failed."));
    }
    let client_id = params
        .get("client_id")
        .map(String::as_str)
        .or(existing)
        .filter(|id| !id.is_empty() && *id != "dynamic_agent_client")
        .ok_or_else(|| HostError::state("ChatGPT registration did not return a client ID."))?;
    if existing.is_some_and(|id| id != client_id) {
        return Err(HostError::state(
            "ChatGPT registration changed during sign-in.",
        ));
    }
    let code = params
        .get("code")
        .filter(|value| !value.is_empty())
        .ok_or_else(|| HostError::state("ChatGPT did not return an authorization code."))?;
    Ok((code.clone(), client_id.to_string()))
}

pub(super) async fn token_request(form: &[(&str, &str)]) -> HostResult<Value> {
    let response = client()?
        .post(format!("{ISSUER}/api/accounts/oauth/token"))
        .form(form)
        .send()
        .await
        .map_err(|_| {
            HostError::state("ChatGPT authentication network request failed. Try again.")
        })?;
    let status = response.status();
    let value: Value = response
        .json()
        .await
        .map_err(|_| HostError::state("ChatGPT returned an invalid token response."))?;
    if !status.is_success() {
        let code = value
            .get("error")
            .and_then(Value::as_str)
            .unwrap_or("authentication_failed");
        // Only expose known codes; a provider response can contain credential material.
        let terminal = matches!(
            code,
            "invalid_grant"
                | "invalid_refresh_token"
                | "token_expired"
                | "refresh_token_expired"
                | "refresh_token_invalidated"
                | "refresh_token_reused"
        );
        return Err(HostError::state(if terminal {
            "ChatGPT session expired. Continue with ChatGPT to sign in again."
        } else {
            "ChatGPT authentication failed. Try again later."
        }));
    }
    Ok(value)
}

pub(super) fn parse_tokens(value: &Value, previous: Option<&Tokens>) -> HostResult<Tokens> {
    let access_token = value
        .get("access_token")
        .and_then(Value::as_str)
        .filter(|s| !s.is_empty())
        .ok_or_else(|| HostError::state("ChatGPT did not return an access token."))?
        .to_string();
    if !value
        .get("token_type")
        .and_then(Value::as_str)
        .is_some_and(|s| s.eq_ignore_ascii_case("bearer"))
    {
        return Err(HostError::state(
            "ChatGPT returned an unsupported token type.",
        ));
    }
    let id_token = value
        .get("id_token")
        .and_then(Value::as_str)
        .map(str::to_string)
        .or_else(|| previous.map(|t| t.id_token.clone()))
        .filter(|s| !s.is_empty())
        .ok_or_else(|| HostError::state("ChatGPT did not return an ID token."))?;
    let expires = value
        .get("expires_in")
        .and_then(Value::as_i64)
        .filter(|v| *v > 0 && *v <= 31_536_000)
        .ok_or_else(|| HostError::state("ChatGPT returned an invalid token expiration."))?;
    let tokens = Tokens {
        access_token,
        id_token,
        refresh_token: value
            .get("refresh_token")
            .and_then(Value::as_str)
            .map(str::to_string)
            .or_else(|| previous.and_then(|t| t.refresh_token.clone())),
        scopes: value
            .get("scope")
            .and_then(Value::as_str)
            .map(|s| s.split_whitespace().map(str::to_string).collect())
            .unwrap_or_else(|| previous.map(|t| t.scopes.clone()).unwrap_or_default()),
        expires_at: chrono::Utc::now().timestamp() + expires,
        identity_pending: false,
    };
    tokens.register_secrets();
    Ok(tokens)
}

#[derive(Clone, Deserialize)]
pub(super) struct Claims {
    pub sub: String,
    pub email: Option<String>,
    pub nonce: Option<String>,
    pub aud: Value,
    pub azp: Option<String>,
    pub iat: i64,
}

pub(super) async fn verify_identity(
    token: &str,
    client_id: &str,
    nonce: Option<&str>,
) -> HostResult<Claims> {
    let response = client()?
        .get(format!("{ISSUER}/.well-known/jwks.json"))
        .send()
        .await
        .map_err(|_| HostError::state("ChatGPT signing keys could not be loaded."))?
        .error_for_status()
        .map_err(|_| HostError::state("ChatGPT signing keys are unavailable."))?;
    let jwks: JwkSet = response
        .json()
        .await
        .map_err(|_| HostError::state("ChatGPT signing keys are invalid."))?;
    validate_identity(token, client_id, nonce, &jwks)
}

pub(super) fn validate_identity(
    token: &str,
    client_id: &str,
    nonce: Option<&str>,
    jwks: &JwkSet,
) -> HostResult<Claims> {
    let invalid = || HostError::state("ChatGPT identity could not be verified.");
    let header = decode_header(token).map_err(|_| invalid())?;
    if header.alg != Algorithm::RS256 {
        return Err(invalid());
    }
    let key = jwks
        .find(header.kid.as_deref().ok_or_else(invalid)?)
        .ok_or_else(invalid)?;
    let key = DecodingKey::from_jwk(key).map_err(|_| invalid())?;
    let mut validation = Validation::new(Algorithm::RS256);
    validation.set_issuer(&[ISSUER]);
    validation.set_audience(&[client_id]);
    validation.set_required_spec_claims(&["sub", "exp", "iat", "iss", "aud"]);
    validation.leeway = 5;
    let claims = decode::<Claims>(token, &key, &validation)
        .map_err(|_| invalid())?
        .claims;
    if claims.iat > chrono::Utc::now().timestamp() + 5
        || claims
            .azp
            .as_deref()
            .is_some_and(|party| party != client_id)
        || claims
            .aud
            .as_array()
            .is_some_and(|audiences| audiences.len() > 1)
            && claims.azp.as_deref() != Some(client_id)
    {
        return Err(invalid());
    }
    if claims.sub.is_empty()
        || nonce.is_some_and(|expected| claims.nonce.as_deref() != Some(expected))
    {
        return Err(invalid());
    }
    Ok(claims)
}
