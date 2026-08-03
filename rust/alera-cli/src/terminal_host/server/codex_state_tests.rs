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
fn deltas_coalesce_into_one_assistant_cell() {
    let mut record = tab();
    append_message(
        &mut record,
        json!({"method":"turn/started","params":{"turn":{"id":"turn"}}}),
    );
    append_message(
        &mut record,
        json!({"method":"item/agentMessage/delta","params":{"turnId":"turn","itemId":"answer","delta":"Hello"}}),
    );
    append_message(
        &mut record,
        json!({"method":"item/agentMessage/delta","params":{"turnId":"turn","itemId":"answer","delta":" world"}}),
    );
    let saved = snapshot(&record);
    let cells = saved["timelineCells"].as_array().unwrap();
    let answer = cells
        .iter()
        .find(|cell| cell["id"] == "item-answer")
        .unwrap();
    assert_eq!(answer["markdownText"], "Hello world");
    assert_eq!(answer["kind"], "assistantMessage");
    assert_eq!(
        cells
            .iter()
            .filter(|cell| cell["id"] == "item-answer")
            .count(),
        1
    );
}

#[test]
fn duplicate_pending_requests_replace_the_previous_entry() {
    let mut record = tab();
    append_message(
        &mut record,
        json!({"id":7,"method":"item/commandExecution/requestApproval","params":{"command":"git status"}}),
    );
    append_message(
        &mut record,
        json!({"id":7,"method":"item/commandExecution/requestApproval","params":{"command":"git diff"}}),
    );
    let saved = snapshot(&record);
    let requests = saved["pendingRequests"].as_array().unwrap();
    assert_eq!(requests.len(), 1);
    assert_eq!(requests[0]["params"]["command"], "git diff");
}

#[test]
fn question_answers_are_persisted_as_timeline_cells() {
    let mut record = tab();
    append_message(
        &mut record,
        json!({
            "id": 7,
            "method": "item/tool/request_user_input",
            "params": {"questions": [{"id": "mode", "question": "Choose a mode"}]}
        }),
    );
    append_question_answer(
        &mut record,
        &json!(7),
        &json!({"answers": {"mode": {"answers": ["Careful"]}}}),
    );
    let saved = snapshot(&record);
    assert_eq!(saved["timelineCells"][0]["kind"], "questionAnswer");
    assert_eq!(saved["timelineCells"][0]["markdownText"], "Careful");
}

#[test]
fn historical_list_question_answers_are_still_persisted() {
    let mut record = tab();
    append_message(
        &mut record,
        json!({
            "id": 7,
            "method": "item/tool/request_user_input",
            "params": {"questions": [{"id": "mode", "question": "Choose a mode"}]}
        }),
    );
    append_question_answer(
        &mut record,
        &json!(7),
        &json!({"answers": [{"answers": ["Careful"]}]}),
    );
    assert_eq!(
        snapshot(&record)["timelineCells"][0]["markdownText"],
        "Careful"
    );
}

#[test]
fn resolved_server_requests_are_removed_from_the_snapshot() {
    let mut record = tab();
    append_message(
        &mut record,
        json!({"id": 7, "method": "item/commandExecution/requestApproval", "params": {}}),
    );
    append_message(
        &mut record,
        json!({"method": "serverRequest/resolved", "params": {"requestId": 7}}),
    );
    assert_eq!(snapshot(&record)["pendingRequests"], json!([]));
}

#[test]
fn diff_updates_replace_the_full_snapshot() {
    let mut record = tab();
    append_message(
        &mut record,
        json!({
            "method": "turn/diff/updated",
            "params": {"turnId": "turn", "diff": "first"}
        }),
    );
    append_message(
        &mut record,
        json!({
            "method": "turn/diff/updated",
            "params": {"turnId": "turn", "diff": "second"}
        }),
    );
    let saved = snapshot(&record);
    let cells = saved["timelineCells"].as_array().unwrap();
    assert_eq!(
        cells.iter().find(|cell| cell["id"] == "diff-turn").unwrap()["detailsText"],
        "second"
    );
}

#[test]
fn empty_diff_snapshot_replaces_previous_content() {
    let mut record = tab();
    append_message(
        &mut record,
        json!({
            "method": "turn/diff/updated",
            "params": {"turnId": "turn", "diff": "content"}
        }),
    );
    append_message(
        &mut record,
        json!({
            "method": "turn/diff/updated",
            "params": {"turnId": "turn", "diff": ""}
        }),
    );
    assert_eq!(
        snapshot(&record)["timelineCells"]
            .as_array()
            .unwrap()
            .iter()
            .find(|cell| cell["id"] == "diff-turn")
            .unwrap()["detailsText"],
        ""
    );
}

#[test]
fn timeline_cells_keep_raw_and_rendered_markdown() {
    let mut record = tab();
    append_message(
        &mut record,
        json!({
            "method": "item/agentMessage/delta",
            "params": {"turnId": "turn", "itemId": "answer", "delta": "**hello"}
        }),
    );
    let saved = snapshot(&record);
    let cell = saved["timelineCells"]
        .as_array()
        .unwrap()
        .iter()
        .find(|cell| cell["id"] == "item-answer")
        .unwrap();
    assert_eq!(cell["markdownText"], "**hello");
    assert_eq!(cell["renderedMarkdownText"], "**hello**");
}

