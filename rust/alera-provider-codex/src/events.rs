use crate::payloads::{normalized_payload, request_payload};
use crate::provider::{CodexProvider, PendingRequest};
use crate::wire;
use alera_provider_protocol::transport::JsonTransport;
use alera_provider_protocol::{
    EventKind, ProviderError, ProviderEvent, ProviderRefs, RequestKind, RuntimeRequest,
    UserInputOption, UserInputQuestion,
};
use serde_json::Value;

pub(crate) fn map_message<T: JsonTransport>(
    provider: &mut CodexProvider<T>,
    message: Value,
) -> Result<ProviderEvent, ProviderError> {
    let method = wire::method(&message)
        .map(ToOwned::to_owned)
        .ok_or_else(|| ProviderError::Protocol("Codex incoming message has no method".into()))?;
    if let Some(id) = message.get("id").cloned() {
        map_request(provider, &id, &method, wire::params(&message), message)
    } else {
        map_notification(provider, &method, wire::params(&message), message)
    }
}

fn map_notification<T: JsonTransport>(
    provider: &mut CodexProvider<T>,
    method: &str,
    params: Value,
    message: Value,
) -> Result<ProviderEvent, ProviderError> {
    let native_thread_id = thread_id(&params);
    let native_turn_id = turn_id(&params);
    let native_item_id = item_id(&params);
    let kind = notification_kind(method, &params);
    let payload = normalized_payload(method, &params)?;
    let thread_id = provider.app_thread_id(native_thread_id.as_deref());
    let mut event = ProviderEvent::new(
        alera_provider_protocol::ProviderKind::Codex,
        provider.config.instance_id.clone(),
        thread_id,
        kind,
        payload,
        Some(raw_event(method, "notification", message)),
    );
    event.turn_id = native_turn_id.clone();
    event.item_id = native_item_id.clone();
    event.provider_refs = Some(ProviderRefs {
        provider_turn_id: native_turn_id,
        provider_item_id: native_item_id,
        provider_request_id: None,
    });
    event.validate()?;
    provider.apply_notification_state(method, event.turn_id.as_deref());
    Ok(event)
}

fn map_request<T: JsonTransport>(
    provider: &mut CodexProvider<T>,
    id: &Value,
    method: &str,
    params: Value,
    message: Value,
) -> Result<ProviderEvent, ProviderError> {
    let rpc_id = wire::request_id(id)?;
    let native_thread_id = thread_id(&params);
    let native_turn_id = turn_id(&params);
    let native_item_id = item_id(&params);
    let app_thread_id = provider.app_thread_id(native_thread_id.as_deref());
    let kind = request_kind(method);
    let request_id = logical_request_id(method, &params, &rpc_id);
    if provider.pending_requests.contains_key(&request_id) {
        return Err(ProviderError::InvalidState(
            "Codex runtime request id is already pending".into(),
        ));
    }
    let questions = request_questions(&params);
    let request = RuntimeRequest {
        request_id: request_id.clone(),
        thread_id: app_thread_id.clone(),
        turn_id: native_turn_id.clone(),
        item_id: native_item_id.clone(),
        kind,
        questions: questions.clone(),
        payload: params.clone(),
    };
    let event_kind = if kind == RequestKind::ToolUserInput {
        EventKind::UserInputRequested
    } else {
        EventKind::RequestOpened
    };
    let mut event = ProviderEvent::new(
        alera_provider_protocol::ProviderKind::Codex,
        provider.config.instance_id.clone(),
        app_thread_id,
        event_kind,
        request_payload(kind, &params, &questions),
        Some(raw_event(method, "request", message)),
    )
    .with_request(request);
    event.turn_id = native_turn_id.clone();
    event.item_id = native_item_id.clone();
    event.provider_refs = Some(ProviderRefs {
        provider_turn_id: native_turn_id,
        provider_item_id: native_item_id,
        provider_request_id: Some(request_id.to_string()),
    });
    event.validate()?;
    provider.pending_requests.insert(
        request_id,
        PendingRequest {
            rpc_id,
            method: method.to_owned(),
        },
    );
    provider.mark_waiting();
    Ok(event)
}

