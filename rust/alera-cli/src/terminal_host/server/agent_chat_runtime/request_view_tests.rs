use super::*;

#[test]
fn acp_decisions_follow_the_offered_options() {
    let native = json!({"options": [
        {"kind": "allow_once", "optionId": "a"},
        {"kind": "reject_once", "optionId": "r"},
    ]});
    assert_eq!(
        approval_decisions("acpRegistry", &native),
        vec!["accept", "decline", "cancel"]
    );
    let grok = json!({"options": [
        {"kind": "allow_always", "optionId": "allow-edits-session"},
        {"kind": "allow_always", "optionId": "forever"},
    ]});
    assert_eq!(
        approval_decisions("grok", &grok),
        vec!["acceptForSession", "acceptAlways", "cancel"]
    );
}

#[test]
fn providers_without_session_scope_do_not_offer_it() {
    assert!(!approval_decisions("pi", &json!({})).contains(&"acceptForSession".to_string()));
    assert!(approval_decisions("cursor", &json!({})).is_empty());
}

fn request(kind: RequestKind, questions: Value, payload: Value) -> RuntimeRequest {
    serde_json::from_value(json!({
        "requestId": "native-1", "threadId": "thread", "kind": kind,
        "questions": questions, "payload": payload,
    }))
    .unwrap()
}

fn view(provider: &str, request: &RuntimeRequest, event_payload: &Value) -> ChatRequest {
    build_request_view(
        provider,
        "request-1".into(),
        request,
        event_payload,
        None,
        None,
        "2026-10-31T00:00:00Z",
    )
}

fn choice_question(id: &str) -> Value {
    json!({"id": id, "header": "", "question": "Which approach?", "options": [
        {"label": "Small", "description": ""},
        {"label": "Large", "description": "Rewrite it"},
        {"label": "Other", "description": ""},
    ]})
}

#[test]
fn option_previews_ride_on_their_options() {
    let preview = "\n  **Proposed change**\n\n```ts\n\tconst enabled = true;\n```\n  ";
    let request = request(
        RequestKind::ToolUserInput,
        json!([choice_question("Approach"), choice_question("Other")]),
        json!({USER_INPUT_OPTION_PREVIEWS: {
            "Approach": [null, preview, "   ", "extra"],
            "Other": "not a list",
            "Missing": ["ignored"],
        }}),
    );
    let view = view("claudeAgent", &request, &json!({}));
    let options = view.questions[0]["options"].as_array().unwrap();
    assert!(options[0].get("preview").is_none());
    assert_eq!(options[1]["preview"], preview);
    assert!(options[2].get("preview").is_none());
    assert_eq!(options.len(), 3);
    assert!(view.questions[1]["options"]
        .as_array()
        .unwrap()
        .iter()
        .all(|option| option.get("preview").is_none()));
    assert_eq!(view.questions[0]["id"], "Approach");
}

#[test]
fn long_option_previews_are_clipped_on_a_char_boundary() {
    let long = "é".repeat(MAX_OPTION_PREVIEW_CHARS + 10);
    let request = request(
        RequestKind::ToolUserInput,
        json!([choice_question("Approach")]),
        json!({USER_INPUT_OPTION_PREVIEWS: {"Approach": [long]}}),
    );
    let view = view("claudeAgent", &request, &json!({}));
    let preview = view.questions[0]["options"][0]["preview"].as_str().unwrap();
    assert_eq!(preview.chars().count(), MAX_OPTION_PREVIEW_CHARS);
    assert!(preview.chars().all(|c| c == 'é'));
}

#[test]
fn questions_without_previews_are_unchanged() {
    let request = request(
        RequestKind::ToolUserInput,
        json!([choice_question("Approach")]),
        json!({"input": {}}),
    );
    let view = view("codex", &request, &json!({}));
    let mut expected = choice_question("Approach");
    expected["multiSelect"] = json!(false);
    assert_eq!(view.questions, vec![expected]);
}

#[test]
fn claude_elicitations_keep_their_form() {
    let schema =
        json!({"type": "object", "properties": {"name": {"type": "string"}}, "required": ["name"]});
    let payload = json!({
        "requestType": "mcp_elicitation_approval", "serverName": "github",
        "message": "Who should review this?", "mode": "form", "requestedSchema": schema,
        "elicitationId": "elicit-1", "title": "GitHub needs a reviewer",
    });
    let form = request(
        RequestKind::McpElicitationApproval,
        json!([]),
        payload.clone(),
    );
    let form_view = view("claudeAgent", &form, &payload);
    assert_eq!(form_view.kind, "mcp_elicitation_approval");
    assert_eq!(form_view.title.as_deref(), Some("GitHub needs a reviewer"));
    assert_eq!(form_view.detail.as_deref(), Some("Who should review this?"));
    assert!(form_view.decisions.is_empty());
    assert!(!form_view.supports_feedback);
    assert_eq!(
        form_view.elicitation,
        Some(json!({
            "mode": "form", "message": "Who should review this?", "schema": schema, "url": null,
        }))
    );

    let link = json!({
        "requestType": "mcp_elicitation_approval", "serverName": "auth",
        "message": "Sign in to continue", "url": "https://auth.example/sign-in",
    });
    let link_request = request(RequestKind::McpElicitationApproval, json!([]), link.clone());
    let link_view = view("claudeAgent", &link_request, &link);
    assert_eq!(
        link_view.title.as_deref(),
        Some("An MCP server needs input")
    );
    let elicitation = link_view.elicitation.unwrap();
    assert_eq!(elicitation["mode"], "url");
    assert_eq!(elicitation["url"], "https://auth.example/sign-in");
    assert_eq!(elicitation["schema"], json!({}));
}
