use crate::wire;
use alera_provider_protocol::{
    CanonicalItemType, ItemStatus, ProviderError, RequestKind, StreamKind, UsageWindowKind,
    UserInputQuestion,
};
use serde_json::{json, Map, Value};

pub(crate) fn normalized_payload(method: &str, params: &Value) -> Result<Value, ProviderError> {
    if is_content_delta(method) {
        let delta = wire::string(params, "delta").ok_or_else(|| {
            ProviderError::Protocol(format!(
                "Codex content delta notification {method} has no string delta"
            ))
        })?;
        return Ok(json!({
            "streamKind": stream_kind(method),
            "delta": delta,
        }));
    }
    if matches!(
        method,
        "item/started"
            | "item/completed"
            | "item/updated"
            | "item/fileChange/patchUpdated"
            | "item/commandExecution/terminalInteraction"
    ) || method.ends_with("/started") && method.starts_with("item/")
        || method.ends_with("/completed") && method.starts_with("item/")
    {
        return normalized_item_payload(params);
    }
    if method == "thread/started" {
        return Ok(normalized_thread_started_payload(params));
    }
    if method == "turn/started" {
        return Ok(normalized_turn_started_payload(params));
    }
    if matches!(
        method,
        "thread/status/changed"
            | "thread/closed"
            | "thread/archived"
            | "thread/deleted"
            | "thread/unarchived"
            | "thread/reverted"
            | "thread/environment/connected"
    ) {
        return normalized_thread_state_payload(method, params);
    }
    if method == "account/rateLimits/updated" {
        return normalized_rate_limits(params);
    }
    if method == "turn/completed" {
        let status = wire::nested_string(params, "turn", "status")
            .or_else(|| wire::string(params, "status"))
            .ok_or_else(|| ProviderError::Protocol("Codex turn.completed has no status".into()))?;
        let state = match status.as_str() {
            "completed" => "completed",
            "failed" => "failed",
            "interrupted" => "interrupted",
            "cancelled" | "canceled" => "cancelled",
            other => {
                return Err(ProviderError::Protocol(format!(
                    "Codex turn.completed has unknown status {other}"
                )))
            }
        };
        let mut payload = json!({ "state": state });
        if let Some(error_message) = params
            .get("turn")
            .and_then(|turn| turn.get("error"))
            .or_else(|| params.get("error"))
            .and_then(|error| error.get("message"))
            .and_then(Value::as_str)
            .filter(|message| !message.trim().is_empty())
        {
            payload["errorMessage"] = Value::String(error_message.to_owned());
        }
        for (field, require_object) in [("usage", false), ("modelUsage", true)] {
            if let Some(value) = turn_or_top_level(params, field)
                .filter(|value| !value.is_null() && (!require_object || value.is_object()))
            {
                payload[field] = value.clone();
            }
        }
        if let Some(stop_reason) = turn_or_top_level(params, "stopReason")
            .and_then(Value::as_str)
            .filter(|reason| !reason.trim().is_empty())
        {
            payload["stopReason"] = Value::String(stop_reason.to_owned());
        }
        if let Some(total_cost) =
            turn_or_top_level(params, "totalCostUsd").filter(|value| value.is_number())
        {
            payload["totalCostUsd"] = total_cost.clone();
        }
        if let Some(usage) = turn_or_top_level(params, "tokenUsage") {
            payload["tokenUsage"] = normalized_token_usage(usage, state == "completed");
        }
        return Ok(payload);
    }
    if method == "turn/aborted" {
        let reason = wire::string(params, "reason")
            .or_else(|| wire::string(params, "message"))
            .or_else(|| wire::nested_string(params, "error", "message"))
            .unwrap_or_else(|| "Codex turn aborted".to_owned());
        let mut payload = json!({ "reason": reason });
        if let Some(usage) = params.get("tokenUsage") {
            payload["tokenUsage"] = normalized_token_usage(usage, false);
        }
        return Ok(payload);
    }
    if method == "thread/environment/disconnected" {
        return normalized_runtime_message(params, Some("Codex environment disconnected"));
    }
    if matches!(method, "error" | "warning" | "guardianWarning") || params.get("error").is_some() {
        return normalized_runtime_message(params, None);
    }
    Ok(params.clone())
}

