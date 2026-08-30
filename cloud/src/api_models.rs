use std::{fmt, str::FromStr};

use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};
use serde_json::Value;
use uuid::Uuid;

use crate::error::ApiError;

#[derive(Clone, Copy, Debug, Deserialize, Eq, PartialEq, Serialize)]
#[serde(rename_all = "camelCase")]
pub enum ProviderKind {
    Google,
    Github,
}

impl ProviderKind {
    pub fn as_str(self) -> &'static str {
        match self {
            Self::Google => "google",
            Self::Github => "github",
        }
    }
}

impl fmt::Display for ProviderKind {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        formatter.write_str(self.as_str())
    }
}

impl FromStr for ProviderKind {
    type Err = ApiError;

    fn from_str(value: &str) -> Result<Self, Self::Err> {
        match value {
            "google" => Ok(Self::Google),
            "github" => Ok(Self::Github),
            _ => Err(ApiError::bad_request(
                "unsupported_provider",
                "The requested identity provider is not supported.",
            )),
        }
    }
}

#[derive(Clone, Copy, Debug, Deserialize, Eq, PartialEq, Serialize)]
#[serde(rename_all = "camelCase")]
pub enum ClientKind {
    Runtime,
    Mobile,
}

impl ClientKind {
    pub fn as_str(self) -> &'static str {
        match self {
            Self::Runtime => "runtime",
            Self::Mobile => "mobile",
        }
    }

    pub fn scopes(self) -> Vec<String> {
        match self {
            Self::Runtime => vec![
                "account:read".to_owned(),
                "configuration:read".to_owned(),
                "configuration:write".to_owned(),
                "enrollment:write".to_owned(),
                "push:send".to_owned(),
                "runtime:write".to_owned(),
                "relay:identity".to_owned(),
                "relay:grant".to_owned(),
            ],
            Self::Mobile => vec![
                "account:read".to_owned(),
                "configuration:read".to_owned(),
                "configuration:write".to_owned(),
                "push:register".to_owned(),
                "subscription:write".to_owned(),
                "runtime:discover".to_owned(),
                "relay:identity".to_owned(),
                "relay:grant".to_owned(),
            ],
        }
    }
}

impl FromStr for ClientKind {
    type Err = ApiError;

    fn from_str(value: &str) -> Result<Self, Self::Err> {
        match value {
            "runtime" => Ok(Self::Runtime),
            "mobile" => Ok(Self::Mobile),
            _ => Err(ApiError::bad_request(
                "invalid_client_kind",
                "The client kind is invalid.",
            )),
        }
    }
}

#[derive(Clone, Debug, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct AccountSummary {
    pub id: Uuid,
    pub email: String,
    pub identities: Vec<IdentitySummary>,
}

#[derive(Clone, Debug, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct AccountDetail {
    #[serde(flatten)]
    pub account: AccountSummary,
    pub runtimes: Vec<RuntimeSummary>,
    pub mobile_devices: Vec<MobileDeviceSummary>,
    pub quota: QuotaSummary,
}

#[derive(Clone, Debug, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct IdentitySummary {
    pub provider: String,
    pub email: String,
    pub email_verified: bool,
}

#[derive(Clone, Debug, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct RuntimeSummary {
    pub id: String,
    pub name: String,
    pub last_seen_at: DateTime<Utc>,
}

#[derive(Clone, Debug, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct MobileDeviceSummary {
    pub id: String,
    pub name: String,
    pub last_seen_at: DateTime<Utc>,
}

#[derive(Clone, Debug, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct QuotaSummary {
    pub daily_used: i32,
    pub daily_limit: i32,
    pub hourly_limit: i32,
    pub burst_limit: i32,
}

#[derive(Clone, Debug, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct ClientSummary {
    pub id: String,
    pub kind: String,
}

#[derive(Clone, Debug, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct TokenEnvelope {
    pub access_token: String,
    pub refresh_token: String,
    pub token_type: &'static str,
    pub expires_in: i64,
    pub account: AccountSummary,
    pub client: ClientSummary,
}

#[derive(Clone, Debug, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct MobileEnrollmentTokenResponse {
    pub runtime_id: String,
    #[serde(flatten)]
    pub tokens: TokenEnvelope,
}

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct CreateAuthTransactionRequest {
    pub provider: ProviderKind,
    pub redirect_uri: String,
    pub code_challenge: String,
    pub client_id: String,
    pub client_kind: ClientKind,
    pub device_name: String,
}

