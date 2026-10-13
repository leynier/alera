use alera_provider_protocol::{UserInputOption, UserInputQuestion};
use serde_json::Value;

pub(crate) fn extract_questions(params: &Value) -> Vec<UserInputQuestion> {
    if let Some(questions) = params.get("questions").and_then(Value::as_array) {
        return questions
            .iter()
            .enumerate()
            .map(|(index, question)| {
                let id = question
                    .get("id")
                    .and_then(Value::as_str)
                    .map(ToOwned::to_owned)
                    .unwrap_or_else(|| format!("question-{}", index + 1));
                let text = question
                    .get("question")
                    .or_else(|| question.get("prompt"))
                    .and_then(Value::as_str)
                    .unwrap_or(&id)
                    .to_owned();
                let options = question
                    .get("options")
                    .and_then(Value::as_array)
                    .map(|values| {
                        values
                            .iter()
                            .filter_map(|option| {
                                let label = option
                                    .get("label")
                                    .or_else(|| option.get("name"))
                                    .or_else(|| option.get("value"))
                                    .and_then(Value::as_str)?
                                    .to_owned();
                                Some(UserInputOption {
                                    description: option
                                        .get("description")
                                        .and_then(Value::as_str)
                                        .unwrap_or(&label)
                                        .to_owned(),
                                    value: option
                                        .get("id")
                                        .or_else(|| option.get("value"))
                                        .and_then(Value::as_str)
                                        .map(ToOwned::to_owned),
                                    label,
                                })
                            })
                            .collect()
                    })
                    .unwrap_or_default();
                UserInputQuestion {
                    id,
                    header: question
                        .get("header")
                        .or_else(|| question.get("title"))
                        .and_then(Value::as_str)
                        .unwrap_or("Answer")
                        .to_owned(),
                    question: text,
                    options,
                    allow_custom_answer: Some(true),
                    initial_answer: question
                        .get("initialAnswer")
                        .and_then(Value::as_str)
                        .map(ToOwned::to_owned),
                    multi_select: question
                        .get("multiSelect")
                        .and_then(Value::as_bool)
                        .unwrap_or(false),
                }
            })
            .collect();
    }
    params
        .get("requestedSchema")
        .and_then(|schema| schema.get("properties"))
        .and_then(Value::as_object)
        .into_iter()
        .flatten()
        .map(|(id, schema)| UserInputQuestion {
            id: id.clone(),
            header: schema
                .get("title")
                .and_then(Value::as_str)
                .unwrap_or(id)
                .to_owned(),
            question: schema
                .get("description")
                .and_then(Value::as_str)
                .unwrap_or(id)
                .to_owned(),
            options: Vec::new(),
            allow_custom_answer: Some(true),
            initial_answer: None,
            multi_select: false,
        })
        .collect()
}
