use crate::provider::{opencode_kind, OpenCodeProvider, PendingRequest};
use alera_provider_protocol::{
    EventKind, ProviderError, ProviderEvent, ProviderRefs, RawEvent, RequestKind, RuntimeRequest,
    UserInputOption, UserInputQuestion,
};
use opencode_agent_sdk::HttpTransport;
use serde_json::{json, Value};

pub(crate) fn map_permission<T: HttpTransport>(
    provider: &mut OpenCodeProvider<T>,
    props: &Value,
    thread_id: &str,
    turn_id: Option<String>,
    raw: Option<RawEvent>,
) -> Result<ProviderEvent, ProviderError> {
    let native_id = request_id(props)?;
    let kind = match props
        .get("permission")
        .or_else(|| props.get("type"))
        .and_then(Value::as_str)
    {
        Some("read") => RequestKind::FileReadApproval,
        Some("edit" | "write" | "external_directory") => RequestKind::FileChangeApproval,
        Some("mcp") => RequestKind::PermissionApproval,
        _ => RequestKind::CommandExecutionApproval,
    };
    provider.pending.insert(
        native_id.clone(),
        PendingRequest {
            native_id: native_id.clone(),
            kind,
            thread_id: thread_id.to_owned(),
            native_session_id: native_session_id(props, provider),
            turn_id: turn_id.clone(),
            questions: Vec::new(),
            is_form: false,
        },
    );
    let request = RuntimeRequest {
        request_id: native_id.clone().into(),
        thread_id: thread_id.to_owned(),
        turn_id: turn_id.clone(),
        item_id: item_id(props),
        kind,
        questions: Vec::new(),
        payload: json!({ "requestType": kind, "args": props }),
    };
    let mut event = ProviderEvent::new(
        opencode_kind(),
        provider.config.provider_instance_id.clone(),
        thread_id,
        EventKind::RequestOpened,
        json!({ "requestType": kind, "args": props }),
        raw,
    )
    .with_request(request);
    event.turn_id = turn_id.clone();
    event.provider_refs = Some(refs(turn_id, item_id(props), Some(native_id)));
    Ok(event)
}

pub(crate) fn map_question<T: HttpTransport>(
    provider: &mut OpenCodeProvider<T>,
    props: &Value,
    thread_id: &str,
    turn_id: Option<String>,
    raw: Option<RawEvent>,
) -> Result<ProviderEvent, ProviderError> {
    let native_id = request_id(props)?;
    let questions = props
        .get("questions")
        .and_then(Value::as_array)
        .map(|questions| {
            questions
                .iter()
                .enumerate()
                .map(|(index, question)| UserInputQuestion {
                    id: question
                        .get("id")
                        .or_else(|| question.get("header"))
                        .and_then(Value::as_str)
                        .map(str::to_owned)
                        .unwrap_or_else(|| format!("question-{index}")),
                    header: question
                        .get("header")
                        .and_then(Value::as_str)
                        .unwrap_or("Question")
                        .to_owned(),
                    question: question
                        .get("question")
                        .or_else(|| question.get("text"))
                        .and_then(Value::as_str)
                        .unwrap_or("OpenCode requested an answer")
                        .to_owned(),
                    options: question
                        .get("options")
                        .and_then(Value::as_array)
                        .map(|options| options.iter().filter_map(option).collect())
                        .unwrap_or_default(),
                    allow_custom_answer: Some(true),
                    initial_answer: None,
                    multi_select: question
                        .get("multiple")
                        .and_then(Value::as_bool)
                        .unwrap_or(false),
                })
                .collect::<Vec<_>>()
        })
        .unwrap_or_default();
    provider.pending.insert(
        native_id.clone(),
        PendingRequest {
            native_id: native_id.clone(),
            kind: RequestKind::ToolUserInput,
            thread_id: thread_id.to_owned(),
            native_session_id: native_session_id(props, provider),
            turn_id: turn_id.clone(),
            questions: questions.clone(),
            is_form: false,
        },
    );
    let request = RuntimeRequest {
        request_id: native_id.clone().into(),
        thread_id: thread_id.to_owned(),
        turn_id: turn_id.clone(),
        item_id: item_id(props),
        kind: RequestKind::ToolUserInput,
        questions: questions.clone(),
        payload: json!({ "requestType": "tool_user_input", "questions": questions }),
    };
    let mut event = ProviderEvent::new(
        opencode_kind(),
        provider.config.provider_instance_id.clone(),
        thread_id,
        EventKind::UserInputRequested,
        json!({ "requestType": "tool_user_input", "questions": questions }),
        raw,
    )
    .with_request(request);
    event.turn_id = turn_id.clone();
    event.provider_refs = Some(refs(turn_id, item_id(props), Some(native_id)));
    Ok(event)
}

