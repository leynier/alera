use anyhow::{Context as _, Result};
use chrono::{DateTime, Utc};
use reqwest::{Client, Method, StatusCode};
use serde::{de::DeserializeOwned, Deserialize, Serialize};
use serde_json::Value;
use thiserror::Error;

use crate::terminal_host::alera_account::cloud_base_url::validate_cloud_base_url;

pub(crate) const DEFAULT_CLOUD_BASE_URL: &str = "https://api.alera.build";

#[derive(Debug, Error)]
#[error("{path}: {message}")]
pub(crate) struct CloudRequestError {
    status: StatusCode,
    retry_after: Option<std::time::Duration>,
    code: Option<String>,
    path: String,
    message: String,
}

impl CloudRequestError {
    pub(crate) fn retry_after(&self) -> Option<std::time::Duration> {
        self.retry_after
    }
    pub(crate) fn is_permanent_failure(&self) -> bool {
        self.status.is_client_error()
            && !matches!(
                self.status,
                StatusCode::REQUEST_TIMEOUT | StatusCode::TOO_MANY_REQUESTS
            )
    }
    pub(crate) fn can_refresh_authorization(&self) -> bool {
        self.status == StatusCode::UNAUTHORIZED && self.code.as_deref() != Some("session_revoked")
    }
    pub(crate) fn is_permanent_authorization_failure(&self) -> bool {
        self.status == StatusCode::UNAUTHORIZED || self.status == StatusCode::FORBIDDEN
    }
    pub(crate) fn is_relay_key_rotation_conflict(&self) -> bool {
        self.status == StatusCode::CONFLICT
            && self.code.as_deref() == Some("relay_key_rotation_conflict")
    }
}

#[derive(Debug, Clone, Copy, Deserialize, Serialize)]
#[serde(rename_all = "lowercase")]
pub(crate) enum AuthProvider {
    Google,
    Github,
}

#[derive(Debug, Clone, Deserialize)]
#[serde(rename_all = "camelCase")]
pub(crate) struct AuthTransaction {
    pub(crate) transaction_id: String,
    pub(crate) state: String,
    pub(crate) authorization_url: String,
    pub(crate) expires_at: DateTime<Utc>,
}

#[derive(Debug, Clone, Deserialize, Serialize)]
#[serde(rename_all = "camelCase")]
pub(crate) struct AccountIdentity {
    pub(crate) provider: String,
    pub(crate) email: Option<String>,
    pub(crate) email_verified: bool,
}

#[derive(Debug, Clone, Deserialize, Serialize)]
#[serde(rename_all = "camelCase")]
pub(crate) struct AleraAccount {
    pub(crate) id: String,
    pub(crate) email: String,
    pub(crate) identities: Vec<AccountIdentity>,
}

#[derive(Debug, Clone, Deserialize)]
#[serde(rename_all = "camelCase")]
pub(crate) struct AuthClient {
    pub(crate) id: String,
    pub(crate) kind: String,
}

#[derive(Debug, Clone, Deserialize)]
#[serde(rename_all = "camelCase")]
pub(crate) struct AuthEnvelope {
    pub(crate) access_token: String,
    pub(crate) refresh_token: String,
    pub(crate) token_type: String,
    pub(crate) expires_in: i64,
    pub(crate) account: AleraAccount,
    pub(crate) client: AuthClient,
}

#[derive(Debug, Clone, Deserialize, Serialize)]
#[serde(rename_all = "camelCase")]
pub(crate) struct MobileEnrollment {
    pub(crate) code: String,
    pub(crate) expires_at: DateTime<Utc>,
    pub(crate) runtime_id: String,
    pub(crate) account_id: String,
}

#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
pub(crate) struct PushEventRequest {
    pub(crate) runtime_id: String,
    pub(crate) event_id: String,
    pub(crate) category: String,
    pub(crate) event_type: String,
    pub(crate) title: String,
    pub(crate) body: String,
    pub(crate) data: Value,
    pub(crate) occurred_at: DateTime<Utc>,
}

#[derive(Debug, Clone, Deserialize)]
#[serde(rename_all = "camelCase")]
pub(crate) struct PushEventResponse {
    pub(crate) active_subscriptions: i64,
}

#[derive(Debug, Clone, Deserialize)]
#[serde(rename_all = "camelCase")]
pub(crate) struct RuntimeSubscriptionStatus {
    pub(crate) active_subscriptions: i64,
}

#[derive(Debug, Clone, Deserialize)]
#[serde(rename_all = "camelCase")]
pub(crate) struct RelayIdentityResponse {
    pub(crate) client_id: String,
    pub(crate) client_kind: String,
    pub(crate) public_key: String,
    pub(crate) key_version: i32,
}

