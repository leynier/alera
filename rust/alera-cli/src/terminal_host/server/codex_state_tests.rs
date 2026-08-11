use super::*;
use crate::terminal_host::server::codex_user_messages::append_user_input;
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
        json!({"method":"turn/started","params":{"turn":{"id":"turn-question"}}}),
    );
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
    let answer = saved["timelineCells"]
        .as_array()
        .unwrap()
        .iter()
        .find(|cell| cell["kind"] == "questionAnswer")
        .unwrap();
    assert_eq!(answer["markdownText"], "Careful");
    assert_eq!(answer["turnId"], "turn-question");
    assert_eq!(answer["metadata"]["questionCount"], 1);
}

#[test]
fn question_answer_cells_preserve_the_original_question_count() {
    let mut record = tab();
    append_message(
        &mut record,
        json!({
            "id": 7,
            "method": "item/tool/request_user_input",
            "params": {
                "questions": [
                    {"id": "scope", "question": "Choose a scope"},
                    {"id": "validation", "question": "Choose validation"}
                ]
            }
        }),
    );
    append_question_answer(
        &mut record,
        &json!(7),
        &json!({"answers": {"scope": {"answers": ["Core"]}}}),
    );

    let saved = snapshot(&record);
    let answer = saved["timelineCells"]
        .as_array()
        .unwrap()
        .iter()
        .find(|cell| cell["kind"] == "questionAnswer")
        .unwrap();
    assert_eq!(answer["metadata"]["questionCount"], 2);
    let questions = answer["metadata"]["questions"].as_array().unwrap();
    assert_eq!(questions.len(), 2);
    assert_eq!(questions[1]["answer"], "No answer provided");
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
        None,
        "turn",
        None,
        false,
    );
    let saved = snapshot(&record);
    assert_eq!(saved["activeTurnId"], "turn");
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
            "method": "codex/event/task_started",
            "params": {"msg": {"turn_id": "turn"}}
        }),
    );
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
    let separator = cells
        .iter()
        .find(|cell| cell["kind"] == "turnSeparator")
        .unwrap();
    assert_eq!(separator["status"], "completed");
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
fn canonical_item_identity_replaces_a_provisional_cell_in_place() {
    let mut cells = vec![json!({
        "id": "progressText-turn",
        "turnId": "turn",
        "kind": "progressText",
        "markdownText": "Inspecting",
        "metadata": {}
    })];

    codex_timeline_cells::upsert_cell(
        &mut cells,
        json!({
            "id": "item-commentary",
            "itemId": "commentary",
            "turnId": "turn",
            "kind": "progressText",
            "markdownText": "Inspecting files",
            "metadata": {"streamPhase": "commentary"}
        }),
    );

    assert_eq!(cells.len(), 1);
    assert_eq!(cells[0]["id"], "item-commentary");
    assert_eq!(cells[0]["itemId"], "commentary");
    assert_eq!(cells[0]["markdownText"], "Inspecting files");
}

#[test]
fn canonical_assistant_identity_replaces_the_legacy_alias_in_place() {
    let mut cells = vec![json!({
        "id": "assistant-turn",
        "turnId": "turn",
        "kind": "assistantMessage",
        "markdownText": "Done",
        "metadata": {}
    })];

    codex_timeline_cells::upsert_cell(
        &mut cells,
        json!({
            "id": "item-answer",
            "itemId": "answer",
            "turnId": "turn",
            "kind": "assistantMessage",
            "markdownText": "Done",
            "metadata": {"streamPhase": "final_answer"}
        }),
    );

    assert_eq!(cells.len(), 1);
    assert_eq!(cells[0]["id"], "item-answer");
    assert_eq!(cells[0]["itemId"], "answer");
}
