use alera_provider_protocol::*;
use serde_json::Value;

pub(crate) fn map_notification(
    instance: &str,
    thread: &str,
    method: String,
    params: Value,
    raw: RawEvent,
    turn_id: Option<String>,
    item_id: Option<String>,
) -> ProviderEvent {
    let (kind, payload) = match method.as_str() {
        "session/started" => (EventKind::SessionStarted, session_started_payload(&params)),
        "session/statusChanged" => (
            EventKind::ThreadStateChanged,
            session_state_payload(&params),
        ),
        "session/closed" => (EventKind::SessionExited, session_closed_payload(&params)),
        "session/modelChanged" => (EventKind::SessionConfigured, json_config(params.clone())),
        "turn/started" => (EventKind::TurnStarted, json_turn_started(&params)),
        "turn/completed" => (EventKind::TurnCompleted, json_turn_completed(&params)),
        "item/started" => (
            EventKind::ItemStarted,
            item_payload(&params, ItemStatus::InProgress),
        ),
        "item/updated" => (
            EventKind::ItemUpdated,
            item_payload(&params, ItemStatus::InProgress),
        ),
        "item/completed" => (
            EventKind::ItemCompleted,
            item_payload(&params, item_status(&params)),
        ),
        "item/delta" if params.get("delta").and_then(Value::as_str).is_some() => {
            (EventKind::ContentDelta, delta_payload(&params))
        }
        "item/delta" => (EventKind::Unknown("item/delta".into()), params.clone()),
        "approval/resolved" => (
            EventKind::RequestResolved,
            resolved_payload(resolved_request_kind(&params), &params),
        ),
        "userInput/settled" => (
            EventKind::UserInputResolved,
            resolved_payload(RequestKind::ToolUserInput, &params),
        ),
        "view/gap" => (
            EventKind::RuntimeWarning,
            serde_json::json!({"message":"MSP view gap detected","gap":params}),
        ),
        "error" => (EventKind::RuntimeError, runtime_message(&params)),
        _ => (EventKind::Unknown(method), params.clone()),
    };
    event(instance, thread, kind, payload, raw, turn_id, item_id)
}

pub(crate) fn event(
    instance: &str,
    thread: &str,
    kind: EventKind,
    payload: Value,
    raw: RawEvent,
    turn_id: Option<String>,
    item_id: Option<String>,
) -> ProviderEvent {
    let mut event = ProviderEvent::new(
        ProviderKind::Other("muse".into()),
        instance,
        thread,
        kind,
        payload,
        Some(raw),
    );
    event.turn_id = turn_id.clone();
    event.item_id = item_id.clone();
    event.provider_refs = Some(ProviderRefs {
        provider_turn_id: turn_id,
        provider_item_id: item_id,
        provider_request_id: None,
    });
    event
}

fn session_started_payload(params: &Value) -> Value {
    let mut payload = serde_json::json!({"message":"Muse session started"});
    if let Some(session_id) = params
        .get("session")
        .and_then(|session| session.get("sessionId"))
        .and_then(Value::as_str)
    {
        payload["resume"] = Value::String(session_id.to_owned());
    }
    payload
}

fn session_state_payload(params: &Value) -> Value {
    let state = match params.get("status").and_then(Value::as_str) {
        Some("running") => "active",
        Some("idle" | "notLoaded") => "idle",
        Some("closed") => "closed",
        Some("error") => "error",
        Some(other) => other,
        None => "unknown",
    };
    let mut payload = serde_json::json!({"state": state});
    if let Some(attention) = params
        .get("attention")
        .filter(|value| value.as_array().is_some_and(|items| !items.is_empty()))
    {
        payload["detail"] = serde_json::json!({"attention": attention});
    }
    payload
}

fn session_closed_payload(params: &Value) -> Value {
    serde_json::json!({
        "reason": params.get("reason").cloned().unwrap_or_else(|| Value::String("hostShutdown".into())),
        "recoverable": true,
        "exitKind": "orderly",
    })
}

fn json_config(params: Value) -> Value {
    serde_json::json!({"config": params})
}

fn json_turn_started(params: &Value) -> Value {
    let model = params
        .get("modelId")
        .cloned()
        .or_else(|| {
            params
                .get("model")
                .and_then(|model| model.get("modelId"))
                .cloned()
        })
        .or_else(|| params.get("model").cloned())
        .unwrap_or(Value::Null);
    serde_json::json!({
        "model": model,
        "effort": params.get("reasoningEffort").cloned().unwrap_or(Value::Null),
    })
}

fn json_turn_completed(params: &Value) -> Value {
    let terminal = params
        .get("terminal")
        .and_then(Value::as_str)
        .unwrap_or("failed");
    let state = match terminal {
        "completed" => "completed",
        "cancelled" => "cancelled",
        "interrupted" => "interrupted",
        _ => "failed",
    };
    let mut payload = serde_json::json!({"state": state, "terminal": terminal});
    if let Some(reason) = params.get("reason").and_then(Value::as_str).or_else(|| {
        params
            .get("error")
            .and_then(|error| error.get("message"))
            .and_then(Value::as_str)
    }) {
        payload["errorMessage"] = Value::String(reason.into());
    }
    if let Some(stop_reason) = params.get("stopReason").cloned() {
        payload["stopReason"] = stop_reason;
    }
    if let Some(usage) = params.get("usage") {
        payload["tokenUsage"] = normalize_usage(usage);
        payload["usage"] = usage.clone();
    }
    payload
}

