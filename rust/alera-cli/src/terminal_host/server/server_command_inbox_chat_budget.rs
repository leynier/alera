use serde_json::Value;

use super::{serialized_bytes, string_bytes, value_bytes};

/// Returns the command-inbox budget for agent-chat runtime events.
pub(super) fn runtime_event_bytes(
    event: &crate::terminal_host::server::agent_chat_runtime::events::ChatRuntimeEvent,
) -> usize {
    use crate::terminal_host::server::agent_chat_runtime::events::ChatRuntimeEvent;

    match event {
        ChatRuntimeEvent::Changed {
            chat_id,
            workspace_id,
            delta,
            ..
        } => string_bytes(chat_id) + string_bytes(workspace_id) + value_bytes(delta),
        ChatRuntimeEvent::ChatsChanged { workspace_id } => workspace_id
            .as_deref()
            .map(string_bytes)
            .unwrap_or_default(),
        ChatRuntimeEvent::TabsChanged { workspace_id } => string_bytes(workspace_id),
    }
}

pub(super) fn string_list_bytes(values: &[String]) -> usize {
    values.iter().map(|value| string_bytes(value)).sum()
}

pub(super) fn bool_result_bytes(result: &Result<bool, String>) -> usize {
    match result {
        Ok(value) => serialized_bytes(value),
        Err(error) => string_bytes(error),
    }
}

pub(super) fn value_result_bytes(result: &Result<Value, String>) -> usize {
    match result {
        Ok(value) => value_bytes(value),
        Err(error) => string_bytes(error),
    }
}
