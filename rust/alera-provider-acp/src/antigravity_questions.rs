//! Antigravity asks its questions through `session/request_permission` with a
//! `toolCall.toolCallId` of `interaction_*`; its options are answers, not
//! approvals. Ported from T3 Code's `AntigravityProtocol.ts`.

use alera_provider_protocol::{
    ProviderError, UserInputAnswers, UserInputOption, UserInputQuestion,
};
use serde_json::{json, Value};

const QUESTION_TEXT_LIMIT: usize = 8_000;
const QUESTION_LABEL_LIMIT: usize = 512;

fn bounded(text: &str, limit: usize) -> String {
    if text.chars().count() <= limit {
        return text.to_owned();
    }
    let mut cut: String = text.chars().take(limit - 3).collect();
    cut.push_str("...");
    cut
}

fn tool_call_id(params: &Value) -> Option<&str> {
    params
        .pointer("/toolCall/toolCallId")
        .and_then(Value::as_str)
        .filter(|id| id.starts_with("interaction_"))
}

fn options(params: &Value) -> Option<&Vec<Value>> {
    params
        .get("options")
        .and_then(Value::as_array)
        .filter(|options| !options.is_empty())
}

fn option_id(option: &Value) -> Option<&str> {
    option.get("optionId").and_then(Value::as_str)
}

fn label(option: &Value) -> String {
    let name = option
        .get("name")
        .and_then(Value::as_str)
        .map(str::trim)
        .filter(|name| !name.is_empty());
    bounded(
        name.or_else(|| option_id(option)).unwrap_or_default(),
        QUESTION_LABEL_LIMIT,
    )
}

/// The single-choice question of an Antigravity `interaction_*` permission
/// request, or `None` when it is an approval or a malformed question: no
/// options, or a blank or repeated `optionId`.
pub(crate) fn antigravity_question(params: &Value) -> Option<UserInputQuestion> {
    let id = tool_call_id(params)?;
    let options = options(params)?;
    let mut ids: Vec<&str> = Vec::new();
    for option in options {
        let option_id = option_id(option).filter(|id| !id.trim().is_empty())?;
        if ids.contains(&option_id) {
            return None;
        }
        ids.push(option_id);
    }
    let question = params
        .pointer("/toolCall/title")
        .and_then(Value::as_str)
        .map(str::trim)
        .filter(|title| !title.is_empty())
        .unwrap_or("Choose an option.");
    Some(UserInputQuestion {
        id: id.to_owned(),
        header: "Question".into(),
        question: bounded(question, QUESTION_TEXT_LIMIT),
        options: options
            .iter()
            .map(|option| UserInputOption {
                label: label(option),
                description: label(option),
                value: option_id(option).map(str::to_owned),
            })
            .collect(),
        allow_custom_answer: Some(false),
        initial_answer: None,
        multi_select: false,
    })
}

/// The permission response that answers an Antigravity question. The answer
/// is an `optionId`, or a label only one option carries; no answers at all
/// (Skip) cancels. Anything else is refused and the question stays open.
pub(crate) fn antigravity_question_response(
    params: &Value,
    answers: &UserInputAnswers,
) -> Result<Value, ProviderError> {
    let question = antigravity_question(params).ok_or_else(|| {
        ProviderError::Validation("Antigravity question request is malformed".into())
    })?;
    if answers.is_empty() {
        return Ok(json!({"outcome":{"outcome":"cancelled"}}));
    }
    let answer = match answers.get(&question.id) {
        Some(Value::String(answer)) => Some(answer.as_str()),
        Some(Value::Array(values)) if values.len() == 1 => values[0].as_str(),
        _ => None,
    }
    .ok_or_else(|| ProviderError::Validation("Choose one of the question's options.".into()))?;
    let options = options(params).expect("validated question options");
    if let Some(exact) = options
        .iter()
        .find(|option| option_id(option) == Some(answer))
    {
        return Ok(json!({"outcome":{"outcome":"selected","optionId":option_id(exact)}}));
    }
    let labelled: Vec<&Value> = options
        .iter()
        .filter(|option| label(option) == answer)
        .collect();
    match labelled.as_slice() {
        [only] => Ok(json!({"outcome":{"outcome":"selected","optionId":option_id(only)}})),
        _ => Err(ProviderError::Validation(
            "Choose one of the question's options.".into(),
        )),
    }
}
