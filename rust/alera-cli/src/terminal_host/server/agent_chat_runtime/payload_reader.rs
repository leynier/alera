//! Human-triggered reads of retained native JSON without starting a provider.

use alera_core::runtime::{AgentChatStoreError, AGENT_CHAT_PAGE_MAX_ITEMS};
use serde_json::{json, Value};

use crate::terminal_host::host_error::{HostError, HostResult};

use super::commands::{optional_string, required_string};
use super::AgentChatRuntime;

impl AgentChatRuntime {
    pub(crate) async fn payload(&self, request: &Value) -> HostResult<Value> {
        let chat_id = required_string(request, "chatId")?;
        let item_id = required_string(request, "itemId")?;
        let index = nonnegative_integer(request, "index", 0)?;
        let limit = nonnegative_integer(request, "limit", AGENT_CHAT_PAGE_MAX_ITEMS as u64)?;
        if limit == 0 {
            return Err(HostError::format("limit must be positive"));
        }
        if let Some(workspace_id) = optional_string(request, "workspaceId")? {
            let chat = self
                .store()
                .agent_chat(&chat_id)
                .await
                .map_err(|error| payload_error(&chat_id, error))?
                .ok_or_else(|| HostError::conflict("chatNotFound", "Unknown chat.", json!({})))?;
            if chat.workspace_id != workspace_id {
                return Err(HostError::format("workspaceId does not own the chat"));
            }
        }
        let page = self
            .store()
            .agent_chat_payload(
                &chat_id,
                &item_id,
                index,
                limit.min(AGENT_CHAT_PAGE_MAX_ITEMS as u64) as i64,
            )
            .await
            .map_err(|error| payload_error(&chat_id, error))?;
        serde_json::to_value(page).map_err(|error| HostError::state(error.to_string()))
    }
}

fn nonnegative_integer(request: &Value, field: &str, default: u64) -> HostResult<u64> {
    match request.get(field) {
        None => Ok(default),
        Some(value) => value
            .as_u64()
            .ok_or_else(|| HostError::format(format!("{field} must be a nonnegative integer"))),
    }
}

fn payload_error(chat_id: &str, error: anyhow::Error) -> HostError {
    match error.downcast_ref::<AgentChatStoreError>() {
        Some(AgentChatStoreError::NotFound(id)) => HostError::conflict(
            if id == chat_id {
                "chatNotFound"
            } else {
                "itemNotFound"
            },
            error.to_string(),
            json!({}),
        ),
        Some(AgentChatStoreError::Invalid(_)) => HostError::format(error.to_string()),
        _ => HostError::state(error.to_string()),
    }
}

#[cfg(test)]
#[path = "payload_reader_flush_tests.rs"]
mod flush_tests;

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn payload_cursors_are_typed_nonnegative_integers() {
        assert_eq!(nonnegative_integer(&json!({}), "index", 0).unwrap(), 0);
        assert_eq!(
            nonnegative_integer(&json!({"index": 2}), "index", 0).unwrap(),
            2
        );
        for invalid in [json!(-1), json!("2"), Value::Null, json!(1.5), json!(true)] {
            assert!(nonnegative_integer(&json!({"index": invalid}), "index", 0).is_err());
        }
    }

    #[test]
    fn missing_payloads_keep_typed_not_found_errors() {
        let error = payload_error("chat", AgentChatStoreError::NotFound("chat".into()).into());
        assert_eq!(error.wire_response(1)["errorCode"], "chatNotFound");
        let error = payload_error("chat", AgentChatStoreError::NotFound("head".into()).into());
        assert_eq!(error.wire_response(1)["errorCode"], "itemNotFound");
        assert!(matches!(
            payload_error("chat", AgentChatStoreError::Invalid("broken".into()).into()),
            HostError::Format(_)
        ));
    }
}
