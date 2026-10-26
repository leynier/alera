use super::*;
use alera_provider_protocol::{ApprovalDecision, RequestId, RequestKind};
use claude_agent_sdk::{McpCallbackWithContext, PermissionCallback, PermissionResult};
use tokio::sync::oneshot;
use tokio::time::{timeout, Duration};

const CALLBACK_TIMEOUT: Duration = Duration::from_secs(300);
const PLAN_CAPTURED_MESSAGE: &str = "The plan was shown to the user as a proposed plan. Stop here and wait: the user will reply with feedback or ask for the implementation in a later turn.";

pub(crate) struct RequestNotice {
    pub(crate) request: RuntimeRequest,
    pub(crate) source: &'static str,
    pub(crate) raw: Value,
    pub(crate) native_request_id: Option<String>,
}

pub(crate) enum PendingResponse {
    Permission {
        sender: oneshot::Sender<RuntimeResponse>,
        request: RuntimeRequest,
        native_request_id: Option<String>,
    },
    Mcp {
        sender: oneshot::Sender<RuntimeResponse>,
        request: RuntimeRequest,
        native_request_id: Option<String>,
    },
}

impl PendingResponse {
    pub(crate) fn is_closed(&self) -> bool {
        match self {
            Self::Permission { sender, .. } | Self::Mcp { sender, .. } => sender.is_closed(),
        }
    }
}

