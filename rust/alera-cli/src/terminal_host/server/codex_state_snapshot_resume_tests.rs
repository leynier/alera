use super::*;

fn resumed_snapshot(cells: Vec<Value>, items_complete: bool) -> Value {
    json!({
        "completeHistoryTurnIds": if items_complete { json!(["turn-1"]) } else { json!([]) },
        "events": [{
            "method": "turn/started",
            "params": {
                "turnId": "turn-1",
                "turn": {"aleraHistoryItemsComplete": items_complete}
            }
        }],
        "timelineCells": cells,
        "pendingRequests": [],
    })
}

#[test]
fn complete_large_history_deduplicates_when_early_events_are_evicted() {
    let repeated = "x".repeat(2000);
    let items = (0..50)
        .map(|index| {
            json!({
                "id": format!("assistant-{index}"),
                "type": "agentMessage",
                "text": if index == 49 {
                    "Same".to_string()
                } else {
                    format!("{index}-{repeated}")
                },
            })
        })
        .collect::<Vec<_>>();
    let response = json!({
        "thread": {"turns": [{
            "id": "turn-large",
            "status": "completed",
            "items": items,
        }]}
    });
    let page = latest_turn_page(&response, 20).unwrap();
    assert_eq!(
        page.snapshot["completeHistoryTurnIds"],
        json!(["turn-large"])
    );
    assert!(page.snapshot["events"]
        .as_array()
        .unwrap()
        .iter()
        .all(|event| event["method"] != "turn/started"));
    let stored = json!({
        "events": [],
        "timelineCells": [
            {"id": "live-a", "turnId": "turn-large", "kind": "assistantMessage", "markdownText": "Same"},
            {"id": "live-b", "turnId": "turn-large", "kind": "assistantMessage", "markdownText": "Same"}
        ],
        "pendingRequests": [],
    });

    let merged = merge_resume_snapshot(&stored, page.snapshot);
    let assistant_count = merged["timelineCells"]
        .as_array()
        .unwrap()
        .iter()
        .filter(|cell| cell["kind"] == "assistantMessage")
        .count();

    assert_eq!(assistant_count, 50);
}

#[test]
fn resume_deduplicates_reordered_messages_with_remapped_item_ids() {
    let stored = json!({
        "events": [],
        "timelineCells": [
            {
                "id": "mcp-startup-codex_apps",
                "kind": "toolCall",
                "title": "codex_apps MCP server"
            },
            {
                "id": "user-client-1",
                "turnId": "turn-1",
                "kind": "userMessage",
                "markdownText": "Hello",
                "metadata": {"clientUserMessageId": "client-1"}
            },
            {
                "id": "turn-turn-1",
                "turnId": "turn-1",
                "kind": "turnSeparator"
            },
            {
                "id": "user-client-1",
                "turnId": "turn-1",
                "kind": "userMessage",
                "markdownText": "Hello",
                "metadata": {"clientUserMessageId": "client-1"}
            },
            {
                "id": "item-item-2",
                "turnId": "turn-1",
                "kind": "assistantMessage",
                "markdownText": "Hello back"
            },
            {
                "id": "item-msg-live",
                "turnId": "turn-1",
                "kind": "assistantMessage",
                "markdownText": "Hello back"
            }
        ],
        "pendingRequests": [],
    });
    let resumed = resumed_snapshot(
        vec![
            json!({
                "id": "turn-turn-1",
                "turnId": "turn-1",
                "kind": "turnSeparator"
            }),
            json!({
                "id": "user-client-1",
                "turnId": "turn-1",
                "kind": "userMessage",
                "markdownText": "Hello",
                "metadata": {"itemType": "userMessage"}
            }),
            json!({
                "id": "item-item-2",
                "turnId": "turn-1",
                "kind": "assistantMessage",
                "markdownText": "Hello back"
            }),
        ],
        true,
    );

    let merged = merge_resume_snapshot(&stored, resumed);
    let cells = merged["timelineCells"].as_array().unwrap();
    let user_messages = cells
        .iter()
        .filter(|cell| cell["kind"] == "userMessage")
        .collect::<Vec<_>>();
    let assistant_messages = cells
        .iter()
        .filter(|cell| cell["kind"] == "assistantMessage")
        .collect::<Vec<_>>();

    assert_eq!(user_messages.len(), 1);
    assert_eq!(assistant_messages.len(), 1);
    assert_eq!(user_messages[0]["id"], "user-client-1");
    assert_eq!(assistant_messages[0]["id"], "item-item-2");
    assert_eq!(
        user_messages[0]["metadata"]["clientUserMessageId"],
        "client-1"
    );
    assert_eq!(cells[0]["id"], "mcp-startup-codex_apps");
}

#[test]
fn resume_preserves_repeated_messages_when_history_turn_is_partial() {
    let stored = json!({
        "events": [],
        "timelineCells": [
            {
                "id": "user-client-1",
                "turnId": "turn-1",
                "kind": "userMessage",
                "markdownText": "Continue",
                "metadata": {"clientUserMessageId": "client-1"}
            },
            {
                "id": "user-client-2",
                "turnId": "turn-1",
                "kind": "userMessage",
                "markdownText": "Continue",
                "metadata": {"clientUserMessageId": "client-2"}
            }
        ],
        "pendingRequests": [],
    });
    let resumed = resumed_snapshot(
        vec![json!({
            "id": "user-client-1",
            "turnId": "turn-1",
            "kind": "userMessage",
            "markdownText": "Continue",
            "metadata": {"itemType": "userMessage"}
        })],
        false,
    );

    let merged = merge_resume_snapshot(&stored, resumed);
    let user_ids = merged["timelineCells"]
        .as_array()
        .unwrap()
        .iter()
        .filter(|cell| cell["kind"] == "userMessage")
        .map(|cell| cell["id"].as_str().unwrap())
        .collect::<Vec<_>>();

    assert_eq!(user_ids, vec!["user-client-1", "user-client-2"]);
}

#[test]
fn resume_preserves_repeated_same_text_steering_messages_in_complete_history() {
    let stored = json!({
        "events": [],
        "timelineCells": [
            {
                "id": "user-client-1",
                "turnId": "turn-1",
                "kind": "userMessage",
                "markdownText": "Continue",
                "metadata": {"clientUserMessageId": "client-1", "isSteering": true}
            },
            {
                "id": "user-client-2",
                "turnId": "turn-1",
                "kind": "userMessage",
                "markdownText": "Continue",
                "metadata": {"clientUserMessageId": "client-2", "isSteering": true}
            }
        ],
        "pendingRequests": [],
    });
    let resumed = resumed_snapshot(
        vec![json!({
            "id": "user-turn-1",
            "turnId": "turn-1",
            "kind": "userMessage",
            "markdownText": "Continue",
            "metadata": {"itemType": "userMessage"}
        })],
        true,
    );

    let merged = merge_resume_snapshot(&stored, resumed);
    let user_ids = merged["timelineCells"]
        .as_array()
        .unwrap()
        .iter()
        .filter(|cell| cell["kind"] == "userMessage")
        .map(|cell| cell["id"].as_str().unwrap())
        .collect::<Vec<_>>();

    assert_eq!(user_ids, vec!["user-turn-1", "user-client-2"]);
}
