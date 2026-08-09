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
            "opencode2",
            json!({"agent": "build", "model": "opencode/deepseek", "autoApprove": true}),
            vec!["--auto"],
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
fn codex_carries_a_separate_plan_mode_effort() {
    let launch = build_managed_agent_launch(
        "codex",
        &json!({"effort": "medium", "planModeEffort": "xhigh"}),
    )
    .unwrap();
    assert_eq!(
        launch.arguments,
        [
            "--config",
            "model_reasoning_effort=medium",
            "--config",
            "plan_mode_reasoning_effort=xhigh"
        ]
    );
    assert_eq!(
        build_managed_agent_launch("codex", &json!({"planModeEffort": "high"}))
            .unwrap()
            .arguments,
        ["--config", "plan_mode_reasoning_effort=high"]
    );
    assert!(
        build_managed_agent_launch("codex", &json!({"planModeEffort": "plan"})).is_err(),
        "an unsupported effort was accepted"
    );
    assert!(build_managed_agent_launch("claude", &json!({"planModeEffort": "high"})).is_err());
}

#[test]
fn claude_can_allow_bypass_without_starting_in_it() {
    let launch = build_managed_agent_launch(
        "claude",
        &json!({"permissionMode": "plan", "allowSkipPermissions": true}),
    )
    .unwrap();
    assert_eq!(
        launch.arguments,
        [
            "--permission-mode",
            "plan",
            "--allow-dangerously-skip-permissions"
        ]
    );
    assert!(
        build_managed_agent_launch("claude", &json!({"allowSkipPermissions": "yes"})).is_err(),
        "a non-boolean was accepted"
    );
    assert_eq!(
        build_managed_agent_launch("claude", &json!({"allowSkipPermissions": false}))
            .unwrap()
            .arguments,
        Vec::<String>::new()
    );
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
fn claude_can_allow_dangerous_skip_permissions_independently_of_start_mode() {
    let launch = build_managed_agent_launch(
        "claude",
        &json!({"allowSkipPermissions": true, "permissionMode": "manual"}),
    )
    .unwrap();
    assert_eq!(
        launch.arguments,
        ["--permission-mode", "manual", "--allow-dangerously-skip-permissions"]
    );
}
