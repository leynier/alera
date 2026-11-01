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

#[test]
fn null_optionals_are_absent_and_oversized_waits_clamp() {
    use super::models::OrchestrationRequest;
    let OrchestrationRequest::Wait(wait) = OrchestrationRequest::parse(
        "wait",
        &serde_json::json!({"taskIds": ["t"], "waitSeconds": null}),
    )
    .unwrap() else {
        panic!("wait");
    };
    assert_eq!(wait.wait_seconds, 50);
    let OrchestrationRequest::Delegate(delegate) = OrchestrationRequest::parse(
        "delegate",
        &serde_json::json!({"requestId": "r", "task": "t", "waitSeconds": 900, "mode": "wait",
            "agent": {"options": null}, "target": {"workspace": {"workspaceId": "w"}}}),
    )
    .unwrap() else {
        panic!("delegate");
    };
    assert_eq!(delegate.wait_seconds, 50);
    assert!(delegate.agent.options.is_none());
    assert!(OrchestrationRequest::parse(
        "delegate",
        &serde_json::json!({"requestId": "r", "task": "t", "agent": null,
            "target": {"workspace": {"workspaceId": "w"}}}),
    )
    .is_ok());
    let OrchestrationRequest::TasksList(list) = OrchestrationRequest::parse(
        "tasks.list",
        &serde_json::json!({"statuses": null, "limit": 900}),
    )
    .unwrap() else {
        panic!("list");
    };
    assert!(list.statuses.is_empty());
    assert_eq!(list.limit, Some(200));
}
