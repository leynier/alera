use anyhow::{anyhow, Context as _, Result};
use chrono::{DateTime, Utc};
use reqwest::{Client, Method, StatusCode};
use serde::{de::DeserializeOwned, Deserialize, Serialize};
use serde_json::Value;

pub(crate) const DEFAULT_CLOUD_BASE_URL: &str = "https://api.alera.build";

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

#[derive(Clone)]
pub(crate) struct CloudAccountClient {
    base_url: String,
    http: Client,
}

impl CloudAccountClient {
    pub(crate) fn new(base_url: String) -> Result<Self> {
        let base_url = base_url.trim_end_matches('/').to_string();
        if !base_url.starts_with("https://")
            && !base_url.starts_with("http://127.0.0.1")
            && !base_url.starts_with("http://localhost")
        {
            return Err(anyhow!(
                "ALERA_CLOUD_URL must use HTTPS or a loopback HTTP origin"
            ));
        }
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

    async fn json<T: DeserializeOwned>(
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
        let body = response.text().await.unwrap_or_default();
        Err(cloud_error(status, &body, path))
    }
}

fn cloud_error(status: StatusCode, body: &str, path: &str) -> anyhow::Error {
    let message = serde_json::from_str::<Value>(body)
        .ok()
        .and_then(|value| {
            value
                .get("error")
                .and_then(|error| error.get("message").or(Some(error)))
                .and_then(Value::as_str)
                .map(str::to_string)
        })
        .filter(|value| !value.trim().is_empty())
        .unwrap_or_else(|| format!("cloud request failed with HTTP {status}"));
    anyhow!("{path}: {message}")
}
