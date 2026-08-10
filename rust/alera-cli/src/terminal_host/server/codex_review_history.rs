//! Reconstructs one logical Codex Review turn from persisted envelope and worker turns.

use chrono::{TimeZone, Utc};
use serde_json::{json, Map, Value};

use super::codex_review_transition::restore_transition;

pub(in crate::terminal_host::server) const REVIEW_WORKER_TURN_ID: &str = "aleraReviewWorkerTurnId";
const UNCOMMITTED_REVIEW_HINT: &str = "current changes";
const UNCOMMITTED_REVIEW_PROMPT: &str = "Review the current code changes (staged, unstaged, and untracked files) and provide prioritized findings.";
const BASE_BRANCH_REVIEW_HINT_PREFIX: &str = "changes against '";
const BASE_BRANCH_REVIEW_PROMPT_PREFIX: &str = "Review the code changes against the base branch '";
const COMMIT_REVIEW_HINT_PREFIX: &str = "commit ";
const COMMIT_REVIEW_PROMPT_PREFIX: &str = "Review the code changes introduced by commit ";
const PRIORITIZED_FINDINGS_SUFFIX: &str = "Provide prioritized, actionable findings.";

pub(in crate::terminal_host::server) fn normalize_history_turns(turns: &[Value]) -> Vec<Value> {
    let mut normalized = Vec::with_capacity(turns.len());
    let mut index = 0;
    while index < turns.len() {
        let current = &turns[index];
        if history_turn_enters_review(current)
            && index + 1 < turns.len()
            && history_turn_is_review_worker(current, &turns[index + 1])
        {
            normalized.push(merge_review_turns(current, &turns[index + 1]));
            index += 2;
            continue;
        }
        if history_turn_enters_review(current) {
            normalized.push(current.clone());
            index += 1;
            continue;
        }
        normalized.push(deduplicate_review_user_messages(current.clone()));
        index += 1;
    }
    normalized
}

pub(in crate::terminal_host::server) fn restore_active_history_transition(
    snapshot: &mut Value,
    turns: &[Value],
) {
    let transition = turns.last().and_then(|turn| {
        if !matches!(
            turn.get("status").and_then(Value::as_str),
            Some("inProgress" | "pending" | "running")
        ) {
            return None;
        }
        Some((
            turn.get("id").and_then(Value::as_str)?,
            turn.get(REVIEW_WORKER_TURN_ID).and_then(Value::as_str)?,
        ))
    });
    let transition = transition.or_else(|| {
        let start = turns.len().checked_sub(2)?;
        let pair = turns.get(start..)?;
        let envelope = &pair[0];
        let worker = &pair[1];
        if !history_turn_enters_review(envelope)
            || !history_turn_is_review_worker(envelope, worker)
            || !matches!(
                worker.get("status").and_then(Value::as_str),
                Some("inProgress" | "pending" | "running")
            )
        {
            return None;
        }
        Some((
            envelope.get("id").and_then(Value::as_str)?,
            worker.get("id").and_then(Value::as_str)?,
        ))
    });
    if let Some((entry_turn_id, worker_turn_id)) = transition.filter(|(entry_turn_id, _)| {
        snapshot.get("activeTurnId").and_then(Value::as_str) == Some(*entry_turn_id)
    }) {
        restore_transition(snapshot, entry_turn_id, worker_turn_id);
    }
}

pub(in crate::terminal_host::server) fn history_turn_may_be_review_worker(turn: &Value) -> bool {
    duplicate_clientless_user_message_text(turn).is_some()
}

fn history_turn_enters_review(turn: &Value) -> bool {
    turn.get("items")
        .and_then(Value::as_array)
        .is_some_and(|items| {
            items
                .iter()
                .any(|item| item.get("type").and_then(Value::as_str) == Some("enteredReviewMode"))
        })
}

fn history_turn_is_review_worker(envelope: &Value, turn: &Value) -> bool {
    let Some(prompt) = duplicate_clientless_user_message_text(turn) else {
        return false;
    };
    review_hint(envelope).is_some_and(|hint| review_prompt_matches_hint(&prompt, hint))
}

fn review_hint(turn: &Value) -> Option<&str> {
    turn.get("items")
        .and_then(Value::as_array)?
        .iter()
        .find(|item| item.get("type").and_then(Value::as_str) == Some("enteredReviewMode"))?
        .get("review")
        .and_then(Value::as_str)
        .map(str::trim)
        .filter(|hint| !hint.is_empty())
}

fn review_prompt_matches_hint(prompt: &str, hint: &str) -> bool {
    let prompt = prompt.trim();
    let hint = hint.trim();
    if prompt == hint {
        return true;
    }
    if hint == UNCOMMITTED_REVIEW_HINT {
        return prompt == UNCOMMITTED_REVIEW_PROMPT;
    }
    if let Some(branch) = hint
        .strip_prefix(BASE_BRANCH_REVIEW_HINT_PREFIX)
        .and_then(|value| value.strip_suffix('\''))
    {
        return prompt.starts_with(&format!("{BASE_BRANCH_REVIEW_PROMPT_PREFIX}{branch}'."))
            && prompt.ends_with(PRIORITIZED_FINDINGS_SUFFIX);
    }
    if let Some(commit_hint) = hint.strip_prefix(COMMIT_REVIEW_HINT_PREFIX) {
        let short_sha = commit_hint
            .split_once(':')
            .map_or(commit_hint, |(sha, _)| sha)
            .trim();
        return !short_sha.is_empty()
            && prompt.starts_with(&format!("{COMMIT_REVIEW_PROMPT_PREFIX}{short_sha}"))
            && prompt.ends_with(PRIORITIZED_FINDINGS_SUFFIX);
    }
    false
}