fn turn_or_top_level<'a>(params: &'a Value, field: &str) -> Option<&'a Value> {
    params
        .get(field)
        .or_else(|| params.get("turn").and_then(|turn| turn.get(field)))
}

fn normalized_thread_started_payload(params: &Value) -> Value {
    let mut payload = Map::new();
    if let Some(provider_thread_id) =
        wire::nested_string(params, "thread", "id").or_else(|| wire::string(params, "threadId"))
    {
        payload.insert("providerThreadId".into(), Value::String(provider_thread_id));
    }
    Value::Object(payload)
}

fn normalized_turn_started_payload(params: &Value) -> Value {
    let mut payload = Map::new();
    if let Some(model) =
        wire::string(params, "model").or_else(|| wire::nested_string(params, "turn", "model"))
    {
        payload.insert("model".into(), Value::String(model));
    }
    if let Some(effort) = wire::string(params, "effort")
        .or_else(|| wire::string(params, "reasoningEffort"))
        .or_else(|| wire::nested_string(params, "turn", "effort"))
        .or_else(|| wire::nested_string(params, "turn", "reasoningEffort"))
    {
        payload.insert("effort".into(), Value::String(effort));
    }
    Value::Object(payload)
}

fn normalized_thread_state_payload(method: &str, params: &Value) -> Result<Value, ProviderError> {
    let state = match method {
        "thread/status/changed" => match params
            .get("status")
            .and_then(|status| status.get("type"))
            .and_then(Value::as_str)
        {
            Some("active") => "active",
            Some("idle" | "notLoaded") => "idle",
            Some("systemError") => "error",
            Some(other) => {
                return Err(ProviderError::Protocol(format!(
                    "Codex thread status has unknown type {other}"
                )))
            }
            None => {
                return Err(ProviderError::Protocol(
                    "Codex thread status has no type".into(),
                ))
            }
        },
        "thread/closed" | "thread/deleted" => "closed",
        "thread/archived" => "archived",
        "thread/unarchived" | "thread/reverted" | "thread/environment/connected" => "active",
        _ => unreachable!("thread state method was checked by caller"),
    };
    let mut payload = json!({ "state": state });
    if method == "thread/status/changed" {
        if let Some(active_flags) = params
            .get("status")
            .and_then(|status| status.get("activeFlags"))
            .filter(|flags| flags.as_array().is_some_and(|flags| !flags.is_empty()))
        {
            payload["detail"] = json!({ "activeFlags": active_flags });
        }
    }
    Ok(payload)
}

fn normalized_token_usage(value: &Value, completed: bool) -> Value {
    if value.get("usageStatus").is_some() || value.get("usageScope").is_some() {
        return value.clone();
    }
    let Some(last) = value.get("last").and_then(Value::as_object) else {
        return json!({
            "usageStatus": "unavailable",
            "usageScope": "main_agent",
            "hasSubagents": false,
        });
    };
    let mut usage = json!({
        "usageStatus": if completed { "complete" } else { "partial" },
        "usageScope": "main_agent",
        "hasSubagents": false,
    });
    for (native, canonical) in [
        ("inputTokens", "inputTokens"),
        ("cachedInputTokens", "cachedInputTokens"),
        ("outputTokens", "outputTokens"),
        ("reasoningOutputTokens", "reasoningTokens"),
    ] {
        if let Some(value) = last.get(native).and_then(Value::as_u64) {
            usage[canonical] = Value::Number(value.into());
        }
    }
    if let Some(value) = last.get("cacheWriteInputTokens").and_then(Value::as_u64) {
        usage["cacheCreationTokens"] = Value::Number(value.into());
    }
    usage
}