#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct AuthTransactionResponse {
    pub transaction_id: Uuid,
    pub state: String,
    pub authorization_url: String,
    pub expires_at: DateTime<Utc>,
}

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct ExchangeAuthRequest {
    pub transaction_id: Uuid,
    pub state: String,
    pub code: String,
    pub code_verifier: String,
}

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct RefreshRequest {
    pub refresh_token: String,
}

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct LinkAccountRequest {
    pub provider: ProviderKind,
    pub redirect_uri: String,
    pub code_challenge: String,
}

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct CreateEnrollmentRequest {
    pub runtime_id: String,
    pub device_id: String,
    pub device_name: String,
}

#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct EnrollmentResponse {
    pub code: String,
    pub expires_at: DateTime<Utc>,
    pub runtime_id: String,
    pub account_id: Uuid,
}

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct RedeemEnrollmentRequest {
    pub code: String,
    pub device_id: String,
    pub device_name: String,
}

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct PushTokenRequest {
    pub token: String,
    pub platform: MobilePlatform,
}

#[derive(Clone, Copy, Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
pub enum MobilePlatform {
    Android,
    Ios,
}

impl MobilePlatform {
    pub fn as_str(self) -> &'static str {
        match self {
            Self::Android => "android",
            Self::Ios => "ios",
        }
    }
}

#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct PushTokenResponse {
    pub registered_at: DateTime<Utc>,
}

#[derive(Clone, Debug, Deserialize, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct SubscriptionCategories {
    pub attention: bool,
    pub done: bool,
    pub terminal_exit: bool,
}

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct UpsertSubscriptionRequest {
    pub categories: SubscriptionCategories,
}

#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct SubscriptionResponse {
    pub runtime_id: String,
    pub categories: SubscriptionCategories,
    pub updated_at: DateTime<Utc>,
}

#[derive(Clone, Debug, Deserialize, Eq, PartialEq, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct RegisterRelayIdentityRequest {
    pub public_key: String,
    pub key_version: i32,
}

#[derive(Clone, Debug, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct RelayIdentityResponse {
    pub client_id: String,
    pub client_kind: String,
    pub public_key: String,
    pub key_version: i32,
}

#[derive(Clone, Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct RelayGrantRequest {
    pub runtime_id: String,
}

#[derive(Clone, Debug, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct RelayGrantResponse {
    pub grant: String,
    pub relay_url: String,
    pub expires_in: i64,
    pub account_id: Uuid,
    pub runtime_id: String,
    pub client_id: String,
    pub client_kind: String,
    pub client_key_version: i32,
    pub client_public_key: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub runtime_public_key: Option<String>,
}

#[derive(Clone, Debug, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct RuntimeRelaySummary {
    pub id: String,
    pub name: String,
    pub last_seen_at: DateTime<Utc>,
    pub relay_public_key: String,
    pub relay_key_version: i32,
}

#[derive(Clone, Debug, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct RuntimeDiscoveryResponse {
    pub runtimes: Vec<RuntimeRelaySummary>,
}

#[derive(Clone, Copy, Debug, Deserialize, Eq, PartialEq)]
#[serde(rename_all = "camelCase")]
pub enum PushCategory {
    Attention,
    Done,
    TerminalExit,
}

impl PushCategory {
    pub fn as_str(self) -> &'static str {
        match self {
            Self::Attention => "attention",
            Self::Done => "done",
            Self::TerminalExit => "terminalExit",
        }
    }
}

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct RuntimeEventRequest {
    pub runtime_id: String,
    pub event_id: String,
    pub category: PushCategory,
    pub event_type: String,
    pub title: String,
    pub body: String,
    #[serde(default)]
    pub data: Value,
    pub occurred_at: DateTime<Utc>,
}

#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct RuntimeEventResponse {
    pub accepted: bool,
    pub duplicate: bool,
    pub deliveries_queued: usize,
    pub active_subscriptions: usize,
}

#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct RuntimeSubscriptionStatus {
    pub active_subscriptions: usize,
}

#[derive(Debug, Deserialize)]
pub struct DeleteAccountRequest {
    pub confirmation: String,
}

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct TransferRuntimeRequest {
    pub runtime_id: String,
    pub target_account_id: Uuid,
    pub confirmation: String,
}

#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct TransferRuntimeResponse {
    pub runtime_id: String,
    pub previous_account_id: Uuid,
    pub account_id: Uuid,
    pub reauthentication_required: bool,
}