pub(crate) fn install_callbacks(
    options: &mut ClaudeAgentOptions,
    request_tx: &mpsc::Sender<RequestNotice>,
    pending: &Arc<Mutex<HashMap<String, PendingResponse>>>,
    next_request: &Arc<AtomicU64>,
    thread_id: &Arc<Mutex<Option<String>>>,
    turn_id: &Arc<Mutex<Option<String>>>,
    plan_interaction: &Arc<AtomicBool>,
) {
    let bypass_permissions = options.permission_mode.as_deref() == Some("bypassPermissions");
    let tx = request_tx.clone();
    let plan_interaction = Arc::clone(plan_interaction);
    let pending_ref = pending;
    let next_request_ref = next_request;
    let thread_id_ref = thread_id;
    let turn_id_ref = turn_id;
    let pending = Arc::clone(pending_ref);
    let next_request = Arc::clone(next_request_ref);
    let thread_id = Arc::clone(thread_id_ref);
    let turn_id = Arc::clone(turn_id_ref);
    let callback: PermissionCallback = Arc::new(move |tool_name, input, context| {
        let tx = tx.clone();
        let pending = Arc::clone(&pending);
        let next_request = Arc::clone(&next_request);
        let thread_id = Arc::clone(&thread_id);
        let turn_id = Arc::clone(&turn_id);
        let plan_interaction = Arc::clone(&plan_interaction);
        Box::pin(async move {
            // In Alera's plan mode the turn ends with the proposed plan, which the
            // mapping already shows; approving ExitPlanMode would start editing.
            if tool_name == "ExitPlanMode" && plan_interaction.load(Ordering::SeqCst) {
                return Ok(PermissionResult::deny(PLAN_CAPTURED_MESSAGE));
            }
            let request_id = format!(
                "claude-request-{}",
                next_request.fetch_add(1, Ordering::Relaxed) + 1
            );
            let request_kind = if tool_name == "AskUserQuestion" {
                RequestKind::ToolUserInput
            } else {
                RequestKind::PermissionApproval
            };
            let questions = if request_kind == RequestKind::ToolUserInput {
                input
                    .get("questions")
                    .and_then(Value::as_array)
                    .map(|values| {
                        values
                            .iter()
                            .enumerate()
                            .filter_map(|(index, value)| {
                                let mut object = value.as_object()?.clone();
                                let stable_id = object
                                    .get("id")
                                    .and_then(Value::as_str)
                                    .or_else(|| object.get("header").and_then(Value::as_str))
                                    .or_else(|| object.get("question").and_then(Value::as_str))
                                    .map(str::to_owned)
                                    .unwrap_or_else(|| format!("question-{index}"));
                                object.insert("id".into(), Value::String(stable_id));
                                serde_json::from_value(Value::Object(object)).ok()
                            })
                            .collect()
                    })
                    .unwrap_or_default()
            } else {
                Vec::new()
            };
            let native_request_id = nonempty_string(&context.control.request_id);
            let raw = nonnull_raw(&context.control.raw, &input);
            let context_value = serde_json::to_value(&context).unwrap_or(Value::Null);
            // Full access never asks unless an ask rule or Claude's own check
            // does, so such an approval says which one.
            let full_access = bypass_permissions && !plan_interaction.load(Ordering::SeqCst);
            let mut payload = json!({
                "toolName": tool_name,
                "input": input,
                "context": context_value,
                "requestType": request_kind,
            });
            if let Some(reason) = approval_reason(&context) {
                payload["reason"] = Value::String(reason);
            }
            if full_access {
                payload["fullAccessOverride"] = Value::String(
                    if context.matched_ask_rule.is_some() {
                        "ask_rule"
                    } else {
                        "provider_check"
                    }
                    .into(),
                );
            }
            let request = RuntimeRequest {
                request_id: RequestId::from(request_id.clone()),
                thread_id: thread_id.lock().await.clone().unwrap_or_default(),
                turn_id: turn_id.lock().await.clone(),
                item_id: context.tool_use_id.clone(),
                kind: request_kind,
                questions,
                payload,
                // Claude passes a deny message to the agent that asked, so a
                // decline can explain what to do instead. Questions are
                // answered, not declined.
                supports_feedback: request_kind != RequestKind::ToolUserInput,
            };
            let (sender, receiver) = oneshot::channel();
            pending.lock().await.insert(
                request_id.clone(),
                PendingResponse::Permission {
                    sender,
                    request: request.clone(),
                    native_request_id: native_request_id.clone(),
                },
            );
            let response = match timeout(CALLBACK_TIMEOUT, async {
                tx.send(RequestNotice {
                    request,
                    source: PERMISSION_SOURCE,
                    raw,
                    native_request_id,
                })
                .await
                .map_err(|_| ClaudeSdkError::Callback("provider request queue is closed".into()))?;
                receiver
                    .await
                    .map_err(|_| ClaudeSdkError::Callback("provider response was dropped".into()))
            })
            .await
            {
                Ok(Ok(response)) => response,
                Ok(Err(error)) => {
                    pending.lock().await.remove(&request_id);
                    return Err(error);
                }
                Err(_) => {
                    pending.lock().await.remove(&request_id);
                    return Err(ClaudeSdkError::Timeout {
                        operation: "permission callback".into(),
                        timeout_ms: CALLBACK_TIMEOUT.as_millis() as u64,
                    });
                }
            };
            permission_result(response, &tool_name, &input)
        })
    });
    options.permission_callback = Some(callback);

    let tx = request_tx.clone();
    let pending = Arc::clone(pending_ref);
    let next_request = Arc::clone(next_request_ref);
    let thread_id = Arc::clone(thread_id_ref);
    let turn_id = Arc::clone(turn_id_ref);
    let callback: McpCallbackWithContext = Arc::new(move |server_name, message, context| {
        let tx = tx.clone();
        let pending = Arc::clone(&pending);
        let next_request = Arc::clone(&next_request);
        let thread_id = Arc::clone(&thread_id);
        let turn_id = Arc::clone(&turn_id);
        Box::pin(async move {
            let request_id = format!(
                "claude-request-{}",
                next_request.fetch_add(1, Ordering::Relaxed) + 1
            );
            let request = RuntimeRequest {
                request_id: RequestId::from(request_id.clone()),
                thread_id: thread_id.lock().await.clone().unwrap_or_default(),
                turn_id: turn_id.lock().await.clone(),
                item_id: None,
                kind: RequestKind::DynamicToolCall,
                questions: Vec::new(),
                payload: json!({
                    "serverName": server_name,
                    "message": message,
                    "requestType": RequestKind::DynamicToolCall,
                }),
                supports_feedback: false,
            };
            let native_request_id = nonempty_string(&context.request_id);
            let raw = nonnull_raw(&context.raw, &message);
            let (sender, receiver) = oneshot::channel();
            pending.lock().await.insert(
                request_id.clone(),
                PendingResponse::Mcp {
                    sender,
                    request: request.clone(),
                    native_request_id: native_request_id.clone(),
                },
            );
            let response = match timeout(CALLBACK_TIMEOUT, async {
                tx.send(RequestNotice {
                    request,
                    source: MCP_SOURCE,
                    raw,
                    native_request_id,
                })
                .await
                .map_err(|_| ClaudeSdkError::Callback("provider request queue is closed".into()))?;
                receiver
                    .await
                    .map_err(|_| ClaudeSdkError::Callback("provider response was dropped".into()))
            })
            .await
            {
                Ok(Ok(response)) => response,
                Ok(Err(error)) => {
                    pending.lock().await.remove(&request_id);
                    return Err(error);
                }
                Err(_) => {
                    pending.lock().await.remove(&request_id);
                    return Err(ClaudeSdkError::Timeout {
                        operation: "MCP callback".into(),
                        timeout_ms: CALLBACK_TIMEOUT.as_millis() as u64,
                    });
                }
            };
            mcp_result(response)
        })
    });
    options.mcp_callback = None;
    options.mcp_callback_with_context = Some(callback);
}

