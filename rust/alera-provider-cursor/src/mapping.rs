use alera_provider_protocol::{
    CanonicalItemType, ContentDeltaPayload, EventKind, ItemLifecyclePayload, ItemStatus,
    ProviderError, ProviderEvent, ProviderKind, ProviderRefs, RawEvent, StreamKind, TurnStatus,
};
use cursor_agent_sdk::RunStreamMessage;
use serde_json::{json, Value};

const SOURCE: &str = "cursor.sdk.bridge";

#[path = "mapping_tools.rs"]
mod tools;

pub(super) struct MappingContext<'a> {
    provider_instance_id: &'a str,
    thread_id: &'a str,
    turn_id: Option<&'a str>,
    native_run_id: Option<&'a str>,
    native_item_id: Option<&'a str>,
    streamed_assistant: bool,
    raw_payload: &'a Value,
}

pub(crate) fn map_run_message(
    message: &RunStreamMessage,
    provider_instance_id: &str,
    thread_id: &str,
    turn_id: Option<&str>,
    native_run_id: Option<&str>,
    native_item_id: Option<&str>,
    streamed_assistant: bool,
) -> Result<Vec<ProviderEvent>, ProviderError> {
    let raw_payload = serde_json::to_value(message).map_err(|error| {
        ProviderError::Protocol(format!("serialize Cursor stream frame: {error}"))
    })?;
    let mut events = Vec::new();
    let context = MappingContext {
        provider_instance_id,
        thread_id,
        turn_id,
        native_run_id,
        native_item_id,
        streamed_assistant,
        raw_payload: &raw_payload,
    };
    if let Some(update) = &message.interaction_update {
        push_delta(&mut events, &context, update)?;
    }
    if let Some(step) = &message.step {
        let step_payload = step.get("step").cloned().unwrap_or_else(|| step.clone());
        let mut event = event(&context, EventKind::TurnPlanUpdated, step_payload);
        set_message_type(&mut event, "step");
        validate(&mut event)?;
        events.push(event);
    }
    if let Some(sdk) = &message.sdk_message {
        let streamed_assistant_in_frame =
            context.streamed_assistant || events.iter().any(is_assistant_delta);
        map_sdk_message(&mut events, &context, sdk, streamed_assistant_in_frame)?;
    }
    if let Some(result) = &message.result {
        let run_result = result.get("result").unwrap_or(result);
        let status = result
            .get("status")
            .or_else(|| run_result.get("status"))
            .and_then(Value::as_str)
            .map(status_name)
            .unwrap_or_else(|| "finished".into());
        let state = match status.as_str() {
            "finished" | "completed" | "success" => TurnStatus::Completed,
            "cancelled" | "canceled" => TurnStatus::Cancelled,
            "expired" | "interrupted" => TurnStatus::Interrupted,
            _ => TurnStatus::Failed,
        };
        let mut payload = json!({ "state": state });
        if let Some(error) = result
            .get("errorMessage")
            .or_else(|| result.get("error_message"))
            .or_else(|| result.get("message"))
            .or_else(|| result.get("error"))
            .or_else(|| run_result.get("errorMessage"))
            .or_else(|| run_result.get("error_message"))
            .or_else(|| run_result.get("message"))
            .or_else(|| run_result.get("error"))
        {
            if let Some(text) = error.as_str() {
                payload["errorMessage"] = Value::String(text.to_owned());
            } else if let Some(text) = error.get("message").and_then(Value::as_str) {
                payload["errorMessage"] = Value::String(text.to_owned());
            }
        }
        for key in [
            "stopReason",
            "stop_reason",
            "usage",
            "modelUsage",
            "model_usage",
            "totalCostUsd",
            "total_cost_usd",
            "tokenUsage",
            "token_usage",
        ] {
            if let Some(value) = result.get(key).or_else(|| run_result.get(key)) {
                let canonical_key = match key {
                    "stop_reason" => "stopReason",
                    "model_usage" => "modelUsage",
                    "total_cost_usd" => "totalCostUsd",
                    "token_usage" => "tokenUsage",
                    other => other,
                };
                payload[canonical_key] = value.clone();
            }
        }
        if let Some(error_code) = result
            .get("errorCode")
            .or_else(|| result.get("error_code"))
            .and_then(Value::as_str)
        {
            payload["errorCode"] = Value::String(error_code.to_owned());
        }
        if !context.streamed_assistant && !events.iter().any(is_assistant_delta) {
            if let Some(text) = final_result_text(run_result, result) {
                let mut final_event = event(
                    &context,
                    EventKind::ContentDelta,
                    serde_json::to_value(ContentDeltaPayload {
                        stream_kind: StreamKind::AssistantText,
                        delta: text,
                        content_index: None,
                        summary_index: None,
                    })
                    .map_err(|error| ProviderError::Protocol(error.to_string()))?,
                );
                set_message_type(&mut final_event, "result");
                validate(&mut final_event)?;
                events.push(final_event);
            }
        }
        let mut event = event(&context, EventKind::TurnCompleted, payload);
        set_message_type(&mut event, "result");
        validate(&mut event)?;
        events.push(event);
    }
    if message.done.is_some() && message.result.is_none() {
        let mut event = event(
            &context,
            EventKind::TurnCompleted,
            json!({ "state": TurnStatus::Completed }),
        );
        set_message_type(&mut event, "done");
        validate(&mut event)?;
        events.push(event);
    }
    Ok(events)
}

