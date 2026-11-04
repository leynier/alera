//! Pi extension UI requests: notifications become notices, and `confirm`,
//! `select`, `input` and `editor` dialogs become runtime requests.

use crate::event_core::{event, unknown};
use crate::payload::{file_change_title, message_item_id};
use crate::provider::{PendingUiRequest, PiProvider};
use crate::rpc;
use alera_agent_transport::JsonTransport;
use alera_provider_protocol::{
    EventKind, Provider, ProviderError, ProviderEvent, ProviderRefs, RequestId, RequestKind,
    RuntimeRequest, UserInputOption, UserInputQuestion,
};
use serde_json::{json, Value};

pub(crate) fn map_extension_request<T: JsonTransport>(
    provider: &mut PiProvider<T>,
    message: Value,
) -> Result<Option<ProviderEvent>, ProviderError> {
    let Some(method) = message.get("method").and_then(Value::as_str) else {
        return Ok(Some(unknown(provider, message, "extension_ui_request")));
    };
    if method == "notify" {
        return Ok(Some(notice(provider, message)));
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
        supports_feedback: false,
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

/// Like T3 Code, an extension notification is a notice rather than a tool
/// call. A blank one has nothing to show and stays a native record.
fn notice<T: JsonTransport>(provider: &PiProvider<T>, message: Value) -> ProviderEvent {
    let Some(text) = message
        .get("message")
        .and_then(Value::as_str)
        .filter(|text| !text.trim().is_empty())
    else {
        return unknown(provider, message, "extension_ui_request");
    };
    let mut payload = json!({ "message": text, "detail": message });
    if let Some(level) = message.get("notifyType").and_then(Value::as_str) {
        payload["notifyType"] = json!(level);
    }
    event(provider, EventKind::RuntimeWarning, payload, &message, None)
}

fn question(native_id: &RequestId, method: &str, message: &Value) -> UserInputQuestion {
    let title = message
        .get("title")
        .and_then(Value::as_str)
        .filter(|value| !value.trim().is_empty())
        .unwrap_or(method);
    // Extensions may send a blank placeholder, which is not a valid question.
    let question_text = ["message", "placeholder"]
        .into_iter()
        .filter_map(|key| message.get(key).and_then(Value::as_str))
        .find(|text| !text.trim().is_empty())
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
