use super::*;

#[test]
fn agent_chat_target_round_trips_and_names_its_workspace() {
    let target: AutomationTarget = serde_json::from_value(serde_json::json!({
        "agentChat": {"chatId": "chat", "workspaceId": "workspace", "runtimeModeCeiling": "auto-accept-edits"}
    }))
    .unwrap();
    assert_eq!(target.kind(), "agentChat");
    assert_eq!(target.workspace_id(), Some("workspace"));
    assert_eq!(target.source_workspace_id(), Some("workspace"));
    assert_eq!(target.agent_profile_id(), None);
    assert_eq!(target.direct_project_id(), None);
    let spec = target.agent_chat().unwrap();
    assert_eq!(spec.chat_id, Some("chat"));
    assert_eq!(spec.runtime_mode_ceiling, Some("auto-accept-edits"));
    assert_eq!(
        serde_json::to_value(&target).unwrap(),
        serde_json::json!({"agentChat": {
            "chatId": "chat",
            "workspaceId": "workspace",
            "runtimeModeCeiling": "auto-accept-edits",
        }})
    );
    assert!(target.validate_project_target(None).is_ok());
}

#[test]
fn agent_chat_validation_requires_a_chat_or_a_provider_and_a_known_mode() {
    let target = |chat: Option<&str>, provider: Option<&str>, mode: Option<&str>| {
        AutomationTarget::AgentChat {
            chat_id: chat.map(str::to_string),
            workspace_id: "workspace".into(),
            runtime_mode_ceiling: mode.map(str::to_string),
            provider: provider.map(str::to_string),
            provider_instance_id: None,
            model: None,
            reasoning_effort: None,
        }
    };
    assert!(target(None, None, None)
        .validate_project_target(None)
        .is_err());
    assert!(target(Some("chat"), None, Some("full-access"))
        .validate_project_target(None)
        .is_ok());
    assert!(target(None, Some("codex"), None)
        .validate_project_target(None)
        .is_ok());
    assert!(target(Some("chat"), None, Some("root"))
        .validate_project_target(None)
        .is_err());
    let empty_workspace = AutomationTarget::AgentChat {
        chat_id: Some("chat".into()),
        workspace_id: " ".into(),
        runtime_mode_ceiling: None,
        provider: None,
        provider_instance_id: None,
        model: None,
        reasoning_effort: None,
    };
    assert!(empty_workspace.validate_project_target(None).is_err());
}
