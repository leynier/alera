use super::*;

#[test]
fn paginated_history_merges_the_review_envelope_and_worker() {
    let page = codex_history_projection::latest_turn_page(
        &json!({
            "thread": {"turns": [
                {
                    "id": "review-envelope",
                    "status": "interrupted",
                    "items": [
                        {"id": "entry", "type": "enteredReviewMode", "review": "Review the changes."},
                        {"id": "exit", "type": "exitedReviewMode"}
                    ]
                },
                {
                    "id": "review-worker",
                    "status": "interrupted",
                    "items": [
                        {"id": "user-1", "type": "userMessage", "clientId": null,
                         "content": [{"type": "text", "text": "Review the changes."}]},
                        {"id": "user-2", "type": "userMessage", "clientId": null,
                         "content": [{"type": "text", "text": "Review the changes."}]},
                        {"id": "answer", "type": "agentMessage", "text": "No findings."}
                    ]
                }
            ]}
        }),
        1,
    )
    .unwrap();

    let cells = page.snapshot["timelineCells"].as_array().unwrap();
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
    assert_eq!(
        cells
            .iter()
            .filter(|cell| cell["kind"] == "turnSeparator")
            .count(),
        1
    );
}

#[test]
fn paginated_history_restores_an_active_review_transition() {
    let page = codex_history_projection::latest_turn_page(
        &json!({
            "thread": {"turns": [
                {
                    "id": "review-envelope",
                    "status": "completed",
                    "items": [
                        {"id": "entry", "type": "enteredReviewMode", "review": "Review the changes."}
                    ]
                },
                {
                    "id": "review-worker",
                    "status": "inProgress",
                    "items": [
                        {"id": "user-1", "type": "userMessage", "clientId": null,
                         "content": [{"type": "text", "text": "Review the changes."}]},
                        {"id": "user-2", "type": "userMessage", "clientId": null,
                         "content": [{"type": "text", "text": "Review the changes."}]}
                    ]
                }
            ]}
        }),
        1,
    )
    .unwrap();

    assert_eq!(page.snapshot["activeTurnId"], "review-envelope");
    assert_eq!(
        page.snapshot["aleraReviewTransition"],
        json!({
            "entryTurnId": "review-envelope",
            "workerTurnId": "review-worker",
        })
    );
    assert!(page.turns[0].get("aleraReviewWorkerTurnId").is_none());
}

#[test]
fn history_does_not_restore_an_older_active_review_after_a_newer_turn() {
    let snapshot = codex_history_projection::project_turns(&[
        json!({
            "id": "review-envelope",
            "status": "completed",
            "items": [{"id": "entry", "type": "enteredReviewMode", "review": "Review the changes."}]
        }),
        json!({
            "id": "review-worker",
            "status": "inProgress",
            "items": [
                {"id": "user-1", "type": "userMessage", "clientId": null,
                 "content": [{"type": "text", "text": "Review the changes."}]},
                {"id": "user-2", "type": "userMessage", "clientId": null,
                 "content": [{"type": "text", "text": "Review the changes."}]}
            ]
        }),
        json!({
            "id": "newer-turn",
            "status": "completed",
            "items": [{"id": "answer", "type": "agentMessage", "text": "Done."}]
        }),
    ]);

    assert!(snapshot.get("activeTurnId").is_none());
    assert!(snapshot.get("aleraReviewTransition").is_none());
}

