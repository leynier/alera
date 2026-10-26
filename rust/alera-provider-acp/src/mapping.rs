use crate::mapping_values::{
    content_text, is_mcp_tool_call, item_id, logical_request_id, permission_kind, prompt_matches,
    string, terminal_state, tool_payload,
};
use crate::questions::extract_questions;
use crate::transport::PendingRequest;
use agent_client_protocol::{AcpIncoming, AcpRequestId, RpcRequest};
use alera_provider_protocol::{
    EventKind, ProviderError, ProviderEvent, ProviderKind, ProviderRefs, RequestKind,
    RuntimeRequest, TurnStatus,
};
use serde_json::{json, Value};

pub(crate) struct MappedIncoming {
    pub event: ProviderEvent,
    pub pending: Option<PendingRequest>,
}

pub(crate) struct MappingContext<'a> {
    pub(crate) provider: &'a ProviderKind,
    pub(crate) instance_id: &'a str,
    pub(crate) thread_id: &'a str,
    pub(crate) native_thread_id: &'a str,
    pub(crate) turn_id: Option<&'a str>,
    pub(crate) prompt_id: Option<&'a AcpRequestId>,
    pub(crate) prompt_meta_id: Option<&'a str>,
}

pub(crate) fn map_incoming(
    incoming: AcpIncoming,
    context: &MappingContext<'_>,
) -> Result<MappedIncoming, ProviderError> {
    match incoming {
        AcpIncoming::Notification {
            method,
            params,
            raw,
        } => map_notification(&method, params, raw, context),
        AcpIncoming::Request(request) => map_request(request, context),
        AcpIncoming::Response(response) => map_response(response, context, context.prompt_id),
    }
}

