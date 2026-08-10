//! Normalizes Codex Review's envelope turn and worker turn into one timeline turn.

use chrono::Utc;
use serde_json::{json, Map, Value};

use super::codex_timeline_cells::{new_cell, upsert_cell};
use super::{ensure_payload_object, turn_id_from_message};

const REVIEW_TRANSITION: &str = "aleraReviewTransition";
const ENTRY_TURN_ID: &str = "entryTurnId";
const WORKER_TURN_ID: &str = "workerTurnId";
const LAST_USER_MESSAGE: &str = "lastUserMessage";
const USER_MESSAGE_SEQUENCE: &str = "userMessageSequence";

pub(in crate::terminal_host::server) use super::codex_review_history::{
    history_turn_may_be_review_worker, normalize_history_turns, restore_active_history_transition,
    REVIEW_WORKER_TURN_ID,
};

pub(super) fn normalize_live_message(snapshot: &mut Value, mut message: Value) -> Value {
    let event_type = legacy_event_type(&message);
    if event_type == "entered_review_mode" {
        if let Some(entry_turn_id) = turn_id_from_message(&message) {
            if transition_entry(snapshot).as_deref() != Some(entry_turn_id.as_str()) {
                set_transition(snapshot, &entry_turn_id, None);
            }
        }
        return message;
    }

    if event_type == "task_started" {
        if let (Some(entry_turn_id), Some(worker_turn_id)) =
            (transition_entry(snapshot), turn_id_from_message(&message))
        {
            set_transition(snapshot, &entry_turn_id, Some(&worker_turn_id));
            if entry_turn_id != worker_turn_id {
                rewrite_message_turn(&mut message, &worker_turn_id, &entry_turn_id);
            }
        }
        return message;
    }

    let Some((worker_turn_id, entry_turn_id)) = transition_ids(snapshot) else {
        if closes_review_turn(&message) {
            clear_transition(snapshot);
        }
        return message;
    };
    rewrite_message_turn(&mut message, &worker_turn_id, &entry_turn_id);
    if closes_review_turn(&message) {
        clear_transition(snapshot);
    }
    message
}

pub(super) fn clear_live_transition(snapshot: &mut Value) {
    clear_transition(snapshot);
}

pub(super) fn record_review_user_message(snapshot: &mut Value, message: &Value) {
    if legacy_event_type(message) != "user_message" {
        return;
    }
    let Some((_, turn_id)) = transition_ids(snapshot) else {
        return;
    };
    let text = message
        .pointer("/params/msg/message")
        .or_else(|| message.pointer("/params/message"))
        .and_then(Value::as_str)
        .map(str::trim)
        .filter(|value| !value.is_empty());
    let Some(text) = text else {
        return;
    };
    if transition_string(snapshot, LAST_USER_MESSAGE).as_deref() == Some(text) {
        return;
    }
    remember_user_message(snapshot, text);
    if has_matching_steering_cell(snapshot, text) {
        return;
    }
    let sequence = next_user_message_sequence(snapshot);
    let object = ensure_payload_object(snapshot);
    let cells = object
        .entry("timelineCells".to_string())
        .or_insert_with(|| Value::Array(Vec::new()));
    let Some(cells) = cells.as_array_mut() else {
        return;
    };
    let now = Utc::now().to_rfc3339();
    upsert_cell(
        cells,
        new_cell(
            &format!("review-user-{turn_id}-{sequence}"),
            &turn_id,
            "userMessage",
            "completed",
            &now,
            None,
            None,
            Some(text.to_string()),
            None,
            false,
            Some(json!({
                "itemType": "userMessage",
                "reviewGenerated": true,
            })),
        ),
    );
}

fn rewrite_message_turn(message: &mut Value, from: &str, to: &str) {
    for pointer in [
        "/params/turn/id",
        "/params/turnId",
        "/params/turn_id",
        "/params/item/turnId",
        "/params/item/turn_id",
        "/params/item/turnID",
        "/params/msg/turn_id",
        "/params/msg/turnId",
        "/result/turn/id",
        "/result/turnId",
    ] {
        let Some(value) = message.pointer_mut(pointer) else {
            continue;
        };
        if value.as_str() == Some(from) {
            *value = Value::String(to.to_string());
        }
    }
}