#[test]
fn history_merges_review_envelope_and_deduplicates_generated_prompt() {
    let turns = [
        json!({
            "id": "review-envelope",
            "status": "interrupted",
            "completedAt": 1_786_375_394_i64,
            "durationMs": 726_980,
            "items": [
                {"id": "entry", "type": "enteredReviewMode", "review": "current changes"},
                {"id": "exit", "type": "exitedReviewMode", "review": "Review finished"}
            ]
        }),
        json!({
            "id": "review-worker",
            "status": "interrupted",
            "startedAt": 1_786_374_667_i64,
            "items": [
                {"id": "user-1", "type": "userMessage", "clientId": null,
                 "content": [{"type": "text", "text": "Review the current code changes (staged, unstaged, and untracked files) and provide prioritized findings."}]},
                {"id": "user-2", "type": "userMessage", "clientId": null,
                 "content": [{"type": "text", "text": "Review the current code changes (staged, unstaged, and untracked files) and provide prioritized findings."}]},
                {"id": "answer", "type": "agentMessage", "text": "No findings."}
            ]
        }),
    ];
    let normalized = codex_review_transition::normalize_history_turns(&turns);
    let item_types = normalized[0]["items"]
        .as_array()
        .unwrap()
        .iter()
        .filter_map(|item| item.get("type").and_then(Value::as_str))
        .collect::<Vec<_>>();
    assert_eq!(
        item_types,
        [
            "enteredReviewMode",
            "userMessage",
            "agentMessage",
            "exitedReviewMode",
        ]
    );
    let snapshot = codex_history_projection::project_turns(&turns);

    let cells = snapshot["timelineCells"].as_array().unwrap();
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
    assert_eq!(
        cells
            .iter()
            .filter(|cell| cell["kind"] == "turnSeparator")
            .count(),
        1
    );
    let separator = cells
        .iter()
        .find(|cell| cell["kind"] == "turnSeparator")
        .unwrap();
    assert_eq!(separator["metadata"]["computedDurationMs"], 727_000);
}

#[test]
fn history_merge_preserves_worker_failure_and_error() {
    let normalized = codex_review_transition::normalize_history_turns(&[
        json!({
            "id": "review-envelope",
            "status": "completed",
            "items": [
                {"id": "entry", "type": "enteredReviewMode", "review": "Review the changes."},
                {"id": "exit", "type": "exitedReviewMode"}
            ]
        }),
        json!({
            "id": "review-worker",
            "status": "failed",
            "error": {"message": "model unavailable"},
            "items": [
                {"id": "user-1", "type": "userMessage", "clientId": null,
                 "content": [{"type": "text", "text": "Review the changes."}]},
                {"id": "user-2", "type": "userMessage", "clientId": null,
                 "content": [{"type": "text", "text": "Review the changes."}]}
            ]
        }),
    ]);

    assert_eq!(normalized[0]["status"], "failed");
    assert_eq!(normalized[0]["error"]["message"], "model unavailable");
}

#[test]
fn history_merge_preserves_an_active_review_worker() {
    let turns = [
        json!({
            "id": "review-envelope",
            "status": "interrupted",
            "completedAt": 1_786_375_394_i64,
            "durationMs": 727_000,
            "items": [
                {"id": "entry", "type": "enteredReviewMode", "review": "Review the changes."},
                {"id": "exit", "type": "exitedReviewMode"}
            ]
        }),
        json!({
            "id": "review-worker",
            "status": "inProgress",
            "startedAt": 1_786_374_667_i64,
            "items": [
                {"id": "user-1", "type": "userMessage", "clientId": null,
                 "content": [{"type": "text", "text": "Review the changes."}]},
                {"id": "user-2", "type": "userMessage", "clientId": null,
                 "content": [{"type": "text", "text": "Review the changes."}]}
            ]
        }),
    ];

    let normalized = codex_review_transition::normalize_history_turns(&turns);
    assert_eq!(normalized[0]["status"], "inProgress");
    assert!(normalized[0].get("completedAt").is_none());
    assert!(normalized[0].get("durationMs").is_none());

    let snapshot = codex_history_projection::project_turns(&turns);
    assert_eq!(snapshot["activeTurnId"], "review-envelope");
    assert_eq!(
        snapshot["aleraReviewTransition"],
        json!({
            "entryTurnId": "review-envelope",
            "workerTurnId": "review-worker",
        })
    );
    assert!(snapshot["timelineCells"]
        .as_array()
        .unwrap()
        .iter()
        .any(|cell| cell["turnId"] == "review-envelope"));

    let mut resumed = snapshot;
    let completed = codex_review_transition::normalize_live_message(
        &mut resumed,
        json!({
            "method": "turn/completed",
            "params": {"turn": {"id": "review-worker"}}
        }),
    );
    assert_eq!(completed["params"]["turn"]["id"], "review-envelope");
    assert!(resumed.get("aleraReviewTransition").is_none());
}

