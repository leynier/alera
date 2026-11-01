use crate::provider::CodexProvider;
use crate::wire;
use alera_agent_transport::JsonTransport;
use alera_provider_protocol::{
    ApprovalDecision, ElicitationAction, ProviderError, RuntimeResponse, SessionStatus,
    UserInputAnswers,
};
use serde_json::{json, Map, Value};

impl<T: JsonTransport> CodexProvider<T> {
    /// Answers the pending native request a runtime response names.
    pub(crate) async fn respond_runtime(
        &mut self,
        response: RuntimeResponse,
    ) -> Result<(), ProviderError> {
        self.ensure_open()?;
        let request_id = response.request_id().clone();
        let (rpc_id, method, allowance) = self
            .pending_requests
            .get(&request_id)
            .ok_or_else(|| ProviderError::InvalidState("unknown Codex runtime request id".into()))
            .map(|pending| {
                (
                    pending.rpc_id.clone(),
                    pending.method.clone(),
                    pending.allowance.clone(),
                )
            })?;
        let method = method.as_str();
        let matches_method = match &response {
            RuntimeResponse::Native { .. } => true,
            RuntimeResponse::Approval { .. } => matches!(
                method,
                "item/commandExecution/requestApproval"
                    | "item/fileChange/requestApproval"
                    | "item/permissions/requestApproval"
                    | "execCommandApproval"
                    | "applyPatchApproval"
            ),
            RuntimeResponse::UserInput { .. } => method == "item/tool/requestUserInput",
            RuntimeResponse::Elicitation { .. } => method == "mcpServer/elicitation/request",
        };
        if !matches_method {
            return Err(ProviderError::Validation(
                "Codex runtime response variant does not match the pending request".into(),
            ));
        }
        let result = match response {
            RuntimeResponse::Approval {
                decision,
                updated_input,
                ..
            } => {
                if let Some(grant) = &allowance {
                    self.session_approvals.record(grant, decision);
                }
                approval_result(method, decision, updated_input)
            }
            RuntimeResponse::UserInput { answers, .. } => user_input_result(answers),
            RuntimeResponse::Elicitation {
                action, content, ..
            } => elicitation_result(action, content)?,
            RuntimeResponse::Native { result, .. } => result,
        };
        if method == "mcpServer/elicitation/request" {
            if result.get("action").is_none() {
                return Err(ProviderError::Validation(
                    "MCP elicitation requires an action response".into(),
                ));
            }
            let Some(content) = result.get("content") else {
                return Err(ProviderError::Validation(
                    "MCP elicitation response requires content".into(),
                ));
            };
            if !content.is_null() && !content.is_object() {
                return Err(ProviderError::Validation(
                    "MCP elicitation content must be null or an object".into(),
                ));
            }
        }
        self.transport.send(wire::response(&rpc_id, result)).await?;
        self.pending_requests.remove(&request_id);
        if self.pending_requests.is_empty() {
            if let Some(session) = self.session.as_mut() {
                if session.status == SessionStatus::Waiting {
                    session.status = if session.active_turn_id.is_some() {
                        SessionStatus::Running
                    } else {
                        SessionStatus::Ready
                    };
                }
            }
        }
        Ok(())
    }
}

pub(crate) fn approval_result(
    method: &str,
    decision: ApprovalDecision,
    updated_input: Option<Value>,
) -> Value {
    let decision = if crate::session_approvals::is_legacy(method) {
        // The v1 approvals answer with a ReviewDecision instead.
        match decision {
            ApprovalDecision::Accept => json!("approved"),
            ApprovalDecision::AcceptForSession | ApprovalDecision::AcceptAlways => {
                json!("approved_for_session")
            }
            ApprovalDecision::Decline => {
                json!({ "denied": { "rejection": "User declined the request." } })
            }
            ApprovalDecision::Cancel => json!("abort"),
        }
    } else {
        json!(match decision {
            ApprovalDecision::Accept => "accept",
            ApprovalDecision::AcceptForSession | ApprovalDecision::AcceptAlways => {
                "acceptForSession"
            }
            ApprovalDecision::Decline => "decline",
            ApprovalDecision::Cancel => "cancel",
        })
    };
    let mut result = json!({ "decision": decision });
    if let Some(updated_input) = updated_input {
        result["updatedInput"] = updated_input;
    }
    result
}

pub(crate) fn user_input_result(answers: UserInputAnswers) -> Value {
    let answers = answers
        .into_iter()
        .map(|(id, value)| {
            let values = match value {
                Value::Array(values) => values
                    .into_iter()
                    .map(|value| {
                        value
                            .as_str()
                            .map_or_else(|| value.to_string(), str::to_owned)
                    })
                    .collect::<Vec<_>>(),
                Value::String(value) => vec![value],
                Value::Null => Vec::new(),
                value => vec![value.to_string()],
            };
            (id, json!({ "answers": values }))
        })
        .collect::<Map<_, _>>();
    json!({ "answers": answers })
}

pub(crate) fn elicitation_result(
    action: ElicitationAction,
    content: Option<Value>,
) -> Result<Value, ProviderError> {
    let action = match action {
        ElicitationAction::Accept => "accept",
        ElicitationAction::Decline => "decline",
        ElicitationAction::Cancel => "cancel",
    };
    let content = match content {
        None | Some(Value::Null) => Value::Null,
        Some(value) if value.is_object() => value,
        Some(_) => {
            return Err(ProviderError::Validation(
                "MCP elicitation content must be null or an object".into(),
            ));
        }
    };
    Ok(json!({ "action": action, "content": content }))
}
