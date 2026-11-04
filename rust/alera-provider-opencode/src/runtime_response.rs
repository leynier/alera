use crate::provider::{timed, OpenCodeProvider};
use alera_provider_protocol::{
    ApprovalDecision, EventKind, ProviderError, ProviderEvent, RequestKind, RuntimeResponse,
};
use opencode_agent_sdk::HttpTransport;
use serde_json::{json, Value};

pub(crate) async fn respond<T: HttpTransport>(
    provider: &mut OpenCodeProvider<T>,
    response: RuntimeResponse,
) -> Result<(), ProviderError> {
    provider.ensure_open()?;
    let request_id = response.request_id().to_string();
    let pending = provider
        .pending
        .remove(&request_id)
        .ok_or_else(|| ProviderError::InvalidState("unknown OpenCode runtime request id".into()))?;
    match response {
        RuntimeResponse::Approval { decision, .. } => {
            if !matches!(
                pending.kind,
                RequestKind::CommandExecutionApproval
                    | RequestKind::FileReadApproval
                    | RequestKind::FileChangeApproval
                    | RequestKind::PermissionApproval
            ) {
                provider.pending.insert(request_id.clone(), pending);
                return Err(ProviderError::Validation(
                    "OpenCode approval response does not match request".into(),
                ));
            }
            if let Err(error) = timed(
                provider.config.request_timeout,
                "permission.reply",
                provider.client.permission_reply(
                    &pending.native_session_id,
                    &pending.native_id,
                    approval_reply(decision, provider.client.config().generation),
                ),
            )
            .await
            {
                provider.pending.insert(request_id.clone(), pending);
                return Err(error);
            }
        }
        RuntimeResponse::UserInput { answers, .. } => {
            if pending.kind != RequestKind::ToolUserInput {
                provider.pending.insert(request_id.clone(), pending);
                return Err(ProviderError::Validation(
                    "OpenCode user input response does not match request".into(),
                ));
            }
            let values = pending
                .questions
                .iter()
                .map(|question| {
                    let value = answers
                        .get(&question.id)
                        .or_else(|| answers.get(&question.header))
                        .or_else(|| answers.get(&question.question))
                        .cloned()
                        .unwrap_or(Value::Null);
                    let value = if pending.is_form {
                        form_answer(value, question.multi_select)
                    } else {
                        Value::Array(match value {
                            Value::Array(values) => values
                                .into_iter()
                                .filter_map(|value| value.as_str().map(str::to_owned))
                                .map(Value::String)
                                .collect(),
                            Value::String(value) => vec![Value::String(value)],
                            _ => Vec::new(),
                        })
                    };
                    (question.id.clone(), value)
                })
                .collect();
            let reply = async {
                if pending.is_form {
                    provider
                        .client
                        .form_reply(&pending.native_session_id, &pending.native_id, values)
                        .await
                } else {
                    let values = values
                        .into_iter()
                        .map(|(question_id, value)| {
                            let values = match value {
                                Value::Array(values) => values
                                    .into_iter()
                                    .filter_map(|value| value.as_str().map(str::to_owned))
                                    .collect(),
                                Value::String(value) => vec![value],
                                _ => Vec::new(),
                            };
                            (question_id, values)
                        })
                        .collect();
                    provider
                        .client
                        .question_reply(&pending.native_session_id, &pending.native_id, values)
                        .await
                }
            };
            if let Err(error) = timed(provider.config.request_timeout, "form.reply", reply).await {
                provider.pending.insert(request_id.clone(), pending);
                return Err(error);
            }
        }
        RuntimeResponse::Native { result, .. } => {
            provider.pending.insert(request_id.clone(), pending);
            return Err(ProviderError::Unsupported(format!(
                "OpenCode native request relay is not implemented: {result}"
            )));
        }
        RuntimeResponse::Elicitation { .. } => {
            provider.pending.insert(request_id.clone(), pending);
            return Err(ProviderError::Unsupported(
                "OpenCode MCP elicitation is not exposed by this adapter".into(),
            ));
        }
    }
    let mut resolved = ProviderEvent::new(
        OpenCodeProvider::<T>::provider_kind(),
        provider.config.provider_instance_id.clone(),
        pending.thread_id.clone(),
        EventKind::RequestResolved,
        json!({ "requestType": pending.kind }),
        None,
    );
    resolved.request_id = Some(request_id);
    resolved.turn_id = pending.turn_id;
    resolved.validate()?;
    provider.queued_events.push_back(resolved);
    Ok(())
}

fn approval_reply(
    decision: ApprovalDecision,
    generation: opencode_agent_sdk::Generation,
) -> &'static str {
    match decision {
        ApprovalDecision::Accept => "once",
        ApprovalDecision::AcceptForSession | ApprovalDecision::AcceptAlways
            if generation == opencode_agent_sdk::Generation::Legacy1 =>
        {
            "always"
        }
        ApprovalDecision::AcceptForSession | ApprovalDecision::AcceptAlways => "once",
        ApprovalDecision::Decline | ApprovalDecision::Cancel => "reject",
    }
}

fn form_answer(value: Value, multi_select: bool) -> Value {
    if multi_select {
        return match value {
            Value::Array(values) => Value::Array(values),
            Value::String(value) => Value::Array(vec![Value::String(value)]),
            other => other,
        };
    }
    match value {
        Value::Array(mut values) => values.drain(..).next().unwrap_or(Value::Null),
        other => other,
    }
}
