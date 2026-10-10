//! Who asked an inbox question: the surface of the connection, or the MCP
//! client that a local Alera CLI process names in `externalOrigin`.

use alera_core::runtime::OrchestrationMessage;
use serde_json::{json, Map, Value};

use crate::terminal_host::host_error::{HostError, HostResult};

use super::super::client_delivery::LocalClientRole;
use super::super::{ClientKind, ServerActor};
use super::inbox_error;

/// Longest value kept for each self-asserted origin field.
const ORIGIN_FIELD_MAX_CHARS: usize = 256;
const ORIGIN_FIELDS: &[&str] = &["clientId", "clientName", "grantId"];
/// Retry keys follow the MCP `clientRequestId` bounds.
const REQUEST_KEY_CHARS: std::ops::RangeInclusive<usize> = 8..=128;

impl ServerActor {
    /// The surface a request came from, decided by the connection.
    pub(in crate::terminal_host::server) fn inbox_origin(&self, client_id: u64) -> Value {
        let Some(client) = self.clients.get(&client_id) else {
            return json!({ "surface": "cli" });
        };
        match client.kind {
            ClientKind::Mobile => json!({
                "surface": "mobile",
                "deviceId": client.mobile_device_id,
                "deviceName": client.mobile_device_name,
            }),
            ClientKind::Local if client.local_role == LocalClientRole::App => {
                json!({ "surface": "desktop" })
            }
            ClientKind::Local => json!({ "surface": "cli" }),
        }
    }

    /// The origin recorded with a new question. Only a local connection, the
    /// CLI process an MCP tool runs, may name the MCP client it acts for; a
    /// phone cannot claim to be one.
    pub(in crate::terminal_host::server) fn inbox_ask_origin(
        &self,
        client_id: u64,
        payload: &Value,
    ) -> HostResult<Value> {
        let Some(external) = payload
            .get("externalOrigin")
            .filter(|value| !value.is_null())
        else {
            return Ok(self.inbox_origin(client_id));
        };
        let local = self
            .clients
            .get(&client_id)
            .is_some_and(|client| matches!(client.kind, ClientKind::Local));
        if !local {
            return Err(HostError::conflict(
                "inbox_origin_forbidden",
                "Only a local Alera CLI process may record an MCP client origin.",
                json!({}),
            ));
        }
        external_origin(external)
    }

    /// The first result of an ask retried with the same `requestKey` by the
    /// same origin client, so a retry after a timeout does not ask twice.
    pub(in crate::terminal_host::server) async fn repeated_inbox_ask(
        &self,
        inbox: &str,
        request_key: Option<&str>,
        origin: &Value,
    ) -> HostResult<Option<Value>> {
        let Some(key) = request_key else {
            return Ok(None);
        };
        let client = origin.get("clientId").and_then(Value::as_str);
        let earlier = self
            .runtime_store
            .inbox_question_by_request_key(inbox, key, client)
            .await
            .map_err(inbox_error)?;
        match earlier {
            Some(message) => Ok(Some(
                self.inbox_ask_result(message, origin.clone(), true).await?,
            )),
            None => Ok(None),
        }
    }

    /// `deduplicated` marks a retry that returned the question asked first.
    pub(in crate::terminal_host::server) async fn inbox_ask_result(
        &self,
        message: OrchestrationMessage,
        origin: Value,
        deduplicated: bool,
    ) -> HostResult<Value> {
        Ok(json!({
            "questionId": message.id,
            "threadId": message.thread_id.clone().unwrap_or_else(|| message.id.clone()),
            "recipient": self.inbox_recipient(&message.to_handle),
            "origin": origin,
            "deduplicated": deduplicated,
            "message": message,
            "revision": self.inbox_revision().await?,
        }))
    }
}

/// Normalizes `externalOrigin` to `{surface: "mcp", transport, clientId?,
/// clientName?, grantId?}`, dropping anything else it carries.
pub(in crate::terminal_host::server) fn external_origin(value: &Value) -> HostResult<Value> {
    let invalid = |reason: String| {
        HostError::conflict(
            "inbox_invalid_origin",
            format!("externalOrigin {reason}."),
            json!({}),
        )
    };
    let object = value
        .as_object()
        .ok_or_else(|| invalid("must be an object".into()))?;
    let transport = object
        .get("transport")
        .and_then(Value::as_str)
        .filter(|transport| matches!(*transport, "remote" | "local"))
        .ok_or_else(|| invalid("needs transport remote or local".into()))?;
    let mut origin = Map::new();
    origin.insert("surface".into(), json!("mcp"));
    origin.insert("transport".into(), json!(transport));
    for field in ORIGIN_FIELDS {
        match object.get(*field) {
            None | Some(Value::Null) => {}
            Some(Value::String(text))
                if !text.trim().is_empty() && text.chars().count() <= ORIGIN_FIELD_MAX_CHARS =>
            {
                origin.insert((*field).into(), json!(text.trim()));
            }
            Some(_) => {
                return Err(invalid(format!(
                "{field} must be a non-empty string of at most {ORIGIN_FIELD_MAX_CHARS} characters"
            )))
            }
        }
    }
    Ok(Value::Object(origin))
}

/// The optional `requestKey` of an ask, checked against the retry key bounds.
pub(in crate::terminal_host::server) fn request_key(payload: &Value) -> HostResult<Option<String>> {
    match payload.get("requestKey") {
        None | Some(Value::Null) => Ok(None),
        Some(Value::String(key)) if REQUEST_KEY_CHARS.contains(&key.chars().count()) => {
            Ok(Some(key.clone()))
        }
        Some(_) => Err(HostError::conflict(
            "inbox_invalid_request_key",
            "requestKey must be a string of 8 to 128 characters.",
            json!({}),
        )),
    }
}

#[cfg(test)]
mod tests {
    use serde_json::json;

    use super::{external_origin, request_key};

    #[test]
    fn external_origins_keep_only_the_known_fields() {
        let origin = external_origin(&json!({
            "transport": "remote",
            "clientId": " https://chatgpt.com ",
            "clientName": "ChatGPT",
            "grantId": "g-1",
            "callId": "c-1",
            "surface": "desktop",
        }))
        .unwrap();
        assert_eq!(
            origin,
            json!({
                "surface": "mcp",
                "transport": "remote",
                "clientId": "https://chatgpt.com",
                "clientName": "ChatGPT",
                "grantId": "g-1",
            })
        );
    }

    #[test]
    fn malformed_external_origins_are_refused() {
        for value in [
            json!("ChatGPT"),
            json!({ "clientName": "ChatGPT" }),
            json!({ "transport": "mobile" }),
            json!({ "transport": "local", "clientName": 7 }),
            json!({ "transport": "local", "clientName": " " }),
            json!({ "transport": "local", "clientId": "x".repeat(257) }),
        ] {
            assert!(external_origin(&value).is_err(), "{value}");
        }
    }

    #[test]
    fn request_keys_follow_the_retry_key_bounds() {
        assert_eq!(request_key(&json!({})).unwrap(), None);
        assert_eq!(
            request_key(&json!({ "requestKey": "request-0001" })).unwrap(),
            Some("request-0001".to_string())
        );
        assert!(request_key(&json!({ "requestKey": "short" })).is_err());
        assert!(request_key(&json!({ "requestKey": 12345678 })).is_err());
    }
}
