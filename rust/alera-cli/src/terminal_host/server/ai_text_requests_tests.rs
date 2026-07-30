use super::*;

#[test]
fn custom_command_uses_stdin_without_placeholder() {
    let plan = plan_custom_command("agent --quiet", "hello").unwrap();
    assert_eq!(plan.binary, "agent");
    assert_eq!(plan.arguments, ["--quiet"]);
    assert_eq!(plan.stdin_payload.as_deref(), Some("hello"));
}

#[test]
fn prompt_settings_override_the_global_agent_and_model() {
    let settings = RuntimeAiTextGenerationSettings {
        agent: "codex".to_string(),
        prompt_settings_by_operation: HashMap::from([(
            "workspaceIdentity".to_string(),
            alera_core::runtime::RuntimeAiTextPromptSettings {
                agent: Some("amp".to_string()),
                model: Some("rush".to_string()),
            },
        )]),
        ..RuntimeAiTextGenerationSettings::default()
    };

    let plan = plan_command(&settings, "workspaceIdentity", "hello").unwrap();

    assert_eq!(plan.binary, "amp");
    assert!(plan
        .arguments
        .windows(2)
        .any(|values| values == ["--mode", "rush"]));
}