#[test]
fn history_does_not_merge_review_envelope_with_a_normal_user_turn() {
    let snapshot = codex_history_projection::project_turns(&[
        json!({
            "id": "review-envelope",
            "status": "completed",
            "items": [{"id": "entry", "type": "enteredReviewMode", "review": "current changes"}]
        }),
        json!({
            "id": "normal-turn",
            "status": "completed",
            "items": [{
                "id": "user-normal",
                "type": "userMessage",
                "clientId": "client-normal",
                "content": [{"type": "text", "text": "Normal prompt"}]
            }]
        }),
    ]);

    let turn_ids = snapshot["timelineCells"]
        .as_array()
        .unwrap()
        .iter()
        .filter_map(|cell| cell.get("turnId").and_then(Value::as_str))
        .collect::<std::collections::HashSet<_>>();
    assert_eq!(turn_ids.len(), 2);
}

#[test]
fn history_does_not_merge_a_single_clientless_user_turn() {
    let snapshot = codex_history_projection::project_turns(&[
        json!({
            "id": "review-envelope",
            "status": "completed",
            "items": [{"id": "entry", "type": "enteredReviewMode", "review": "current changes"}]
        }),
        json!({
            "id": "normal-turn",
            "status": "completed",
            "items": [{
                "id": "user-normal",
                "type": "userMessage",
                "content": [{"type": "text", "text": "Normal prompt"}]
            }]
        }),
    ]);

    let turn_ids = snapshot["timelineCells"]
        .as_array()
        .unwrap()
        .iter()
        .filter_map(|cell| cell.get("turnId").and_then(Value::as_str))
        .collect::<std::collections::HashSet<_>>();
    assert_eq!(turn_ids.len(), 2);
}

#[test]
fn history_does_not_merge_duplicate_clientless_text_without_matching_review_identity() {
    let normalized = codex_review_transition::normalize_history_turns(&[
        json!({
            "id": "review-envelope",
            "status": "completed",
            "items": [{
                "id": "entry",
                "type": "enteredReviewMode",
                "review": "current changes"
            }]
        }),
        json!({
            "id": "ordinary-turn",
            "status": "completed",
            "items": [
                {"id": "user-1", "type": "userMessage", "clientId": null,
                 "content": [{"type": "text", "text": "Repeat this ordinary prompt."}]},
                {"id": "user-2", "type": "userMessage", "clientId": null,
                 "content": [{"type": "text", "text": "Repeat this ordinary prompt."}]}
            ]
        }),
    ]);

    assert_eq!(normalized.len(), 2);
    assert_eq!(normalized[0]["id"], "review-envelope");
    assert_eq!(normalized[1]["id"], "ordinary-turn");
    assert_eq!(normalized[1]["items"].as_array().unwrap().len(), 2);
}

#[test]
fn standalone_duplicate_clientless_turn_is_not_fabricated_as_review() {
    let response = json!({
        "thread": {"turns": [{
            "id": "review-worker",
            "status": "completed",
            "items": [
                {"id": "user-1", "type": "userMessage", "clientId": null,
                 "content": [{"type": "text", "text": "Review the changes."}]},
                {"id": "user-2", "type": "userMessage", "clientId": null,
                 "content": [{"type": "text", "text": "Review the changes."}]},
                {"id": "answer", "type": "agentMessage", "text": "No findings."}
            ]
        }]}
    });
    let normalized = codex_review_transition::normalize_history_turns(
        response["thread"]["turns"].as_array().unwrap(),
    );
    assert_eq!(
        normalized[0]["items"]
            .as_array()
            .unwrap()
            .iter()
            .filter(|item| item["type"] == "userMessage")
            .count(),
        2
    );
    let page = codex_history_projection::latest_turn_page(&response, 1).unwrap();

    let cells = page.snapshot["timelineCells"].as_array().unwrap();
    assert_eq!(
        cells
            .iter()
            .filter(|cell| cell["metadata"]["itemType"] == "enteredReviewMode")
            .count(),
        0
    );
}
