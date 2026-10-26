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
    let mut kind = notification_kind(method, &params);
    let mut payload = normalized_payload(method, &params)?;
    if let Some(task) = crate::lineage::native_task(&params)? {
        provider.register_children(&task, &params);
        payload["nativeTask"] = serde_json::to_value(task).expect("native task is serializable");
    }
    if kind == EventKind::RuntimeError {
        let class = crate::failure::error_info(&params)
            .map(crate::failure::failure_class)
            .unwrap_or_default();
        if !class.is_unknown() {
            payload["failureClass"] = serde_json::json!(class);
        }
    }
    let child_parent = native_thread_id
        .as_deref()
        .and_then(|id| provider.native_child_parents.get(id))
        .cloned();
    let root = child_parent.is_none()
        && native_thread_id.as_deref().is_none_or(|id| {
            provider
                .session
                .as_ref()
                .is_none_or(|session| session.native_thread_id == id)
        });
    if root {
        classify_root_failure(provider, method, &params, &mut payload);
    }
    if let (Some(child), Some(parent)) = (native_thread_id.as_ref(), child_parent.as_ref()) {
        let terminal = matches!(method, "turn/completed" | "turn/aborted" | "thread/closed");
        let item = matches!(
            kind,
            EventKind::ItemStarted
                | EventKind::ItemUpdated
                | EventKind::ItemCompleted
                | EventKind::ContentDelta
        );
        // A native sub-agent's result goes back to its parent agent.
        let task = provider.child_task_payload(child, parent, method, &params, payload.clone());
        match item
            .then(|| provider.child_item_payload(child, payload.clone()))
            .flatten()
        {
            // The child's own work stays an item, under the call that spawned it.
            Some(item) => payload = item,
            None => {
                kind = if terminal {
                    EventKind::TaskCompleted
                } else if matches!(method, "thread/started" | "turn/started") {
                    EventKind::TaskStarted
                } else {
                    EventKind::TaskProgress
                };
                payload = task;
            }
        }
    }
    let thread_id = provider.app_thread_id(native_thread_id.as_deref());
    let mut event = ProviderEvent::new(
        alera_provider_protocol::ProviderKind::Codex,
        provider.config.instance_id.clone(),
        thread_id,
        kind,
        payload,
        Some(raw_event(method, "notification", message)),
    );
    event.turn_id = if child_parent.is_some() {
        provider
            .session
            .as_ref()
            .and_then(|session| session.active_turn_id.clone())
    } else {
        native_turn_id.clone()
    };
    event.item_id = native_item_id.clone();
    event.provider_refs = Some(ProviderRefs {
        provider_turn_id: native_turn_id,
        provider_item_id: native_item_id,
        provider_request_id: None,
    });
    event.validate()?;
    if root {
        provider.apply_notification_state(method, event.turn_id.as_deref());
    }
    Ok(event)
}

/// Gives a failed root turn its class, and says whether native child turns
/// outlive it. A `codexErrorInfo` on the completion decides the class; a
/// missing one falls back to the turn's last final `error` notification.
fn classify_root_failure<T>(
    provider: &mut CodexProvider<T>,
    method: &str,
    params: &Value,
    payload: &mut Value,
) {
    match method {
        "turn/started" => provider.turn_failure_class = None,
        "error" if params.get("willRetry") != Some(&Value::Bool(true)) => {
            provider.turn_failure_class = Some(
                crate::failure::error_info(params)
                    .map(crate::failure::failure_class)
                    .unwrap_or_default(),
            );
        }
        "turn/completed" => {
            if payload["state"] == "failed" {
                let class = crate::failure::error_info(params)
                    .map(crate::failure::failure_class)
                    .or(provider.turn_failure_class)
                    .unwrap_or_default();
                payload["failureClass"] = serde_json::json!(class);
                if !provider.active_child_turns.is_empty() {
                    payload["childTurnsContinue"] = Value::Bool(true);
                }
            }
            provider.turn_failure_class = None;
        }
        "turn/aborted" => provider.turn_failure_class = None,
        _ => {}
    }
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
    let allowance = provider.allowance_grant(method, &params);
    let questions = request_questions(&params);
    let request = RuntimeRequest {
        request_id: request_id.clone(),
        thread_id: app_thread_id.clone(),
        turn_id: native_turn_id.clone(),
        item_id: native_item_id.clone(),
        kind,
        questions: questions.clone(),
        payload: params.clone(),
        supports_feedback: false,
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
            allowance,
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