fn map_notification(
    method: &str,
    params: Value,
    raw: Value,
    context: &MappingContext<'_>,
) -> Result<MappedIncoming, ProviderError> {
    if let Some(session_id) = params
        .get("sessionId")
        .or_else(|| params.get("session_id"))
        .and_then(Value::as_str)
    {
        if session_id != context.native_thread_id {
            return Ok(MappedIncoming {
                event: event(
                    context,
                    method,
                    EventKind::Unknown(format!("acp.foreign-session.{method}")),
                    params,
                    raw,
                    None,
                ),
                pending: None,
            });
        }
    }
    if matches!(
        method,
        "x.ai/session/prompt_complete" | "_x.ai/session/prompt_complete"
    ) {
        let native_prompt_id = params
            .get("promptId")
            .or_else(|| params.get("prompt_id"))
            .and_then(Value::as_str);
        if native_prompt_id.is_some_and(|id| id.starts_with("task-completed-")) {
            return Ok(MappedIncoming {
                event: event(context, method, EventKind::TaskCompleted, params, raw, None),
                pending: None,
            });
        }
        if native_prompt_id.is_some_and(|native| {
            !prompt_matches(native, context.prompt_id, context.prompt_meta_id)
        }) {
            return Ok(MappedIncoming {
                event: event(
                    context,
                    method,
                    EventKind::Unknown(format!("acp.{method}")),
                    params,
                    raw,
                    None,
                ),
                pending: None,
            });
        }
        let payload = json!({
            "state": terminal_state(
                params.get("stopReason").or_else(|| params.get("stop_reason")),
            ),
            "stopReason": params.get("stopReason").or_else(|| params.get("stop_reason")),
            "usage": params.get("usage"),
            "result": params.get("agentResult").or_else(|| params.get("agent_result")),
            "errorMessage": params
                .get("errorMessage")
                .or_else(|| params.get("error"))
                .and_then(Value::as_str),
        });
        return Ok(MappedIncoming {
            event: event(
                context,
                method,
                EventKind::TurnCompleted,
                payload,
                raw,
                None,
            ),
            pending: None,
        });
    }
    let is_update = matches!(
        method,
        "session/update"
            | "x.ai/session_notification"
            | "_x.ai/session_notification"
            | "_x.ai/session/update"
    );
    if !is_update {
        let event = event(
            context,
            method,
            EventKind::Unknown(format!("acp.{method}")),
            params,
            raw,
            None,
        );
        return Ok(MappedIncoming {
            event,
            pending: None,
        });
    }
    let update = params.get("update").cloned().unwrap_or(params.clone());
    let name = update
        .get("sessionUpdate")
        .and_then(Value::as_str)
        .unwrap_or("unknown");
    let (kind, payload, item_id) = match name {
        "agent_message_chunk" => {
            let text = content_text(update.get("content"));
            if text.is_empty() {
                (
                    EventKind::Unknown("acp.session-update.agent_message_chunk".into()),
                    update.clone(),
                    string(update.get("messageId")),
                )
            } else {
                (
                    EventKind::ContentDelta,
                    json!({"streamKind":"assistant_text","delta":text}),
                    string(update.get("messageId")),
                )
            }
        }
        "agent_thought_chunk" => {
            let text = content_text(update.get("content"));
            if text.is_empty() {
                (
                    EventKind::Unknown("acp.session-update.agent_thought_chunk".into()),
                    update.clone(),
                    string(update.get("messageId")),
                )
            } else {
                (
                    EventKind::ContentDelta,
                    json!({"streamKind":"reasoning_text","delta":text}),
                    string(update.get("messageId")),
                )
            }
        }
        "terminal_output_chunk" => (
            EventKind::ContentDelta,
            json!({
                "streamKind":"command_output",
                "delta": update.get("data").and_then(Value::as_str).unwrap_or_default()
            }),
            string(update.get("terminalId")),
        ),
        "tool_call" | "tool_call_update" => {
            let status = update.get("status").and_then(Value::as_str);
            let kind = if status == Some("completed") || status == Some("failed") {
                EventKind::ItemCompleted
            } else if name == "tool_call" {
                EventKind::ItemStarted
            } else {
                EventKind::ItemUpdated
            };
            let is_mcp = is_mcp_tool_call(&update) || is_mcp_tool_call(&params);
            (
                kind,
                tool_payload(&update, is_mcp),
                string(update.get("toolCallId")),
            )
        }
        "state_update" => {
            if update.get("state").and_then(Value::as_str) == Some("idle")
                && context.turn_id.is_some()
            {
                let state = match update.get("stopReason").and_then(Value::as_str) {
                    Some("cancelled") | Some("interrupted") => TurnStatus::Interrupted,
                    Some("error") | Some("failed") => TurnStatus::Failed,
                    _ => TurnStatus::Completed,
                };
                (
                    EventKind::TurnCompleted,
                    json!({
                        "state": state,
                        "stopReason": update.get("stopReason"),
                        "usage": update.get("usage"),
                        "errorMessage": update
                            .get("errorMessage")
                            .or_else(|| update.get("error"))
                            .and_then(Value::as_str),
                    }),
                    None,
                )
            } else {
                (EventKind::ThreadStateChanged, update.clone(), None)
            }
        }
        "turn_completed" => {
            let native_prompt_id = update
                .get("prompt_id")
                .or_else(|| update.get("promptId"))
                .and_then(Value::as_str);
            if native_prompt_id.is_some_and(|id| id.starts_with("task-completed-")) {
                (EventKind::TaskCompleted, update.clone(), None)
            } else {
                let matches_prompt = native_prompt_id
                    .map(|native| prompt_matches(native, context.prompt_id, context.prompt_meta_id))
                    .unwrap_or(context.prompt_id.is_none() || context.prompt_meta_id.is_some());
                if !matches_prompt {
                    (
                        EventKind::Unknown(format!("acp.session-update.{name}")),
                        update.clone(),
                        None,
                    )
                } else {
                    (
                        EventKind::TurnCompleted,
                        json!({
                            "state": terminal_state(
                                update.get("stop_reason").or_else(|| update.get("stopReason")),
                            ),
                            "stopReason": update.get("stop_reason").or_else(|| update.get("stopReason")),
                            "usage": update.get("usage"),
                            "result": update.get("agent_result").or_else(|| update.get("agentResult")),
                            "errorMessage": update
                                .get("errorMessage")
                                .or_else(|| update.get("error"))
                                .and_then(Value::as_str),
                        }),
                        None,
                    )
                }
            }
        }
        "plan" | "plan_update" | "plan_removed" => {
            (EventKind::TurnPlanUpdated, json!({"plan": update}), None)
        }
        "available_commands_update" | "config_option_update" | "current_mode_update" => {
            (EventKind::ThreadMetadataUpdated, update.clone(), None)
        }
        "compaction_update" | "compaction_summary_chunk" => (
            EventKind::ItemUpdated,
            json!({"itemType":"context_compaction","data":update}),
            None,
        ),
        _ => (
            EventKind::Unknown(format!("acp.session-update.{name}")),
            update.clone(),
            None,
        ),
    };
    let event = event(context, method, kind, payload, raw, item_id.as_deref());
    Ok(MappedIncoming {
        event,
        pending: None,
    })
}

