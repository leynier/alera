use agent_client_protocol::AcpRequestId;
use alera_provider_protocol::{
    CanonicalItemType, EventKind, ItemStatus, ProviderSlashCommand, ProviderSlashCommandsUpdate,
    RequestKind, TurnStatus,
};
use serde_json::{json, Value};

pub(crate) fn prompt_matches(
    native: &str,
    prompt_id: Option<&AcpRequestId>,
    prompt_meta_id: Option<&str>,
) -> bool {
    prompt_meta_id == Some(native) || prompt_id.is_some_and(|prompt| prompt.to_string() == native)
}

pub(crate) fn permission_kind(params: &Value) -> RequestKind {
    if matches!(
        params
            .get("toolCall")
            .and_then(|value| value.get("kind"))
            .and_then(Value::as_str),
        Some("execute" | "command")
    ) {
        return RequestKind::CommandExecutionApproval;
    }
    match params
        .get("subject")
        .and_then(|value| value.get("type"))
        .and_then(Value::as_str)
    {
        Some("command") => RequestKind::CommandExecutionApproval,
        Some("tool_call") => RequestKind::DynamicToolCall,
        _ => RequestKind::PermissionApproval,
    }
}

pub(crate) fn logical_request_id(id: &AcpRequestId) -> alera_provider_protocol::RequestId {
    alera_provider_protocol::RequestId::String(format!("acp:{}", id.key()))
}

pub(crate) fn item_id(params: &Value) -> Option<String> {
    params
        .get("toolCallId")
        .or_else(|| {
            params
                .get("subject")
                .and_then(|value| value.get("toolCallId"))
        })
        .and_then(Value::as_str)
        .map(ToOwned::to_owned)
}

pub(crate) fn string(value: Option<&Value>) -> Option<String> {
    value.and_then(Value::as_str).map(ToOwned::to_owned)
}

pub(crate) fn content_text(value: Option<&Value>) -> String {
    match value {
        Some(Value::String(value)) => value.clone(),
        Some(Value::Object(object))
            if object.get("type").and_then(Value::as_str) == Some("text") =>
        {
            object
                .get("text")
                .and_then(Value::as_str)
                .unwrap_or_default()
                .into()
        }
        Some(Value::Array(values)) => values
            .iter()
            .map(|value| content_text(Some(value)))
            .collect(),
        _ => String::new(),
    }
}

pub(crate) fn tool_payload(update: &Value, is_mcp: bool) -> Value {
    let item_type = if is_mcp {
        CanonicalItemType::McpToolCall
    } else {
        match update.get("kind").and_then(Value::as_str) {
            Some("execute") | Some("command") => CanonicalItemType::CommandExecution,
            Some("edit") | Some("delete") | Some("move") => CanonicalItemType::FileChange,
            _ => CanonicalItemType::DynamicToolCall,
        }
    };
    json!({
        "itemType": item_type,
        "status": tool_status(update),
        "title": update.get("title").and_then(Value::as_str),
        "detail": update
            .get("content")
            .and_then(Value::as_str)
            .or_else(|| update.get("detail").and_then(Value::as_str)),
        "data": update,
    })
}

/// The item status of a tool call update. A cancelled call settles as failed,
/// as in T3 Code, so it never stays running after its turn ends.
pub(crate) fn tool_status(update: &Value) -> Option<ItemStatus> {
    let status = update.get("status").and_then(Value::as_str)?;
    Some(match status {
        "completed" => ItemStatus::Completed,
        "failed" | "cancelled" | "canceled" => ItemStatus::Failed,
        "declined" => ItemStatus::Declined,
        _ => ItemStatus::InProgress,
    })
}

/// The event kind of a `tool_call` or `tool_call_update` named `name`: any
/// terminal status completes the item.
pub(crate) fn tool_event_kind(name: &str, update: &Value) -> EventKind {
    match tool_status(update) {
        Some(ItemStatus::Completed | ItemStatus::Failed | ItemStatus::Declined) => {
            EventKind::ItemCompleted
        }
        _ if name == "tool_call" => EventKind::ItemStarted,
        _ => EventKind::ItemUpdated,
    }
}

