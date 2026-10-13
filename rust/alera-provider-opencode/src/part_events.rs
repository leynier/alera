use crate::provider::{opencode_kind, OpenCodeProvider};
use crate::request_events::refs;
use alera_provider_protocol::{
    CanonicalItemType, EventKind, ItemLifecyclePayload, ItemStatus, ProviderError, ProviderEvent,
    RawEvent,
};
use opencode_agent_sdk::HttpTransport;
use serde_json::Value;

pub(crate) fn map_part_updated<T: HttpTransport>(
    provider: &OpenCodeProvider<T>,
    props: &Value,
    thread_id: &str,
    turn_id: Option<String>,
    item_id: Option<String>,
    raw: Option<RawEvent>,
) -> Result<ProviderEvent, ProviderError> {
    let part = props.get("part").unwrap_or(props);
    let part_type = part
        .get("type")
        .and_then(Value::as_str)
        .unwrap_or("unknown");
    let is_mcp = part_type == "tool"
        && part
            .get("tool")
            .and_then(Value::as_str)
            .is_some_and(|tool| {
                provider.scoped_mcp_servers.iter().any(|server| {
                    let normalized = server
                        .chars()
                        .map(|character| {
                            if character.is_ascii_alphanumeric() || matches!(character, '_' | '-') {
                                character
                            } else {
                                '_'
                            }
                        })
                        .collect::<String>();
                    tool.starts_with(&format!("{normalized}_"))
                })
            });
    let item_type = match part_type {
        _ if provider.native_parts.is_user_part(props) => CanonicalItemType::UserMessage,
        "text" => CanonicalItemType::AssistantMessage,
        "reasoning" => CanonicalItemType::Reasoning,
        "tool" if is_mcp => CanonicalItemType::McpToolCall,
        "tool" | "step-start" | "step-finish" => CanonicalItemType::CommandExecution,
        "file" => CanonicalItemType::FileChange,
        "compaction" => CanonicalItemType::ContextCompaction,
        _ => CanonicalItemType::Unknown,
    };
    let status = part
        .get("state")
        .and_then(|state| state.get("status"))
        .or_else(|| part.get("status"))
        .and_then(Value::as_str)
        .map(|status| match status {
            "completed" | "done" => ItemStatus::Completed,
            "error" | "failed" => ItemStatus::Failed,
            "declined" => ItemStatus::Declined,
            _ => ItemStatus::InProgress,
        });
    let payload = serde_json::to_value(ItemLifecyclePayload {
        item_type,
        status,
        title: part.get("tool").and_then(Value::as_str).map(str::to_owned),
        detail: part.get("text").and_then(Value::as_str).map(str::to_owned),
        data: Some(part.clone()),
        agent_id: None,
        parent_tool_use_id: part
            .get("callID")
            .and_then(Value::as_str)
            .map(str::to_owned),
    })
    .map_err(|error| ProviderError::Protocol(error.to_string()))?;
    let mut event = ProviderEvent::new(
        opencode_kind(),
        "opencode",
        thread_id,
        if status == Some(ItemStatus::Completed) {
            EventKind::ItemCompleted
        } else {
            EventKind::ItemUpdated
        },
        payload,
        raw,
    );
    event.turn_id = turn_id;
    event.item_id = item_id.clone();
    event.provider_refs = Some(refs(None, item_id, None));
    Ok(event)
}

pub(crate) fn map_message_updated(
    props: &Value,
    thread_id: &str,
    turn_id: Option<String>,
    raw: Option<RawEvent>,
) -> Result<ProviderEvent, ProviderError> {
    let info = props.get("info").unwrap_or(props);
    let role = info
        .get("role")
        .and_then(Value::as_str)
        .unwrap_or("assistant");
    let item_id = info.get("id").and_then(Value::as_str).map(str::to_owned);
    let item_type = if role == "user" {
        CanonicalItemType::UserMessage
    } else {
        CanonicalItemType::AssistantMessage
    };
    let payload = serde_json::to_value(ItemLifecyclePayload {
        item_type,
        status: Some(ItemStatus::Completed),
        title: None,
        detail: None,
        data: Some(info.clone()),
        agent_id: None,
        parent_tool_use_id: None,
    })
    .map_err(|error| ProviderError::Protocol(error.to_string()))?;
    let mut event = ProviderEvent::new(
        opencode_kind(),
        "opencode",
        thread_id,
        EventKind::ItemCompleted,
        payload,
        raw,
    );
    event.turn_id = turn_id;
    event.item_id = item_id.clone();
    event.provider_refs = Some(refs(None, item_id, None));
    Ok(event)
}
