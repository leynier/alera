use alera_provider_protocol::{CanonicalItemType, ItemStatus};
use serde_json::{json, Map, Value};

pub(crate) fn item_payload(
    item_type: CanonicalItemType,
    status: ItemStatus,
    data: Option<Value>,
) -> Value {
    let mut payload = Map::new();
    payload.insert(
        "itemType".into(),
        serde_json::to_value(item_type).expect("item type"),
    );
    payload.insert(
        "status".into(),
        serde_json::to_value(status).expect("item status"),
    );
    if let Some(data) = data {
        payload.insert("data".into(), data);
    }
    Value::Object(payload)
}

pub(crate) fn message_item_id(message: &Value) -> Option<String> {
    message
        .get("message")
        .and_then(|value| value.get("id"))
        .or_else(|| message.get("id"))
        .and_then(Value::as_str)
        .filter(|value| !value.trim().is_empty())
        .map(ToOwned::to_owned)
}

pub(crate) fn message_item_type(message: &Value) -> CanonicalItemType {
    match message
        .get("message")
        .and_then(|value| value.get("role"))
        .and_then(Value::as_str)
    {
        Some("user") => CanonicalItemType::UserMessage,
        Some("assistant") => CanonicalItemType::AssistantMessage,
        Some("system") => CanonicalItemType::ContextCompaction,
        _ => CanonicalItemType::Unknown,
    }
}

pub(crate) fn file_change_title(title: &str) -> bool {
    ["edit", "write", "apply_patch", "patch"]
        .iter()
        .any(|name| title.to_ascii_lowercase().contains(name))
}

pub(crate) fn normalize_usage(value: &Value, complete: bool) -> Value {
    let input = value.get("input").and_then(Value::as_u64);
    let output = value.get("output").and_then(Value::as_u64);
    let mut usage = json!({
        "usageStatus": if complete { "complete" } else { "partial" },
        "usageScope": "main_agent",
        "hasSubagents": false,
    });
    if let Some(value) = input {
        usage["inputTokens"] = Value::Number(value.into());
    }
    if let Some(value) = output {
        usage["outputTokens"] = Value::Number(value.into());
    }
    for (native, canonical) in [
        ("cacheRead", "cachedInputTokens"),
        ("cacheWrite", "cacheCreationTokens"),
    ] {
        if let Some(value) = value.get(native).and_then(Value::as_u64) {
            usage[canonical] = Value::Number(value.into());
        }
    }
    usage
}
