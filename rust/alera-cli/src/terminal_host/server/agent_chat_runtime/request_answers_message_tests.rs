use serde_json::{json, Value};

use super::*;

fn questions() -> Vec<Value> {
    vec![
        json!({"id": "target", "question": "Which target?", "options": [{"label": "Staging"}]}),
        json!({"id": "checks", "question": "Which checks?", "multiSelect": true}),
        json!({"id": "note", "question": "Anything else?", "required": false}),
    ]
}

fn text(answers: Value) -> HostResult<String> {
    message_answer_text(&questions(), answers.as_object().unwrap())
}

fn code(error: HostError) -> String {
    error.wire_response(1)["errorCode"]
        .as_str()
        .unwrap()
        .to_owned()
}

#[test]
fn answers_become_question_and_answer_blocks() {
    let answer = text(json!({
        "target": " Preview ",
        "checks": {"answers": ["Lint", "Typecheck"]},
        "note": "",
    }))
    .unwrap();
    assert_eq!(
        answer,
        "Which target?\nPreview\n\nWhich checks?\nLint, Typecheck"
    );
    let with_note = text(json!({"target": "Staging", "checks": ["Lint"], "note": "Ship it"}));
    assert!(with_note.unwrap().ends_with("Anything else?\nShip it"));
}

#[test]
fn blank_unknown_and_partial_answers_are_rejected() {
    for answers in [
        json!({"target": "Staging", "checks": ["Lint"], "other": "x"}),
        json!({"target": "", "checks": ["Lint"]}),
        json!({"target": "Staging", "checks": []}),
        json!({"target": "Staging", "checks": ["Lint", " "]}),
        json!({"target": "Staging"}),
        json!({"target": 3, "checks": ["Lint"]}),
        json!({"note": ""}),
    ] {
        let error = text(answers.clone()).unwrap_err();
        assert_eq!(code(error), "invalidAnswers", "{answers}");
    }
}

#[test]
fn only_optional_questions_left_blank_send_nothing() {
    let questions = vec![json!({"id": "note", "question": "Anything?", "required": false})];
    let error =
        message_answer_text(&questions, json!({"note": ""}).as_object().unwrap()).unwrap_err();
    assert_eq!(code(error), "invalidAnswers");
}
