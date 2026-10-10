use super::*;

#[test]
fn structured_payload_assembles_json() {
    let payload = build_structured_payload(
        None,
        Some("task_1".to_string()),
        Some("ctx_1".to_string()),
        Some("a.rs, b.rs".to_string()),
        Some("/tmp/report.md".to_string()),
        Some("implementing".to_string()),
    )
    .unwrap()
    .unwrap();
    let value: Value = serde_json::from_str(&payload).unwrap();
    assert_eq!(value["taskId"], "task_1");
    assert_eq!(value["dispatchId"], "ctx_1");
    assert_eq!(value["filesModified"], json!(["a.rs", "b.rs"]));
    assert_eq!(value["reportPath"], "/tmp/report.md");
    assert_eq!(value["phase"], "implementing");
}

#[test]
fn raw_payload_must_be_valid_json() {
    assert!(
        build_structured_payload(Some("{not json".to_string()), None, None, None, None, None)
            .is_err()
    );
    let passthrough =
        build_structured_payload(Some("{\"x\":1}".to_string()), None, None, None, None, None)
            .unwrap();
    assert_eq!(passthrough.as_deref(), Some("{\"x\":1}"));
}

#[test]
fn empty_structured_payload_is_none() {
    let payload = build_structured_payload(None, None, None, None, None, None).unwrap();
    assert!(payload.is_none());
}

#[test]
fn dispatch_summary_prints_dry_run_preamble() {
    let summary = human_summary(
        "orchestration.dispatch",
        &json!({
            "dryRun": true,
            "preamble": "handoff text to paste"
        }),
    );
    assert_eq!(summary, "handoff text to paste");
}

#[test]
fn dispatch_requires_override_capability_only_when_assuming_an_agent() {
    assert_eq!(
        dispatch_required_capability(None),
        RUNTIME_HOST_ORCHESTRATION_CAPABILITY
    );
    assert_eq!(
        dispatch_required_capability(Some("codex")),
        RUNTIME_HOST_ORCHESTRATION_ASSUME_AGENT_CAPABILITY
    );
}

#[test]
fn dispatch_summary_prints_returned_preamble() {
    let summary = human_summary(
        "orchestration.dispatch",
        &json!({
            "dispatch": {
                "id": "ctx_1"
            },
            "preamble": "manual injection text"
        }),
    );
    assert_eq!(summary, "manual injection text");
}

#[test]
fn dispatch_summary_labels_dry_run_without_preamble() {
    let summary = human_summary("orchestration.dispatch", &json!({ "dryRun": true }));
    assert_eq!(summary, "dispatch dry run");
}

#[test]
fn default_check_summary_prints_message_contents() {
    let summary = human_summary(
        "orchestration.check",
        &json!({
            "messages": [{
                "id": "msg_1",
                "from_handle": "coord",
                "to_handle": "worker",
                "subject": "Follow up",
                "body": "Please rerun tests.",
                "type": "status",
                "priority": "normal",
                "thread_id": null,
                "payload": "{\"taskId\":\"task_1\"}",
                "read": false,
                "sequence": 1,
                "created_at": "2026-07-05 19:00:00",
                "delivered_at": null
            }]
        }),
    );
    assert!(summary.contains("From: coord (status)"));
    assert!(summary.contains("Subject: Follow up"));
    assert!(summary.contains("Please rerun tests."));
    assert!(summary.contains("alera orchestration reply --id msg_1"));
}

#[test]
fn terminal_startup_failure_is_detected_without_waiting_for_timeout() {
    assert_eq!(
        terminal_startup_error(&json!({
            "startupState": "failed",
            "startupError": "agent exited"
        })),
        Some("agent exited")
    );
    assert_eq!(
        terminal_startup_error(&json!({"startupState": "process_started"})),
        None
    );
}

#[test]
fn result_extra_adds_schema_defined_completion_fields() {
    let mut result = json!({
        "summary": "done",
        "completionKind": "success",
        "artifacts": [],
        "filesModified": [],
        "validation": []
    });
    merge_result_extra(&mut result, Some(r#"{"ticket":42}"#)).unwrap();
    assert_eq!(result["ticket"], json!(42));
    assert!(merge_result_extra(&mut result, Some("[]")).is_err());
}
