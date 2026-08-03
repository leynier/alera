//! Durable Codex timeline snapshots stored inside workspace tab payloads.
//!
//! The app-server emits many deltas for one logical item. This module keeps a
//! bounded raw log for diagnostics and a stable, persisted timeline projection
//! for every client. The projection is intentionally JSON so older hosts and
//! newer desktop/mobile clients can reconnect without a protocol bump.

use alera_core::runtime::WorkspaceTabRecord;
use chrono::Utc;
use serde_json::{json, Value};

use crate::terminal_host::protocol::CODEX_TAB_KIND;

#[path = "codex_markdown.rs"]
mod codex_markdown;
#[path = "codex_state_snapshot.rs"]
mod codex_state_snapshot;
#[path = "codex_timeline_cells.rs"]
mod codex_timeline_cells;
#[path = "codex_timeline_state.rs"]
mod codex_timeline_state;

use codex_state_snapshot::{
    bound_snapshot, ensure_payload_object, normalize_snapshot, persist_snapshot, trim_cells,
    trim_events, update_context_usage,
};

pub(super) const CODEX_SNAPSHOT_VERSION: i64 = 2;
const MAX_SNAPSHOT_EVENTS: usize = 160;
const MAX_SNAPSHOT_CELLS: usize = 240;
const MAX_SNAPSHOT_BYTES: usize = 512 * 1024;

pub(super) fn is_codex_tab(tab: &WorkspaceTabRecord) -> bool {
    tab.kind == CODEX_TAB_KIND
}

pub(super) fn tab_thread_id(tab: &WorkspaceTabRecord) -> Option<String> {
    tab.payload
        .get("codexThreadId")
        .and_then(Value::as_str)
        .filter(|value| !value.trim().is_empty())
        .map(str::to_string)
}

pub(super) fn snapshot(tab: &WorkspaceTabRecord) -> Value {
    tab.payload
        .get("codexSnapshot")
        .filter(|value| value.is_object())
        .cloned()
        .unwrap_or_else(|| {
            json!({
                "schemaVersion": CODEX_SNAPSHOT_VERSION,
                "events": [],
                "timelineCells": [],
                "pendingRequests": [],
            })
        })
}

pub(super) fn set_thread_and_snapshot(
    tab: &mut WorkspaceTabRecord,
    thread_id: &str,
    next_snapshot: Value,
) {
    let payload = ensure_payload_object(&mut tab.payload);
    payload.insert(
        "codexThreadId".to_string(),
        Value::String(thread_id.to_string()),
    );
    payload.insert(
        "codexSnapshot".to_string(),
        normalize_snapshot(next_snapshot),
    );
    payload.remove("codexActiveTurnId");
    tab.updated_at = Utc::now();
}

pub(super) fn append_user_input(
    tab: &mut WorkspaceTabRecord,
    input: &Value,
    turn_id: &str,
) -> Value {
    let text = input
        .as_array()
        .into_iter()
        .flatten()
        .filter_map(|part| {
            if part.get("type").and_then(Value::as_str) == Some("text") {
                part.get("text").and_then(Value::as_str)
            } else {
                None
            }
        })
        .collect::<Vec<_>>()
        .join("\n");
    let attachments = input
        .as_array()
        .into_iter()
        .flatten()
        .filter(|part| part.get("type").and_then(Value::as_str) != Some("text"))
        .cloned()
        .collect::<Vec<_>>();
    let mut next = snapshot(tab);
    let object = ensure_payload_object(&mut next);
    let cells = object
        .entry("timelineCells".to_string())
        .or_insert_with(|| Value::Array(Vec::new()));
    if let Value::Array(cells) = cells {
        let now = Utc::now().to_rfc3339();
        cells.push(json!({
            "id": format!("user-{turn_id}"),
            "turnId": turn_id,
            "kind": "userMessage",
            "status": "completed",
            "createdAt": now,
            "updatedAt": now,
            "isStreaming": false,
            "isCollapsed": false,
            "markdownText": text,
            "renderedMarkdownText": codex_markdown::render_markdown(&text),
            "metadata": {"attachments": attachments},
        }));
        trim_cells(cells);
    }
    persist_snapshot(tab, next.clone());
    next
}

pub(super) fn append_message(tab: &mut WorkspaceTabRecord, message: Value) -> Value {
    let mut next = snapshot(tab);
    let object = ensure_payload_object(&mut next);
    object.insert(
        "schemaVersion".to_string(),
        Value::Number(CODEX_SNAPSHOT_VERSION.into()),
    );
    let events = object
        .entry("events".to_string())
        .or_insert_with(|| Value::Array(Vec::new()));
    if let Value::Array(events) = events {
        events.push(message.clone());
        trim_events(events);
    }
    reduce_timeline(&mut next, &message);
    update_turn_and_pending(&mut next, &message);
    next = normalize_snapshot(next);
    bound_snapshot(&mut next);
    persist_snapshot(tab, next.clone());
    next
}