fn set_transition(snapshot: &mut Value, entry_turn_id: &str, worker_turn_id: Option<&str>) {
    let mut transition = Map::new();
    transition.insert(
        ENTRY_TURN_ID.to_string(),
        Value::String(entry_turn_id.to_string()),
    );
    if let Some(worker_turn_id) = worker_turn_id {
        transition.insert(
            WORKER_TURN_ID.to_string(),
            Value::String(worker_turn_id.to_string()),
        );
    }
    ensure_payload_object(snapshot).insert(REVIEW_TRANSITION.to_string(), transition.into());
}

pub(super) fn restore_transition(snapshot: &mut Value, entry_turn_id: &str, worker_turn_id: &str) {
    set_transition(snapshot, entry_turn_id, Some(worker_turn_id));
}

fn clear_transition(snapshot: &mut Value) {
    ensure_payload_object(snapshot).remove(REVIEW_TRANSITION);
}

fn closes_review_turn(message: &Value) -> bool {
    matches!(
        legacy_event_type(message),
        "task_complete" | "task_failed" | "turn_aborted" | "turn_interrupted"
    ) || matches!(
        message.get("method").and_then(Value::as_str),
        Some("turn/completed" | "turn/failed" | "turn/aborted" | "turn/interrupted")
    )
}

fn transition_entry(snapshot: &Value) -> Option<String> {
    snapshot
        .pointer(&format!("/{REVIEW_TRANSITION}/{ENTRY_TURN_ID}"))
        .and_then(Value::as_str)
        .map(str::to_string)
}

fn transition_ids(snapshot: &Value) -> Option<(String, String)> {
    let entry = transition_entry(snapshot)?;
    let worker = snapshot
        .pointer(&format!("/{REVIEW_TRANSITION}/{WORKER_TURN_ID}"))
        .and_then(Value::as_str)?
        .to_string();
    Some((worker, entry))
}

fn transition_string(snapshot: &Value, key: &str) -> Option<String> {
    snapshot
        .pointer(&format!("/{REVIEW_TRANSITION}/{key}"))
        .and_then(Value::as_str)
        .map(str::to_string)
}

fn remember_user_message(snapshot: &mut Value, text: &str) {
    if let Some(transition) = ensure_payload_object(snapshot)
        .get_mut(REVIEW_TRANSITION)
        .and_then(Value::as_object_mut)
    {
        transition.insert(LAST_USER_MESSAGE.to_string(), text.to_string().into());
    }
}

fn next_user_message_sequence(snapshot: &mut Value) -> u64 {
    let Some(transition) = ensure_payload_object(snapshot)
        .get_mut(REVIEW_TRANSITION)
        .and_then(Value::as_object_mut)
    else {
        return 0;
    };
    let sequence = transition
        .get(USER_MESSAGE_SEQUENCE)
        .and_then(Value::as_u64)
        .unwrap_or(0);
    transition.insert(USER_MESSAGE_SEQUENCE.to_string(), (sequence + 1).into());
    sequence
}

fn has_matching_steering_cell(snapshot: &Value, text: &str) -> bool {
    snapshot
        .get("timelineCells")
        .and_then(Value::as_array)
        .is_some_and(|cells| {
            cells.iter().any(|cell| {
                cell.get("kind").and_then(Value::as_str) == Some("userMessage")
                    && cell
                        .pointer("/metadata/isSteering")
                        .and_then(Value::as_bool)
                        == Some(true)
                    && cell.get("markdownText").and_then(Value::as_str) == Some(text)
            })
        })
}

fn legacy_event_type(message: &Value) -> &str {
    if let Some(item_type) = message.pointer("/params/item/type").and_then(Value::as_str) {
        return match item_type {
            "enteredReviewMode" => "entered_review_mode",
            "exitedReviewMode" => "exited_review_mode",
            _ => "",
        };
    }
    message
        .pointer("/params/msg/type")
        .and_then(Value::as_str)
        .or_else(|| {
            message
                .get("method")
                .and_then(Value::as_str)
                .and_then(|method| method.strip_prefix("codex/event/"))
        })
        .or_else(|| match message.get("method").and_then(Value::as_str) {
            Some("turn/started" | "turn/created") => Some("task_started"),
            Some("turn/completed") => Some("task_complete"),
            Some("turn/failed") => Some("task_failed"),
            Some("turn/aborted") => Some("turn_aborted"),
            Some("turn/interrupted") => Some("turn_interrupted"),
            _ => None,
        })
        .unwrap_or_default()
}
