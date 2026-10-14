use alera_provider_protocol::{
    ApprovalDecision, ElicitationAction, ProviderError, UserInputAnswers,
};
use serde_json::{json, Map, Value};

pub(crate) fn approval_result(decision: ApprovalDecision, updated_input: Option<Value>) -> Value {
    let decision = match decision {
        ApprovalDecision::Accept => "accept",
        ApprovalDecision::AcceptForSession | ApprovalDecision::AcceptAlways => "acceptForSession",
        ApprovalDecision::Decline => "decline",
        ApprovalDecision::Cancel => "cancel",
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
