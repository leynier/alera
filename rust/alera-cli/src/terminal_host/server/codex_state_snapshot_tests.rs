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
fn token_usage_updates_context_metadata() {
    let mut record = tab();
    append_message(
        &mut record,
        json!({
            "method": "thread/tokenUsage/updated",
            "params": {"tokenUsage": {"totalTokens": 42, "contextWindow": 1000}}
        }),
    );
    let saved = snapshot(&record);
    assert_eq!(saved["contextUsed"], 42);
    assert_eq!(saved["contextLimit"], 1000);
}

#[test]
fn nested_token_usage_updates_context_metadata() {
    let mut record = tab();
    append_message(
        &mut record,
        json!({
            "method": "thread/tokenUsage/updated",
            "params": {
                "tokenUsage": {
                    "total": {"inputTokens": 12, "outputTokens": 8},
                    "modelContextWindow": 2000
                }
            }
        }),
    );
    let saved = snapshot(&record);
    assert_eq!(saved["contextUsed"], 20);
    assert_eq!(saved["contextLimit"], 2000);
}

#[test]
fn current_token_usage_uses_last_window_instead_of_cumulative_total() {
    let mut record = tab();
    append_message(
        &mut record,
        json!({
            "method": "thread/tokenUsage/updated",
            "params": {
                "tokenUsage": {
                    "total": {"totalTokens": 424400},
                    "last": {
                        "inputTokens": 60000,
                        "cachedInputTokens": 50000,
                        "outputTokens": 5000,
                        "reasoningOutputTokens": 3000,
                        "totalTokens": 65000
                    },
                    "modelContextWindow": 258400
                }
            }
        }),
    );
    let saved = snapshot(&record);
    assert_eq!(saved["contextUsed"], 65000);
    assert_eq!(saved["contextLimit"], 258400);
}

#[test]
fn snapshot_delta_only_upserts_changed_cells() {
    let previous = json!({
        "timelineCells": [
            {"id": "stable", "markdownText": "unchanged"},
            {"id": "stream", "markdownText": "one"},
            {"id": "removed", "markdownText": "old"}
        ],
        "pendingRequests": [],
        "activeTurnId": "turn-1"
    });
    let next = json!({
        "timelineCells": [
            {"id": "stable", "markdownText": "unchanged"},
            {"id": "stream", "markdownText": "one two"},
            {"id": "added", "markdownText": "new"}
        ],
        "pendingRequests": [{"id": 1}],
        "contextUsed": 42
    });
    let delta = snapshot_delta(
        &previous,
        &next,
        &[json!({"method": "item/agentMessage/delta"})],
    );

    assert_eq!(delta["timelineUpserts"].as_array().unwrap().len(), 2);
    assert_eq!(delta["timelineUpserts"][0]["id"], "stream");
    assert_eq!(delta["timelineUpserts"][1]["id"], "added");
    assert_eq!(delta["timelineRemovedIds"], json!([]));
    assert_eq!(delta["eventsAppend"], json!([]));
    assert_eq!(delta["eventsReplace"], json!([]));
    assert_eq!(delta["pendingRequests"], json!([{"id": 1}]));
    assert_eq!(delta["activeTurnId"], Value::Null);
    assert_eq!(delta["contextUsed"], 42);
}

#[test]
fn snapshot_delta_keeps_cells_evicted_from_the_bounded_live_window() {
    let previous = json!({
        "timelineCells": [
            {"id": "loaded-history", "markdownText": "older"},
            {"id": "live", "markdownText": "one"}
        ]
    });
    let next = json!({
        "timelineCells": [
            {"id": "live", "markdownText": "one two"},
            {"id": "new", "markdownText": "new"}
        ]
    });

    let delta = snapshot_delta(&previous, &next, &[]);

    assert_eq!(delta["timelineRemovedIds"], json!([]));
    assert_eq!(delta["timelineUpserts"][0]["id"], "live");
    assert_eq!(delta["timelineUpserts"][1]["id"], "new");
}

#[test]
fn snapshot_bounding_clears_stale_diff_supersession() {
    let mut cells = vec![json!({
        "id": "item-file-change",
        "turnId": "turn-1",
        "kind": "diff",
        "metadata": {
            "itemType": "fileChange",
            "changes": [{
                "path": "lib/example.dart",
                "diff": "@@ -1 +1 @@\n-old\n+new"
            }]
        }
    })];
    cells.extend((0..MAX_SNAPSHOT_CELLS - 1).map(|index| {
        json!({
            "id": format!("filler-{index}"),
            "turnId": "other-turn",
            "kind": "assistantMessage"
        })
    }));
    cells.push(json!({
        "id": "diff-turn-1",
        "turnId": "turn-1",
        "kind": "diff",
        "detailsText": "diff --git a/lib/example.dart b/lib/example.dart\n--- a/lib/example.dart\n+++ b/lib/example.dart\n@@ -1 +1 @@\n-old\n+new",
        "metadata": {"supersededByStructuredFileChanges": true}
    }));
    let mut snapshot = json!({"timelineCells": cells});

    bound_snapshot(&mut snapshot);

    assert_eq!(
        snapshot["timelineCells"]
            .as_array()
            .and_then(|cells| cells.last())
            .and_then(|cell| cell.pointer("/metadata/supersededByStructuredFileChanges")),
        None
    );
}

