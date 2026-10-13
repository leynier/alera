use serde_json::json;

use super::models::OrchestrationRequest;

#[test]
fn new_workspace_requires_an_explicit_strategy_before_admission() {
    assert!(OrchestrationRequest::parse(
        "delegate",
        &json!({"requestId": "missing-mode",
        "task": "Prepare a workspace.", "target": {"newWorkspace": {
            "projectId": "project", "hostId": "local"}}})
    )
    .is_err());
    for mode in ["worktree", "shared"] {
        assert!(OrchestrationRequest::parse(
            "delegate",
            &json!({"requestId": mode,
            "task": "Prepare a workspace.", "target": {"newWorkspace": {
                "projectId": "project", "hostId": "local", "mode": mode}}})
        )
        .is_ok());
    }
}

#[test]
fn wait_seconds_requires_an_unsigned_integer_with_zero_as_a_valid_bound() {
    for value in [json!(-1), json!("50"), json!(true)] {
        assert!(OrchestrationRequest::parse(
            "wait",
            &json!({"taskIds": ["task"], "waitSeconds": value})
        )
        .is_err());
    }
    assert!(
        OrchestrationRequest::parse("wait", &json!({"taskIds": ["task"], "waitSeconds": 0}))
            .is_ok()
    );
}
