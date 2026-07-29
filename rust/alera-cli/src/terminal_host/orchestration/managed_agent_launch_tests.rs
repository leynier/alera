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