#[test]
fn direct_cell_trimming_clears_stale_diff_supersession() {
    let mut cells = vec![json!({
        "id": "item-file-change",
        "turnId": "turn-1",
        "kind": "diff",
        "metadata": {
            "itemType": "fileChange",
            "changes": [{
                "path": "lib/example.dart",
                "diff": "@@ -1 +1 @@\n-old\n+new"
            }]
        }
    })];
    cells.extend((0..MAX_SNAPSHOT_CELLS - 1).map(|index| {
        json!({
            "id": format!("filler-{index}"),
            "turnId": "other-turn",
            "kind": "assistantMessage"
        })
    }));
    cells.push(json!({
        "id": "diff-turn-1",
        "turnId": "turn-1",
        "kind": "diff",
        "detailsText": "diff --git a/lib/example.dart b/lib/example.dart\n--- a/lib/example.dart\n+++ b/lib/example.dart\n@@ -1 +1 @@\n-old\n+new",
        "metadata": {"supersededByStructuredFileChanges": true}
    }));

    trim_cells(&mut cells);

    assert_eq!(cells.len(), MAX_SNAPSHOT_CELLS);
    assert_eq!(
        cells
            .last()
            .and_then(|cell| cell.pointer("/metadata/supersededByStructuredFileChanges")),
        None
    );
}

#[test]
fn snapshot_delta_replaces_events_when_the_byte_budget_evicts_them() {
    let previous = json!({
        "events": [{"method": "old"}],
        "timelineCells": [],
    });
    let next = json!({
        "events": [{"method": "retained"}],
        "timelineCells": [],
    });
    let delta = snapshot_delta(&previous, &next, &[json!({"method": "large"})]);

    assert_eq!(delta["eventsReplace"], json!([{"method": "retained"}]));
    assert_eq!(delta["eventsAppend"], json!([]));
}

#[test]
fn resume_preserves_history_before_the_latest_context_boundary() {
    let stored = json!({
        "events": [],
        "timelineCells": [
            {"id": "old", "kind": "assistantMessage"},
            {"id": "boundary", "metadata": {"noticeType": "threadBoundary"}},
            {
                "id": "assistant-current",
                "kind": "assistantMessage",
                "markdownText": "Partial"
            }
        ],
        "pendingRequests": [],
    });
    let resumed = json!({
        "events": [{"method": "current"}],
        "timelineCells": [{"id": "fresh-current", "kind": "assistantMessage"}],
        "pendingRequests": [],
    });

    let merged = merge_resume_snapshot(&stored, resumed);
    let ids = merged["timelineCells"]
        .as_array()
        .unwrap()
        .iter()
        .filter_map(|cell| cell["id"].as_str())
        .collect::<Vec<_>>();
    assert_eq!(ids, vec!["old", "boundary", "fresh-current"]);
    assert_eq!(merged["events"], json!([{"method": "current"}]));
}

#[test]
fn resume_preserves_alera_owned_cells_after_the_latest_context_boundary() {
    let stored = json!({
        "events": [],
        "timelineCells": [
            {"id": "old", "kind": "assistantMessage"},
            {"id": "boundary", "metadata": {"noticeType": "threadBoundary"}},
            {
                "id": "user-current",
                "kind": "userMessage",
                "markdownText": "Review this file",
                "metadata": {
                    "clientUserMessageId": "client-current",
                    "attachments": [{"path": "/tmp/report.csv"}]
                }
            },
            {"id": "answer-current", "kind": "questionAnswer"},
            {
                "id": "assistant-current",
                "kind": "assistantMessage",
                "markdownText": "Partial"
            }
        ],
        "pendingRequests": [],
    });
    let resumed = json!({
        "events": [{"method": "current"}],
        "timelineCells": [
            {
                "id": "user-current",
                "kind": "userMessage",
                "markdownText": "/tmp/report.csv Review this file",
                "metadata": {"itemType": "userMessage"}
            },
            {
                "id": "assistant-current",
                "kind": "assistantMessage",
                "markdownText": "Complete"
            }
        ],
        "pendingRequests": [],
    });

    let merged = merge_resume_snapshot(&stored, resumed);
    let cells = merged["timelineCells"].as_array().unwrap();
    let ids = cells
        .iter()
        .filter_map(|cell| cell["id"].as_str())
        .collect::<Vec<_>>();

    assert_eq!(
        ids,
        vec![
            "old",
            "boundary",
            "user-current",
            "answer-current",
            "assistant-current"
        ]
    );
    assert_eq!(cells[2]["markdownText"], "Review this file");
    assert_eq!(cells[4]["markdownText"], "Complete");
    assert_eq!(cells[2]["metadata"]["itemType"], "userMessage");
    assert_eq!(
        cells[2]["metadata"]["attachments"][0]["path"],
        "/tmp/report.csv"
    );
}

