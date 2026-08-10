use super::*;

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
fn live_review_events_share_one_canonical_turn_and_user_message() {
    let mut record = tab();
    append_message(
        &mut record,
        json!({
            "method": "codex/event/entered_review_mode",
            "params": {"msg": {
                "type": "entered_review_mode",
                "turn_id": "review-envelope",
                "item_id": "review-entry",
                "review": "current changes"
            }}
        }),
    );
    append_message(
        &mut record,
        json!({
            "method": "codex/event/task_started",
            "params": {"msg": {
                "type": "task_started",
                "turn_id": "review-worker",
                "started_at": 1_786_374_667_i64
            }}
        }),
    );
    for _ in 0..2 {
        append_message(
            &mut record,
            json!({
                "method": "codex/event/user_message",
                "params": {"msg": {
                    "type": "user_message",
                    "message": "Review the current changes."
                }}
            }),
        );
    }
    append_message(
        &mut record,
        json!({
            "method": "item/completed",
            "params": {
                "item": {
                    "id": "read-1",
                    "turnID": "review-worker",
                    "type": "commandExecution",
                    "command": "rg --files",
                    "status": "completed"
                }
            }
        }),
    );

    let saved = snapshot(&record);
    assert_eq!(saved["activeTurnId"], "review-envelope");
    let cells = saved["timelineCells"].as_array().unwrap();
    assert!(cells
        .iter()
        .filter_map(|cell| cell.get("turnId").and_then(Value::as_str))
        .all(|turn_id| turn_id == "review-envelope"));
    assert_eq!(
        cells
            .iter()
            .filter(|cell| cell["kind"] == "userMessage")
            .count(),
        1
    );
    let review = cells
        .iter()
        .find(|cell| cell["metadata"]["itemType"] == "enteredReviewMode")
        .unwrap();
    assert_eq!(review["turnId"], "review-envelope");
    assert!(cells
        .iter()
        .any(|cell| { cell["kind"] == "command" && cell["turnId"] == "review-envelope" }));
}

#[test]
fn typed_live_review_notifications_share_one_canonical_turn() {
    let mut record = tab();
    append_message(
        &mut record,
        json!({
            "method": "item/started",
            "params": {
                "turnId": "review-envelope",
                "item": {
                    "id": "review-entry",
                    "type": "enteredReviewMode",
                    "review": "current changes"
                }
            }
        }),
    );
    append_message(
        &mut record,
        json!({
            "method": "turn/started",
            "params": {"turn": {"id": "review-worker"}}
        }),
    );
    append_message(
        &mut record,
        json!({
            "method": "item/completed",
            "params": {
                "turnId": "review-envelope",
                "item": {
                    "id": "review-entry",
                    "type": "enteredReviewMode",
                    "review": "current changes"
                }
            }
        }),
    );
    for item_id in ["review-prompt-1", "review-prompt-2"] {
        append_message(
            &mut record,
            json!({
                "method": "item/completed",
                "params": {
                    "turnId": "review-worker",
                    "item": {
                        "id": item_id,
                        "type": "userMessage",
                        "clientId": null,
                        "content": [{
                            "type": "text",
                            "text": "Review the current code changes (staged, unstaged, and untracked files) and provide prioritized findings."
                        }]
                    }
                }
            }),
        );
    }

    let saved = snapshot(&record);
    assert_eq!(saved["activeTurnId"], "review-envelope");
    assert_eq!(
        saved["aleraReviewTransition"],
        json!({
            "entryTurnId": "review-envelope",
            "workerTurnId": "review-worker",
        })
    );
    let cells = saved["timelineCells"].as_array().unwrap();
    assert!(cells
        .iter()
        .filter_map(|cell| cell.get("turnId").and_then(Value::as_str))
        .all(|turn_id| turn_id == "review-envelope"));
    assert_eq!(
        cells
            .iter()
            .filter(|cell| cell["kind"] == "userMessage")
            .count(),
        1
    );
}

#[test]
fn live_review_reuses_the_existing_envelope_separator_identity() {
    let mut record = tab();
    append_message(
        &mut record,
        json!({
            "method": "codex/event/task_started",
            "params": {"msg": {
                "type": "task_started",
                "turn_id": "review-envelope"
            }}
        }),
    );
    let previous = snapshot(&record);
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

    let saved = snapshot(&record);
    let separators = saved["timelineCells"]
        .as_array()
        .unwrap()
        .iter()
        .filter(|cell| cell["kind"] == "turnSeparator")
        .collect::<Vec<_>>();
    assert_eq!(separators.len(), 1);
    assert_eq!(separators[0]["id"], "turn-review-envelope");
    assert_eq!(separators[0]["turnId"], "review-envelope");
    assert_eq!(saved["activeTurnId"], "review-envelope");
    let delta = snapshot_delta(&previous, &saved, &[]);
    assert_eq!(delta["timelineRemovedIds"], json!([]));
    assert!(delta["timelineUpserts"]
        .as_array()
        .unwrap()
        .iter()
        .all(|cell| cell["id"] != "turn-review-worker"));
}

