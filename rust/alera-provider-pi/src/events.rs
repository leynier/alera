use crate::event_core::{event, event_with_item, runtime_error, tool_detail, unknown};
use crate::payload::{
    file_change_title, item_payload, message_item_id, message_item_type, normalize_usage,
};
use crate::provider::{PendingUiRequest, PiProvider};
use crate::rpc;
use alera_agent_transport::JsonTransport;
use alera_provider_protocol::{
    CanonicalItemType, ContentDeltaPayload, EventKind, ItemStatus, Provider, ProviderError,
    ProviderEvent, ProviderRefs, RequestId, RequestKind, RuntimeRequest, StreamKind,
    UserInputOption, UserInputQuestion,
};
use serde_json::{json, Value};

pub(crate) fn map_message<T: JsonTransport>(
    provider: &mut PiProvider<T>,
    message: Value,
) -> Result<Option<ProviderEvent>, ProviderError> {
    let event_type = rpc::record_type(&message).unwrap_or("unknown").to_owned();
    match event_type.as_str() {
        "agent_start" => Ok(Some(turn_started(provider, message))),
        "agent_end" => Ok(Some(unknown(provider, message, "agent_end"))),
        "agent_settled" => Ok(Some(agent_settled(provider, message)?)),
        "message_start" => Ok(Some(message_start(provider, message)?)),
        "message_update" => map_message_update(provider, message),
        "message_end" => Ok(Some(message_end(provider, message)?)),
        "tool_execution_start" => Ok(Some(tool_event(provider, message, EventKind::ItemStarted)?)),
        "tool_execution_update" => Ok(Some(tool_event(provider, message, EventKind::ItemUpdated)?)),
        "tool_execution_end" => Ok(Some(tool_event(
            provider,
            message,
            EventKind::ItemCompleted,
        )?)),
        "extension_ui_request" => map_extension_request(provider, message),
        "extension_error" | "error" => Ok(Some(runtime_error(provider, message)?)),
        "response" => Ok(None),
        _ => Ok(Some(unknown(provider, message, &event_type))),
    }
}

fn turn_started<T: JsonTransport>(provider: &PiProvider<T>, message: Value) -> ProviderEvent {
    let payload = provider
        .session()
        .and_then(|session| session.model.clone())
        .map_or_else(|| json!({}), |model| json!({ "model": model }));
    event(provider, EventKind::TurnStarted, payload, &message, None)
}

pub(crate) fn agent_settled<T: JsonTransport>(
    provider: &mut PiProvider<T>,
    message: Value,
) -> Result<ProviderEvent, ProviderError> {
    let interrupted = message
        .get("aborted")
        .and_then(Value::as_bool)
        .unwrap_or(false)
        || provider.interrupt_requested;
    let failed = message
        .get("stopReason")
        .and_then(Value::as_str)
        .map(|reason| reason == "error")
        .unwrap_or(false)
        || message
            .get("errorMessage")
            .and_then(Value::as_str)
            .is_some_and(|error| !error.trim().is_empty());
    let state = if interrupted {
        "interrupted"
    } else if failed {
        "failed"
    } else {
        "completed"
    };
    let mut payload = json!({ "state": state });
    for key in ["errorMessage", "stopReason"] {
        if let Some(value) = message.get(key).and_then(Value::as_str) {
            if !value.trim().is_empty() {
                payload[key] = Value::String(value.to_owned());
            }
        }
    }
    if let Some(usage) = message.get("usage") {
        payload["tokenUsage"] = normalize_usage(usage, !interrupted && !failed);
    }
    Ok(event(
        provider,
        EventKind::TurnCompleted,
        payload,
        &message,
        None,
    ))
}

fn message_start<T: JsonTransport>(
    provider: &PiProvider<T>,
    message: Value,
) -> Result<ProviderEvent, ProviderError> {
    let native_id = message_item_id(&message).unwrap_or_else(|| "message:unknown".into());
    let item_type = message_item_type(&message);
    let payload = item_payload(item_type, ItemStatus::InProgress, Some(message.clone()));
    Ok(event_with_item(
        provider,
        EventKind::ItemStarted,
        payload,
        &message,
        Some(native_id),
    ))
}