fn merge_review_turns(envelope: &Value, worker: &Value) -> Value {
    let mut merged = envelope.clone();
    let envelope_items = envelope
        .get("items")
        .and_then(Value::as_array)
        .cloned()
        .unwrap_or_default();
    let exit_index = envelope_items
        .iter()
        .position(|item| item.get("type").and_then(Value::as_str) == Some("exitedReviewMode"))
        .unwrap_or(envelope_items.len());
    let mut items = envelope_items[..exit_index].to_vec();
    items.extend(
        worker
            .get("items")
            .and_then(Value::as_array)
            .cloned()
            .unwrap_or_default(),
    );
    items.extend_from_slice(&envelope_items[exit_index..]);
    if let Some(object) = merged.as_object_mut() {
        object.insert("items".to_string(), Value::Array(items));
        if let Some(worker_turn_id) = worker.get("id").and_then(Value::as_str) {
            object.insert(
                REVIEW_WORKER_TURN_ID.to_string(),
                Value::String(worker_turn_id.to_string()),
            );
        }
        merge_review_timestamps(object, envelope, worker);
        merge_review_worker_state(object, worker);
        let complete = envelope
            .get("aleraHistoryItemsComplete")
            .and_then(Value::as_bool)
            == Some(true)
            && worker
                .get("aleraHistoryItemsComplete")
                .and_then(Value::as_bool)
                == Some(true);
        if complete {
            object.insert("aleraHistoryItemsComplete".to_string(), Value::Bool(true));
        } else {
            object.remove("aleraHistoryItemsComplete");
        }
    }
    deduplicate_review_user_messages(merged)
}

fn merge_review_worker_state(object: &mut Map<String, Value>, worker: &Value) {
    if matches!(
        worker.get("status").and_then(Value::as_str),
        Some("inProgress" | "pending" | "running")
    ) {
        object.insert(
            "status".to_string(),
            Value::String("inProgress".to_string()),
        );
        object.remove("completedAt");
        object.remove("durationMs");
        return;
    }
    let worker_failed = worker.get("status").and_then(Value::as_str) == Some("failed")
        || worker.get("error").is_some_and(|error| !error.is_null());
    if !worker_failed {
        return;
    }
    object.insert("status".to_string(), Value::String("failed".to_string()));
    if let Some(error) = worker.get("error").filter(|error| !error.is_null()) {
        object.insert("error".to_string(), error.clone());
    }
}

fn duplicate_clientless_user_message_text(turn: &Value) -> Option<String> {
    let items = turn.get("items").and_then(Value::as_array)?;
    let mut seen = std::collections::HashSet::new();
    for item in items {
        if item.get("type").and_then(Value::as_str) != Some("userMessage")
            || item
                .get("clientId")
                .and_then(Value::as_str)
                .is_some_and(|client_id| !client_id.trim().is_empty())
        {
            continue;
        }
        let Some(text) = history_user_message_text(item) else {
            continue;
        };
        if !seen.insert(text.clone()) {
            return Some(text);
        }
    }
    None
}

fn merge_review_timestamps(object: &mut Map<String, Value>, envelope: &Value, worker: &Value) {
    let started_at = worker
        .get("startedAt")
        .and_then(Value::as_i64)
        .or_else(|| envelope.get("startedAt").and_then(Value::as_i64));
    let completed_at = worker
        .get("completedAt")
        .and_then(Value::as_i64)
        .or_else(|| envelope.get("completedAt").and_then(Value::as_i64));
    if let Some(started_at) = started_at {
        object.insert("startedAt".to_string(), started_at.into());
    }
    if let Some(completed_at) = completed_at {
        object.insert("completedAt".to_string(), completed_at.into());
    }
    if let (Some(started_at), Some(completed_at)) = (started_at, completed_at) {
        if let (Some(started), Some(completed)) = (
            Utc.timestamp_opt(started_at, 0).single(),
            Utc.timestamp_opt(completed_at, 0).single(),
        ) {
            object.insert(
                "durationMs".to_string(),
                json!((completed - started).num_milliseconds().max(0)),
            );
        }
    }
}

fn deduplicate_review_user_messages(mut turn: Value) -> Value {
    if !history_turn_enters_review(&turn) {
        return turn;
    }
    let Some(items) = turn.get_mut("items").and_then(Value::as_array_mut) else {
        return turn;
    };
    let mut seen = std::collections::HashSet::new();
    items.retain(|item| {
        if item.get("type").and_then(Value::as_str) != Some("userMessage")
            || item
                .get("clientId")
                .and_then(Value::as_str)
                .is_some_and(|client_id| !client_id.trim().is_empty())
        {
            return true;
        }
        let Some(text) = history_user_message_text(item) else {
            return true;
        };
        seen.insert(text)
    });
    turn
}

fn history_user_message_text(item: &Value) -> Option<String> {
    let text = item
        .get("content")
        .and_then(Value::as_array)?
        .iter()
        .filter_map(|part| part.get("text").and_then(Value::as_str))
        .collect::<Vec<_>>()
        .join("\n");
    (!text.is_empty()).then_some(text)
}
