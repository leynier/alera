use serde_json::{Value, json};

pub(super) fn text(props: &Value, key: &str, fallback: &str) -> String {
    props[key].as_str().filter(|value| !value.trim().is_empty()).unwrap_or(fallback).to_owned()
}

pub(super) fn display(value: &Value) -> String {
    if value.is_null() { return String::new(); }
    display_nested(value)
}

fn display_nested(value: &Value) -> String {
    match value {
        Value::String(value) => value.clone(),
        Value::Array(items) => format!("[{}]", items.iter().map(display_nested).collect::<Vec<_>>().join(", ")),
        Value::Object(items) => format!("{{{}}}", items.iter().map(|(key, value)| format!("{key}: {}", display_nested(value))).collect::<Vec<_>>().join(", ")),
        _ => value.to_string(),
    }
}

pub(super) fn decision_action(canvas: &Value, props: &Value, resolution: &Value) -> Option<Value> {
    let explicit_id = props["id"].as_str().filter(|id| !id.trim().is_empty());
    let question = props["question"].as_str().unwrap_or_default();
    let id = explicit_id.filter(|id| canvas["decisions"].as_array().is_some_and(|decisions| decisions.iter().any(|decision| decision["id"] == *id))).or_else(|| {
        if explicit_id.is_some() { return None; }
        canvas["decisions"].as_array()?.iter().find(|decision| {
            decision["state"] == "pending" && decision["revision"] == canvas["revision"]
                && (question.is_empty() || decision["question"] == question)
        })?["id"].as_str()
    })?;
    Some(json!({"kind":"resolveDecision", "decisionId":id, "resolution":resolution, "confirmed":true}))
}

pub(super) fn typed_action(value: &Value) -> Option<Value> {
    let object = value.get("action").and_then(Value::as_object).or_else(|| value.as_object())?;
    let mut action = object.clone();
    action.remove("label");
    // A published document cannot supply the user's confirmation.
    action.remove("confirmed");
    action.get("kind")?.as_str()?;
    Some(Value::Object(action))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn agent_canvas_decision_preserves_structured_resolution_and_current_revision() {
        let canvas = json!({"revision":3,"decisions":[
            {"id":"old","revision":2,"state":"pending","question":"Pick"},
            {"id":"resolved","revision":3,"state":"resolved","question":"Pick"},
            {"id":"current","revision":3,"state":"pending","question":"Pick"}
        ]});
        let option = json!({"label":"Editor","value":"editor"});
        let action = decision_action(&canvas, &json!({"question":"Pick"}), &option).unwrap();
        assert_eq!(action["decisionId"], "current");
        assert_eq!(action["resolution"], option);
        assert!(decision_action(&canvas, &json!({"question":"Unknown"}), &option).is_none());
        assert_eq!(decision_action(&canvas, &json!({"id":"resolved"}), &option).unwrap()["decisionId"], "resolved");
        assert!(decision_action(&canvas, &json!({"id":"another-canvas-decision"}), &option).is_none());
    }

    #[test]
    fn agent_canvas_typed_action_unwraps_payload_but_never_document_confirmation() {
        assert_eq!(typed_action(&json!({"label":"Open","action":{"kind":"openFile","relativePath":"readme.md","confirmed":true}})),
            Some(json!({"kind":"openFile","relativePath":"readme.md"})));
        assert_eq!(typed_action(&json!({"label":"Search","kind":"openSearch"})), Some(json!({"kind":"openSearch"})));
        assert!(typed_action(&json!({"label":"Invalid"})).is_none());
    }
}
