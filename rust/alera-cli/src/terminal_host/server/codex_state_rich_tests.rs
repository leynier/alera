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
fn turn_completion_records_server_duration_on_the_separator() {
    let mut record = tab();
    append_message(
        &mut record,
        json!({
            "method": "turn/started",
            "params": {"turn": {"id": "turn", "startedAt": "2026-08-03T12:00:00Z"}}
        }),
    );
    append_message(
        &mut record,
        json!({
            "method": "turn/completed",
            "params": {"turn": {
                "id": "turn",
                "startedAt": "2026-08-03T12:00:00Z",
                "completedAt": "2026-08-03T12:00:01.250Z",
                "durationMs": 1250
            }}
        }),
    );
    let saved = snapshot(&record);
    let separator = saved["timelineCells"]
        .as_array()
        .unwrap()
        .iter()
        .find(|cell| cell["kind"] == "turnSeparator")
        .unwrap();
    assert_eq!(separator["metadata"]["computedDurationMs"], 1250);
    assert_eq!(
        separator["metadata"]["completedAt"],
        "2026-08-03T12:00:01.250Z"
    );
}

#[test]
fn modern_app_server_items_keep_rich_content_and_metadata() {
    let mut record = tab();
    append_message(
        &mut record,
        json!({
            "method": "item/completed",
            "params": {"turnId": "turn", "item": {
                "id": "search",
                "type": "webSearch",
                "query": "Alera",
                "action": {"type": "search", "query": "Alera"},
                "status": "completed"
            }}
        }),
    );
    append_message(
        &mut record,
        json!({
            "method": "item/completed",
            "params": {"turnId": "turn", "item": {
                "id": "mcp",
                "type": "mcpToolCall",
                "server": "codex_apps",
                "tool": "calendar.lookup",
                "arguments": {"calendarId": "work"},
                "result": {
                    "content": [{"type": "text", "text": "Found 2 events"}],
                    "structuredContent": {"count": 2}
                },
                "durationMs": 21,
                "status": "completed"
            }}
        }),
    );
    append_message(
        &mut record,
        json!({
            "method": "item/completed",
            "params": {"turnId": "turn", "item": {
                "id": "dynamic",
                "type": "dynamicToolCall",
                "namespace": "workspace",
                "tool": "inspect",
                "arguments": {"path": "README.md"},
                "contentItems": [{"type": "inputText", "text": "done"}],
                "durationMs": 42,
                "status": "completed"
            }}
        }),
    );
    append_message(
        &mut record,
        json!({
            "method": "item/completed",
            "params": {"turnId": "turn", "item": {
                "id": "generated",
                "type": "imageGeneration",
                "result": "https://example.com/generated.png",
                "status": "completed"
            }}
        }),
    );
    append_message(
        &mut record,
        json!({
            "method": "item/completed",
            "params": {"turnId": "turn", "item": {
                "id": "legacy-output",
                "type": "dynamicToolCall",
                "tool": "legacy.inspect",
                "output": {"records": [1, 2]},
                "status": "completed"
            }}
        }),
    );
    let saved = snapshot(&record);
    let cells = saved["timelineCells"].as_array().unwrap();
    let search = cells
        .iter()
        .find(|cell| cell["id"] == "item-search")
        .unwrap();
    assert_eq!(search["kind"], "toolCall");
    assert_eq!(search["title"], "Web search");
    assert_eq!(search["metadata"]["query"], "Alera");
    let mcp = cells.iter().find(|cell| cell["id"] == "item-mcp").unwrap();
    assert_eq!(mcp["metadata"]["server"], "codex_apps");
    assert_eq!(mcp["metadata"]["tool"], "calendar.lookup");
    assert_eq!(mcp["metadata"]["arguments"]["calendarId"], "work");
    assert_eq!(mcp["metadata"]["result"]["structuredContent"]["count"], 2);
    assert_eq!(mcp["metadata"]["detailsSource"], "result");
    let dynamic = cells
        .iter()
        .find(|cell| cell["id"] == "item-dynamic")
        .unwrap();
    assert_eq!(dynamic["kind"], "toolCall");
    assert_eq!(dynamic["title"], "inspect");
    assert_eq!(dynamic["metadata"]["namespace"], "workspace");
    assert_eq!(dynamic["metadata"]["contentItems"][0]["text"], "done");
    assert_eq!(dynamic["metadata"]["durationMs"], 42);
    assert_eq!(dynamic["metadata"]["detailsSource"], "contentItems");
    assert!(dynamic["detailsText"].is_null());
    let generated = cells
        .iter()
        .find(|cell| cell["id"] == "item-generated")
        .unwrap();
    assert_eq!(generated["title"], "Generated image");
    assert_eq!(
        generated["detailsText"],
        "https://example.com/generated.png"
    );
    assert_eq!(
        generated["metadata"]["result"],
        "https://example.com/generated.png"
    );
    let legacy_output = cells
        .iter()
        .find(|cell| cell["id"] == "item-legacy-output")
        .unwrap();
    assert!(legacy_output["detailsText"].is_null());
    assert_eq!(legacy_output["metadata"]["detailsSource"], "output");
    assert_eq!(
        legacy_output["metadata"]["output"]["records"],
        json!([1, 2])
    );
}

#[test]
fn large_embedded_tool_media_stays_inside_snapshot_and_delta_budgets() {
    let mut record = tab();
    let embedded = "YWJj".repeat(MAX_SNAPSHOT_BYTES);
    let message = json!({
        "method": "item/completed",
        "params": {"turnId": "turn", "item": {
            "id": "dynamic-media",
            "type": "dynamicToolCall",
            "tool": "media.inspect",
            "contentItems": [{
                "type": "inputImage",
                "imageUrl": format!("data:image/png;base64,{embedded}")
            }],
            "status": "completed"
        }}
    });
    let previous = snapshot(&record);
    let saved = append_message(&mut record, message.clone());
    let saved_bytes = serde_json::to_vec(&saved).unwrap();
    assert!(saved_bytes.len() <= MAX_SNAPSHOT_BYTES);
    assert!(saved["events"].as_array().is_some_and(Vec::is_empty));

    let media = &saved["timelineCells"][0]["metadata"]["contentItems"][0];
    assert_eq!(media["type"], "image");
    assert_eq!(media["mimeType"], "image/*");
    assert!(media["byteLength"].as_u64().is_some_and(|bytes| bytes > 0));
    assert!(media.get("imageUrl").is_none());
    assert!(saved["timelineCells"][0]["detailsText"].is_null());

    let delta = snapshot_delta(&previous, &saved, &[message]);
    assert!(delta["eventsAppend"].as_array().is_some_and(Vec::is_empty));
    assert!(serde_json::to_vec(&delta).unwrap().len() <= MAX_SNAPSHOT_BYTES);
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