pub(super) fn mark_server_failure(tab: &mut WorkspaceTabRecord, reason: &str) -> Value {
    let mut next = snapshot(tab);
    let object = ensure_payload_object(&mut next);
    object.remove("activeTurnId");
    if let Some(cells) = object
        .get_mut("timelineCells")
        .and_then(Value::as_array_mut)
    {
        for cell in cells.iter_mut() {
            if cell.get("isStreaming").and_then(Value::as_bool) != Some(true) {
                continue;
            }
            if let Some(map) = cell.as_object_mut() {
                map.insert("status".to_string(), Value::String("failed".to_string()));
                map.insert("isStreaming".to_string(), Value::Bool(false));
            }
        }
        let now = Utc::now().to_rfc3339();
        cells.push(json!({
            "id": format!("server-error-{}", Utc::now().timestamp_nanos_opt().unwrap_or_default()),
            "kind": "systemNotice",
            "status": "failed",
            "createdAt": now,
            "updatedAt": now,
            "isStreaming": false,
            "isCollapsed": false,
            "title": "Codex error",
            "markdownText": reason,
            "renderedMarkdownText": codex_markdown::render_markdown(reason),
            "metadata": {"source": "codexServer"},
        }));
        trim_cells(cells);
    }
    persist_snapshot(tab, next.clone());
    next
}

pub(super) fn active_turn_id(snapshot: &Value) -> Option<String> {
    snapshot
        .get("activeTurnId")
        .and_then(Value::as_str)
        .filter(|value| !value.is_empty())
        .map(str::to_string)
}

pub(super) fn remove_pending_request(tab: &mut WorkspaceTabRecord, request_id: &Value) {
    let payload = ensure_payload_object(&mut tab.payload);
    let Some(snapshot) = payload
        .get_mut("codexSnapshot")
        .and_then(Value::as_object_mut)
    else {
        return;
    };
    if let Some(requests) = snapshot
        .get_mut("pendingRequests")
        .and_then(Value::as_array_mut)
    {
        requests.retain(|request| request.get("id") != Some(request_id));
    }
}

pub(super) fn append_question_answer(
    tab: &mut WorkspaceTabRecord,
    request_id: &Value,
    result: &Value,
) {
    let payload = ensure_payload_object(&mut tab.payload);
    let Some(saved_snapshot) = payload.get("codexSnapshot").cloned() else {
        return;
    };
    let Some(request) = saved_snapshot
        .get("pendingRequests")
        .and_then(Value::as_array)
        .and_then(|requests| {
            requests.iter().find(|request| {
                request.get("id") == Some(request_id)
                    && request
                        .get("method")
                        .and_then(Value::as_str)
                        .is_some_and(|method| {
                            method.to_lowercase().contains("question")
                                || method.to_lowercase().contains("input")
                        })
            })
        })
    else {
        return;
    };
    let answers = result.get("answers");
    let question_values = request
        .pointer("/params/questions")
        .and_then(Value::as_array)
        .cloned()
        .unwrap_or_default();
    let mut answered = Vec::new();
    for (index, question) in question_values.iter().enumerate() {
        let question_id = question
            .get("id")
            .or_else(|| question.get("key"))
            .and_then(Value::as_str)
            .unwrap_or(if index == 0 { "question-0" } else { "" });
        let Some(raw_answer) = answers.and_then(|answers| {
            answers
                .as_object()
                .and_then(|values| values.get(question_id))
                .or_else(|| answers.as_array().and_then(|values| values.get(index)))
        }) else {
            continue;
        };
        let answer = raw_answer
            .get("answers")
            .and_then(Value::as_array)
            .map(|values| {
                values
                    .iter()
                    .filter_map(Value::as_str)
                    .collect::<Vec<_>>()
                    .join(", ")
            })
            .or_else(|| {
                raw_answer.as_array().map(|values| {
                    values
                        .iter()
                        .filter_map(Value::as_str)
                        .collect::<Vec<_>>()
                        .join(", ")
                })
            })
            .or_else(|| raw_answer.as_str().map(str::to_string))
            .unwrap_or_else(|| raw_answer.to_string());
        if !answer.trim().is_empty() && answer != "null" {
            let question_text = question
                .get("question")
                .or_else(|| question.get("prompt"))
                .and_then(Value::as_str)
                .unwrap_or("Codex question");
            answered.push(json!({"question": question_text, "answer": answer}));
        }
    }
    if answered.is_empty() {
        return;
    }
    let mut next = saved_snapshot;
    let object = ensure_payload_object(&mut next);
    let cells = object
        .entry("timelineCells".to_string())
        .or_insert_with(|| Value::Array(Vec::new()));
    if let Value::Array(cells) = cells {
        let now = Utc::now().to_rfc3339();
        let summary = answered
            .iter()
            .filter_map(|answer| answer.get("answer").and_then(Value::as_str))
            .map(str::to_string)
            .collect::<Vec<_>>()
            .join(", ");
        cells.push(json!({
            "id": format!("qa-{}", request_id),
            "kind": "questionAnswer",
            "status": "completed",
            "createdAt": now,
            "updatedAt": now,
            "isStreaming": false,
            "isCollapsed": false,
            "title": "Question Answer",
            "markdownText": summary,
            "renderedMarkdownText": codex_markdown::render_markdown(&summary),
            "metadata": {"questions": answered},
        }));
        trim_cells(cells);
    }
    persist_snapshot(tab, next);
}