#[test]
fn resume_preserves_the_stored_title_when_history_has_none() {
    let stored = json!({
        "title": "Manually renamed conversation",
        "events": [],
        "timelineCells": [],
        "pendingRequests": [],
    });
    let resumed = json!({
        "events": [],
        "timelineCells": [],
        "pendingRequests": [],
    });

    let merged = merge_resume_snapshot(&stored, resumed);

    assert_eq!(merged["title"], "Manually renamed conversation");
}

#[test]
fn resume_preserves_durable_current_thread_cells_missing_from_rollout_history() {
    let stored = json!({
        "events": [],
        "timelineCells": [
            {"id": "user", "kind": "userMessage", "markdownText": "Question"},
            {"id": "command", "kind": "command", "markdownText": "cargo test"},
            {"id": "assistant", "kind": "assistantMessage", "markdownText": "Partial"}
        ],
        "pendingRequests": [],
    });
    let resumed = json!({
        "events": [{"method": "current"}],
        "timelineCells": [
            {"id": "user", "kind": "userMessage", "markdownText": "Question"},
            {"id": "assistant", "kind": "assistantMessage", "markdownText": "Complete"},
            {"id": "follow-up", "kind": "assistantMessage", "markdownText": "New"}
        ],
        "pendingRequests": [],
    });

    let merged = merge_resume_snapshot(&stored, resumed);
    let cells = merged["timelineCells"].as_array().unwrap();
    let ids = cells
        .iter()
        .filter_map(|cell| cell["id"].as_str())
        .collect::<Vec<_>>();

    assert_eq!(ids, vec!["user", "command", "assistant", "follow-up"]);
    assert_eq!(cells[2]["markdownText"], "Complete");
}

#[test]
fn resume_inserts_older_server_history_before_the_stored_live_window() {
    let stored = json!({
        "events": [],
        "timelineCells": [
            {"id": "recent", "kind": "assistantMessage", "markdownText": "Recent"}
        ],
        "pendingRequests": [],
    });
    let resumed = json!({
        "events": [],
        "timelineCells": [
            {"id": "older", "kind": "userMessage", "markdownText": "Older"},
            {"id": "recent", "kind": "assistantMessage", "markdownText": "Recent from server"}
        ],
        "pendingRequests": [],
    });

    let merged = merge_resume_snapshot(&stored, resumed);
    let cells = merged["timelineCells"].as_array().unwrap();

    assert_eq!(cells[0]["id"], "older");
    assert_eq!(cells[1]["id"], "recent");
    assert_eq!(cells[1]["markdownText"], "Recent from server");
}

#[test]
fn resume_preserves_alera_owned_user_message_presentation() {
    let stored = json!({
        "events": [],
        "timelineCells": [{
            "id": "user-client-1",
            "turnId": "turn-1",
            "kind": "userMessage",
            "createdAt": "2026-08-08T10:00:00Z",
            "markdownText": "Review these files",
            "renderedMarkdownText": "Review these files",
            "metadata": {
                "attachments": [{"path": "/tmp/report.csv", "displayName": "report.csv"}],
                "clientUserMessageId": "client-1",
                "isSteering": true
            }
        }],
        "pendingRequests": [],
    });
    let resumed = json!({
        "events": [],
        "timelineCells": [{
            "id": "user-client-1",
            "turnId": "turn-1",
            "kind": "userMessage",
            "createdAt": "2026-08-08T10:00:01Z",
            "updatedAt": "2026-08-08T10:00:02Z",
            "markdownText": "/tmp/report.csv Review these files",
            "renderedMarkdownText": "/tmp/report.csv Review these files",
            "metadata": {"itemType": "userMessage"}
        }],
        "pendingRequests": [],
    });

    let merged = merge_resume_snapshot(&stored, resumed);
    let cell = &merged["timelineCells"][0];

    assert_eq!(cell["markdownText"], "Review these files");
    assert_eq!(cell["renderedMarkdownText"], "Review these files");
    assert_eq!(cell["createdAt"], "2026-08-08T10:00:00Z");
    assert_eq!(cell["updatedAt"], "2026-08-08T10:00:02Z");
    assert_eq!(cell["metadata"]["itemType"], "userMessage");
    assert_eq!(cell["metadata"]["clientUserMessageId"], "client-1");
    assert_eq!(cell["metadata"]["isSteering"], true);
    assert_eq!(
        cell["metadata"]["attachments"][0]["path"],
        "/tmp/report.csv"
    );
}