#[derive(Debug, Clone, Deserialize)]
#[serde(rename_all = "camelCase")]
pub(crate) struct RelayGrant {
    pub(crate) grant: String,
    pub(crate) relay_url: String,
    pub(crate) expires_in: i64,
    pub(crate) account_id: String,
    pub(crate) runtime_id: String,
    pub(crate) client_id: String,
    pub(crate) client_kind: String,
    pub(crate) client_key_version: i32,
    pub(crate) client_public_key: String,
    pub(crate) runtime_public_key: Option<String>,
}

#[derive(Clone)]
pub(crate) struct CloudAccountClient {
    base_url: String,
    http: Client,
}

impl CloudAccountClient {
    pub(crate) fn new(base_url: String) -> Result<Self> {
        let base_url = base_url.trim_end_matches('/').to_string();
        validate_cloud_base_url(&base_url)?;
        Ok(Self {
            base_url,
            http: Client::builder()
                .timeout(std::time::Duration::from_secs(15))
                .build()?,
        })
    }

    pub(crate) async fn create_transaction(
        &self,
        provider: AuthProvider,
        redirect_uri: &str,
        code_challenge: &str,
        runtime_id: &str,
        device_name: &str,
    ) -> Result<AuthTransaction> {
        self.json(
            Method::POST,
            "/v1/auth/transactions",
            None,
            Some(serde_json::json!({
                "provider": provider,
                "redirectUri": redirect_uri,
                "codeChallenge": code_challenge,
                "clientId": runtime_id,
                "clientKind": "runtime",
                "deviceName": device_name,
            })),
        )
        .await
    }

    pub(crate) async fn exchange(
        &self,
        transaction_id: &str,
        state: &str,
        code: &str,
        verifier: &str,
    ) -> Result<AuthEnvelope> {
        self.json(
            Method::POST,
            "/v1/auth/exchange",
            None,
            Some(serde_json::json!({
                "transactionId": transaction_id,
                "state": state,
                "code": code,
                "codeVerifier": verifier,
            })),
        )
        .await
    }

    pub(crate) async fn create_link_transaction(
        &self,
        access_token: &str,
        provider: AuthProvider,
        redirect_uri: &str,
        code_challenge: &str,
    ) -> Result<AuthTransaction> {
        self.json(
            Method::POST,
            "/v1/account/link",
            Some(access_token),
            Some(serde_json::json!({
                "provider": provider,
                "redirectUri": redirect_uri,
                "codeChallenge": code_challenge,
            })),
        )
        .await
    }

    pub(crate) async fn refresh(&self, refresh_token: &str) -> Result<AuthEnvelope> {
        self.json(
            Method::POST,
            "/v1/auth/refresh",
            None,
            Some(serde_json::json!({ "refreshToken": refresh_token })),
        )
        .await
    }

    pub(crate) async fn revoke(&self, refresh_token: &str) -> Result<()> {
        self.empty(
            Method::POST,
            "/v1/auth/revoke",
            None,
            Some(serde_json::json!({ "refreshToken": refresh_token })),
        )
        .await
    }

    pub(crate) async fn delete_account(&self, access_token: &str) -> Result<()> {
        self.empty(
            Method::DELETE,
            "/v1/account",
            Some(access_token),
            Some(serde_json::json!({ "confirmation": "DELETE" })),
        )
        .await
    }

    pub(crate) async fn transfer_runtime(
        &self,
        access_token: &str,
        runtime_id: &str,
        target_account_id: &str,
    ) -> Result<Value> {
        self.json(
            Method::POST,
            "/v1/runtime/transfer",
            Some(access_token),
            Some(serde_json::json!({
                "runtimeId": runtime_id,
                "targetAccountId": target_account_id,
                "confirmation": runtime_id,
            })),
        )
        .await
    }

    pub(crate) async fn create_mobile_enrollment(
        &self,
        access_token: &str,
        runtime_id: &str,
        device_id: &str,
        device_name: &str,
    ) -> Result<MobileEnrollment> {
        self.json(
            Method::POST,
            "/v1/mobile/enrollments",
            Some(access_token),
            Some(serde_json::json!({
                "runtimeId": runtime_id,
                "deviceId": device_id,
                "deviceName": device_name,
            })),
        )
        .await
    }

    pub(crate) async fn send_event(
        &self,
        access_token: &str,
        event: &PushEventRequest,
    ) -> Result<PushEventResponse> {
        self.json(
            Method::POST,
            "/v1/runtime/events",
            Some(access_token),
            Some(serde_json::to_value(event)?),
        )
        .await
    }

