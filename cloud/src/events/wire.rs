//! The webhook wire format shared by event deliveries and verification challenges.

use chrono::{DateTime, SecondsFormat, Utc};
use serde_json::{Map, Value};

use super::secrets::signature_header;

/// The webhook body: `{ eventId, name, timestamp, data, cursor }`.
pub fn event_body(
    event_id: &str,
    kind: &str,
    occurred_at: DateTime<Utc>,
    envelope: (&str, Option<&str>, Option<&str>, i64),
    data: &Value,
    cursor: &str,
) -> Value {
    let (runtime_id, workspace_id, project_id, seq) = envelope;
    let mut payload = Map::new();
    if let Some(object) = data.as_object() {
        payload.extend(object.clone());
    }
    payload.insert("runtimeId".to_owned(), Value::from(runtime_id));
    if let Some(workspace_id) = workspace_id {
        payload.insert("workspaceId".to_owned(), Value::from(workspace_id));
    }
    if let Some(project_id) = project_id {
        payload.insert("projectId".to_owned(), Value::from(project_id));
    }
    payload.insert("seq".to_owned(), Value::from(seq));
    serde_json::json!({
        "eventId": event_id,
        "name": kind,
        "timestamp": occurred_at.to_rfc3339_opts(SecondsFormat::Millis, true),
        "data": payload,
        "cursor": cursor,
    })
}

/// Signed request headers for one attempt; each attempt gets a new timestamp.
pub fn signed_headers(
    message_id: &str,
    subscription_header: (&str, &str),
    keys: &[Vec<u8>],
    body: &[u8],
) -> Vec<(String, String)> {
    let timestamp = Utc::now().timestamp();
    vec![
        ("content-type".to_owned(), "application/json".to_owned()),
        ("user-agent".to_owned(), "Alera-Webhooks/1".to_owned()),
        ("webhook-id".to_owned(), message_id.to_owned()),
        ("webhook-timestamp".to_owned(), timestamp.to_string()),
        (
            "webhook-signature".to_owned(),
            signature_header(keys, message_id, timestamp, body),
        ),
        (
            subscription_header.0.to_owned(),
            subscription_header.1.to_owned(),
        ),
    ]
}
