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
fn grok_uses_a_prompt_file_and_the_current_default_model() {
    let settings = RuntimeAiTextGenerationSettings {
        agent: "grok".to_string(),
        ..RuntimeAiTextGenerationSettings::default()
    };

    let plan = plan_command(&settings, "commitMessage", "hello").unwrap();
    let directory = plan.temporary_directory.clone();

    assert_eq!(plan.binary, "grok");
    assert_eq!(plan.label, "Grok Build");
    assert!(plan
        .arguments
        .windows(2)
        .any(|values| values == ["--model", "grok-4.6"]));
    assert!(plan.arguments.contains(&"--prompt-file".to_string()));
    assert!(!plan.arguments.contains(&"--effort".to_string()));
    assert!(plan.environment.contains_key("GROK_HOME"));
    assert!(directory.is_some());

    if let Some(directory) = directory {
        let _ = std::fs::remove_dir_all(directory);
    }
}

#[test]
fn grok_forwards_an_explicit_reasoning_effort() {
    let settings = RuntimeAiTextGenerationSettings {
        agent: "grok".to_string(),
        selected_thinking_by_model: HashMap::from([("grok-4.6".to_string(), "max".to_string())]),
        ..RuntimeAiTextGenerationSettings::default()
    };

    let plan = plan_command(&settings, "commitMessage", "hello").unwrap();
    let directory = plan.temporary_directory.clone();

    assert!(plan
        .arguments
        .windows(2)
        .any(|values| values == ["--effort", "max"]));

    if let Some(directory) = directory {
        let _ = std::fs::remove_dir_all(directory);
    }
}

#[test]
fn fx_uses_ask_stdin_without_forcing_a_model() {
    let settings = RuntimeAiTextGenerationSettings {
        agent: "fx".to_string(),
        ..RuntimeAiTextGenerationSettings::default()
    };

    let plan = plan_command(&settings, "commitMessage", "hello").unwrap();

    assert_eq!(plan.binary, "fx");
    assert_eq!(plan.arguments, ["ask", "--no-save"]);
    assert_eq!(plan.stdin_payload.as_deref(), Some("hello"));
    assert_eq!(
        plan.environment
            .get("FX_PERMISSION_MODE")
            .map(String::as_str),
        Some("ask")
    );
    assert_eq!(
        plan.environment.get("FX_AUTO_UPGRADE").map(String::as_str),
        Some("0")
    );
    assert_eq!(
        plan.environment.get("FX_HERDR").map(String::as_str),
        Some("0")
    );
    assert!(!plan.environment.contains_key("FX_MODEL"));
}

#[test]
fn fx_passes_an_explicit_model_through_the_environment() {
    let settings = RuntimeAiTextGenerationSettings {
        agent: "fx".to_string(),
        selected_model_by_agent: HashMap::from([(
            "fx".to_string(),
            "xai/grok-4.1-fast".to_string(),
        )]),
        ..RuntimeAiTextGenerationSettings::default()
    };

    let plan = plan_command(&settings, "commitMessage", "hello").unwrap();

    assert_eq!(
        plan.environment.get("FX_MODEL").map(String::as_str),
        Some("xai/grok-4.1-fast")
    );
}
