use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};
use serde_json::{Map, Value};
use uuid::Uuid;

#[derive(Clone, Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct DomainEventBatch {
    pub runtime_id: String,
    pub events: Vec<DomainEventInput>,
}

#[derive(Clone, Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct DomainEventInput {
    pub event_id: String,
    pub seq: i64,
    pub kind: String,
    #[serde(default)]
    pub workspace_id: Option<String>,
    #[serde(default)]
    pub project_id: Option<String>,
    #[serde(default = "empty_object")]
    pub data: Value,
    pub occurred_at: DateTime<Utc>,
}

fn empty_object() -> Value {
    Value::Object(Map::new())
}

#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct DomainEventBatchResponse {
    /// Events stored by this request.
    pub accepted: usize,
    /// Events already stored earlier (same runtime and event id) or repeated in the batch.
    pub duplicate: usize,
    pub active_subscriptions: usize,
    /// Events refused by the payload policy. The rest of the batch is still stored, so
    /// one bad event never blocks the runtime's journal. Omitted when empty.
    #[serde(skip_serializing_if = "Vec::is_empty")]
    pub rejected: Vec<RejectedEvent>,
}

#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct RejectedEvent {
    /// As sent, cut to 64 characters.
    pub event_id: String,
    /// The error code the event would have produced on its own, such as `invalid_event_time`.
    pub code: &'static str,
}

#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct EventSubscriptionCount {
    pub active_subscriptions: usize,
}

#[derive(Clone, Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct CreateWebhookRequest {
    pub url: String,
    pub kinds: Vec<String>,
    #[serde(default)]
    pub runtime_ids: Option<Vec<String>>,
    #[serde(default)]
    pub all_runtimes: bool,
}

#[derive(Clone, Debug, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct WebhookSummary {
    pub id: String,
    pub url: String,
    pub kinds: Vec<String>,
    pub runtime_ids: Vec<String>,
    pub all_runtimes: bool,
    pub status: String,
    pub created_at: DateTime<Utc>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub last_delivery_at: Option<DateTime<Utc>>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub last_error: Option<String>,
}

#[derive(Debug, Serialize)]
pub struct WebhookList {
    pub webhooks: Vec<WebhookSummary>,
}

#[derive(Debug, Serialize)]
pub struct CreatedWebhook {
    pub webhook: WebhookSummary,
    /// The `whsec_` signing secret. Returned only once.
    pub secret: String,
}

#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct TestDelivery {
    pub delivery_id: Uuid,
}

#[derive(Clone, Debug, Deserialize)]
pub struct McpDelivery {
    pub mode: String,
    pub url: String,
    #[serde(default)]
    pub secret: Option<String>,
}

#[derive(Clone, Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct McpSubscribeRequest {
    pub name: String,
    #[serde(default)]
    pub arguments: Map<String, Value>,
    pub delivery: McpDelivery,
    #[serde(default)]
    pub cursor: Option<String>,
    /// Absent or null both get the 24-hour maximum.
    #[serde(default)]
    pub ttl_ms: Option<i64>,
}

#[derive(Clone, Debug, Deserialize)]
pub struct McpUnsubscribeRequest {
    pub name: String,
    #[serde(default)]
    pub arguments: Map<String, Value>,
    pub delivery: McpDelivery,
}

#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct McpSubscribeResponse {
    pub id: String,
    pub refresh_before: String,
    pub cursor: String,
    pub truncated: bool,
}
