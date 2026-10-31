//! Checks a person's answers to a user-input request before the request is
//! resolved, since an adapter would otherwise pass unusable answers on to the
//! agent. A rejected answer leaves the request open for another try.

use alera_provider_protocol::UserInputAnswers;
use serde_json::{Map, Value};

use crate::terminal_host::host_error::{HostError, HostResult};

use super::commands::conflict;

fn invalid(message: String) -> HostError {
    conflict("invalidAnswers", message)
}

/// The answer's values: a string, a list of strings, or `{answers: [...]}`.
fn answer_values(question_id: &str, answer: &Value) -> HostResult<Vec<String>> {
    let list = match answer {
        Value::String(text) => return Ok(vec![text.clone()]),
        Value::Array(values) => values,
        Value::Object(object) => match object.get("answers") {
            Some(Value::Array(values)) if object.len() == 1 => values,
            _ => {
                return Err(invalid(format!(
                    "The answer to {question_id:?} must be text or a list of texts."
                )))
            }
        },
        _ => {
            return Err(invalid(format!(
                "The answer to {question_id:?} must be text or a list of texts."
            )))
        }
    };
    list.iter()
        .map(|value| {
            value.as_str().map(str::to_owned).ok_or_else(|| {
                invalid(format!(
                    "The answer to {question_id:?} must be text or a list of texts."
                ))
            })
        })
        .collect()
}

/// The answers to pass to the provider. Every key names a question; every
/// question the person answered gets a nonblank answer, as many as it takes,
/// from its options unless it accepts free text. An empty map skips the
/// request as a whole. A question stored with `required: false` may stay
/// unanswered.
pub(super) fn validated_answers(
    questions: &[Value],
    answers: &Map<String, Value>,
) -> HostResult<UserInputAnswers> {
    if answers.is_empty() {
        return Ok(UserInputAnswers::new());
    }
    let id_of = |question: &Value| {
        question
            .get("id")
            .and_then(Value::as_str)
            .map(str::to_owned)
    };
    if let Some(unknown) = answers.keys().find(|id| {
        !questions
            .iter()
            .any(|q| id_of(q).as_deref() == Some(id.as_str()))
    }) {
        return Err(invalid(format!(
            "This request asks no question {unknown:?}."
        )));
    }
    let mut validated = UserInputAnswers::new();
    for question in questions {
        let Some(id) = id_of(question) else {
            continue;
        };
        let values = match answers.get(&id) {
            Some(answer) => answer_values(&id, answer)?,
            None => Vec::new(),
        };
        let given: Vec<&String> = values
            .iter()
            .filter(|value| !value.trim().is_empty())
            .collect();
        if given.is_empty() {
            if question.get("required") == Some(&Value::Bool(false)) {
                if let Some(answer) = answers.get(&id) {
                    validated.insert(id, answer.clone());
                }
                continue;
            }
            return Err(invalid(format!("Answer the question {id:?}.")));
        }
        let multi_select = question.get("multiSelect").and_then(Value::as_bool) == Some(true);
        if !multi_select && given.len() > 1 {
            return Err(invalid(format!("The question {id:?} takes one answer.")));
        }
        let options = question
            .get("options")
            .and_then(Value::as_array)
            .map(Vec::as_slice)
            .unwrap_or_default();
        // A question without options can only be answered in free text.
        let custom = options.is_empty()
            || question.get("allowCustomAnswer").and_then(Value::as_bool) == Some(true);
        if !custom {
            let offered = |text: &str| {
                options.iter().any(|option| {
                    ["value", "label"]
                        .into_iter()
                        .any(|key| option.get(key).and_then(Value::as_str) == Some(text))
                })
            };
            if let Some(other) = given.iter().find(|value| !offered(value)) {
                return Err(invalid(format!(
                    "{other:?} is not an option of the question {id:?}."
                )));
            }
        }
        let answer = match answers.get(&id) {
            Some(Value::Object(object)) => object["answers"].clone(),
            Some(answer) => answer.clone(),
            None => Value::Null,
        };
        validated.insert(id, answer);
    }
    Ok(validated)
}

#[cfg(test)]
mod tests {
    use serde_json::json;

    use super::*;

    fn questions() -> Vec<Value> {
        vec![
            json!({"id": "target", "question": "Which target?", "options": [
                {"label": "Staging", "description": ""},
                {"label": "Production", "description": "", "value": "prod"},
            ]}),
            json!({"id": "checks", "question": "Which checks?", "multiSelect": true,
                "allowCustomAnswer": true, "options": [{"label": "Lint", "description": ""}]}),
            json!({"id": "note", "question": "Anything else?"}),
        ]
    }

    fn check(answers: Value) -> HostResult<UserInputAnswers> {
        validated_answers(&questions(), answers.as_object().unwrap())
    }

    fn code(error: HostError) -> String {
        error.wire_response(1)["errorCode"]
            .as_str()
            .unwrap()
            .to_owned()
    }

    #[test]
    fn complete_answers_pass_and_the_nested_form_is_flattened() {
        let answers = check(json!({
            "target": "prod",
            "checks": {"answers": ["Lint", "Typecheck"]},
            "note": ["Ship it"],
        }))
        .unwrap();
        assert_eq!(answers["target"], json!("prod"));
        assert_eq!(answers["checks"], json!(["Lint", "Typecheck"]));
        assert_eq!(answers["note"], json!(["Ship it"]));
        // The label also names an option that has a value.
        assert!(check(json!({"target": "Production", "checks": "Lint", "note": "x"})).is_ok());
    }

    #[test]
    fn an_empty_map_skips_the_request() {
        assert!(check(json!({})).unwrap().is_empty());
    }

    #[test]
    fn unusable_answers_are_rejected() {
        for answers in [
            json!({"target": "Staging", "checks": "Lint", "note": "x", "other": "y"}),
            json!({"target": "Staging", "checks": "Lint"}),
            json!({"target": " ", "checks": "Lint", "note": "x"}),
            json!({"target": "Preview", "checks": "Lint", "note": "x"}),
            json!({"target": ["Staging", "prod"], "checks": "Lint", "note": "x"}),
            json!({"target": 3, "checks": "Lint", "note": "x"}),
            json!({"target": {"answers": "Staging"}, "checks": "Lint", "note": "x"}),
        ] {
            let error = check(answers.clone()).unwrap_err();
            assert_eq!(code(error), "invalidAnswers", "{answers}");
        }
    }

    #[test]
    fn an_optional_question_may_stay_unanswered() {
        let questions = vec![
            json!({"id": "a", "question": "A?"}),
            json!({"id": "b", "question": "B?", "required": false}),
        ];
        let answers = validated_answers(&questions, json!({"a": "yes"}).as_object().unwrap());
        assert_eq!(answers.unwrap().len(), 1);
    }
}