    pub(crate) async fn runtime_subscriptions(
        &self,
        access_token: &str,
    ) -> Result<RuntimeSubscriptionStatus> {
        self.json(
            Method::GET,
            "/v1/runtime/subscriptions",
            Some(access_token),
            None,
        )
        .await
    }

    pub(crate) async fn register_relay_identity(
        &self,
        access_token: &str,
        public_key: &str,
        key_version: i32,
    ) -> Result<RelayIdentityResponse> {
        self.json(
            Method::POST,
            "/v1/relay/identity",
            Some(access_token),
            Some(serde_json::json!({
                "publicKey": public_key,
                "keyVersion": key_version,
            })),
        )
        .await
    }

    pub(crate) async fn relay_grant(
        &self,
        access_token: &str,
        runtime_id: &str,
    ) -> Result<RelayGrant> {
        self.json(
            Method::POST,
            "/v1/relay/grants",
            Some(access_token),
            Some(serde_json::json!({ "runtimeId": runtime_id })),
        )
        .await
    }

    pub(super) async fn json<T: DeserializeOwned>(
        &self,
        method: Method,
        path: &str,
        bearer: Option<&str>,
        body: Option<Value>,
    ) -> Result<T> {
        let response = self.request(method, path, bearer, body).await?;
        response
            .json::<T>()
            .await
            .with_context(|| format!("invalid response from {path}"))
    }

    async fn empty(
        &self,
        method: Method,
        path: &str,
        bearer: Option<&str>,
        body: Option<Value>,
    ) -> Result<()> {
        self.request(method, path, bearer, body).await?;
        Ok(())
    }

    async fn request(
        &self,
        method: Method,
        path: &str,
        bearer: Option<&str>,
        body: Option<Value>,
    ) -> Result<reqwest::Response> {
        let mut request = self
            .http
            .request(method, format!("{}{path}", self.base_url));
        if let Some(token) = bearer {
            request = request.bearer_auth(token);
        }
        if let Some(body) = body {
            request = request.json(&body);
        }
        let response = request.send().await?;
        if response.status().is_success() {
            return Ok(response);
        }
        let status = response.status();
        let retry_after = response
            .headers()
            .get("retry-after")
            .and_then(|value| value.to_str().ok())
            .and_then(parse_retry_after);
        let body = response.text().await.unwrap_or_default();
        let mut error = cloud_error(status, &body, path);
        if let Some(request) = error.downcast_mut::<CloudRequestError>() {
            request.retry_after = retry_after;
        }
        Err(error)
    }
}

fn cloud_error(status: StatusCode, body: &str, path: &str) -> anyhow::Error {
    let parsed = serde_json::from_str::<Value>(body).ok();
    let error = parsed.as_ref().and_then(|value| value.get("error"));
    let code = error
        .and_then(|value| value.get("code"))
        .and_then(Value::as_str)
        .map(str::to_string);
    let message = error
        .and_then(|value| value.get("message").or(Some(value)))
        .and_then(Value::as_str)
        .map(str::to_string)
        .filter(|value| !value.trim().is_empty())
        .unwrap_or_else(|| format!("cloud request failed with HTTP {status}"));
    CloudRequestError {
        status,
        retry_after: None,
        code,
        path: path.to_owned(),
        message,
    }
    .into()
}

fn parse_retry_after(value: &str) -> Option<std::time::Duration> {
    if let Ok(seconds) = value.parse::<u64>() {
        return Some(std::time::Duration::from_secs(seconds));
    }
    DateTime::parse_from_rfc2822(value).ok().map(|date| {
        std::time::Duration::from_secs((date.timestamp() - Utc::now().timestamp()).max(0) as u64)
    })
}

#[cfg(test)]
mod tests {
    use reqwest::StatusCode;

    use super::{cloud_error, CloudRequestError};

    #[test]
    fn relay_key_conflicts_remain_machine_readable() {
        let error = cloud_error(
            StatusCode::CONFLICT,
            r#"{"error":{"code":"relay_key_rotation_conflict","message":"conflict"}}"#,
            "/v1/relay/identity",
        );
        let request = error.downcast_ref::<CloudRequestError>().unwrap();

        assert!(request.is_relay_key_rotation_conflict());
        assert_eq!(error.to_string(), "/v1/relay/identity: conflict");
    }

    #[test]
    fn unrelated_conflicts_do_not_rotate_relay_keys() {
        let error = cloud_error(
            StatusCode::CONFLICT,
            r#"{"error":{"code":"different_conflict","message":"conflict"}}"#,
            "/v1/relay/identity",
        );
        let request = error.downcast_ref::<CloudRequestError>().unwrap();

        assert!(!request.is_relay_key_rotation_conflict());
    }
}