fn raw_event(
    method: &str,
    message_type: &str,
    payload: Value,
) -> alera_provider_protocol::RawEvent {
    alera_provider_protocol::RawEvent {
        source: format!("codex.app-server.{message_type}"),
        method: Some(method.to_owned()),
        message_type: Some(message_type.to_owned()),
        payload,
    }
}

fn thread_id(params: &Value) -> Option<String> {
    wire::string(params, "threadId").or_else(|| wire::nested_string(params, "thread", "id"))
}

fn turn_id(params: &Value) -> Option<String> {
    wire::string(params, "turnId").or_else(|| wire::nested_string(params, "turn", "id"))
}

fn item_id(params: &Value) -> Option<String> {
    wire::string(params, "itemId").or_else(|| wire::nested_string(params, "item", "id"))
}

fn notification_kind(method: &str, params: &Value) -> EventKind {
    match method {
        "thread/started" => EventKind::ThreadStarted,
        "thread/status/changed"
        | "thread/closed"
        | "thread/archived"
        | "thread/deleted"
        | "thread/unarchived"
        | "thread/reverted" => EventKind::ThreadStateChanged,
        "thread/name/updated"
        | "thread/attachment/updated"
        | "thread/goal/updated"
        | "thread/goal/cleared"
        | "thread/project/updated"
        | "thread/settings/updated" => EventKind::ThreadMetadataUpdated,
        "thread/tokenUsage/updated" => EventKind::ThreadTokenUsageUpdated,
        "thread/realtime/started" => EventKind::ThreadRealtimeStarted,
        "thread/realtime/itemAdded" | "thread/realtime/item/started" => {
            EventKind::ThreadRealtimeItemAdded
        }
        "thread/realtime/item/transcript/delta"
        | "thread/realtime/transcript/delta"
        | "thread/realtime/outputAudio/delta" => EventKind::ThreadRealtimeAudioDelta,
        "thread/realtime/error" => EventKind::ThreadRealtimeError,
        "thread/realtime/closed" => EventKind::ThreadRealtimeClosed,
        "turn/started" => EventKind::TurnStarted,
        "turn/completed" => EventKind::TurnCompleted,
        "turn/aborted" => EventKind::TurnAborted,
        "turn/plan/updated" => EventKind::TurnPlanUpdated,
        "turn/diff/updated" => EventKind::TurnDiffUpdated,
        "item/started" | "item/autoApprovalReview/started" => EventKind::ItemStarted,
        "item/completed"
        | "item/autoApprovalReview/completed"
        | "rawResponseItem/completed"
        | "rawResponse/completed" => EventKind::ItemCompleted,
        "item/agentMessage/delta" => EventKind::ContentDelta,
        "item/reasoning/textDelta"
        | "item/reasoning/summaryTextDelta"
        | "item/plan/delta"
        | "command/exec/outputDelta"
        | "process/outputDelta"
        | "item/commandExecution/outputDelta"
        | "item/fileChange/outputDelta" => EventKind::ContentDelta,
        "item/fileChange/patchUpdated" | "item/commandExecution/terminalInteraction" => {
            EventKind::ItemUpdated
        }
        "item/mcpToolCall/progress" => EventKind::ToolProgress,
        "hook/started" => EventKind::HookStarted,
        "hook/completed" => EventKind::HookCompleted,
        "account/updated" | "account/gatewayOAuth/changed" => EventKind::AccountUpdated,
        "account/rateLimits/updated" => EventKind::AccountRateLimitsUpdated,
        "mcpServer/startupStatus/updated" | "mcpServer/event/stream/notification" => {
            EventKind::McpStatusUpdated
        }
        "mcpServer/oauthLogin/completed" => EventKind::McpOauthCompleted,
        "model/rerouted" => EventKind::ModelRerouted,
        "config/warning" | "configWarning" => EventKind::ConfigWarning,
        "deprecation/notice" | "deprecationNotice" => EventKind::DeprecationNotice,
        "files/persisted" => EventKind::FilesPersisted,
        "tool/denied" => EventKind::ToolDenied,
        "error" => EventKind::RuntimeError,
        "warning" | "guardianWarning" | "thread/environment/disconnected" => {
            EventKind::RuntimeWarning
        }
        "thread/environment/connected" => EventKind::ThreadStateChanged,
        _ if params.get("error").is_some_and(|error| !error.is_null()) => EventKind::RuntimeError,
        _ => EventKind::Unknown(method.to_owned()),
    }
}

