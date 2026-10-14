use agent_client_protocol::AcpError;
use alera_provider_protocol::{ApprovalDecision, ProviderError, UserInputAnswers};
use serde_json::{json, Value};
use std::collections::BTreeMap;

pub(crate) fn permission_response(
    params: &Value,
    decision: ApprovalDecision,
) -> Result<Value, ProviderError> {
    if matches!(decision, ApprovalDecision::Cancel) {
        return Ok(json!({"outcome":{"outcome":"cancelled"}}));
    }
    let options = params
        .get("options")
        .and_then(Value::as_array)
        .ok_or_else(|| ProviderError::Validation("ACP permission request lacks options".into()))?;
    let wanted = match decision {
        ApprovalDecision::Accept => ["allow_once", "allow_always"].as_slice(),
        ApprovalDecision::AcceptForSession | ApprovalDecision::AcceptAlways => {
            ["allow_always", "allow_once"].as_slice()
        }
        ApprovalDecision::Decline => ["reject_once", "reject_always"].as_slice(),
        ApprovalDecision::Cancel => unreachable!(),
    };
    let option = wanted
        .iter()
        .find_map(|kind| {
            options
                .iter()
                .find(|option| option.get("kind").and_then(Value::as_str) == Some(*kind))
        })
        .and_then(|option| option.get("optionId"))
        .and_then(Value::as_str)
        .ok_or_else(|| ProviderError::Validation("ACP permission option lacks optionId".into()))?;
    Ok(json!({"outcome":{"outcome":"selected","optionId":option}}))
}

pub(crate) fn grok_permission_response(
    params: &Value,
    decision: ApprovalDecision,
) -> Result<Value, ProviderError> {
    if matches!(decision, ApprovalDecision::Cancel) {
        return Ok(json!({"outcome":{"outcome":"cancelled"}}));
    }
    let options = params
        .get("options")
        .and_then(Value::as_array)
        .ok_or_else(|| ProviderError::Validation("ACP permission request lacks options".into()))?;
    let option = match decision {
        ApprovalDecision::Accept => options
            .iter()
            .find(|option| option.get("kind").and_then(Value::as_str) == Some("allow_once")),
        ApprovalDecision::AcceptForSession => options.iter().find(|option| {
            option.get("kind").and_then(Value::as_str) == Some("allow_always")
                && option.get("optionId").and_then(Value::as_str) == Some("allow-edits-session")
        }),
        ApprovalDecision::AcceptAlways => options
            .iter()
            .find(|option| option.get("kind").and_then(Value::as_str) == Some("allow_always")),
        ApprovalDecision::Decline => options
            .iter()
            .find(|option| option.get("kind").and_then(Value::as_str) == Some("reject_once")),
        ApprovalDecision::Cancel => unreachable!(),
    };
    let option_id = option
        .and_then(|option| option.get("optionId"))
        .and_then(Value::as_str)
        .ok_or_else(|| {
            ProviderError::Validation("requested Grok permission scope is unavailable".into())
        })?;
    Ok(json!({"outcome":{"outcome":"selected","optionId":option_id}}))
}

pub(crate) fn user_input_response(answers: UserInputAnswers) -> Value {
    let answers = answers
        .into_iter()
        .map(|(id, value)| {
            let values = match value {
                Value::Array(values) => values.into_iter().map(string_answer).collect::<Vec<_>>(),
                value => vec![string_answer(value)],
            };
            (id, Value::Array(values))
        })
        .collect::<BTreeMap<_, _>>();
    json!({"outcome":"accepted","answers":answers})
}

pub(crate) fn xai_user_input_response(
    params: &Value,
    answers: UserInputAnswers,
) -> Result<Value, ProviderError> {
    let questions = params
        .get("questions")
        .and_then(Value::as_array)
        .ok_or_else(|| ProviderError::Validation("x.ai question request lacks questions".into()))?;
    let mut normalized = serde_json::Map::new();
    for question in questions {
        let text = question
            .get("question")
            .and_then(Value::as_str)
            .ok_or_else(|| ProviderError::Validation("x.ai question lacks question text".into()))?;
        let key = question.get("id").and_then(Value::as_str).unwrap_or(text);
        let Some(answer) = answers.get(key).or_else(|| answers.get(text)) else {
            continue;
        };
        let values = match answer {
            Value::Array(values) => values.clone(),
            value => vec![value.clone()],
        };
        let labels = values
            .into_iter()
            .filter_map(|value| value.as_str().map(ToOwned::to_owned))
            .map(|value| {
                question
                    .get("options")
                    .and_then(Value::as_array)
                    .and_then(|options| {
                        options.iter().find_map(|option| {
                            let label = option.get("label").and_then(Value::as_str)?;
                            let option_id = option
                                .get("id")
                                .or_else(|| option.get("value"))
                                .and_then(Value::as_str);
                            (label == value || option_id == Some(value.as_str()))
                                .then(|| label.to_owned())
                        })
                    })
                    .unwrap_or_else(|| "Other".into())
            })
            .collect::<Vec<_>>();
        if !labels.is_empty() {
            normalized.insert(
                text.into(),
                Value::Array(labels.into_iter().map(Value::String).collect()),
            );
        }
    }
    Ok(json!({"outcome":"accepted","answers":normalized}))
}

pub(crate) fn cancelled_response(pending: &crate::transport::PendingRequest) -> Value {
    match pending.kind {
        alera_provider_protocol::RequestKind::CommandExecutionApproval
        | alera_provider_protocol::RequestKind::FileChangeApproval
        | alera_provider_protocol::RequestKind::FileReadApproval
        | alera_provider_protocol::RequestKind::PermissionApproval
        | alera_provider_protocol::RequestKind::ApplyPatchApproval
        | alera_provider_protocol::RequestKind::ExecCommandApproval
        | alera_provider_protocol::RequestKind::DynamicToolCall => {
            json!({"outcome":{"outcome":"cancelled"}})
        }
        alera_provider_protocol::RequestKind::ToolUserInput => json!({"outcome":"cancelled"}),
        alera_provider_protocol::RequestKind::McpElicitationApproval => {
            json!({"action":"cancel","content":null})
        }
        alera_provider_protocol::RequestKind::AuthTokensRefresh
        | alera_provider_protocol::RequestKind::Unknown => Value::Null,
    }
}

fn string_answer(value: Value) -> Value {
    match value {
        Value::String(value) => Value::String(value),
        Value::Null => Value::String(String::new()),
        value => Value::String(value.to_string()),
    }
}

pub(crate) fn acp_error(error: AcpError) -> ProviderError {
    match error {
        AcpError::Transport(error) => ProviderError::Transport(error),
        AcpError::Rpc {
            code,
            message,
            data,
        } => ProviderError::Rpc {
            code,
            message,
            data,
        },
        AcpError::Timeout { method, .. } => ProviderError::Timeout { operation: method },
        AcpError::Closed => ProviderError::Closed,
        AcpError::Json(error) => ProviderError::Protocol(error.to_string()),
        AcpError::Protocol(error) | AcpError::Unsupported(error) => ProviderError::Protocol(error),
        AcpError::QueueFull { capacity } => {
            ProviderError::Protocol(format!("ACP incoming queue full at {capacity}"))
        }
    }
}
