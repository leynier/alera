use serde_json::{json, Map, Value};

use super::{managed_command_preview, managed_risk_markers, parse_agent_profiles};

#[test]
fn parses_wrapped_agent_profile_list() {
    let profiles = parse_agent_profiles(json!({
        "items": [{
            "id": "profile-1",
            "name": "Primary",
            "agentType": "claude",
            "command": "claude",
            "launchMode": "managed",
            "managedConfig": {
                "model": "claude-sonnet-4-5",
                "permissionMode": "plan"
            },
            "description": "Default Claude Profile",
            "quotaGroup": "anthropic"
        }]
    }))
    .expect("valid profile list");

    assert_eq!(profiles.len(), 1);
    let profile = &profiles[0];
    assert_eq!(profile.id, "profile-1");
    assert_eq!(profile.name, "Primary");
    assert_eq!(profile.agent_type, "claude");
    assert_eq!(profile.launch_mode, "managed");
    assert_eq!(
        profile.managed_config.get("permissionMode"),
        Some(&Value::String("plan".to_owned()))
    );
    assert_eq!(profile.quota_group.as_deref(), Some("anthropic"));
}

#[test]
fn legacy_profile_defaults_to_command_mode() {
    let profiles = parse_agent_profiles(json!([{
        "id": "legacy",
        "name": "Legacy",
        "agentType": "codex",
        "command": "codex --search"
    }]))
    .expect("valid legacy profile");

    assert_eq!(profiles[0].launch_mode, "command");
    assert!(profiles[0].managed_config.is_empty());
    assert_eq!(profiles[0].description, "");
    assert_eq!(profiles[0].quota_group, None);
}

#[test]
fn command_preview_matches_managed_codex_arguments() {
    let config: Map<String, Value> = json!({
        "model": "gpt-5.4",
        "effort": "high",
        "sandbox": "workspace-write",
        "approvalPolicy": "on-request",
        "webSearch": true
    })
    .as_object()
    .expect("object")
    .clone();

    assert_eq!(
        managed_command_preview("codex", &config),
        "codex --model gpt-5.4 --config model_reasoning_effort=high --sandbox workspace-write --ask-for-approval on-request --search"
    );
}

#[test]
fn command_preview_quotes_values_with_spaces() {
    let config: Map<String, Value> = json!({
        "model": "claude sonnet",
        "agent": "reviewer's choice"
    })
    .as_object()
    .expect("object")
    .clone();

    assert_eq!(
        managed_command_preview("claude", &config),
        "claude --model 'claude sonnet' --agent 'reviewer'\"'\"'s choice'"
    );
}

#[test]
fn command_preview_routes_claude_through_ccs_profile() {
    let config: Map<String, Value> = json!({
        "ccsProfile": "work",
        "model": "opus",
        "permissionMode": "acceptEdits"
    })
    .as_object()
    .expect("object")
    .clone();

    assert_eq!(
        managed_command_preview("claude", &config),
        "ccs work --model opus --permission-mode acceptEdits"
    );
}

#[test]
fn risk_markers_match_reduced_protection_options() {
    let config = json!({
        "sandbox": "danger-full-access",
        "approvalPolicy": "never",
        "webSearch": true
    })
    .as_object()
    .expect("object")
    .clone();

    assert_eq!(
        managed_risk_markers("codex", &config),
        ["dangerFullAccess".to_owned(), "neverAsk".to_owned()]
            .into_iter()
            .collect()
    );
}
