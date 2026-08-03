//! Durable Codex timeline snapshots stored inside workspace tab payloads.

use alera_core::runtime::WorkspaceTabRecord;
use chrono::Utc;
use serde_json::{json, Map, Value};

use crate::terminal_host::protocol::CODEX_TAB_KIND;

pub(super) const CODEX_SNAPSHOT_VERSION: i64 = 1;
const MAX_SNAPSHOT_EVENTS: usize = 240;
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
    payload.insert("codexSnapshot".to_string(), next_snapshot);
    payload.remove("codexActiveTurnId");
    tab.updated_at = Utc::now();
}

pub(super) fn append_message(tab: &mut WorkspaceTabRecord, message: Value) -> Value {
    let mut next = snapshot(tab);
    let object = ensure_payload_object(&mut next);
    object.insert(
        "schemaVersion".to_string(),
        Value::Number(CODEX_SNAPSHOT_VERSION.into()),
    );
    let events = object
        .entry("events")
        .or_insert_with(|| Value::Array(Vec::new()));
    if let Value::Array(events) = events {
        events.push(message.clone());
    }
    loop {
        let event_count = next
            .get("events")
            .and_then(Value::as_array)
            .map_or(0, Vec::len);
        let too_large =
            serde_json::to_vec(&next).is_ok_and(|bytes| bytes.len() > MAX_SNAPSHOT_BYTES);
        if event_count <= MAX_SNAPSHOT_EVENTS && !too_large {
            break;
        }
        let Some(events) = next.get_mut("events").and_then(Value::as_array_mut) else {
            break;
        };
        if events.len() <= 1 {
            break;
        }
        events.remove(0);
    }
    update_turn_and_pending(&mut next, &message);
    let active_turn = active_turn_id(&next);
    if let Some(payload) = tab.payload.as_object_mut() {
        payload.insert("codexSnapshot".to_string(), next.clone());
        match active_turn {
            Some(turn_id) => {
                payload.insert("codexActiveTurnId".to_string(), Value::String(turn_id));
            }
            None => {
                payload.remove("codexActiveTurnId");
            }
        }
    }
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
    let Some(requests) = snapshot
        .get_mut("pendingRequests")
        .and_then(Value::as_array_mut)
    else {
        return;
    };
    requests.retain(|request| request.get("id") != Some(request_id));
}

pub(super) fn thread_id_from_message(message: &Value) -> Option<String> {
    for candidate in [
        message.pointer("/params/threadId"),
        message.pointer("/params/thread/id"),
        message.pointer("/params/turn/threadId"),
        message.pointer("/params/item/threadId"),
        message.pointer("/result/thread/id"),
        message.pointer("/result/threadId"),
    ] {
        if let Some(value) = candidate
            .and_then(Value::as_str)
            .filter(|value| !value.is_empty())
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
        message.pointer("/params/item/turnId"),
        message.pointer("/result/turn/id"),
        message.pointer("/result/turnId"),
    ] {
        if let Some(value) = candidate
            .and_then(Value::as_str)
            .filter(|value| !value.is_empty())
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

fn update_turn_and_pending(snapshot: &mut Value, message: &Value) {
    let Some(object) = snapshot.as_object_mut() else {
        return;
    };
    let method = message
        .get("method")
        .and_then(Value::as_str)
        .unwrap_or_default();
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
    if method.is_empty() && message.get("id").is_some() {
        if let Some(requests) = object
            .get_mut("pendingRequests")
            .and_then(Value::as_array_mut)
        {
            let response_id = message.get("id");
            requests.retain(|request| request.get("id") != response_id);
        }
    } else if let (Some(id), Some(method)) = (message.get("id"), message.get("method")) {
        if !id.is_null() {
            let requests = object
                .entry("pendingRequests")
                .or_insert_with(|| Value::Array(Vec::new()));
            if let Value::Array(requests) = requests {
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

fn ensure_payload_object(value: &mut Value) -> &mut Map<String, Value> {
    if !value.is_object() {
        *value = Value::Object(Map::new());
    }
    value
        .as_object_mut()
        .expect("value was normalized to an object")
}

#[cfg(test)]
mod tests {
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
    fn snapshots_keep_events_and_active_turn() {
        let mut record = tab();
        let snapshot = append_message(
            &mut record,
            json!({
                "method": "turn/started",
                "params": {"threadId": "thread", "turn": {"id": "turn"}}
            }),
        );
        assert_eq!(active_turn_id(&snapshot).as_deref(), Some("turn"));
        assert_eq!(
            thread_id_from_message(&snapshot["events"][0]),
            Some("thread".into())
        );
    }

    #[test]
    fn snapshots_are_bounded() {
        let mut record = tab();
        for index in 0..(MAX_SNAPSHOT_EVENTS + 20) {
            append_message(&mut record, json!({"index": index, "text": "event"}));
        }
        let mut snapshot = snapshot(&record);
        assert!(snapshot["events"]
            .as_array()
            .is_some_and(|events| events.len() <= MAX_SNAPSHOT_EVENTS));
        let _ = &mut snapshot;
    }

    #[test]
    fn pending_request_can_be_removed_from_the_durable_snapshot() {
        let mut record = tab();
        append_message(
            &mut record,
            json!({
                "id": 7,
                "method": "item/commandExecution/requestApproval",
                "params": {"threadId": "thread", "turnId": "turn"}
            }),
        );
        remove_pending_request(&mut record, &json!(7));
        assert_eq!(snapshot(&record)["pendingRequests"], json!([]));
    }

    #[test]
    fn thread_name_notifications_are_available_to_the_title_reducer() {
        assert_eq!(
            thread_title_from_message(&json!({
                "method": "thread/name/updated",
                "params": {"threadName": "Review session"}
            }))
            .as_deref(),
            Some("Review session")
        );
    }
}
