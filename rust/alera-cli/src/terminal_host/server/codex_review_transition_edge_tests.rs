use super::*;
use chrono::Utc;

fn tab() -> WorkspaceTabRecord {
    WorkspaceTabRecord {
        id: "tab".into(),
        workspace_id: "workspace".into(),
        kind: CODEX_TAB_KIND.into(),
        title: "Codex".into(),
        created_at: Utc::now(),
        updated_at: Utc::now(),
        payload: json!({}),
    }
}

#[test]
fn review_failure_before_worker_start_does_not_capture_the_next_turn() {
    let mut record = tab();
    append_message(
        &mut record,
        json!({
            "method": "codex/event/entered_review_mode",
            "params": {"msg": {
                "type": "entered_review_mode",
                "turn_id": "review-envelope"
            }}
        }),
    );
    mark_server_failure(&mut record, "app-server exited");
    append_message(
        &mut record,
        json!({
            "method": "codex/event/task_started",
            "params": {"msg": {
                "type": "task_started",
                "turn_id": "normal-turn"
            }}
        }),
    );

    let saved = snapshot(&record);
    assert!(saved.get("aleraReviewTransition").is_none());
    let turn_ids = saved["timelineCells"]
        .as_array()
        .unwrap()
        .iter()
        .filter_map(|cell| cell.get("turnId").and_then(Value::as_str))
        .collect::<std::collections::HashSet<_>>();
    assert!(turn_ids.contains("review-envelope"));
    assert!(turn_ids.contains("normal-turn"));
}

#[test]
fn review_user_echoes_do_not_duplicate_alera_owned_steering() {
    let mut record = tab();
    append_message(
        &mut record,
        json!({
            "method": "codex/event/entered_review_mode",
            "params": {"msg": {
                "type": "entered_review_mode",
                "turn_id": "review-envelope"
            }}
        }),
    );
    append_message(
        &mut record,
        json!({
            "method": "codex/event/task_started",
            "params": {"msg": {
                "type": "task_started",
                "turn_id": "review-worker"
            }}
        }),
    );
    append_message(
        &mut record,
        json!({
            "method": "codex/event/user_message",
            "params": {"msg": {"type": "user_message", "message": "Generated review prompt"}}
        }),
    );
    super::super::codex_user_messages::append_user_input(
        &mut record,
        &json!([{"type": "text", "text": "Focus on pagination"}]),
        Some(&json!({"text": "Focus on pagination"})),
        "review-envelope",
        Some("steering-1"),
        true,
    );
    for _ in 0..2 {
        append_message(
            &mut record,
            json!({
                "method": "codex/event/user_message",
                "params": {"msg": {"type": "user_message", "message": "Focus on pagination"}}
            }),
        );
    }

    let saved = snapshot(&record);
    let user_text = saved["timelineCells"]
        .as_array()
        .unwrap()
        .iter()
        .filter(|cell| cell["kind"] == "userMessage")
        .filter_map(|cell| cell.get("markdownText").and_then(Value::as_str))
        .collect::<Vec<_>>();
    assert_eq!(
        user_text,
        ["Generated review prompt", "Focus on pagination"]
    );
}
