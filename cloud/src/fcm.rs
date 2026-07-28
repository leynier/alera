use std::{collections::BTreeMap, sync::Arc, time::Duration};

use async_trait::async_trait;
use reqwest::{Client, StatusCode};
use serde::{Deserialize, Serialize};
use thiserror::Error;

use crate::google_credentials::GoogleAccessTokenProvider;

const MAX_SEND_ATTEMPTS: i32 = 3;
const RETRY_DELAYS: [Duration; 2] = [Duration::from_millis(100), Duration::from_millis(300)];

#[derive(Clone, Debug)]
pub struct FcmMessage {
    pub token: String,
    pub title: String,
    pub body: String,
    pub data: BTreeMap<String, String>,
    pub channel_id: String,
}

#[derive(Clone, Debug)]
pub struct FcmReceipt {
    pub message_id: String,
}

#[derive(Debug, Error)]
pub enum FcmError {
    #[error("FCM registration token is unregistered")]
    Unregistered,
    #[error("FCM rejected the message: {0}")]
    InvalidArgument(String),
    #[error("FCM rate limited the project")]
    RateLimited,
    #[error("FCM authorization failed")]
    Unauthorized,
    #[error("FCM is temporarily unavailable: {0}")]
    Transient(String),
    #[error("FCM delivery is disabled")]
    Disabled,
}

impl FcmError {
    pub fn code(&self) -> &'static str {
        match self {
            Self::Unregistered => "unregistered",
            Self::InvalidArgument(_) => "invalid_argument",
            Self::RateLimited => "rate_limited",
            Self::Unauthorized => "unauthorized",
            Self::Transient(_) => "transient",
            Self::Disabled => "disabled",
        }
    }

    fn retryable(&self) -> bool {
        matches!(self, Self::RateLimited | Self::Transient(_))
    }
}

#[async_trait]
pub trait FcmSender: Send + Sync {
    async fn send(&self, message: FcmMessage) -> Result<FcmReceipt, FcmError>;
}

pub async fn send_with_retry(
    sender: &dyn FcmSender,
    message: FcmMessage,
) -> (i32, Result<FcmReceipt, FcmError>) {
    let mut attempt = 1_i32;
    loop {
        let result = sender.send(message.clone()).await;
        let should_retry =
            result.as_ref().err().is_some_and(FcmError::retryable) && attempt < MAX_SEND_ATTEMPTS;
        if !should_retry {
            return (attempt, result);
        }
        let delay = RETRY_DELAYS
            .get((attempt - 1) as usize)
            .copied()
            .unwrap_or(Duration::ZERO);
        tokio::time::sleep(delay).await;
        attempt += 1;
    }
}

pub struct HttpFcmSender {
    client: Client,
    endpoint: String,
    token_provider: Arc<dyn GoogleAccessTokenProvider>,
}

impl HttpFcmSender {
    pub fn new(
        project_id: &str,
        token_provider: Arc<dyn GoogleAccessTokenProvider>,
        timeout: Duration,
    ) -> anyhow::Result<Self> {
        if project_id.is_empty()
            || !project_id
                .bytes()
                .all(|byte| byte.is_ascii_alphanumeric() || byte == b'-')
        {
            anyhow::bail!("invalid FCM project id");
        }
        Ok(Self {
            client: Client::builder().timeout(timeout).build()?,
            endpoint: format!("https://fcm.googleapis.com/v1/projects/{project_id}/messages:send"),
            token_provider,
        })
    }
}

#[async_trait]
impl FcmSender for HttpFcmSender {
    async fn send(&self, message: FcmMessage) -> Result<FcmReceipt, FcmError> {
        let bearer = self
            .token_provider
            .access_token()
            .await
            .map_err(|error| FcmError::Transient(error.to_string()))?;
        let request = FcmRequest {
            message: FcmWireMessage {
                token: message.token,
                notification: FcmNotification {
                    title: message.title,
                    body: message.body,
                },
                data: message.data,
                android: AndroidConfig {
                    priority: "HIGH",
                    notification: AndroidNotification {
                        channel_id: message.channel_id,
                    },
                },
                apns: ApnsConfig {
                    payload: ApnsPayload {
                        aps: Aps { sound: "default" },
                    },
                },
            },
        };
        let response = self
            .client
            .post(&self.endpoint)
            .bearer_auth(bearer)
            .json(&request)
            .send()
            .await
            .map_err(|error| FcmError::Transient(error.to_string()))?;
        if response.status().is_success() {
            let receipt = response
                .json::<FcmResponse>()
                .await
                .map_err(|error| FcmError::Transient(error.to_string()))?;
            return Ok(FcmReceipt {
                message_id: receipt.name,
            });
        }

        let status = response.status();
        let body = response
            .text()
            .await
            .unwrap_or_else(|_| "FCM response body unavailable".to_owned());
        Err(map_fcm_error(status, &body))
    }
}

pub struct DisabledFcmSender;

#[async_trait]
impl FcmSender for DisabledFcmSender {
    async fn send(&self, _message: FcmMessage) -> Result<FcmReceipt, FcmError> {
        Err(FcmError::Disabled)
    }
}