fn permission_result(
    response: RuntimeResponse,
    tool_name: &str,
    input: &Value,
) -> Result<PermissionResult, ClaudeSdkError> {
    match response {
        RuntimeResponse::Approval {
            decision,
            updated_input,
            feedback,
            ..
        } => {
            let feedback = feedback
                .map(|feedback| feedback.trim().to_owned())
                .filter(|feedback| !feedback.is_empty());
            match decision {
                ApprovalDecision::Accept
                | ApprovalDecision::AcceptForSession
                | ApprovalDecision::AcceptAlways => Ok(PermissionResult::Allow {
                    updated_input: updated_input.or_else(|| Some(input.clone())),
                    updated_permissions: None,
                }),
                ApprovalDecision::Decline => {
                    Ok(PermissionResult::deny(feedback.unwrap_or_else(|| {
                        format!("permission denied for {tool_name}")
                    })))
                }
                ApprovalDecision::Cancel => Ok(PermissionResult::Deny {
                    message: feedback
                        .unwrap_or_else(|| format!("permission cancelled for {tool_name}")),
                    interrupt: true,
                }),
            }
        }
        RuntimeResponse::UserInput { answers, .. } => Ok(PermissionResult::Allow {
            updated_input: Some(json!({ "answers": answers })),
            updated_permissions: None,
        }),
        _ => Err(ClaudeSdkError::Callback(
            "response kind does not match Claude permission request".into(),
        )),
    }
}

fn mcp_result(response: RuntimeResponse) -> Result<Option<Value>, ClaudeSdkError> {
    match response {
        RuntimeResponse::Native { result, .. } => Ok(Some(result)),
        RuntimeResponse::Elicitation { .. } => Err(ClaudeSdkError::Callback(
            "MCP JSON-RPC requests require a Native response, not Elicitation".into(),
        )),
        _ => Err(ClaudeSdkError::Callback(
            "response kind does not match MCP request".into(),
        )),
    }
}

/// Claude's decision reason without terminal escapes, unless it only repeats
/// the prompt already shown.
fn approval_reason(context: &claude_agent_sdk::ToolPermissionContext) -> Option<String> {
    let reason = strip_terminal_controls(context.decision_reason.as_deref()?);
    let reason = reason.trim();
    let repeats = [&context.title, &context.description]
        .into_iter()
        .flatten()
        .any(|prompt| prompt.trim() == reason);
    (!reason.is_empty() && !repeats).then(|| reason.to_owned())
}

/// Drops ANSI escape sequences and other control characters, keeping line
/// breaks and tabs.
fn strip_terminal_controls(text: &str) -> String {
    let mut out = String::with_capacity(text.len());
    let mut chars = text.chars().peekable();
    while let Some(c) = chars.next() {
        match c {
            '\u{1b}' => match chars.peek() {
                // CSI: parameters and intermediates up to a final byte.
                Some('[') => {
                    chars.next();
                    for c in chars.by_ref() {
                        if ('\u{40}'..='\u{7e}').contains(&c) {
                            break;
                        }
                    }
                }
                // OSC: up to BEL or ST.
                Some(']') => {
                    chars.next();
                    while let Some(c) = chars.next() {
                        if c == '\u{7}' || (c == '\u{1b}' && chars.next_if_eq(&'\\').is_some()) {
                            break;
                        }
                    }
                }
                _ => {
                    chars.next();
                }
            },
            '\n' | '\t' => out.push(c),
            c if c.is_control() => {}
            c => out.push(c),
        }
    }
    out
}

fn nonempty_string(value: &str) -> Option<String> {
    (!value.is_empty()).then(|| value.to_owned())
}

fn nonnull_raw(raw: &Value, fallback: &Value) -> Value {
    if raw.is_null() {
        fallback.clone()
    } else {
        raw.clone()
    }
}

#[cfg(test)]
mod tests {
    use super::strip_terminal_controls;

    #[test]
    fn terminal_controls_are_stripped_from_reasons() {
        assert_eq!(
            strip_terminal_controls(
                "\u{1b}[1;31mrm\u{1b}[0m matches\u{7} rule\u{1b}]8;;https://x\u{1b}\\\nnext"
            ),
            "rm matches rule\nnext"
        );
    }
}
