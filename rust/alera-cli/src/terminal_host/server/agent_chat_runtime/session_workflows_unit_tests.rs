use super::*;
use alera_provider_protocol::ProviderKind;

fn event(kind: EventKind, payload: Value) -> ProviderEvent {
    ProviderEvent::new(ProviderKind::Claude, "claude", "chat", kind, payload, None)
}

#[test]
fn only_a_silent_workflow_frame_keeps_a_settled_status() {
    let silent = event(
        EventKind::TaskProgress,
        json!({"taskId": "wf", "workflow": {}}),
    );
    assert_eq!(
        workflow_status(&silent, "running", Some("completed")),
        "completed"
    );
    assert_eq!(
        workflow_status(&silent, "running", Some("running")),
        "running"
    );
    assert_eq!(workflow_status(&silent, "running", None), "running");
    let restarted = event(
        EventKind::TaskStarted,
        json!({"taskId": "wf", "workflow": {}}),
    );
    assert_eq!(
        workflow_status(&restarted, "running", Some("completed")),
        "running"
    );
    let plain = event(EventKind::TaskProgress, json!({"taskId": "t"}));
    assert_eq!(
        workflow_status(&plain, "running", Some("completed")),
        "running"
    );
    let reported = event(
        EventKind::TaskUpdated,
        json!({"taskId": "wf", "status": "running", "workflow": {}}),
    );
    assert_eq!(
        workflow_status(&reported, "running", Some("stopped")),
        "running"
    );
}

#[test]
fn frames_fold_into_the_stored_workflow_and_a_bad_one_changes_nothing() {
    let mut subagent = json!({"status": "running"});
    fold_workflow(
        &mut subagent,
        &event(
            EventKind::TaskStarted,
            json!({"workflow": {"name": "probe-wf", "phases": [{"index": 1, "title": "Alpha"}]}}),
        ),
    );
    fold_workflow(
        &mut subagent,
        &event(
            EventKind::TaskProgress,
            json!({"workflow": {"totalTokens": 5}}),
        ),
    );
    let before = subagent.clone();
    fold_workflow(
        &mut subagent,
        &event(EventKind::TaskProgress, json!({"workflow": {"phases": 3}})),
    );
    assert_eq!(subagent, before);
    assert_eq!(subagent["workflow"]["name"], "probe-wf");
    assert_eq!(subagent["workflow"]["phases"][0]["title"], "Alpha");
    assert_eq!(subagent["workflow"]["totalTokens"], 5);
}