#[derive(Serialize)]
struct FcmRequest {
    message: FcmWireMessage,
}

#[derive(Serialize)]
struct FcmWireMessage {
    token: String,
    notification: FcmNotification,
    data: BTreeMap<String, String>,
    android: AndroidConfig,
    apns: ApnsConfig,
}

#[derive(Serialize)]
struct FcmNotification {
    title: String,
    body: String,
}

#[derive(Serialize)]
struct AndroidConfig {
    priority: &'static str,
    notification: AndroidNotification,
}

#[derive(Serialize)]
struct AndroidNotification {
    channel_id: String,
}

#[derive(Serialize)]
struct ApnsConfig {
    payload: ApnsPayload,
}

#[derive(Serialize)]
struct ApnsPayload {
    aps: Aps,
}

#[derive(Serialize)]
struct Aps {
    sound: &'static str,
}

#[derive(Deserialize)]
struct FcmResponse {
    name: String,
}

fn map_fcm_error(status: StatusCode, body: &str) -> FcmError {
    let normalized = body.to_ascii_uppercase();
    if normalized.contains("UNREGISTERED") {
        FcmError::Unregistered
    } else if status == StatusCode::TOO_MANY_REQUESTS {
        FcmError::RateLimited
    } else if matches!(status, StatusCode::UNAUTHORIZED | StatusCode::FORBIDDEN) {
        FcmError::Unauthorized
    } else if normalized.contains("INVALID_ARGUMENT") || status == StatusCode::BAD_REQUEST {
        FcmError::InvalidArgument(safe_provider_message(body))
    } else {
        FcmError::Transient(format!("FCM returned HTTP {status}"))
    }
}

fn safe_provider_message(body: &str) -> String {
    serde_json::from_str::<serde_json::Value>(body)
        .ok()
        .and_then(|value| {
            value
                .get("error")
                .and_then(|error| error.get("message"))
                .and_then(|message| message.as_str())
                .map(ToOwned::to_owned)
        })
        .filter(|value| value.len() <= 300)
        .unwrap_or_else(|| "FCM rejected the message payload".to_owned())
}

#[cfg(test)]
mod tests {
    use std::sync::atomic::{AtomicUsize, Ordering};

    use async_trait::async_trait;
    use reqwest::StatusCode;

    use super::{map_fcm_error, send_with_retry, FcmError, FcmMessage, FcmReceipt, FcmSender};

    struct TestSender {
        calls: AtomicUsize,
        transient_failures: usize,
        permanent: bool,
    }

    #[async_trait]
    impl FcmSender for TestSender {
        async fn send(&self, _message: FcmMessage) -> Result<FcmReceipt, FcmError> {
            let call = self.calls.fetch_add(1, Ordering::SeqCst);
            if self.permanent {
                return Err(FcmError::InvalidArgument("invalid".to_owned()));
            }
            if call < self.transient_failures {
                return Err(FcmError::Transient("temporary".to_owned()));
            }
            Ok(FcmReceipt {
                message_id: "message-1".to_owned(),
            })
        }
    }

    #[test]
    fn maps_unregistered_before_generic_invalid_argument() {
        let error = map_fcm_error(
            StatusCode::BAD_REQUEST,
            r#"{"error":{"status":"INVALID_ARGUMENT","details":[{"errorCode":"UNREGISTERED"}]}}"#,
        );
        assert!(matches!(error, FcmError::Unregistered));
    }

    #[test]
    fn maps_rate_limit_and_transient_failures() {
        assert!(matches!(
            map_fcm_error(StatusCode::TOO_MANY_REQUESTS, "{}"),
            FcmError::RateLimited
        ));
        assert!(matches!(
            map_fcm_error(StatusCode::SERVICE_UNAVAILABLE, "{}"),
            FcmError::Transient(_)
        ));
    }

    #[tokio::test]
    async fn retries_transient_failures_up_to_three_attempts() {
        let sender = TestSender {
            calls: AtomicUsize::new(0),
            transient_failures: 2,
            permanent: false,
        };
        let (attempts, result) = send_with_retry(&sender, message()).await;
        assert_eq!(attempts, 3);
        assert!(result.is_ok());
        assert_eq!(sender.calls.load(Ordering::SeqCst), 3);
    }

    #[tokio::test]
    async fn does_not_retry_permanent_failures() {
        let sender = TestSender {
            calls: AtomicUsize::new(0),
            transient_failures: 0,
            permanent: true,
        };
        let (attempts, result) = send_with_retry(&sender, message()).await;
        assert_eq!(attempts, 1);
        assert!(matches!(result, Err(FcmError::InvalidArgument(_))));
        assert_eq!(sender.calls.load(Ordering::SeqCst), 1);
    }

    fn message() -> FcmMessage {
        FcmMessage {
            token: "token".to_owned(),
            title: "Title".to_owned(),
            body: "Body".to_owned(),
            data: Default::default(),
            channel_id: "channel".to_owned(),
        }
    }
}