#[test]
fn close_and_restart_snapshot_preserves_timeline() {
    let mut record = tab();
    append_user_input(
        &mut record,
        &json!([{"type":"text","text":"hello"}]),
        "turn",
    );
    let saved = snapshot(&record);
    let mut restarted = tab();
    restarted.payload["codexSnapshot"] = saved;
    let restored = snapshot(&restarted);
    assert_eq!(restored["timelineCells"][0]["kind"], "userMessage");
}

#[test]
fn snapshots_remain_bounded() {
    let mut record = tab();
    for index in 0..(MAX_SNAPSHOT_EVENTS + 20) {
        append_message(&mut record, json!({"index": index, "text": "event"}));
    }
    assert!(snapshot(&record)["events"].as_array().unwrap().len() <= MAX_SNAPSHOT_EVENTS);
}

#[test]
fn pending_request_can_be_removed_from_durable_snapshot() {
    let mut record = tab();
    append_message(
        &mut record,
        json!({"id":7,"method":"item/commandExecution/requestApproval","params":{}}),
    );
    remove_pending_request(&mut record, &json!(7));
    assert_eq!(snapshot(&record)["pendingRequests"], json!([]));
}

#[test]
fn command_terminal_and_file_change_streams_keep_specific_kinds() {
    let mut record = tab();
    append_message(
        &mut record,
        json!({
            "method": "item/commandExecution/outputDelta",
            "params": {"turnId": "turn", "itemId": "command", "delta": "done"}
        }),
    );
    append_message(
        &mut record,
        json!({
            "method": "item/fileChange/outputDelta",
            "params": {"turnId": "turn", "itemId": "files", "delta": "diff"}
        }),
    );
    let saved = snapshot(&record);
    let cells = saved["timelineCells"].as_array().unwrap();
    assert_eq!(
        cells
            .iter()
            .find(|cell| cell["id"] == "item-command")
            .unwrap()["kind"],
        "command"
    );
    assert_eq!(
        cells
            .iter()
            .find(|cell| cell["id"] == "item-files")
            .unwrap()["kind"],
        "diff"
    );
}

#[test]
fn legacy_item_events_and_task_completion_reduce_to_timeline_cells() {
    let mut record = tab();
    append_message(
        &mut record,
        json!({
            "method": "codex/event/item_started",
            "params": {"msg": {"turn_id": "turn", "item": {"id": "answer", "type": "agentMessage"}}}
        }),
    );
    append_message(
        &mut record,
        json!({
            "method": "codex/event/task_complete",
            "params": {"msg": {"turn_id": "turn", "last_agent_message": "done"}}
        }),
    );
    let saved = snapshot(&record);
    let cells = saved["timelineCells"].as_array().unwrap();
    let answer = cells
        .iter()
        .find(|cell| cell["id"] == "assistant-turn")
        .unwrap();
    assert_eq!(answer["kind"], "assistantMessage");
    assert_eq!(answer["markdownText"], "done");
    assert_eq!(answer["isStreaming"], false);
}

#[test]
fn commentary_phase_and_repeated_output_are_reduced_once() {
    let mut record = tab();
    append_message(
        &mut record,
        json!({
            "method": "codex/event/item_started",
            "params": {"msg": {"turn_id": "turn", "item": {
                "id": "commentary", "type": "AgentMessage", "phase": "commentary"
            }}}
        }),
    );
    append_message(
        &mut record,
        json!({
            "method": "item/agentMessage/delta",
            "params": {"turnId": "turn", "itemId": "commentary", "delta": "Inspecting files"}
        }),
    );
    append_message(
        &mut record,
        json!({
            "method": "item/commandExecution/outputDelta",
            "params": {"turnId": "turn", "itemId": "command", "delta": "clean"}
        }),
    );
    append_message(
        &mut record,
        json!({
            "method": "item/commandExecution/outputDelta",
            "params": {"turnId": "turn", "itemId": "command", "delta": "clean"}
        }),
    );
    let saved = snapshot(&record);
    let cells = saved["timelineCells"].as_array().unwrap();
    assert_eq!(
        cells
            .iter()
            .find(|cell| cell["id"] == "item-commentary")
            .unwrap()["kind"],
        "progressText"
    );
    assert_eq!(
        cells
            .iter()
            .find(|cell| cell["id"] == "item-command")
            .unwrap()["detailsText"],
        "clean"
    );
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
fn server_failure_closes_streams_without_deleting_thread_history() {
    let mut record = tab();
    record.payload = json!({
        "codexThreadId": "thread-1",
        "codexSnapshot": {
            "events": [{"method": "turn/started"}],
            "timelineCells": [{
                "id": "item-answer",
                "turnId": "turn-1",
                "kind": "assistantMessage",
                "status": "inProgress",
                "isStreaming": true
            }],
            "pendingRequests": []
        }
    });
    let saved = mark_server_failure(&mut record, "app-server exited");
    assert_eq!(record.payload["codexThreadId"], "thread-1");
    assert!(saved["activeTurnId"].is_null());
    assert!(saved["timelineCells"]
        .as_array()
        .unwrap()
        .iter()
        .any(|cell| cell["status"] == "failed" && cell["kind"] == "systemNotice"));
}