#[test]
fn live_review_delta_appends_the_normalized_events_without_replacing_history() {
    let mut record = tab();
    let previous = snapshot(&record);
    let messages = [
        json!({
            "method": "codex/event/entered_review_mode",
            "params": {"msg": {
                "type": "entered_review_mode",
                "turn_id": "review-envelope"
            }}
        }),
        json!({
            "method": "codex/event/task_started",
            "params": {"msg": {
                "type": "task_started",
                "turn_id": "review-worker"
            }}
        }),
        json!({
            "method": "item/completed",
            "params": {
                "turnId": "review-worker",
                "item": {
                    "id": "read-1",
                    "type": "commandExecution",
                    "command": "rg --files",
                    "status": "completed"
                }
            }
        }),
    ];
    let mut normalized = Vec::new();
    for message in messages {
        let (_, normalized_message) = append_message_with_normalized(&mut record, message);
        normalized.push(normalized_message);
    }

    let saved = snapshot(&record);
    let delta = snapshot_delta(&previous, &saved, &normalized);
    assert_eq!(delta["eventsAppend"], Value::Array(normalized));
    assert!(delta.get("eventsReplace").is_none());
}

#[test]
fn review_completion_closes_the_canonical_turn() {
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
            "method": "codex/event/task_complete",
            "params": {"msg": {
                "type": "task_complete",
                "turn_id": "review-envelope"
            }}
        }),
    );

    let saved = snapshot(&record);
    assert!(saved["activeTurnId"].is_null());
    assert!(saved.get("aleraReviewTransition").is_none());
    let separator = saved["timelineCells"]
        .as_array()
        .unwrap()
        .iter()
        .find(|cell| cell["kind"] == "turnSeparator")
        .unwrap();
    assert_eq!(separator["turnId"], "review-envelope");
    assert!(separator["metadata"]["computedDurationMs"].is_number());

    append_message(
        &mut record,
        json!({
            "method": "codex/event/user_message",
            "params": {"msg": {
                "type": "user_message",
                "message": "A later normal prompt"
            }}
        }),
    );
    let saved = snapshot(&record);
    assert_eq!(
        saved["timelineCells"]
            .as_array()
            .unwrap()
            .iter()
            .filter(|cell| cell["kind"] == "userMessage")
            .count(),
        0
    );
}

#[test]
fn legacy_review_abort_closes_the_transition_before_the_next_turn() {
    let mut record = tab();
    for message in [
        json!({
            "method": "codex/event/entered_review_mode",
            "params": {"msg": {
                "type": "entered_review_mode",
                "turn_id": "review-envelope"
            }}
        }),
        json!({
            "method": "codex/event/task_started",
            "params": {"msg": {
                "type": "task_started",
                "turn_id": "review-worker"
            }}
        }),
        json!({
            "method": "codex/event/turn_aborted",
            "params": {"msg": {
                "type": "turn_aborted",
                "turn_id": "review-worker"
            }}
        }),
        json!({
            "method": "codex/event/task_started",
            "params": {"msg": {
                "type": "task_started",
                "turn_id": "normal-turn"
            }}
        }),
    ] {
        append_message(&mut record, message);
    }

    let saved = snapshot(&record);
    assert!(saved.get("aleraReviewTransition").is_none());
    assert_eq!(saved["activeTurnId"], "normal-turn");
    let separators = saved["timelineCells"]
        .as_array()
        .unwrap()
        .iter()
        .filter(|cell| cell["kind"] == "turnSeparator")
        .map(|cell| (&cell["turnId"], &cell["status"]))
        .collect::<Vec<_>>();
    assert!(separators.contains(&(&json!("review-envelope"), &json!("completed"))));
    assert!(separators.contains(&(&json!("normal-turn"), &json!("info"))));
}

#[test]
fn legacy_task_failure_closes_the_review_turn_and_streams() {
    let mut record = tab();
    append_message(
        &mut record,
        json!({
            "method": "codex/event/task_started",
            "params": {"msg": {"type": "task_started", "turn_id": "turn-failed"}}
        }),
    );
    append_message(
        &mut record,
        json!({
            "method": "item/started",
            "params": {
                "turnId": "turn-failed",
                "item": {"id": "reasoning", "type": "reasoning", "status": "inProgress"}
            }
        }),
    );
    append_message(
        &mut record,
        json!({
            "method": "codex/event/task_failed",
            "params": {"msg": {
                "type": "task_failed",
                "turn_id": "turn-failed",
                "message": "review failed"
            }}
        }),
    );

    let saved = snapshot(&record);
    assert!(saved.get("activeTurnId").is_none());
    assert!(saved["timelineCells"]
        .as_array()
        .unwrap()
        .iter()
        .filter(|cell| cell["turnId"] == "turn-failed")
        .all(|cell| cell["isStreaming"] != true));
    let separator = saved["timelineCells"]
        .as_array()
        .unwrap()
        .iter()
        .find(|cell| cell["kind"] == "turnSeparator")
        .unwrap();
    assert_eq!(separator["status"], "failed");
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
