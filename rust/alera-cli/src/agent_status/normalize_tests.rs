use serde_json::{json, Value};

use super::*;

fn event(agent_type: &str, event_name: &str, payload: Value) -> AgentHookEvent {
    AgentHookEvent {
        terminal_session_id: "session-1".into(),
        workspace_id: "workspace-1".into(),
        tab_id: "tab-1".into(),
        agent_type: agent_type.into(),
        payload,
        event_name: Some(event_name.into()),
    }
}

#[test]
fn every_supported_agent_reports_working() {
    for (agent_type, event_name) in [
        ("codex", "UserPromptSubmit"),
        ("claude", "UserPromptSubmit"),
        ("copilot", "userPromptSubmitted"),
        ("cursor", "beforeSubmitPrompt"),
        ("agy", "PreInvocation"),
        ("opencode", "SessionBusy"),
        ("pi", "agent_start"),
        ("amp", "session.start"),
        ("grok", "UserPromptSubmit"),
    ] {
        let status = normalize_hook_event(&event(agent_type, event_name, json!({})), None)
            .unwrap_or_else(|| panic!("{agent_type} event was not normalized"));
        assert_eq!(status.state, AgentPresenceState::Working, "{agent_type}");
    }
}

#[test]
fn codex_waiting_status_preserves_nested_tool_details() {
    let status = normalize_hook_event(
        &event(
            "codex",
            "PreToolUse",
            json!({
                "prompt": "Choose a deployment",
                "toolCall": {
                    "name": "request_user_input",
                    "arguments": {"environment": "production"}
                }
            }),
        ),
        None,
    )
    .expect("codex status");

    assert_eq!(status.state, AgentPresenceState::Waiting);
    assert_eq!(status.prompt, "Choose a deployment");
    assert_eq!(status.tool_name.as_deref(), Some("request_user_input"));
    assert!(status
        .tool_input
        .as_deref()
        .is_some_and(|value| { value.contains("environment") && value.contains("production") }));
}

#[test]
fn new_turn_clears_stale_tool_details() {
    let previous = AgentPresence {
        agent_type: "codex".into(),
        state: AgentPresenceState::Waiting,
        state_started_at: chrono::Utc::now(),
        updated_at: chrono::Utc::now(),
        prompt: "Old prompt".into(),
        tool_name: Some("request_user_input".into()),
        tool_input: Some("old input".into()),
        last_assistant_message: None,
        interrupted: None,
    };
    let status = normalize_hook_event(
        &event("codex", "UserPromptSubmit", json!({"prompt": "New prompt"})),
        Some(&previous),
    )
    .expect("codex status");

    assert_eq!(status.prompt, "New prompt");
    assert_eq!(status.tool_name, None);
    assert_eq!(status.tool_input, None);
}

#[test]
fn lifecycle_events_are_detected_before_state_normalization() {
    assert!(hook_event_resets_session(&event(
        "grok",
        "session_start",
        json!({})
    )));
    assert!(hook_event_closes_session(&event(
        "pi",
        "session_shutdown",
        json!({})
    )));
}

#[test]
fn copilot_can_infer_missing_event_name() {
    let mut event = event(
        "copilot",
        "ignored",
        json!({"prompt": "Implement the change"}),
    );
    event.event_name = None;
    let status = normalize_hook_event(&event, None).expect("copilot status");
    assert_eq!(status.state, AgentPresenceState::Working);
    assert_eq!(status.prompt, "Implement the change");
}