pub(super) fn thread_id_from_message(message: &Value) -> Option<String> {
    for candidate in [
        message.pointer("/params/threadId"),
        message.pointer("/params/thread/id"),
        message.pointer("/params/turn/threadId"),
        message.pointer("/params/turn/thread_id"),
        message.pointer("/params/msg/thread_id"),
        message.pointer("/params/msg/threadId"),
        message.pointer("/params/item/threadId"),
        message.pointer("/result/thread/id"),
        message.pointer("/result/threadId"),
    ] {
        if let Some(value) = candidate
            .and_then(Value::as_str)
            .filter(|value| !value.trim().is_empty())
        {
            return Some(value.to_string());
        }
    }
    None
}

pub(super) fn turn_id_from_message(message: &Value) -> Option<String> {
    for candidate in [
        message.pointer("/params/turn/id"),
        message.pointer("/params/turnId"),
        message.pointer("/params/turn_id"),
        message.pointer("/params/item/turnId"),
        message.pointer("/params/item/turn_id"),
        message.pointer("/params/item/turnID"),
        message.pointer("/params/msg/turn_id"),
        message.pointer("/params/msg/turnId"),
        message.pointer("/result/turn/id"),
        message.pointer("/result/turnId"),
    ] {
        if let Some(value) = candidate
            .and_then(Value::as_str)
            .filter(|value| !value.trim().is_empty())
        {
            return Some(value.to_string());
        }
    }
    None
}

pub(super) fn thread_title_from_message(message: &Value) -> Option<String> {
    [
        message.pointer("/params/name"),
        message.pointer("/params/title"),
        message.pointer("/params/threadName"),
        message.pointer("/params/thread/name"),
        message.pointer("/result/thread/name"),
    ]
    .into_iter()
    .filter_map(|value| value.and_then(Value::as_str))
    .map(str::trim)
    .find(|value| !value.is_empty())
    .map(str::to_string)
}

fn reduce_timeline(snapshot: &mut Value, message: &Value) {
    codex_timeline_state::reduce_timeline(snapshot, message);
}

fn update_turn_and_pending(snapshot: &mut Value, message: &Value) {
    let Some(object) = snapshot.as_object_mut() else {
        return;
    };
    let raw_method = message
        .get("method")
        .and_then(Value::as_str)
        .unwrap_or_default();
    let method = match raw_method {
        "codex/event/task_complete" => "turn/completed",
        "codex/event/token_count" => "token_count",
        other => other,
    };
    if matches!(method, "turn/started" | "turn/created") {
        if let Some(turn_id) = turn_id_from_message(message) {
            object.insert("activeTurnId".to_string(), Value::String(turn_id));
        }
    } else if matches!(
        method,
        "turn/completed" | "turn/failed" | "turn/aborted" | "turn/interrupted"
    ) {
        object.remove("activeTurnId");
    }
    update_context_usage(object, message, method);
    if method == "serverRequest/resolved" {
        let request_id = message
            .pointer("/params/requestId")
            .or_else(|| message.pointer("/params/request_id"));
        if let Some(request_id) = request_id {
            if let Some(requests) = object
                .get_mut("pendingRequests")
                .and_then(Value::as_array_mut)
            {
                requests.retain(|request| request.get("id") != Some(request_id));
            }
        }
    } else if method.is_empty() && message.get("id").is_some() {
        if let Some(requests) = object
            .get_mut("pendingRequests")
            .and_then(Value::as_array_mut)
        {
            requests.retain(|request| request.get("id") != message.get("id"));
        }
    } else if let (Some(id), Some(method)) = (message.get("id"), message.get("method")) {
        if !id.is_null() {
            let requests = object
                .entry("pendingRequests".to_string())
                .or_insert_with(|| Value::Array(Vec::new()));
            if let Value::Array(requests) = requests {
                requests.retain(|request| request.get("id") != Some(id));
                requests.push(json!({
                    "id": id,
                    "method": method,
                    "params": message.get("params").cloned().unwrap_or(Value::Null),
                }));
                if requests.len() > 32 {
                    let excess = requests.len() - 32;
                    requests.drain(0..excess);
                }
            }
        }
    }
}

#[cfg(test)]
#[path = "codex_state_tests.rs"]
mod tests;
