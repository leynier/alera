use serde_json::json;

use super::authorization::modes_at_or_below;
use super::models::{DelegateMode, OrchestrationRequest, ParsedTarget, WaitUntil};
use super::tasks::truncate_result;

#[test]
fn wait_defaults_to_bounded_all_wait() {
    let request = OrchestrationRequest::parse("wait", &json!({"taskIds": ["task-1"]}))
        .expect("wait should parse");
    let OrchestrationRequest::Wait(input) = request else {
        panic!("expected wait request");
    };
    assert_eq!(input.wait_seconds, 50);
    assert_eq!(input.until, WaitUntil::All);
}

#[test]
fn async_delegate_defaults_to_zero_wait_and_explicit_target() {
    let request = OrchestrationRequest::parse(
        "delegate",
        &json!({
            "requestId": "r1",
            "task": "inspect the other workspace",
            "target": {"workspace": {"workspaceId": "workspace-1"}}
        }),
    )
    .expect("delegate should parse");
    let OrchestrationRequest::Delegate(input) = request else {
        panic!("expected delegate request");
    };
    assert_eq!(input.mode, DelegateMode::Async);
    assert_eq!(input.wait_seconds, 0);
    assert_eq!(
        input.target,
        ParsedTarget::Workspace {
            workspace_id: "workspace-1".into()
        }
    );
}

#[test]
fn wait_rejects_values_over_host_ceiling_and_multiple_targets() {
    assert!(OrchestrationRequest::parse(
        "wait",
        &json!({"taskIds": ["task-1"], "waitSeconds": 51}),
    )
    .is_err());
    assert!(OrchestrationRequest::parse(
        "delegate",
        &json!({
            "requestId": "r1",
            "task": "inspect",
            "target": {
                "chat": {"chatId": "chat-1"},
                "workspace": {"workspaceId": "workspace-1"}
            }
        }),
    )
    .is_err());
}

#[test]
fn result_truncation_keeps_utf8_boundaries() {
    let text = "é".repeat(5 * 1024);
    let (truncated, was_truncated) = truncate_result(&text);
    assert!(was_truncated);
    assert!(truncated.len() <= 8 * 1024);
    assert!(truncated.is_char_boundary(truncated.len()));
}

#[test]
fn mode_ceiling_is_inclusive() {
    assert_eq!(
        modes_at_or_below("auto"),
        vec!["approval-required", "auto-accept-edits", "auto"]
    );
}
