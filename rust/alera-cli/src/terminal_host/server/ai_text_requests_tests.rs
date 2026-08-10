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

#[test]
fn agy_inherits_its_configured_model_without_forcing_a_stale_default() {
    let settings = RuntimeAiTextGenerationSettings {
        agent: "agy".to_string(),
        ..RuntimeAiTextGenerationSettings::default()
    };

    let plan = plan_command(&settings, "workspaceIdentity", "hello").unwrap();

    assert_eq!(plan.binary, "agy");
    assert!(!plan.arguments.iter().any(|argument| argument == "--model"));
}

#[test]
fn agy_passes_an_explicit_discovered_model_unchanged() {
    let settings = RuntimeAiTextGenerationSettings {
        agent: "agy".to_string(),
        selected_model_by_agent: HashMap::from([(
            "agy".to_string(),
            "gemini-3.1-pro-low".to_string(),
        )]),
        ..RuntimeAiTextGenerationSettings::default()
    };

    let plan = plan_command(&settings, "workspaceIdentity", "hello").unwrap();

    assert_eq!(
        plan.arguments,
        [
            "--print",
            "--sandbox",
            "--print-timeout",
            "120s",
            "--model",
            "gemini-3.1-pro-low",
        ]
    );
}

#[test]
fn operation_reasoning_overrides_global_reasoning() {
    let settings = RuntimeAiTextGenerationSettings {
        selected_thinking_by_model: HashMap::from([("gpt-5.5".to_string(), "low".to_string())]),
        selected_thinking_by_operation: HashMap::from([(
            "workspaceIdentity".to_string(),
            HashMap::from([("gpt-5.5".to_string(), "high".to_string())]),
        )]),
        ..RuntimeAiTextGenerationSettings::default()
    };

    let workspace_plan = plan_command(&settings, "workspaceIdentity", "hello").unwrap();
    assert!(workspace_plan
        .arguments
        .windows(2)
        .any(|values| values == ["-c", "model_reasoning_effort=high"]));
}

#[test]
fn failure_detail_extracts_a_multiline_json_message() {
    let stderr = r#"
ERROR: {
  "type": "error",
  "error": {
    "code": "invalid_json_schema",
    "message": "The version property must declare an integer type."
  },
  "status": 400
}
"#;

    assert_eq!(
        ai_text_failure_detail("", stderr).as_deref(),
        Some("The version property must declare an integer type.")
    );
}
