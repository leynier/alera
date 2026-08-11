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
fn complete_history_deduplicates_when_early_events_are_missing() {
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
    let mut page = latest_turn_page(&response, 20).unwrap();
    assert_eq!(
        page.snapshot["completeHistoryTurnIds"],
        json!(["turn-large"])
    );
    page.snapshot["events"]
        .as_array_mut()
        .unwrap()
        .retain(|event| event["method"] != "turn/started");
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

#[test]
fn resume_reconciles_progress_text_with_remapped_item_ids() {
    let stored = resumed_snapshot(
        vec![json!({
            "id": "item-live-progress",
            "turnId": "turn-1",
            "kind": "progressText",
            "markdownText": "Inspecting files",
            "metadata": {"streamPhase": "commentary"}
        })],
        true,
    );
    let resumed = resumed_snapshot(
        vec![json!({
            "id": "item-rollout-progress",
            "turnId": "turn-1",
            "kind": "progressText",
            "markdownText": "Inspecting   files",
            "metadata": {"streamPhase": "commentary"}
        })],
        true,
    );

    let merged = merge_resume_snapshot(&stored, resumed);
    let progress = merged["timelineCells"]
        .as_array()
        .unwrap()
        .iter()
        .filter(|cell| cell["kind"] == "progressText")
        .collect::<Vec<_>>();

    assert_eq!(progress.len(), 1);
    assert_eq!(progress[0]["id"], "item-rollout-progress");
}

#[test]
fn resume_reconciles_a_legacy_agent_cell_without_stream_phase() {
    let stored = resumed_snapshot(
        vec![json!({
            "id": "item-live-answer",
            "turnId": "turn-1",
            "kind": "assistantMessage",
            "markdownText": "Finished"
        })],
        false,
    );
    let resumed = resumed_snapshot(
        vec![json!({
            "id": "item-rollout-answer",
            "turnId": "turn-1",
            "kind": "assistantMessage",
            "markdownText": "Finished",
            "metadata": {"streamPhase": "final_answer"}
        })],
        false,
    );

    let merged = merge_resume_snapshot(&stored, resumed);
    let answers = merged["timelineCells"]
        .as_array()
        .unwrap()
        .iter()
        .filter(|cell| cell["kind"] == "assistantMessage")
        .collect::<Vec<_>>();

    assert_eq!(answers.len(), 1);
    assert_eq!(answers[0]["id"], "item-rollout-answer");
}

#[test]
fn resume_reconciles_an_explicit_phase_with_phase_less_history() {
    let stored = resumed_snapshot(
        vec![json!({
            "id": "item-live-answer",
            "turnId": "turn-1",
            "kind": "assistantMessage",
            "markdownText": "Finished",
            "metadata": {"streamPhase": "final_answer"}
        })],
        false,
    );
    let resumed = resumed_snapshot(
        vec![json!({
            "id": "item-rollout-answer",
            "turnId": "turn-1",
            "kind": "assistantMessage",
            "markdownText": "Finished"
        })],
        false,
    );

    let merged = merge_resume_snapshot(&stored, resumed);
    let answers = merged["timelineCells"]
        .as_array()
        .unwrap()
        .iter()
        .filter(|cell| cell["kind"] == "assistantMessage")
        .collect::<Vec<_>>();

    assert_eq!(answers.len(), 1);
    assert_eq!(answers[0]["id"], "item-rollout-answer");
}

#[test]
fn phase_less_history_does_not_claim_ambiguous_explicit_phases() {
    let stored = resumed_snapshot(
        vec![
            json!({
                "id": "item-live-commentary",
                "turnId": "turn-1",
                "kind": "assistantMessage",
                "markdownText": "Done",
                "metadata": {"streamPhase": "commentary"}
            }),
            json!({
                "id": "item-live-answer",
                "turnId": "turn-1",
                "kind": "assistantMessage",
                "markdownText": "Done",
                "metadata": {"streamPhase": "final_answer"}
            }),
        ],
        false,
    );
    let resumed = resumed_snapshot(
        vec![json!({
            "id": "item-rollout-phase-less",
            "turnId": "turn-1",
            "kind": "assistantMessage",
            "markdownText": "Done"
        })],
        false,
    );

    let merged = merge_resume_snapshot(&stored, resumed);
    let ids = merged["timelineCells"]
        .as_array()
        .unwrap()
        .iter()
        .filter(|cell| cell["kind"] == "assistantMessage")
        .map(|cell| cell["id"].as_str().unwrap())
        .collect::<Vec<_>>();

    assert_eq!(
        ids,
        vec![
            "item-rollout-phase-less",
            "item-live-commentary",
            "item-live-answer"
        ]
    );
}

#[test]
fn resume_keeps_explicit_agent_stream_phases_distinct() {
    let stored = resumed_snapshot(
        vec![
            json!({
                "id": "item-live-commentary",
                "turnId": "turn-1",
                "kind": "assistantMessage",
                "markdownText": "Done",
                "metadata": {"streamPhase": "commentary"}
            }),
            json!({
                "id": "item-live-answer",
                "turnId": "turn-1",
                "kind": "assistantMessage",
                "markdownText": "Done",
                "metadata": {"streamPhase": "final_answer"}
            }),
        ],
        false,
    );
    let resumed = resumed_snapshot(
        vec![json!({
            "id": "item-rollout-answer",
            "turnId": "turn-1",
            "kind": "assistantMessage",
            "markdownText": "Done",
            "metadata": {"streamPhase": "final_answer"}
        })],
        false,
    );

    let merged = merge_resume_snapshot(&stored, resumed);
    let ids = merged["timelineCells"]
        .as_array()
        .unwrap()
        .iter()
        .filter(|cell| cell["kind"] == "assistantMessage")
        .map(|cell| cell["id"].as_str().unwrap())
        .collect::<Vec<_>>();

    assert_eq!(ids, vec!["item-live-commentary", "item-rollout-answer"]);
}