pub(crate) fn request_payload(
    kind: RequestKind,
    params: &Value,
    questions: &[UserInputQuestion],
) -> Value {
    let mut payload = Map::new();
    payload.insert(
        "requestType".into(),
        serde_json::to_value(kind).expect("request kind is serializable"),
    );
    if let Some(detail) = wire::string(params, "reason")
        .or_else(|| wire::string(params, "command"))
        .or_else(|| wire::string(params, "message"))
    {
        if !detail.trim().is_empty() {
            payload.insert("detail".into(), Value::String(detail));
        }
    }
    if kind == RequestKind::ToolUserInput {
        payload.insert(
            "questions".into(),
            serde_json::to_value(questions).expect("input questions are serializable"),
        );
    } else {
        payload.insert("args".into(), params.clone());
    }
    Value::Object(payload)
}

fn normalized_item_payload(params: &Value) -> Result<Value, ProviderError> {
    let item = params.get("item").filter(|item| item.is_object());
    let item_type = item
        .and_then(|item| wire::string(item, "type"))
        .or_else(|| wire::string(params, "itemType"))
        .map(|item_type| canonical_item_type(&item_type))
        .unwrap_or(CanonicalItemType::Unknown);
    let status = item
        .and_then(|item| wire::string(item, "status"))
        .or_else(|| wire::string(params, "status"))
        .map(|status| match status.as_str() {
            "inProgress" => Ok(ItemStatus::InProgress),
            "completed" => Ok(ItemStatus::Completed),
            "failed" => Ok(ItemStatus::Failed),
            "declined" => Ok(ItemStatus::Declined),
            other => Err(ProviderError::Protocol(format!(
                "Codex item has unknown status {other}"
            ))),
        })
        .transpose()?;
    let title = item
        .and_then(|item| {
            wire::string(item, "title")
                .or_else(|| wire::string(item, "name"))
                .or_else(|| wire::string(item, "command"))
        })
        .filter(|value| !value.trim().is_empty());
    let detail = item
        .and_then(|item| {
            wire::string(item, "detail")
                .or_else(|| wire::string(item, "reason"))
                .or_else(|| wire::string(item, "aggregatedOutput"))
        })
        .filter(|value| !value.trim().is_empty());
    let mut payload = Map::new();
    payload.insert("itemType".into(), serde_json::to_value(item_type).unwrap());
    if let Some(status) = status {
        payload.insert("status".into(), serde_json::to_value(status).unwrap());
    }
    if let Some(title) = title {
        payload.insert("title".into(), Value::String(title));
    }
    if let Some(detail) = detail {
        payload.insert("detail".into(), Value::String(detail));
    }
    if let Some(item) = item {
        payload.insert("data".into(), item.clone());
    }
    Ok(Value::Object(payload))
}

fn normalized_runtime_message(
    params: &Value,
    fallback: Option<&str>,
) -> Result<Value, ProviderError> {
    let message = wire::string(params, "message")
        .or_else(|| wire::nested_string(params, "error", "message"))
        .or_else(|| {
            params
                .get("error")
                .and_then(Value::as_str)
                .map(ToOwned::to_owned)
        })
        .filter(|message| !message.trim().is_empty())
        .or_else(|| fallback.map(ToOwned::to_owned))
        .ok_or_else(|| ProviderError::Protocol("Codex runtime message has no message".into()))?;
    let mut payload = json!({ "message": message });
    if let Some(error) = params.get("error").filter(|error| !error.is_null()) {
        payload["detail"] = error.clone();
    }
    Ok(payload)
}

