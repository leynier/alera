use super::{
    latest_turn_page, older_turn_page, page_item_source_bytes, project_turns,
    MAX_HISTORY_SOURCE_BYTES,
};
use chrono::{SecondsFormat, TimeZone, Utc};
use serde_json::{json, Value};

#[test]
fn projects_persisted_turn_items_into_timeline_cells() {
    let snapshot = project_turns(&[json!({
        "id": "turn-1",
        "status": "completed",
        "items": [
            {"id": "user-1", "type": "userMessage", "content": [{"type": "text", "text": "Hello"}]},
            {"id": "assistant-1", "type": "agentMessage", "text": "Hi there"}
        ]
    })]);
    let cells = snapshot["timelineCells"].as_array().unwrap();
    assert!(cells.iter().any(|cell| cell["kind"] == "userMessage"));
    assert!(cells.iter().any(|cell| cell["kind"] == "assistantMessage"));
    assert!(snapshot["activeTurnId"].is_null());
}

#[test]
fn projected_history_preserves_persisted_turn_timestamps() {
    let started_at = 1_720_000_000;
    let completed_at = 1_720_000_045;
    let snapshot = project_turns(&[json!({
        "id": "turn-timestamped",
        "status": "completed",
        "startedAt": started_at,
        "completedAt": completed_at,
        "items": [
            {"id": "user-timestamped", "type": "userMessage", "content": [{"type": "text", "text": "Hello"}]},
            {"id": "assistant-timestamped", "type": "agentMessage", "text": "Hi"}
        ]
    })]);
    let expected_start = Utc
        .timestamp_opt(started_at, 0)
        .single()
        .unwrap()
        .to_rfc3339_opts(SecondsFormat::Secs, true);
    let expected_completion = Utc
        .timestamp_opt(completed_at, 0)
        .single()
        .unwrap()
        .to_rfc3339_opts(SecondsFormat::Secs, true);

    let cells = snapshot["timelineCells"].as_array().unwrap();
    let turn_cells = cells
        .iter()
        .filter(|cell| cell["turnId"] == "turn-timestamped")
        .collect::<Vec<_>>();
    assert!(!turn_cells.is_empty());
    assert!(turn_cells
        .iter()
        .all(|cell| cell["createdAt"] == expected_start));
    assert!(turn_cells
        .iter()
        .all(|cell| cell["updatedAt"] == expected_completion));
}

#[test]
fn in_progress_turns_keep_the_active_turn_marker() {
    let snapshot = project_turns(&[json!({
        "id": "turn-live",
        "status": "inProgress",
        "items": []
    })]);
    assert_eq!(snapshot["activeTurnId"], "turn-live");
}

#[test]
fn in_progress_items_remain_active_when_history_is_projected() {
    let snapshot = project_turns(&[json!({
        "id": "turn-live",
        "status": "inProgress",
        "items": [{
            "id": "command-live",
            "type": "commandExecution",
            "status": "inProgress",
            "command": "cargo test"
        }]
    })]);
    let command = snapshot["timelineCells"]
        .as_array()
        .unwrap()
        .iter()
        .find(|cell| cell["id"] == "item-command-live")
        .unwrap();

    assert_eq!(command["status"], "inProgress");
    assert_eq!(command["isStreaming"], true);
}

#[test]
fn failed_turns_keep_their_failure_status() {
    let snapshot = project_turns(&[json!({
        "id": "turn-failed",
        "status": "failed",
        "items": [{
            "id": "assistant-failed",
            "type": "agentMessage",
            "text": "Partial response"
        }]
    })]);
    assert_eq!(
        snapshot["events"].as_array().unwrap().last().unwrap()["method"],
        "turn/failed"
    );
    assert!(snapshot["activeTurnId"].is_null());
}

#[test]
fn latest_page_keeps_an_empty_in_progress_turn() {
    let response = json!({
        "thread": {
            "turns": [
                {
                    "id": "turn-old",
                    "status": "completed",
                    "items": [{"id": "user-old", "type": "userMessage", "content": [{"type": "text", "text": "Old"}]}]
                },
                {
                    "id": "turn-live",
                    "status": "inProgress",
                    "items": []
                }
            ]
        }
    });

    let latest = latest_turn_page(&response, 1).unwrap();

    assert_eq!(latest.snapshot["activeTurnId"], "turn-live");
    assert_eq!(latest.turns.len(), 1);
    assert_eq!(latest.turns[0]["id"], "turn-live");
    assert_eq!(latest.next_cursor.as_deref(), Some("turn-before:turn-live"));
}

#[test]
fn latest_page_keeps_an_empty_failed_turn_and_its_error() {
    let response = json!({
        "thread": {
            "turns": [
                {
                    "id": "turn-old",
                    "status": "completed",
                    "items": [{"id": "user-old", "type": "userMessage", "content": [{"type": "text", "text": "Old"}]}]
                },
                {
                    "id": "turn-failed",
                    "status": "failed",
                    "error": {"message": "The model failed before producing output."},
                    "items": []
                }
            ]
        }
    });

    let latest = latest_turn_page(&response, 1).unwrap();

    assert_eq!(latest.turns.len(), 1);
    assert_eq!(latest.turns[0]["id"], "turn-failed");
    assert_eq!(
        latest.snapshot["events"]
            .as_array()
            .unwrap()
            .last()
            .unwrap()["method"],
        "turn/failed"
    );
    assert_eq!(
        latest.snapshot["events"]
            .as_array()
            .unwrap()
            .last()
            .unwrap()["params"]["turn"]["error"]["message"],
        "The model failed before producing output."
    );
    let failure = latest.snapshot["timelineCells"]
        .as_array()
        .unwrap()
        .iter()
        .find(|cell| cell["kind"] == "systemNotice")
        .expect("an itemless failed turn remains visible");
    assert_eq!(failure["status"], "failed");
    assert_eq!(
        failure["markdownText"],
        "The model failed before producing output."
    );
    assert_eq!(
        latest.next_cursor.as_deref(),
        Some("turn-before:turn-failed")
    );
}