fn map_sdk_message(
    events: &mut Vec<ProviderEvent>,
    context: &MappingContext<'_>,
    sdk: &Value,
    streamed_assistant: bool,
) -> Result<(), ProviderError> {
    let kind = sdk.get("type").and_then(Value::as_str).unwrap_or("unknown");
    let payload = sdk.get("message").cloned().unwrap_or_else(|| sdk.clone());
    match kind {
        "assistant" => {
            if streamed_assistant {
                return Ok(());
            }
            let content = payload.get("content").unwrap_or(&payload);
            for (index, text) in text_blocks(content).into_iter().enumerate() {
                push_text(
                    events,
                    context,
                    StreamKind::AssistantText,
                    text,
                    Some(index as i64),
                    Some(kind),
                )?;
            }
        }
        "thinking" | "reasoning" => {
            let content = payload
                .get("text")
                .or_else(|| payload.get("thinking"))
                .and_then(Value::as_str)
                .unwrap_or_default();
            if !content.is_empty() {
                push_text(
                    events,
                    context,
                    StreamKind::ReasoningText,
                    content.to_owned(),
                    None,
                    Some(kind),
                )?;
            }
        }
        "tool_call" | "tool" => {
            let status = payload
                .get("status")
                .and_then(Value::as_str)
                .map(status_name)
                .unwrap_or_else(|| "running".into());
            let item_status = match status.as_str() {
                "completed" | "success" => ItemStatus::Completed,
                "error" | "failed" => ItemStatus::Failed,
                _ => ItemStatus::InProgress,
            };
            let item_type = tools::tool_item_type(&payload);
            let mut event = event(
                context,
                if item_status == ItemStatus::InProgress {
                    EventKind::ItemStarted
                } else {
                    EventKind::ItemCompleted
                },
                serde_json::to_value(ItemLifecyclePayload {
                    item_type,
                    status: Some(item_status),
                    title: payload
                        .get("args")
                        .and_then(tools::mcp_tool_name)
                        .or_else(|| {
                            payload
                                .get("name")
                                .and_then(Value::as_str)
                                .map(str::to_owned)
                        })
                        .or_else(|| {
                            payload
                                .get("toolName")
                                .and_then(Value::as_str)
                                .map(str::to_owned)
                        }),
                    detail: payload
                        .get("message")
                        .and_then(Value::as_str)
                        .map(str::to_owned),
                    data: Some(payload),
                    agent_id: None,
                    parent_tool_use_id: None,
                })
                .map_err(|error| ProviderError::Protocol(error.to_string()))?,
            );
            set_message_type(&mut event, kind);
            validate(&mut event)?;
            events.push(event);
        }
        "status" => {
            let status = payload
                .get("status")
                .and_then(Value::as_str)
                .map(status_name)
                .unwrap_or_else(|| "unknown".into());
            let kind = if matches!(status.as_str(), "error" | "failed") {
                EventKind::RuntimeError
            } else {
                EventKind::ThreadStateChanged
            };
            let value = if kind == EventKind::RuntimeError {
                json!({ "message": payload.get("message").and_then(Value::as_str).unwrap_or(status.as_str()) })
            } else {
                payload.clone()
            };
            let mut event = event(context, kind, value);
            set_message_type(&mut event, "status");
            validate(&mut event)?;
            events.push(event);
        }
        "system" => {
            let subtype = payload
                .get("subtype")
                .and_then(Value::as_str)
                .unwrap_or("system");
            let kind = if subtype == "init" {
                EventKind::ThreadStarted
            } else {
                EventKind::ThreadStateChanged
            };
            let mut event = event(context, kind, payload);
            set_message_type(&mut event, "system");
            validate(&mut event)?;
            events.push(event);
        }
        _ => {
            let mut event = event(
                context,
                EventKind::ItemUpdated,
                serde_json::to_value(ItemLifecyclePayload {
                    item_type: CanonicalItemType::Unknown,
                    status: None,
                    title: Some(kind.to_owned()),
                    detail: None,
                    data: Some(payload),
                    agent_id: None,
                    parent_tool_use_id: None,
                })
                .map_err(|error| ProviderError::Protocol(error.to_string()))?,
            );
            set_message_type(&mut event, kind);
            validate(&mut event)?;
            events.push(event);
        }
    }
    Ok(())
}