fn normalize_usage(usage: &Value) -> Value {
    let mut normalized = serde_json::json!({
        "usageScope": "main_agent",
        "hasSubagents": false,
        "usageStatus": "complete",
    });
    let mut complete = true;
    for (source, target) in [
        ("inputTokens", "inputTokens"),
        ("outputTokens", "outputTokens"),
        ("cachedTokens", "cachedInputTokens"),
        ("reasoningTokens", "reasoningTokens"),
    ] {
        if let Some(value) = usage.get(source).and_then(Value::as_u64) {
            normalized[target] = Value::from(value);
        } else if matches!(source, "inputTokens" | "outputTokens") {
            complete = false;
        }
    }
    if !complete {
        normalized["usageStatus"] = Value::String("partial".into());
    }
    normalized
}

fn item_status(params: &Value) -> ItemStatus {
    match params
        .get("item")
        .and_then(|item| item.get("status"))
        .and_then(Value::as_str)
    {
        Some("failed") | Some("rejected") => ItemStatus::Failed,
        Some("cancelled") | Some("timedOut") => ItemStatus::Declined,
        Some("completed") => ItemStatus::Completed,
        _ => ItemStatus::InProgress,
    }
}

fn item_payload(params: &Value, fallback: ItemStatus) -> Value {
    let item = params
        .get("item")
        .cloned()
        .unwrap_or_else(|| params.clone());
    let kind = item
        .get("kind")
        .and_then(Value::as_str)
        .unwrap_or("unknown");
    let item_type = match kind {
        "userMessage" => CanonicalItemType::UserMessage,
        "agentMessage" => CanonicalItemType::AssistantMessage,
        "reasoning" => CanonicalItemType::Reasoning,
        "toolCall" | "userShell" => CanonicalItemType::CommandExecution,
        "subagent" | "workflow" => CanonicalItemType::CollabAgentToolCall,
        "compaction" => CanonicalItemType::ContextCompaction,
        "webSearch" => CanonicalItemType::WebSearch,
        _ => CanonicalItemType::Unknown,
    };
    serde_json::json!({
        "itemType": item_type,
        "status": fallback,
        "title": item
            .get("tool")
            .and_then(Value::as_str)
            .or_else(|| item.get("kind").and_then(Value::as_str)),
        "detail": item
            .get("text")
            .and_then(Value::as_str)
            .or_else(|| item.get("failureReason").and_then(Value::as_str)),
        "data": item,
    })
}

fn delta_payload(params: &Value) -> Value {
    let field = params
        .get("field")
        .and_then(Value::as_str)
        .unwrap_or("text");
    let stream_kind = match field {
        "summary" => StreamKind::ReasoningSummaryText,
        value if value.starts_with("summary.") => StreamKind::ReasoningSummaryText,
        "output" => StreamKind::CommandOutput,
        _ => StreamKind::AssistantText,
    };
    serde_json::json!({
        "streamKind": stream_kind,
        "delta": params.get("delta").cloned().unwrap_or(Value::String(String::new())),
    })
}

fn resolved_payload(kind: RequestKind, params: &Value) -> Value {
    let id = params
        .get("approvalId")
        .or_else(|| params.get("userInputId"))
        .cloned()
        .unwrap_or(Value::String("unknown".into()));
    serde_json::json!({
        "requestType": kind,
        "requestId": id,
        "decision": params.get("outcome").cloned().unwrap_or(Value::String("resolved".into())),
    })
}

fn resolved_request_kind(params: &Value) -> RequestKind {
    match params
        .get("subject")
        .and_then(|subject| subject.get("kind"))
        .and_then(Value::as_str)
    {
        Some("fileAccess") => RequestKind::FileReadApproval,
        Some("fileChange") => RequestKind::FileChangeApproval,
        _ => RequestKind::CommandExecutionApproval,
    }
}

fn runtime_message(params: &Value) -> Value {
    let message = params
        .get("message")
        .or_else(|| params.get("error"))
        .and_then(Value::as_str)
        .unwrap_or("Muse runtime error");
    serde_json::json!({"message": message})
}

pub(crate) fn question(value: &Value) -> Option<UserInputQuestion> {
    let id = value.get("id").and_then(Value::as_str)?.to_owned();
    let header = value
        .get("header")
        .and_then(Value::as_str)
        .unwrap_or(&id)
        .to_owned();
    let question = value.get("question").and_then(Value::as_str)?.to_owned();
    let options = value
        .get("options")
        .and_then(Value::as_array)
        .into_iter()
        .flatten()
        .filter_map(|option| {
            Some(UserInputOption {
                label: option.get("label")?.as_str()?.into(),
                description: option
                    .get("description")
                    .and_then(Value::as_str)
                    .unwrap_or("")
                    .into(),
                value: None,
            })
        })
        .collect();
    Some(UserInputQuestion {
        id,
        header,
        question,
        options,
        allow_custom_answer: Some(true),
        initial_answer: None,
        multi_select: value
            .get("selection")
            .and_then(|selection| selection.get("mode"))
            .and_then(Value::as_str)
            == Some("multiple"),
    })
}
