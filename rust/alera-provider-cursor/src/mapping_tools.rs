use super::{event, set_message_type, validate, MappingContext};
use alera_provider_protocol::{
    CanonicalItemType, EventKind, ItemLifecyclePayload, ItemStatus, ProviderError, ProviderEvent,
};
use serde_json::Value;

pub(super) fn push_tool_lifecycle(
    events: &mut Vec<ProviderEvent>,
    context: &MappingContext<'_>,
    native_type: &str,
    payload: &Value,
) -> Result<(), ProviderError> {
    let tool = tool_payload(payload);
    let status = payload
        .get("status")
        .or_else(|| payload.get("result").and_then(|value| value.get("status")))
        .and_then(Value::as_str)
        .map(status_name)
        .unwrap_or_else(|| {
            if native_type.ends_with("completed") {
                "completed".into()
            } else {
                "running".into()
            }
        });
    let item_status = match status.as_str() {
        "completed" | "success" => ItemStatus::Completed,
        "error" | "failed" => ItemStatus::Failed,
        _ => ItemStatus::InProgress,
    };
    let kind = if native_type.ends_with("started") {
        EventKind::ItemStarted
    } else if item_status == ItemStatus::Completed || item_status == ItemStatus::Failed {
        EventKind::ItemCompleted
    } else {
        EventKind::ItemUpdated
    };
    let mut event = event(
        context,
        kind,
        serde_json::to_value(ItemLifecyclePayload {
            item_type: tool_item_type(payload),
            status: Some(item_status),
            title: tool
                .get("args")
                .and_then(mcp_tool_name)
                .or_else(|| tool.get("name").and_then(Value::as_str).map(str::to_owned))
                .or_else(|| {
                    tool.get("toolName")
                        .and_then(Value::as_str)
                        .map(str::to_owned)
                }),
            detail: payload
                .get("message")
                .and_then(Value::as_str)
                .map(str::to_owned),
            data: Some(payload.clone()),
            agent_id: None,
            parent_tool_use_id: None,
        })
        .map_err(|error| ProviderError::Protocol(error.to_string()))?,
    );
    set_message_type(&mut event, native_type);
    validate(&mut event)?;
    events.push(event);
    Ok(())
}

pub(super) fn tool_item_type(payload: &Value) -> CanonicalItemType {
    let payload = tool_payload(payload);
    let kind = payload
        .get("type")
        .or_else(|| payload.get("toolType"))
        .or_else(|| payload.get("tool_type"))
        .and_then(Value::as_str)
        .unwrap_or_default();
    if kind.eq_ignore_ascii_case("mcp")
        || payload
            .get("args")
            .and_then(|args| args.get("providerIdentifier"))
            .is_some()
        || payload
            .get("args")
            .and_then(|args| args.get("provider_identifier"))
            .is_some()
    {
        CanonicalItemType::McpToolCall
    } else {
        CanonicalItemType::Unknown
    }
}

fn tool_payload(payload: &Value) -> &Value {
    payload
        .get("toolCall")
        .or_else(|| payload.get("tool_call"))
        .unwrap_or(payload)
}

pub(super) fn mcp_tool_name(args: &Value) -> Option<String> {
    let server = args
        .get("providerIdentifier")
        .or_else(|| args.get("provider_identifier"))
        .and_then(Value::as_str)
        .unwrap_or("mcp");
    let tool = args
        .get("toolName")
        .or_else(|| args.get("tool_name"))
        .and_then(Value::as_str)
        .unwrap_or("unknown");
    (server != "mcp" || tool != "unknown").then(|| format!("mcp__{server}__{tool}"))
}

fn status_name(status: &str) -> String {
    status
        .strip_prefix("RUN_LIFECYCLE_STATUS_")
        .unwrap_or(status)
        .to_ascii_lowercase()
}