fn map_response(
    response: agent_client_protocol::AcpResponse,
    context: &MappingContext<'_>,
    prompt_id: Option<&AcpRequestId>,
) -> Result<MappedIncoming, ProviderError> {
    if !prompt_id.is_some_and(|prompt| prompt == &response.id) {
        let payload = response
            .result
            .clone()
            .or_else(|| {
                response.error.as_ref().map(
                    |error| json!({"error": error.message, "code": error.code, "data": error.data}),
                )
            })
            .unwrap_or(Value::Null);
        return Ok(MappedIncoming {
            event: event(
                context,
                "session/prompt",
                EventKind::Unknown("acp.response".into()),
                payload,
                response.raw,
                None,
            ),
            pending: None,
        });
    }
    let payload = if let Some(error) = response.error {
        json!({
            "state": TurnStatus::Failed,
            "errorMessage": error.message,
            "error": {"code": error.code, "data": error.data},
        })
    } else {
        let result = response.result.unwrap_or(Value::Null);
        json!({
            "state": terminal_state(result.get("stopReason").or_else(|| result.get("stop_reason"))),
            "stopReason": result.get("stopReason").or_else(|| result.get("stop_reason")),
            "usage": result.get("usage"),
            "result": result,
        })
    };
    Ok(MappedIncoming {
        event: event(
            context,
            "session/prompt",
            EventKind::TurnCompleted,
            payload,
            response.raw,
            None,
        ),
        pending: None,
    })
}

fn map_request(
    request: RpcRequest,
    context: &MappingContext<'_>,
) -> Result<MappedIncoming, ProviderError> {
    let kind = match request.method.as_str() {
        "session/request_permission" => permission_kind(&request.params),
        "ask_user" | "ask_user_question" | "x.ai/ask_user_question" | "_x.ai/ask_user_question" => {
            RequestKind::ToolUserInput
        }
        "elicitation/create" | "session/elicitation" | "_session/elicitation" => {
            RequestKind::McpElicitationApproval
        }
        _ => RequestKind::Unknown,
    };
    if kind == RequestKind::Unknown {
        let params = request.params.clone();
        let raw = request.raw.clone();
        return Ok(MappedIncoming {
            event: event(
                context,
                &request.method,
                EventKind::Unknown(format!("acp.request.{}", request.method)),
                params,
                raw,
                None,
            ),
            pending: Some(PendingRequest {
                logical_id: logical_request_id(&request.id).to_string(),
                rpc_id: request.id,
                kind,
                method: request.method,
                params: request.params.clone(),
                raw: request.raw.clone(),
            }),
        });
    }
    let logical = logical_request_id(&request.id);
    let questions = extract_questions(&request.params);
    let runtime_request = RuntimeRequest {
        request_id: logical.clone(),
        thread_id: context.thread_id.to_owned(),
        turn_id: context.turn_id.map(ToOwned::to_owned),
        item_id: item_id(&request.params),
        kind,
        questions: questions.clone(),
        payload: request.params.clone(),
        supports_feedback: false,
    };
    let event_kind = if kind != RequestKind::McpElicitationApproval && !questions.is_empty() {
        EventKind::UserInputRequested
    } else {
        EventKind::RequestOpened
    };
    let payload = if event_kind == EventKind::UserInputRequested {
        json!({"requestType": kind, "questions": questions})
    } else {
        json!({
            "requestType": kind,
            "detail": request.params.get("title").or_else(|| request.params.get("description")),
            "args": request.params.get("subject").unwrap_or(&request.params),
            "options": request.params.get("options").cloned().unwrap_or_else(|| json!([])),
        })
    };
    let mut event = event(
        context,
        &request.method,
        event_kind,
        payload,
        request.raw.clone(),
        item_id(&request.params).as_deref(),
    )
    .with_request(runtime_request);
    event.provider_refs = Some(ProviderRefs {
        provider_turn_id: context.turn_id.map(ToOwned::to_owned),
        provider_item_id: item_id(&request.params),
        provider_request_id: Some(request.id.to_string()),
    });
    event.validate()?;
    Ok(MappedIncoming {
        event,
        pending: Some(PendingRequest {
            logical_id: logical.to_string(),
            rpc_id: request.id,
            kind,
            method: request.method,
            params: request.params,
            raw: request.raw,
        }),
    })
}

fn event(
    context: &MappingContext<'_>,
    method: &str,
    kind: EventKind,
    payload: Value,
    raw_payload: Value,
    item_id: Option<&str>,
) -> ProviderEvent {
    let mut event = ProviderEvent::new(
        context.provider.clone(),
        context.instance_id,
        context.thread_id,
        kind,
        payload,
        Some(alera_provider_protocol::RawEvent {
            source: "acp.jsonrpc".into(),
            method: Some(method.into()),
            message_type: Some(method.into()),
            payload: raw_payload,
        }),
    );
    event.turn_id = context.turn_id.map(ToOwned::to_owned);
    event.item_id = item_id.map(ToOwned::to_owned);
    event
}
