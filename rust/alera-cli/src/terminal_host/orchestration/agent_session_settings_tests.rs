use serde_json::{json, Map, Value};

use super::*;

fn args(values: &[&str]) -> Vec<String> {
    values.iter().map(|value| value.to_string()).collect()
}

fn settings(value: Value) -> Map<String, Value> {
    value.as_object().unwrap().clone()
}

#[test]
fn claude_hooks_report_mode_effort_and_the_starting_model() {
    assert_eq!(
        settings_from_hook(
            "claude",
            &json!({"model": "opus", "permission_mode": "default", "effort": {"level": "high"}})
        ),
        settings(json!({"model": "opus", "permissionMode": "manual", "effort": "high"}))
    );
    assert_eq!(
        settings_from_hook("claude", &json!({"permission_mode": "plan"})),
        settings(json!({"permissionMode": "plan"}))
    );
    assert!(settings_from_hook("claude", &json!({"prompt": "hello"})).is_empty());
}

#[test]
fn other_agents_report_what_their_hooks_carry() {
    assert_eq!(
        settings_from_hook(
            "codex",
            &json!({"model": "gpt-5", "permission_mode": "plan"})
        ),
        settings(json!({"model": "gpt-5"}))
    );
    assert_eq!(
        settings_from_hook("grok", &json!({"permissionMode": "auto"})),
        settings(json!({"permissionMode": "auto"}))
    );
    assert_eq!(
        settings_from_hook("agy", &json!({"model_name": "gemini"})),
        settings(json!({"model": "gemini"}))
    );
    assert!(settings_from_hook("opencode", &json!({"model": "x"})).is_empty());
}

#[test]
fn codex_settings_come_from_the_last_turn_context() {
    let tail = [
        json!({"type": "turn_context", "payload": {"model": "old", "effort": "low"}}).to_string(),
        "{not json".to_string(),
        json!({"type": "turn_context", "payload": {
            "model": "gpt-5", "effort": "high", "approval_policy": "never",
            "sandbox_policy": {"type": "danger-full-access"}
        }})
        .to_string(),
        json!({"type": "event_msg", "payload": {}}).to_string(),
    ]
    .join("\n");
    assert_eq!(
        codex_settings_from_rollout_tail(&tail),
        settings(json!({
            "model": "gpt-5", "effort": "high", "approvalPolicy": "never",
            "sandbox": "danger-full-access"
        }))
    );
}

#[test]
fn grok_and_copilot_settings_come_from_their_session_files() {
    assert_eq!(
        grok_settings_from_summary(&json!({
            "current_model_id": "grok-4", "reasoning_effort": "low", "sandbox_profile": "off"
        })),
        settings(json!({"model": "grok-4", "effort": "low"}))
    );
    let events = [
        json!({"type": "session.model_change", "data": {"newModel": "a", "reasoningEffort": "low"}}),
        json!({"type": "session.mode_changed", "data": {"newMode": "plan"}}),
        json!({"type": "session.model_change", "data": {"newModel": "b", "reasoningEffort": "high"}}),
    ]
    .map(|event| event.to_string())
    .join("\n");
    assert_eq!(
        copilot_settings_from_events_tail(&events),
        settings(json!({"model": "b", "effort": "high", "mode": "plan"}))
    );
}

#[test]
fn codex_resume_replaces_profile_flags_with_the_conversation_settings() {
    let mut arguments = args(&[
        "--model",
        "old",
        "--config",
        "model_reasoning_effort=low",
        "--config",
        "plan_mode_reasoning_effort=high",
        "--dangerously-bypass-approvals-and-sandbox",
        "--search",
    ]);
    apply_session_settings(
        "codex",
        &mut arguments,
        Some(&settings(json!({
            "model": "gpt-5", "effort": "high", "approvalPolicy": "on-request",
            "sandbox": "workspace-write"
        }))),
    );
    assert_eq!(
        arguments,
        args(&[
            "--config",
            "plan_mode_reasoning_effort=high",
            "--search",
            "--model",
            "gpt-5",
            "--config",
            "model_reasoning_effort=high",
            "--sandbox",
            "workspace-write",
            "--ask-for-approval",
            "on-request",
        ])
    );
}

#[test]
fn a_value_the_builder_rejects_leaves_the_profile_flag_alone() {
    let mut arguments = args(&["--ask-for-approval", "never"]);
    apply_session_settings(
        "codex",
        &mut arguments,
        Some(&settings(json!({"approvalPolicy": "on-failure"}))),
    );
    assert_eq!(arguments, args(&["--ask-for-approval", "never"]));
}

#[test]
fn claude_resume_lets_the_conversation_restore_its_model() {
    let mut arguments = args(&[
        "work",
        "--model",
        "opus",
        "--dangerously-skip-permissions",
        "--allow-dangerously-skip-permissions",
    ]);
    apply_session_settings(
        "claude",
        &mut arguments,
        Some(&settings(
            json!({"model": "sonnet", "permissionMode": "plan", "effort": "max"}),
        )),
    );
    assert_eq!(
        arguments,
        args(&[
            "work",
            "--allow-dangerously-skip-permissions",
            "--permission-mode",
            "plan",
            "--effort",
            "max",
        ])
    );
}

#[test]
fn resume_drops_flags_the_agent_restores_or_refuses_even_without_settings() {
    let mut pi = args(&["--model", "a/b", "--thinking", "high", "--approve"]);
    apply_session_settings("pi", &mut pi, None);
    assert_eq!(pi, args(&["--approve"]));

    let mut grok = args(&["--sandbox", "strict", "--agent", "plan", "-m", "old"]);
    apply_session_settings(
        "grok",
        &mut grok,
        Some(&settings(
            json!({"model": "grok-4", "permissionMode": "auto"}),
        )),
    );
    assert_eq!(
        grok,
        args(&[
            "--agent",
            "plan",
            "--model",
            "grok-4",
            "--permission-mode",
            "auto"
        ])
    );
}

#[test]
fn settings_are_inserted_before_an_option_terminator() {
    let mut arguments = args(&["--model", "old", "--", "positional"]);
    apply_session_settings(
        "copilot",
        &mut arguments,
        Some(&settings(json!({"model": "new"}))),
    );
    assert_eq!(arguments, args(&["--model", "new", "--", "positional"]));
}

#[test]
fn an_opaque_command_keeps_flags_the_user_wrote() {
    let values = settings(json!({"permissionMode": "plan", "effort": "high"}));
    assert_eq!(
        session_settings_for_command("claude", "claude --permission-mode auto", Some(&values)),
        args(&["--effort", "high"])
    );
    assert_eq!(
        session_settings_for_command("claude", "claude", Some(&values)),
        args(&["--permission-mode", "plan", "--effort", "high"])
    );
    assert_eq!(
        session_settings_for_command(
            "codex",
            "codex -c model_reasoning_effort=low",
            Some(&settings(json!({"effort": "high"})))
        ),
        Vec::<String>::new()
    );
    assert!(session_settings_for_command("claude", "claude", None).is_empty());
}