pub(crate) fn map_form<T: HttpTransport>(
    provider: &mut OpenCodeProvider<T>,
    props: &Value,
    thread_id: &str,
    turn_id: Option<String>,
    raw: Option<RawEvent>,
) -> Result<ProviderEvent, ProviderError> {
    let form = props
        .get("form")
        .ok_or_else(|| ProviderError::Protocol("OpenCode form.created has no form".into()))?;
    let native_id = request_id(form)?;
    let questions = form
        .get("fields")
        .and_then(Value::as_array)
        .map(|fields| {
            fields
                .iter()
                .filter_map(|field| {
                    let id = field.get("key").and_then(Value::as_str)?.to_owned();
                    let header = field
                        .get("title")
                        .and_then(Value::as_str)
                        .unwrap_or(&id)
                        .to_owned();
                    let options = field
                        .get("options")
                        .and_then(Value::as_array)
                        .map(|options| options.iter().filter_map(option).collect())
                        .unwrap_or_default();
                    Some(UserInputQuestion {
                        id,
                        header: header.clone(),
                        question: field
                            .get("description")
                            .and_then(Value::as_str)
                            .unwrap_or(&header)
                            .to_owned(),
                        options,
                        allow_custom_answer: field.get("custom").and_then(Value::as_bool),
                        initial_answer: field
                            .get("default")
                            .and_then(Value::as_str)
                            .map(str::to_owned),
                        multi_select: field
                            .get("type")
                            .and_then(Value::as_str)
                            .is_some_and(|kind| kind == "multiselect"),
                    })
                })
                .collect::<Vec<_>>()
        })
        .unwrap_or_default();
    let native_session_id = form
        .get("sessionID")
        .and_then(Value::as_str)
        .map(str::to_owned)
        .or_else(|| {
            provider
                .session
                .as_ref()
                .map(|session| session.native_thread_id.clone())
        })
        .unwrap_or_default();
    provider.pending.insert(
        native_id.clone(),
        PendingRequest {
            native_id: native_id.clone(),
            kind: RequestKind::ToolUserInput,
            thread_id: thread_id.to_owned(),
            native_session_id,
            turn_id: turn_id.clone(),
            questions: questions.clone(),
            is_form: true,
        },
    );
    let request = RuntimeRequest {
        request_id: native_id.clone().into(),
        thread_id: thread_id.to_owned(),
        turn_id: turn_id.clone(),
        item_id: None,
        kind: RequestKind::ToolUserInput,
        questions: questions.clone(),
        payload: json!({ "requestType": "tool_user_input", "form": form }),
    };
    let mut event = ProviderEvent::new(
        opencode_kind(),
        provider.config.provider_instance_id.clone(),
        thread_id,
        EventKind::UserInputRequested,
        json!({ "requestType": "tool_user_input", "questions": questions }),
        raw,
    )
    .with_request(request);
    event.turn_id = turn_id.clone();
    event.provider_refs = Some(refs(turn_id, None, Some(native_id)));
    Ok(event)
}

pub(crate) fn map_request_resolved<T: HttpTransport>(
    provider: &mut OpenCodeProvider<T>,
    props: &Value,
    thread_id: &str,
    turn_id: Option<String>,
    raw: Option<RawEvent>,
) -> Result<ProviderEvent, ProviderError> {
    let native_id = request_id(props)?;
    let pending = provider.pending.remove(&native_id);
    let kind = pending
        .as_ref()
        .map(|pending| pending.kind)
        .unwrap_or(RequestKind::Unknown);
    let mut event = ProviderEvent::new(
        opencode_kind(),
        provider.config.provider_instance_id.clone(),
        thread_id,
        EventKind::RequestResolved,
        json!({ "requestType": kind, "detail": props }),
        raw,
    );
    event.request_id = Some(native_id.clone());
    event.turn_id = turn_id;
    event.provider_refs = Some(refs(event.turn_id.clone(), None, Some(native_id)));
    Ok(event)
}

pub(crate) fn option(value: &Value) -> Option<UserInputOption> {
    Some(UserInputOption {
        label: value
            .get("label")
            .or_else(|| value.get("value"))
            .and_then(Value::as_str)?
            .to_owned(),
        description: value
            .get("description")
            .and_then(Value::as_str)
            .unwrap_or_default()
            .to_owned(),
        value: value
            .get("value")
            .and_then(Value::as_str)
            .map(str::to_owned),
    })
}

pub(crate) fn request_id(props: &Value) -> Result<String, ProviderError> {
    props
        .get("id")
        .or_else(|| props.get("requestID"))
        .and_then(Value::as_str)
        .filter(|id| !id.trim().is_empty())
        .map(str::to_owned)
        .ok_or_else(|| ProviderError::Protocol("OpenCode request has no native id".into()))
}

pub(crate) fn item_id(props: &Value) -> Option<String> {
    props
        .get("partID")
        .or_else(|| props.get("itemID"))
        .or_else(|| props.get("part").and_then(|part| part.get("id")))
        .or_else(|| props.get("messageID"))
        .or_else(|| props.get("assistantMessageID"))
        .or_else(|| props.get("info").and_then(|info| info.get("id")))
        .and_then(Value::as_str)
        .map(str::to_owned)
}

fn native_session_id<T: HttpTransport>(props: &Value, provider: &OpenCodeProvider<T>) -> String {
    props
        .get("sessionID")
        .and_then(Value::as_str)
        .map(str::to_owned)
        .or_else(|| {
            provider
                .session
                .as_ref()
                .map(|session| session.native_thread_id.clone())
        })
        .unwrap_or_default()
}

pub(crate) fn refs(
    turn_id: Option<String>,
    item_id: Option<String>,
    request_id: Option<String>,
) -> ProviderRefs {
    ProviderRefs {
        provider_turn_id: turn_id,
        provider_item_id: item_id,
        provider_request_id: request_id,
    }
}