fn logical_request_id(
    method: &str,
    params: &Value,
    rpc_id: &alera_provider_protocol::RequestId,
) -> alera_provider_protocol::RequestId {
    let value = match method {
        "item/commandExecution/requestApproval" => params
            .get("approvalId")
            .filter(|value| !value.is_null())
            .or_else(|| params.get("itemId")),
        "execCommandApproval" => params
            .get("approvalId")
            .filter(|value| !value.is_null())
            .or_else(|| params.get("callId")),
        "item/fileChange/requestApproval"
        | "item/permissions/requestApproval"
        | "item/tool/requestUserInput" => params.get("itemId"),
        "applyPatchApproval" => params.get("callId"),
        "mcpServer/elicitation/request" => params.get("elicitationId"),
        "item/tool/call" => params.get("callId").or_else(|| params.get("itemId")),
        _ => None,
    };
    value
        .and_then(|value| wire::request_id(value).ok())
        .unwrap_or_else(|| rpc_id.clone())
}

fn request_kind(method: &str) -> RequestKind {
    match method {
        "item/commandExecution/requestApproval" => RequestKind::CommandExecutionApproval,
        "item/fileChange/requestApproval" => RequestKind::FileChangeApproval,
        "item/tool/requestUserInput" => RequestKind::ToolUserInput,
        "mcpServer/elicitation/request" => RequestKind::McpElicitationApproval,
        "item/permissions/requestApproval" => RequestKind::PermissionApproval,
        "item/tool/call" => RequestKind::DynamicToolCall,
        "account/chatgptAuthTokens/refresh" => RequestKind::AuthTokensRefresh,
        "execCommandApproval" => RequestKind::ExecCommandApproval,
        "applyPatchApproval" => RequestKind::ApplyPatchApproval,
        _ => RequestKind::Unknown,
    }
}

fn request_questions(params: &Value) -> Vec<UserInputQuestion> {
    params
        .get("questions")
        .and_then(Value::as_array)
        .into_iter()
        .flatten()
        .enumerate()
        .map(|(index, question)| {
            let id = wire::string(question, "id").unwrap_or_else(|| format!("question-{index}"));
            let header = wire::string(question, "header")
                .filter(|value| !value.trim().is_empty())
                .unwrap_or_else(|| format!("Question {}", index + 1));
            let text = wire::string(question, "question")
                .filter(|value| !value.trim().is_empty())
                .unwrap_or_else(|| "Codex requested an answer".to_owned());
            let options = question
                .get("options")
                .and_then(Value::as_array)
                .into_iter()
                .flatten()
                .filter_map(|option| {
                    Some(UserInputOption {
                        label: wire::string(option, "label")?,
                        description: wire::string(option, "description").unwrap_or_default(),
                        value: wire::string(option, "value"),
                    })
                })
                .collect();
            UserInputQuestion {
                id,
                header,
                question: text,
                options,
                allow_custom_answer: question.get("isOther").and_then(Value::as_bool),
                initial_answer: None,
                multi_select: false,
            }
        })
        .collect()
}