#[test]
fn pages_supported_thread_read_results_in_chronological_order() {
    let response = json!({
        "thread": {
            "turns": [
                {
                    "id": "turn-old",
                    "status": "completed",
                    "items": [{"id": "user-old", "type": "userMessage", "content": [{"type": "text", "text": "Old"}]}]
                },
                {
                    "id": "turn-middle",
                    "status": "completed",
                    "items": [{"id": "user-middle", "type": "userMessage", "content": [{"type": "text", "text": "Middle"}]}]
                },
                {
                    "id": "turn-new",
                    "status": "completed",
                    "items": [{"id": "user-new", "type": "userMessage", "content": [{"type": "text", "text": "New"}]}]
                }
            ]
        }
    });
    let latest = latest_turn_page(&response, 2).unwrap();
    assert_eq!(
        latest.next_cursor.as_deref(),
        Some("turn-before:turn-middle")
    );
    let cells = latest.snapshot["timelineCells"].as_array().unwrap();
    let messages = cells
        .iter()
        .filter(|cell| cell["kind"] == "userMessage")
        .map(|cell| cell["markdownText"].as_str().unwrap_or_default())
        .collect::<Vec<_>>();
    assert_eq!(messages, vec!["Middle", "New"]);
    assert!(latest
        .turns
        .iter()
        .all(|turn| turn.get("aleraHistoryItemsComplete").is_none()));
    assert_eq!(
        latest.snapshot["completeHistoryTurnIds"],
        json!(["turn-middle", "turn-new"])
    );

    let older = older_turn_page(&response, "turn-before:turn-middle", 2).unwrap();
    assert!(older.next_cursor.is_none());
    assert_eq!(older.turns[0]["id"], "turn-old");
}

#[test]
fn rejects_stale_or_malformed_history_cursors() {
    let response = json!({"thread": {"turns": []}});
    assert!(older_turn_page(&response, "server-cursor", 20).is_err());
    assert!(older_turn_page(&response, "turn-before:missing", 20).is_err());
}

#[test]
fn dense_turn_pages_do_not_skip_trimmed_items() {
    let items = (0..300)
        .map(|index| {
            json!({
                "id": format!("assistant-{index}"),
                "type": "agentMessage",
                "text": format!("History item {index}"),
            })
        })
        .collect::<Vec<_>>();
    let response = json!({
        "thread": {
            "turns": [{
                "id": "turn-dense",
                "status": "completed",
                "items": items,
            }]
        }
    });

    let mut page = latest_turn_page(&response, 20).unwrap();
    assert!(page.turns[0].get("aleraHistoryItemsComplete").is_none());
    assert!(page.snapshot["completeHistoryTurnIds"].is_null());
    let mut ids = page.snapshot["timelineCells"]
        .as_array()
        .unwrap()
        .iter()
        .filter_map(|cell| cell.get("id").and_then(Value::as_str))
        .filter(|id| id.starts_with("item-assistant-"))
        .map(str::to_string)
        .collect::<std::collections::HashSet<_>>();
    let mut page_count = 1;
    while let Some(cursor) = page.next_cursor.as_deref() {
        page = older_turn_page(&response, cursor, 20).unwrap();
        ids.extend(
            page.snapshot["timelineCells"]
                .as_array()
                .unwrap()
                .iter()
                .filter_map(|cell| cell.get("id").and_then(Value::as_str))
                .filter(|id| id.starts_with("item-assistant-"))
                .map(str::to_string),
        );
        page_count += 1;
        assert!(page_count < 10, "history cursor did not advance");
    }

    assert_eq!(ids.len(), 300);
}

#[test]
fn truncates_a_single_history_item_that_exceeds_the_byte_budget() {
    let response = json!({
        "thread": {
            "turns": [{
                "id": "turn-large",
                "status": "completed",
                "items": [{
                    "id": "assistant-large",
                    "type": "agentMessage",
                    "text": "x".repeat(MAX_HISTORY_SOURCE_BYTES + 1),
                }],
            }],
        },
    });

    let page = latest_turn_page(&response, 20).unwrap();

    assert_eq!(page.turns.len(), 1);
    assert!(page.next_cursor.is_none());
    assert!(page.turns[0]["items"][0]["truncated"].as_bool().unwrap());
    assert!(page_item_source_bytes(&page.turns) <= MAX_HISTORY_SOURCE_BYTES);
    assert!(page.snapshot["timelineCells"]
        .as_array()
        .unwrap()
        .iter()
        .any(|cell| cell["markdownText"]
            .as_str()
            .is_some_and(|text| text.contains("truncated"))));
}