pub(crate) fn is_mcp_tool_call(value: &Value) -> bool {
    value
        .get("_meta")
        .and_then(|meta| meta.get("is_mcp_tool_call"))
        .and_then(Value::as_bool)
        .unwrap_or(false)
}

pub(crate) fn terminal_state(value: Option<&Value>) -> TurnStatus {
    match value.and_then(Value::as_str) {
        Some("cancelled") | Some("canceled") | Some("interrupted") => TurnStatus::Interrupted,
        Some("error") | Some("failed") => TurnStatus::Failed,
        _ => TurnStatus::Completed,
    }
}

/// The commands of an `available_commands_update`, which replaces the whole
/// list each time it arrives.
pub(crate) fn available_commands(update: &Value) -> ProviderSlashCommandsUpdate {
    let commands = update
        .get("availableCommands")
        .or_else(|| update.get("available_commands"))
        .and_then(Value::as_array)
        .map(Vec::as_slice)
        .unwrap_or_default();
    ProviderSlashCommandsUpdate::new(commands.iter().filter_map(|command| {
        ProviderSlashCommand::from_native(
            command.get("name").and_then(Value::as_str)?,
            command.get("description").and_then(Value::as_str),
            command
                .get("input")
                .and_then(|input| input.get("hint"))
                .and_then(Value::as_str),
        )
    }))
}

#[cfg(test)]
mod permission_tests {
    use super::permission_kind;
    use alera_provider_protocol::RequestKind;
    use serde_json::json;

    #[test]
    fn standard_tool_call_command_kinds_are_command_approvals() {
        for kind in ["execute", "command"] {
            assert_eq!(
                permission_kind(&json!({"toolCall":{"kind":kind}})),
                RequestKind::CommandExecutionApproval
            );
            assert_eq!(
                permission_kind(&json!({"toolCall":{"kind":kind},"subject":{"type":"tool_call"}})),
                RequestKind::CommandExecutionApproval
            );
        }
    }

    #[test]
    fn legacy_subject_and_generic_permissions_keep_their_classification() {
        assert_eq!(
            permission_kind(&json!({"subject":{"type":"command"}})),
            RequestKind::CommandExecutionApproval
        );
        assert_eq!(
            permission_kind(&json!({"subject":{"type":"tool_call"}})),
            RequestKind::DynamicToolCall
        );
        assert_eq!(
            permission_kind(&json!({"toolCall":{"kind":"read"}})),
            RequestKind::PermissionApproval
        );
    }
}

#[cfg(test)]
mod tool_status_tests {
    use super::{tool_event_kind, tool_status};
    use alera_provider_protocol::{EventKind, ItemStatus};
    use serde_json::json;

    #[test]
    fn cancelled_tool_calls_settle_as_failed() {
        for status in ["cancelled", "canceled", "failed"] {
            let update = json!({"status": status});
            assert_eq!(tool_status(&update), Some(ItemStatus::Failed));
            assert_eq!(
                tool_event_kind("tool_call_update", &update),
                EventKind::ItemCompleted
            );
        }
    }

    #[test]
    fn other_statuses_keep_their_meaning() {
        assert_eq!(
            tool_status(&json!({"status":"declined"})),
            Some(ItemStatus::Declined)
        );
        assert_eq!(
            tool_status(&json!({"status":"pending"})),
            Some(ItemStatus::InProgress)
        );
        assert_eq!(tool_status(&json!({})), None);
        assert_eq!(
            tool_event_kind("tool_call", &json!({"status":"pending"})),
            EventKind::ItemStarted
        );
        assert_eq!(
            tool_event_kind("tool_call_update", &json!({"status":"in_progress"})),
            EventKind::ItemUpdated
        );
        assert_eq!(
            tool_event_kind("tool_call", &json!({"status":"declined"})),
            EventKind::ItemCompleted
        );
    }
}