fn map_message_update<T: JsonTransport>(
    provider: &PiProvider<T>,
    message: Value,
) -> Result<Option<ProviderEvent>, ProviderError> {
    let delta = message.get("assistantMessageEvent").unwrap_or(&message);
    let Some(delta_type) = delta.get("type").and_then(Value::as_str) else {
        return Ok(Some(unknown(provider, message, "message_update")));
    };
    if matches!(delta_type, "text_end" | "thinking_end") {
        let text = delta
            .get("content")
            .or_else(|| delta.get("thinking"))
            .and_then(Value::as_str)
            .unwrap_or_default();
        if text.is_empty() {
            return Ok(Some(unknown(provider, message, "message_update")));
        }
        let item_type = if delta_type == "text_end" {
            CanonicalItemType::AssistantMessage
        } else {
            CanonicalItemType::Reasoning
        };
        let payload = item_payload(item_type, ItemStatus::Completed, Some(message.clone()));
        return Ok(Some(event_with_item(
            provider,
            EventKind::ItemUpdated,
            payload,
            &message,
            message_item_id(&message),
        )));
    }
    let stream_kind = match delta_type {
        "text_delta" => StreamKind::AssistantText,
        "thinking_delta" => StreamKind::ReasoningText,
        _ => return Ok(Some(unknown(provider, message, "message_update"))),
    };
    let text = delta
        .get("delta")
        .or_else(|| delta.get("content"))
        .or_else(|| delta.get("thinking"))
        .and_then(Value::as_str)
        .unwrap_or_default();
    if text.is_empty() {
        return Ok(Some(unknown(provider, message, "message_update")));
    }
    let mut payload = serde_json::to_value(ContentDeltaPayload {
        stream_kind,
        delta: text.to_owned(),
        content_index: delta.get("contentIndex").and_then(Value::as_i64),
        summary_index: None,
    })
    .expect("content delta is serializable");
    if let Some(index) = delta.get("summaryIndex").and_then(Value::as_i64) {
        payload["summaryIndex"] = Value::Number(index.into());
    }
    Ok(Some(event(
        provider,
        EventKind::ContentDelta,
        payload,
        &message,
        None,
    )))
}

fn message_end<T: JsonTransport>(
    provider: &PiProvider<T>,
    message: Value,
) -> Result<ProviderEvent, ProviderError> {
    let native_id = message_item_id(&message).unwrap_or_else(|| "message:unknown".into());
    let failed = message
        .get("message")
        .and_then(|value| value.get("stopReason"))
        .and_then(Value::as_str)
        == Some("error");
    let payload = item_payload(
        message_item_type(&message),
        if failed {
            ItemStatus::Failed
        } else {
            ItemStatus::Completed
        },
        Some(message.clone()),
    );
    Ok(event_with_item(
        provider,
        EventKind::ItemCompleted,
        payload,
        &message,
        Some(native_id),
    ))
}

fn tool_event<T: JsonTransport>(
    provider: &PiProvider<T>,
    message: Value,
    kind: EventKind,
) -> Result<ProviderEvent, ProviderError> {
    let native_id = message
        .get("toolCallId")
        .and_then(Value::as_str)
        .or_else(|| message.get("id").and_then(Value::as_str))
        .unwrap_or("tool:unknown")
        .to_owned();
    let tool_name = message
        .get("toolName")
        .and_then(Value::as_str)
        .unwrap_or("tool");
    let item_type = match tool_name {
        "bash" | "powershell" => CanonicalItemType::CommandExecution,
        "edit" | "write" => CanonicalItemType::FileChange,
        _ => CanonicalItemType::DynamicToolCall,
    };
    let status = match kind {
        EventKind::ItemStarted | EventKind::ItemUpdated => ItemStatus::InProgress,
        EventKind::ItemCompleted => {
            if message.get("isError").and_then(Value::as_bool) == Some(true) {
                ItemStatus::Failed
            } else {
                ItemStatus::Completed
            }
        }
        _ => ItemStatus::InProgress,
    };
    let mut payload = item_payload(item_type, status, Some(message.clone()));
    payload["title"] = Value::String(tool_name.to_owned());
    if let Some(detail) = tool_detail(&message) {
        payload["detail"] = Value::String(detail);
    }
    Ok(event_with_item(
        provider,
        kind,
        payload,
        &message,
        Some(native_id),
    ))
}

