use serde_json::json;

use super::*;

#[test]
fn codex_builds_structured_arguments_and_rejects_conflicting_bypass() {
    let launch = build_managed_agent_launch(
        "codex",
        &json!({
            "model": "gpt-5.6-sol",
            "effort": "high",
            "sandbox": "workspace-write",
            "approvalPolicy": "on-request",
            "webSearch": true
        }),
    )
    .unwrap();
    assert_eq!(
        launch.arguments,
        [
            "--model",
            "gpt-5.6-sol",
            "--config",
            "model_reasoning_effort=high",
            "--sandbox",
            "workspace-write",
            "--ask-for-approval",
            "on-request",
            "--search"
        ]
    );
    assert!(build_managed_agent_launch(
        "codex",
        &json!({
            "bypassApprovalsAndSandbox": true,
            "sandbox": "danger-full-access"
        })
    )
    .is_err());
}

#[test]
fn every_adapter_builds_its_native_session_flags() {
    let cases = [
        (
            "claude",
            json!({"permissionMode": "bypassPermissions"}),
            vec!["--permission-mode", "bypassPermissions"],
        ),
        (
            "copilot",
            json!({"allowAll": true, "mode": "autopilot"}),
            vec!["--mode", "autopilot", "--allow-all"],
        ),
        (
            "cursor",
            json!({"permissionMode": "autoReview", "sandbox": "enabled"}),
            vec!["--auto-review", "--sandbox", "enabled"],
        ),
        (
            "agy",
            json!({"skipPermissions": true, "sandbox": true}),
            vec!["--dangerously-skip-permissions", "--sandbox"],
        ),
        (
            "opencode",
            json!({"agent": "build", "autoApprove": true}),
            vec!["--agent", "build", "--auto"],
        ),
        (
            "pi",
            json!({"thinking": "xhigh", "projectTrust": "ignore"}),
            vec!["--thinking", "xhigh", "--no-approve"],
        ),
        (
            "amp",
            json!({"mode": "ultra", "fast": true}),
            vec!["--mode", "ultra", "--fast"],
        ),
    ];
    for (agent, config, expected) in cases {
        assert_eq!(
            build_managed_agent_launch(agent, &config)
                .unwrap()
                .arguments,
            expected
        );
    }
}

#[test]
fn a_claude_ccs_profile_replaces_the_executable_and_leads_the_arguments() {
    let launch = build_managed_agent_launch(
        "claude",
        &json!({
            "ccsProfile": "work",
            "model": "opus",
            "permissionMode": "acceptEdits"
        }),
    )
    .unwrap();
    assert_eq!(launch.executable, "ccs");
    assert_eq!(
        launch.arguments,
        [
            "work",
            "--model",
            "opus",
            "--permission-mode",
            "acceptEdits"
        ]
    );

    let direct = build_managed_agent_launch("claude", &json!({"model": "opus"})).unwrap();
    assert_eq!(direct.executable, "claude");
    assert_eq!(direct.arguments, ["--model", "opus"]);
}

#[test]
fn a_claude_ccs_profile_must_be_a_single_name_that_is_not_an_option() {
    for rejected in [json!("--work"), json!("work extra"), json!("  "), json!(3)] {
        assert!(
            build_managed_agent_launch("claude", &json!({"ccsProfile": rejected})).is_err(),
            "accepted {rejected}"
        );
    }
    assert!(build_managed_agent_launch("codex", &json!({"ccsProfile": "work"})).is_err());
}

#[test]
fn rendering_quotes_each_token_for_supported_shell_families() {
    let launch = ManagedAgentLaunch {
        executable: "agy".to_string(),
        arguments: vec![
            "--model".to_string(),
            "Gemini 3.5 Flash (High)".to_string(),
            "it's ready".to_string(),
        ],
    };
    assert_eq!(
        render_managed_launch(&launch, "/bin/zsh"),
        "'agy' '--model' 'Gemini 3.5 Flash (High)' 'it'\"'\"'s ready'"
    );
    assert_eq!(
        render_managed_launch(&launch, "pwsh.exe"),
        "'agy' '--model' 'Gemini 3.5 Flash (High)' 'it''s ready'"
    );
    assert_eq!(
        render_managed_launch(&launch, "cmd.exe"),
        "\"agy\" \"--model\" \"Gemini 3.5 Flash (High)\" \"it's ready\""
    );
}

#[test]
fn codex_managed_prompt_follows_the_option_terminator_on_every_shell() {
    let mut launch = build_managed_agent_launch("codex", &json!({"webSearch": true})).unwrap();
    crate::terminal_host::orchestration::agent_startup_command::append_codex_initial_prompt_argument(
        &mut launch.arguments,
        "- Review why it's pending\n- Implement memory".to_string(),
    );
    assert_eq!(
        render_managed_launch(&launch, "/bin/zsh"),
        "'codex' '--search' '--' '- Review why it'\"'\"'s pending\n- Implement memory'"
    );
    assert_eq!(
        render_managed_launch(&launch, "pwsh.exe"),
        "'codex' '--search' '--' '- Review why it''s pending\n- Implement memory'"
    );
    assert_eq!(
        render_managed_launch(&launch, "cmd.exe"),
        "\"codex\" \"--search\" \"--\" \"- Review why it's pending\n- Implement memory\""
    );
}
