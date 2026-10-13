use crate::event_mapping::{event, map_notification, question};
use alera_provider_protocol::*;
use muse_agent_sdk::MuseFrame;
use serde_json::{Map, Value};

pub(crate) const SOURCE: &str = "muse.msp";

#[derive(Debug, Clone)]
pub(crate) struct PendingRequest {
    pub logical_id: RequestId,
    pub wire_id: Option<Value>,
    pub params: Value,
    pub kind: RequestKind,
    pub turn_id: Option<String>,
}

pub(crate) enum MappedFrame {
    Event(ProviderEvent),
    RuntimeRequest {
        event: ProviderEvent,
        pending: PendingRequest,
    },
}

fn request_id(value: Value) -> RequestId {
    match value {
        Value::Number(number) => number
            .as_i64()
            .map(RequestId::Integer)
            .unwrap_or_else(|| RequestId::String(number.to_string())),
        Value::String(value) => RequestId::String(value),
        other => RequestId::String(other.to_string()),
    }
}

pub(crate) fn map_frame(
    frame: MuseFrame,
    provider_instance_id: &str,
    thread_id: &str,
    active_turn_id: Option<&str>,
) -> Option<MappedFrame> {
    let (method, params, raw, wire_id) = match frame {
        MuseFrame::Notification {
            method,
            params,
            raw,
        } => (method, params, raw, None),
        MuseFrame::ServerRequest {
            id,
            method,
            params,
            raw,
        } => (method, params, raw, Some(id)),
        MuseFrame::Unknown(raw) => {
            let method = raw
                .get("method")
                .and_then(Value::as_str)
                .unwrap_or("unknown")
                .to_owned();
            (method, Value::Object(Map::new()), raw, None)
        }
    };
    let explicit_turn_id = params
        .get("turnId")
        .and_then(Value::as_str)
        .map(str::to_owned);
    let turn_id = explicit_turn_id.or_else(|| {
        (method != "turn/completed")
            .then_some(active_turn_id)
            .flatten()
            .map(str::to_owned)
    });
    let item_id = params
        .get("itemId")
        .and_then(Value::as_str)
        .or_else(|| {
            params
                .get("item")
                .and_then(|item| item.get("itemId"))
                .and_then(Value::as_str)
        })
        .map(str::to_owned);
    let raw_event = RawEvent {
        source: SOURCE.into(),
        method: Some(method.clone()),
        message_type: Some(method.clone()),
        payload: raw,
    };
    if method == "approval/request" || method == "approval/requested" {
        return Some(map_approval(
            provider_instance_id,
            thread_id,
            method,
            params,
            raw_event,
            wire_id,
            turn_id,
            item_id,
        ));
    }
    if method == "userInput/request" || method == "userInput/requested" {
        return Some(map_user_input(
            provider_instance_id,
            thread_id,
            method,
            params,
            raw_event,
            wire_id,
            turn_id,
            item_id,
        ));
    }
    Some(MappedFrame::Event(map_notification(
        provider_instance_id,
        thread_id,
        method,
        params,
        raw_event,
        turn_id,
        item_id,
    )))
}

#[allow(clippy::too_many_arguments)]
fn map_approval(
    instance: &str,
    thread: &str,
    method: String,
    params: Value,
    raw: RawEvent,
    wire_id: Option<Value>,
    turn_id: Option<String>,
    item_id: Option<String>,
) -> MappedFrame {
    let logical_id = params
        .get("approvalId")
        .and_then(Value::as_str)
        .map(RequestId::from)
        .or_else(|| wire_id.clone().map(request_id))
        .unwrap_or_else(|| RequestId::String(format!("approval:{thread}")));
    let kind = match params
        .get("subject")
        .and_then(|subject| subject.get("kind"))
        .and_then(Value::as_str)
    {
        Some("fileAccess") => RequestKind::FileReadApproval,
        Some("fileChange") => RequestKind::FileChangeApproval,
        _ => RequestKind::CommandExecutionApproval,
    };
    let request = RuntimeRequest {
        request_id: logical_id.clone(),
        thread_id: thread.into(),
        turn_id: turn_id.clone(),
        item_id: item_id.clone(),
        kind,
        questions: Vec::new(),
        payload: params.clone(),
    };
    let event_kind = EventKind::RequestOpened;
    let payload = serde_json::json!({
        "requestType": kind,
        "approvalId": logical_id.to_string(),
        "availableChoices": params.get("availableChoices").cloned().unwrap_or(Value::Array(Vec::new())),
        "nativeMethod": method,
    });
    let event = event(
        instance,
        thread,
        event_kind,
        payload,
        raw,
        turn_id.clone(),
        item_id.clone(),
    )
    .with_request(request);
    MappedFrame::RuntimeRequest {
        event,
        pending: PendingRequest {
            logical_id,
            wire_id,
            params,
            kind,
            turn_id,
        },
    }
}

#[allow(clippy::too_many_arguments)]
fn map_user_input(
    instance: &str,
    thread: &str,
    method: String,
    params: Value,
    raw: RawEvent,
    wire_id: Option<Value>,
    turn_id: Option<String>,
    item_id: Option<String>,
) -> MappedFrame {
    let logical_id = params
        .get("userInputId")
        .and_then(Value::as_str)
        .map(RequestId::from)
        .or_else(|| wire_id.clone().map(request_id))
        .unwrap_or_else(|| RequestId::String(format!("user-input:{thread}")));
    let questions: Vec<UserInputQuestion> = params
        .get("questions")
        .and_then(Value::as_array)
        .map(|questions| questions.iter().filter_map(question).collect())
        .unwrap_or_default();
    let request = RuntimeRequest {
        request_id: logical_id.clone(),
        thread_id: thread.into(),
        turn_id: turn_id.clone(),
        item_id: item_id.clone(),
        kind: RequestKind::ToolUserInput,
        questions: questions.clone(),
        payload: params.clone(),
    };
    let payload = serde_json::json!({
        "requestType": RequestKind::ToolUserInput,
        "userInputId": logical_id.to_string(),
        "questions": questions,
        "nativeMethod": method,
    });
    let event = event(
        instance,
        thread,
        EventKind::UserInputRequested,
        payload,
        raw,
        turn_id.clone(),
        item_id.clone(),
    )
    .with_request(request);
    MappedFrame::RuntimeRequest {
        event,
        pending: PendingRequest {
            logical_id,
            wire_id,
            params,
            kind: RequestKind::ToolUserInput,
            turn_id,
        },
    }
}