fn map_extension_request<T: JsonTransport>(
    provider: &mut PiProvider<T>,
    message: Value,
) -> Result<Option<ProviderEvent>, ProviderError> {
    let Some(method) = message.get("method").and_then(Value::as_str) else {
        return Ok(Some(unknown(provider, message, "extension_ui_request")));
    };
    if method == "notify" {
        let text = message
            .get("message")
            .and_then(Value::as_str)
            .unwrap_or_default();
        let payload = json!({
            "itemType": "dynamic_tool",
            "status": "completed",
            "title": "notify",
            "detail": text,
            "data": message,
        });
        return Ok(Some(event(
            provider,
            EventKind::ItemCompleted,
            payload,
            &message,
            None,
        )));
    }
    if !matches!(method, "confirm" | "select" | "input" | "editor") {
        return Ok(Some(unknown(provider, message, "extension_ui_request")));
    }
    if method == "select" && message.get("multiSelect").and_then(Value::as_bool) == Some(true) {
        return Err(ProviderError::Unsupported(
            "Pi multi-select extension prompts are not supported".into(),
        ));
    }
    let native_id = message
        .get("id")
        .ok_or_else(|| ProviderError::Protocol("Pi extension request has no id".into()))
        .and_then(rpc::request_id)?;
    let request_kind = if method == "confirm" {
        if file_change_title(
            message
                .get("title")
                .and_then(Value::as_str)
                .unwrap_or_default(),
        ) {
            RequestKind::FileChangeApproval
        } else {
            RequestKind::CommandExecutionApproval
        }
    } else {
        RequestKind::ToolUserInput
    };
    let questions = if request_kind == RequestKind::ToolUserInput {
        vec![question(&native_id, method, &message)]
    } else {
        Vec::new()
    };
    let thread_id = provider
        .session()
        .map(|session| session.thread_id.clone())
        .unwrap_or_else(|| "pi-pending-thread".into());
    let request = RuntimeRequest {
        request_id: native_id.clone(),
        thread_id: thread_id.clone(),
        turn_id: provider.active_turn_id(),
        item_id: None,
        kind: request_kind,
        questions: questions.clone(),
        payload: message.clone(),
    };
    let event_kind = if request_kind == RequestKind::ToolUserInput {
        EventKind::UserInputRequested
    } else {
        EventKind::RequestOpened
    };
    provider.pending_ui_insert(
        native_id.clone(),
        PendingUiRequest {
            native_id: native_id.clone(),
            method: method.to_owned(),
            request: request.clone(),
            expires_at: message
                .get("timeout")
                .and_then(Value::as_i64)
                .and_then(|timeout| {
                    if timeout == 0 {
                        None
                    } else {
                        Some(
                            std::time::Instant::now()
                                + std::time::Duration::from_millis(timeout.max(0) as u64),
                        )
                    }
                }),
        },
    )?;
    let payload = if request_kind == RequestKind::ToolUserInput {
        json!({
            "requestType": request_kind,
            "questions": questions,
        })
    } else {
        json!({
            "requestType": request_kind,
            "args": message,
        })
    };
    let mut event = event(
        provider,
        event_kind,
        payload,
        &message,
        Some(native_id.to_string()),
    );
    event.request_id = Some(native_id.to_string());
    event.runtime_request = Some(request);
    event.item_id = message_item_id(
        event
            .raw
            .as_ref()
            .map(|raw| &raw.payload)
            .unwrap_or(&Value::Null),
    );
    event.provider_refs = Some(ProviderRefs {
        provider_turn_id: None,
        provider_item_id: event.item_id.clone(),
        provider_request_id: Some(native_id.to_string()),
    });
    Ok(Some(event))
}

fn question(native_id: &RequestId, method: &str, message: &Value) -> UserInputQuestion {
    let title = message
        .get("title")
        .and_then(Value::as_str)
        .filter(|value| !value.trim().is_empty())
        .unwrap_or(method);
    let question_text = message
        .get("message")
        .or_else(|| message.get("placeholder"))
        .and_then(Value::as_str)
        .unwrap_or(title);
    let options = if method == "select" {
        message
            .get("options")
            .and_then(Value::as_array)
            .into_iter()
            .flatten()
            .filter_map(|option| option.as_str())
            .map(|option| UserInputOption {
                label: if option.is_empty() {
                    "Empty value".into()
                } else {
                    option.into()
                },
                description: option.into(),
                value: Some(option.into()),
            })
            .collect()
    } else {
        vec![UserInputOption {
            label: "Submit empty value".into(),
            description: "Send an empty string to the extension.".into(),
            value: Some(String::new()),
        }]
    };
    UserInputQuestion {
        id: native_id.to_string(),
        header: title.into(),
        question: question_text.into(),
        options,
        allow_custom_answer: Some(method != "select"),
        initial_answer: message
            .get("prefill")
            .and_then(Value::as_str)
            .map(ToOwned::to_owned),
        multi_select: false,
    }
}