fn push_delta(
    events: &mut Vec<ProviderEvent>,
    context: &MappingContext<'_>,
    update: &Value,
) -> Result<(), ProviderError> {
    let delta_payload = update
        .get("update")
        .filter(|value| value.is_object())
        .unwrap_or(update);
    let native_type = update
        .get("type")
        .or_else(|| delta_payload.get("kind"))
        .and_then(Value::as_str);
    if native_type.is_some_and(|kind| kind.starts_with("tool-call-")) {
        tools::push_tool_lifecycle(
            events,
            context,
            native_type.unwrap_or_default(),
            delta_payload,
        )?;
    }
    let stream_kind = stream_kind_for_update(native_type);
    let text = delta_payload
        .get("delta")
        .or_else(|| update.get("text"))
        .or_else(|| delta_payload.get("text"))
        .or_else(|| delta_payload.get("output"))
        .or_else(|| delta_payload.get("data"))
        .or_else(|| delta_payload.get("stdout"))
        .or_else(|| delta_payload.get("stderr"))
        .or_else(|| delta_payload.get("chunk"))
        .and_then(Value::as_str)
        .unwrap_or_default();
    if !text.is_empty() {
        push_text(
            events,
            context,
            stream_kind,
            text.to_owned(),
            delta_payload
                .get("contentIndex")
                .or_else(|| delta_payload.get("content_index"))
                .and_then(Value::as_i64),
            native_type.or(Some("interaction_update")),
        )?;
    }
    Ok(())
}

fn stream_kind_for_update(native_type: Option<&str>) -> StreamKind {
    match native_type.unwrap_or_default() {
        "text-delta" | "assistant-delta" => StreamKind::AssistantText,
        "thinking-delta" | "reasoning-delta" | "thinking" | "reasoning" => {
            StreamKind::ReasoningText
        }
        "plan-delta" | "plan" => StreamKind::PlanText,
        "shell-output-delta" | "shelloutput" | "shell-output" => StreamKind::CommandOutput,
        _ => StreamKind::Unknown,
    }
}

fn push_text(
    events: &mut Vec<ProviderEvent>,
    context: &MappingContext<'_>,
    stream_kind: StreamKind,
    delta: String,
    content_index: Option<i64>,
    message_type: Option<&str>,
) -> Result<(), ProviderError> {
    let payload = serde_json::to_value(ContentDeltaPayload {
        stream_kind,
        delta,
        content_index,
        summary_index: None,
    })
    .map_err(|error| ProviderError::Protocol(error.to_string()))?;
    let mut event = event(context, EventKind::ContentDelta, payload);
    if let Some(raw) = event.raw.as_mut() {
        raw.message_type = message_type.map(str::to_owned);
    }
    validate(&mut event)?;
    events.push(event);
    Ok(())
}

pub(super) fn event(
    context: &MappingContext<'_>,
    kind: EventKind,
    payload: Value,
) -> ProviderEvent {
    let mut event = ProviderEvent::new(
        ProviderKind::Other("cursor".into()),
        context.provider_instance_id,
        context.thread_id,
        kind,
        payload,
        Some(RawEvent {
            source: SOURCE.into(),
            method: None,
            message_type: None,
            payload: context.raw_payload.clone(),
        }),
    );
    event.turn_id = context.turn_id.map(str::to_owned);
    event.provider_refs = Some(ProviderRefs {
        provider_turn_id: context.native_run_id.map(str::to_owned),
        provider_item_id: context.native_item_id.map(str::to_owned),
        provider_request_id: None,
    });
    event
}

pub(super) fn validate(event: &mut ProviderEvent) -> Result<(), ProviderError> {
    event.validate()
}

pub(super) fn set_message_type(event: &mut ProviderEvent, message_type: &str) {
    if let Some(raw) = event.raw.as_mut() {
        raw.message_type = Some(message_type.to_owned());
    }
}

fn status_name(status: &str) -> String {
    status
        .strip_prefix("RUN_LIFECYCLE_STATUS_")
        .unwrap_or(status)
        .to_ascii_lowercase()
}

fn final_result_text(run_result: &Value, envelope: &Value) -> Option<String> {
    run_result
        .get("result")
        .or_else(|| run_result.get("text"))
        .or_else(|| envelope.get("text"))
        .and_then(Value::as_str)
        .filter(|text| !text.is_empty())
        .map(str::to_owned)
}

fn is_assistant_delta(event: &ProviderEvent) -> bool {
    event.kind == EventKind::ContentDelta
        && event
            .payload
            .get("streamKind")
            .and_then(Value::as_str)
            .is_some_and(|kind| kind.eq_ignore_ascii_case("assistant_text"))
}

fn text_blocks(value: &Value) -> Vec<String> {
    match value {
        Value::String(text) if !text.is_empty() => vec![text.to_owned()],
        Value::Array(values) => values
            .iter()
            .filter_map(|value| {
                value
                    .get("text")
                    .or_else(|| value.get("content"))
                    .and_then(Value::as_str)
                    .filter(|text| !text.is_empty())
                    .map(str::to_owned)
            })
            .collect(),
        Value::Object(_) => value
            .get("text")
            .and_then(Value::as_str)
            .filter(|text| !text.is_empty())
            .map(|text| vec![text.to_owned()])
            .unwrap_or_default(),
        _ => Vec::new(),
    }
}
