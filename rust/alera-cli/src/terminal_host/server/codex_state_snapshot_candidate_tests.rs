use super::*;

fn resumed_snapshot(cells: Vec<Value>) -> Value {
    json!({
        "completeHistoryTurnIds": [],
        "events": [{
            "method": "turn/started",
            "params": {
                "turnId": "turn-1",
                "turn": {"aleraHistoryItemsComplete": false}
            }
        }],
        "timelineCells": cells,
        "pendingRequests": [],
    })
}

#[test]
fn resume_matches_repeated_legacy_agent_cells_one_to_one() {
    let stored = resumed_snapshot(vec![
        json!({
            "id": "item-live-answer-1",
            "turnId": "turn-1",
            "kind": "assistantMessage",
            "markdownText": "Done"
        }),
        json!({
            "id": "item-live-answer-2",
            "turnId": "turn-1",
            "kind": "assistantMessage",
            "markdownText": "Done"
        }),
    ]);
    let resumed = resumed_snapshot(vec![json!({
        "id": "item-rollout-answer",
        "turnId": "turn-1",
        "kind": "assistantMessage",
        "markdownText": "Done",
        "metadata": {"streamPhase": "final_answer"}
    })]);

    let merged = merge_resume_snapshot(&stored, resumed);
    let ids = merged["timelineCells"]
        .as_array()
        .unwrap()
        .iter()
        .filter(|cell| cell["kind"] == "assistantMessage")
        .map(|cell| cell["id"].as_str().unwrap())
        .collect::<Vec<_>>();

    assert_eq!(ids, vec!["item-rollout-answer", "item-live-answer-2"]);
}

#[test]
fn complete_history_removes_every_matching_phase_less_agent_copy() {
    let stored = resumed_snapshot(vec![
        json!({
            "id": "item-live-answer-1",
            "turnId": "turn-1",
            "kind": "assistantMessage",
            "markdownText": "Done"
        }),
        json!({
            "id": "item-live-answer-2",
            "turnId": "turn-1",
            "kind": "assistantMessage",
            "markdownText": "Done"
        }),
    ]);
    let mut resumed = resumed_snapshot(vec![json!({
        "id": "item-rollout-answer",
        "turnId": "turn-1",
        "kind": "assistantMessage",
        "markdownText": "Done",
        "metadata": {"streamPhase": "final_answer"}
    })]);
    resumed["completeHistoryTurnIds"] = json!(["turn-1"]);
    resumed["events"][0]["params"]["turn"]["aleraHistoryItemsComplete"] = json!(true);

    let merged = merge_resume_snapshot(&stored, resumed);
    let ids = merged["timelineCells"]
        .as_array()
        .unwrap()
        .iter()
        .filter(|cell| cell["kind"] == "assistantMessage")
        .map(|cell| cell["id"].as_str().unwrap())
        .collect::<Vec<_>>();

    assert_eq!(ids, vec!["item-rollout-answer"]);
}

#[test]
fn partial_history_keeps_one_unmatched_phase_less_agent_copy() {
    let stored = resumed_snapshot(vec![
        json!({
            "id": "item-live-answer-1",
            "turnId": "turn-1",
            "kind": "assistantMessage",
            "markdownText": "Done"
        }),
        json!({
            "id": "item-live-answer-2",
            "turnId": "turn-1",
            "kind": "assistantMessage",
            "markdownText": "Done"
        }),
    ]);
    let resumed = resumed_snapshot(vec![json!({
        "id": "item-rollout-answer",
        "turnId": "turn-1",
        "kind": "assistantMessage",
        "markdownText": "Done",
        "metadata": {"streamPhase": "final_answer"}
    })]);

    let merged = merge_resume_snapshot(&stored, resumed);
    let ids = merged["timelineCells"]
        .as_array()
        .unwrap()
        .iter()
        .filter(|cell| cell["kind"] == "assistantMessage")
        .map(|cell| cell["id"].as_str().unwrap())
        .collect::<Vec<_>>();

    assert_eq!(ids, vec!["item-rollout-answer", "item-live-answer-2"]);
}

#[test]
fn resume_replaces_a_unique_streaming_prefix_in_place() {
    let stored = resumed_snapshot(vec![json!({
        "id": "progress-turn-1",
        "turnId": "turn-1",
        "kind": "progressText",
        "markdownText": "Inspecting",
        "isStreaming": true,
        "metadata": {"streamPhase": "commentary"}
    })]);
    let resumed = resumed_snapshot(vec![json!({
        "id": "item-rollout-progress",
        "turnId": "turn-1",
        "kind": "progressText",
        "markdownText": "Inspecting files",
        "isStreaming": false,
        "metadata": {"streamPhase": "commentary"}
    })]);

    let merged = merge_resume_snapshot(&stored, resumed);
    let cells = merged["timelineCells"].as_array().unwrap();

    assert_eq!(cells.len(), 1);
    assert_eq!(cells[0]["id"], "item-rollout-progress");
    assert_eq!(cells[0]["markdownText"], "Inspecting files");
}

#[test]
fn delta_retires_the_legacy_assistant_alias_after_promotion() {
    let previous = json!({
        "timelineCells": [{
            "id": "assistant-turn-1",
            "turnId": "turn-1",
            "kind": "assistantMessage",
            "markdownText": "Done"
        }]
    });
    let next = json!({
        "timelineCells": [{
            "id": "item-answer",
            "itemId": "answer",
            "turnId": "turn-1",
            "kind": "assistantMessage",
            "markdownText": "Done"
        }]
    });

    let delta = snapshot_delta(&previous, &next, &[]);

    assert_eq!(delta["timelineRemovedIds"], json!(["assistant-turn-1"]));
    assert_eq!(delta["timelineUpserts"][0]["id"], "item-answer");
}

#[test]
fn delta_does_not_retire_a_legacy_alias_that_already_has_an_item_id() {
    let previous = json!({
        "timelineCells": [{
            "id": "assistant-turn-1",
            "itemId": "older-answer",
            "turnId": "turn-1",
            "kind": "assistantMessage"
        }]
    });
    let next = json!({
        "timelineCells": [{
            "id": "item-answer",
            "itemId": "answer",
            "turnId": "turn-1",
            "kind": "assistantMessage"
        }]
    });

    let delta = snapshot_delta(&previous, &next, &[]);

    assert_eq!(delta["timelineRemovedIds"], json!([]));
}