pub(crate) fn normalized_rate_limits(params: &Value) -> Result<Value, ProviderError> {
    let snapshot = params.get("rateLimits").unwrap_or(params);
    if wire::string(snapshot, "limitId")
        .filter(|limit_id| limit_id != "codex")
        .is_some()
    {
        return Ok(json!({ "limits": { "windows": [] } }));
    }
    let monthly_plan = matches!(
        wire::string(snapshot, "planType").as_deref(),
        Some("free" | "go")
    );
    let windows = [
        ("primary", "primary", monthly_plan, 5_u64 * 60),
        ("secondary", "secondary", false, 7_u64 * 24 * 60),
    ]
    .into_iter()
    .filter_map(|(key, id, monthly_window, fallback_minutes)| {
        let window = snapshot.get(key)?.as_object()?;
        let used = window.get("usedPercent")?.as_f64()?;
        if !used.is_finite() {
            return None;
        }
        let duration = window
            .get("windowDurationMins")
            .and_then(Value::as_u64)
            .unwrap_or(if monthly_window {
                30_u64 * 24 * 60
            } else {
                fallback_minutes
            });
        let kind = if duration >= 30_u64 * 24 * 60 {
            UsageWindowKind::Monthly
        } else if duration >= 7_u64 * 24 * 60 {
            UsageWindowKind::Weekly
        } else {
            UsageWindowKind::Session
        };
        let label = match kind {
            UsageWindowKind::Monthly => "Monthly",
            UsageWindowKind::Weekly => "Weekly",
            UsageWindowKind::Session => "Session",
            UsageWindowKind::Other => "Other",
        };
        let mut result = json!({
            "id": id,
            "kind": kind,
            "label": label,
            "usedPercent": used.clamp(0.0, 100.0),
            "windowDurationMins": duration,
        });
        if let Some(resets_at) = iso_timestamp(window.get("resetsAt")) {
            result["resetsAt"] = Value::String(resets_at);
        }
        Some(result)
    })
    .collect::<Vec<_>>();
    Ok(json!({ "limits": { "windows": windows } }))
}

fn iso_timestamp(value: Option<&Value>) -> Option<String> {
    if let Some(value) = value.and_then(Value::as_str) {
        return chrono::DateTime::parse_from_rfc3339(value)
            .ok()
            .map(|date| date.to_rfc3339());
    }
    let seconds = value?.as_i64()?;
    chrono::DateTime::<chrono::Utc>::from_timestamp(seconds, 0).map(|date| date.to_rfc3339())
}

fn canonical_item_type(value: &str) -> CanonicalItemType {
    match value {
        "userMessage" => CanonicalItemType::UserMessage,
        "agentMessage" => CanonicalItemType::AssistantMessage,
        "reasoning" => CanonicalItemType::Reasoning,
        "plan" => CanonicalItemType::Plan,
        "commandExecution" => CanonicalItemType::CommandExecution,
        "fileChange" => CanonicalItemType::FileChange,
        "mcpToolCall" => CanonicalItemType::McpToolCall,
        "dynamicToolCall" => CanonicalItemType::DynamicToolCall,
        "collabAgentToolCall" => CanonicalItemType::CollabAgentToolCall,
        "webSearch" => CanonicalItemType::WebSearch,
        "imageView" => CanonicalItemType::ImageView,
        "reviewEntered" => CanonicalItemType::ReviewEntered,
        "reviewExited" => CanonicalItemType::ReviewExited,
        "contextCompaction" => CanonicalItemType::ContextCompaction,
        "error" => CanonicalItemType::Error,
        _ => CanonicalItemType::Unknown,
    }
}

fn is_content_delta(method: &str) -> bool {
    matches!(
        method,
        "item/agentMessage/delta"
            | "item/reasoning/textDelta"
            | "item/reasoning/summaryTextDelta"
            | "item/plan/delta"
            | "command/exec/outputDelta"
            | "process/outputDelta"
            | "item/commandExecution/outputDelta"
            | "item/fileChange/outputDelta"
    )
}

fn stream_kind(method: &str) -> StreamKind {
    match method {
        "item/agentMessage/delta" => StreamKind::AssistantText,
        "item/reasoning/textDelta" => StreamKind::ReasoningText,
        "item/reasoning/summaryTextDelta" => StreamKind::ReasoningSummaryText,
        "item/plan/delta" => StreamKind::PlanText,
        "item/fileChange/outputDelta" => StreamKind::FileChangeOutput,
        _ => StreamKind::CommandOutput,
    }
}
