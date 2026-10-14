use crate::provider::{opencode_kind, OpenCodeProvider};
use crate::request_events::refs;
use alera_provider_protocol::{
    CanonicalItemType, EventKind, ItemLifecyclePayload, ItemStatus, ProviderError, ProviderEvent,
    RawEvent,
};
use opencode_agent_sdk::HttpTransport;
use serde_json::Value;

pub(crate) fn map_tool<T: HttpTransport>(
    provider: &mut OpenCodeProvider<T>,
    event_type: &str,
    props: &Value,
    thread_id: &str,
    turn_id: Option<String>,
    item_id_hint: Option<String>,
    raw: Option<RawEvent>,
) -> Result<ProviderEvent, ProviderError> {
    let item_id = props
        .get("id")
        .and_then(Value::as_str)
        .map(str::to_owned)
        .or(item_id_hint)
        .ok_or_else(|| ProviderError::Protocol("OpenCode tool event has no id".into()))?;
    let name = props
        .get("name")
        .or_else(|| props.get("tool"))
        .and_then(Value::as_str)
        .map(str::to_owned);
    let explicit_server = props
        .get("server")
        .or_else(|| props.get("serverName"))
        .or_else(|| props.get("metadata").and_then(|value| value.get("server")))
        .and_then(Value::as_str);
    let matches_mcp_name = |tool: &str| {
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
    };
    let is_mcp = explicit_server.is_some_and(|server| {
        provider
            .scoped_mcp_servers
            .iter()
            .any(|name| name == server)
    }) || name.as_deref().is_some_and(matches_mcp_name)
        || provider.mcp_tool_ids.contains(&item_id);
    if is_mcp {
        provider.mcp_tool_ids.insert(item_id.clone());
    }
    let item_type = if is_mcp {
        CanonicalItemType::McpToolCall
    } else {
        CanonicalItemType::CommandExecution
    };
    let terminal = matches!(event_type, "session.tool.success" | "session.tool.failed");
    let status = if event_type == "session.tool.success" {
        ItemStatus::Completed
    } else if event_type == "session.tool.failed" {
        ItemStatus::Failed
    } else {
        ItemStatus::InProgress
    };
    let detail = props
        .get("delta")
        .or_else(|| props.get("text"))
        .or_else(|| props.get("error").and_then(|value| value.get("message")))
        .and_then(Value::as_str)
        .map(str::to_owned);
    let payload = serde_json::to_value(ItemLifecyclePayload {
        item_type,
        status: Some(status),
        title: name,
        detail,
        data: Some(props.clone()),
        agent_id: None,
        parent_tool_use_id: props
            .get("assistantMessageID")
            .and_then(Value::as_str)
            .map(str::to_owned),
    })
    .map_err(|error| ProviderError::Protocol(error.to_string()))?;
    let kind = if event_type == "session.tool.input.started" {
        EventKind::ItemStarted
    } else if terminal {
        EventKind::ItemCompleted
    } else {
        EventKind::ItemUpdated
    };
    let mut event = ProviderEvent::new(
        opencode_kind(),
        provider.config.provider_instance_id.clone(),
        thread_id,
        kind,
        payload,
        raw,
    );
    event.turn_id = turn_id.clone();
    event.item_id = Some(item_id.clone());
    event.provider_refs = Some(refs(turn_id, Some(item_id.clone()), None));
    if terminal {
        provider.mcp_tool_ids.remove(&item_id);
    }
    Ok(event)
}
