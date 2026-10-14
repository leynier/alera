//! Transcript history projections without provider-native or filesystem claims.

use serde_json::{json, Map, Value};

use crate::terminal_host::host_error::{HostError, HostResult};

use super::ids::now;
use super::item_normalization::project_item_data;
use super::session::ChatSession;
use super::session_snapshot::HISTORY_MAX_ITEMS;
use super::wire::{ChatItem, ChatRequest};

const HISTORY_SCAN_MAX_PAGES: usize = 64;
const HISTORY_REPLY_MAX_BYTES: usize = 192 * 1024;
const HISTORY_LABEL_MAX_CHARS: usize = 512;

fn history_before(before: Option<&str>) -> HostResult<i64> {
    match before {
        None => Ok(i64::MAX),
        Some(token) => token
            .strip_prefix("seq:")
            .and_then(|value| value.parse::<i64>().ok())
            .filter(|value| *value > 0)
            .ok_or_else(|| HostError::format("before must be a historyBefore token")),
    }
}

fn bounded_label(text: &str) -> String {
    text.chars().take(HISTORY_LABEL_MAX_CHARS).collect()
}

fn request_projection(
    request: &ChatRequest,
    status: &str,
    response: Option<&Value>,
    actor: Option<&str>,
    timestamp: &str,
) -> Value {
    let mut value = json!({
        "requestId": request.request_id,
        "kind": request.kind,
        "decisions": request.decisions,
        "status": status,
    });
    if let Some(title) = request.title.as_deref() {
        value["title"] = json!(bounded_label(title));
    }
    if let Some(actor) = actor {
        value["actor"] = json!(bounded_label(actor));
    }
    if status != "pending" {
        value["resolvedAt"] = json!(timestamp);
    }
    if let Some(response) = response {
        let mut projected = Map::new();
        if let Some(kind @ ("approval" | "userInput" | "elicitation" | "native")) =
            response.get("type").and_then(Value::as_str)
        {
            projected.insert("type".into(), json!(kind));
            if kind == "approval" {
                if let Some(decision) = response.get("decision").and_then(Value::as_str) {
                    if request.decisions.iter().any(|offered| offered == decision) {
                        projected.insert("decision".into(), json!(decision));
                    }
                }
            }
        }
        if !projected.is_empty() {
            value["response"] = Value::Object(projected);
        }
    }
    value
}

fn request_history_item(
    request: &ChatRequest,
    status: &str,
    response: Option<&Value>,
    actor: Option<&str>,
    timestamp: &str,
    generation: i64,
) -> ChatItem {
    let mut item = ChatItem::new(
        format!("approvalHistory:{}", request.request_id),
        "notice",
        &request.created_at,
        generation,
    );
    item.turn_id = request.turn_id.clone();
    item.updated_at = timestamp.into();
    item.status = if status == "pending" {
        "inProgress"
    } else {
        "completed"
    }
    .into();
    item.title = request.title.as_deref().map(bounded_label);
    item.actor = actor.map(bounded_label);
    item.detail = Some(
        match status {
            "pending" => "The provider requested a response.",
            "resolved" => "The response was sent to the provider.",
            "providerResolved" => "The provider resolved the request.",
            "expired" => "The request expired before a response.",
            _ => "The request is no longer pending.",
        }
        .into(),
    );
    item.normalized.insert(
        "approvalHistory".into(),
        request_projection(request, status, response, actor, timestamp),
    );
    item
}

fn is_request_history(item: &Value) -> bool {
    item.get("normalized")
        .and_then(|normalized| normalized.get("approvalHistory"))
        .is_some_and(Value::is_object)
}

fn provider_diff(item: &Value, turn_id: &str) -> Option<Value> {
    if item.get("turnId").and_then(Value::as_str) != Some(turn_id)
        || !matches!(
            item.get("type").and_then(Value::as_str),
            Some("file_change" | "turn_diff")
        )
    {
        return None;
    }
    let normalized = item.get("normalized");
    let data = item.get("data");
    let exact = |field: &str| {
        normalized
            .and_then(|value| value.get(field))
            .filter(|value| value.is_array() || value.is_object())
            .or_else(|| {
                data.and_then(|value| value.get(field))
                    .filter(|value| value.is_array() || value.is_object())
            })
    };
    let changes = exact("changes").or_else(|| exact("fileChanges"));
    let diff = [normalized, data].into_iter().flatten().find_map(|value| {
        value
            .get("diff")
            .or_else(|| value.get("unifiedDiff"))
            .and_then(Value::as_str)
    });
    let payload_ref = normalized
        .and_then(|value| value.get("payloadRef"))
        .filter(|value| value.is_object());
    if changes.is_none() && diff.is_none() && payload_ref.is_none() {
        return None;
    }
    let mut result = json!({"itemId": item["itemId"], "status": item["status"]});
    if let Some(changes) = changes {
        result["changes"] = changes.clone();
    }
    if let Some(diff) = diff {
        result["diff"] = json!(diff);
    }
    if let Some(payload_ref) = payload_ref {
        result["payloadRef"] = payload_ref.clone();
    }
    Some(result)
}

impl ChatSession {
    pub(super) async fn record_turn_diff(
        &mut self,
        turn_id: &str,
        payload: &Value,
    ) -> Result<(), String> {
        let timestamp = now();
        let item_id = format!("turnDiff:{turn_id}");
        let reported = Value::Object(
            ["diff", "unifiedDiff", "changes", "fileChanges"]
                .into_iter()
                .filter_map(|field| {
                    payload
                        .get(field)
                        .map(|value| (field.into(), value.clone()))
                })
                .collect(),
        );
        let projected = project_item_data("file_change", &reported, &[]);
        let mut item = ChatItem::new(item_id.clone(), "turn_diff", &timestamp, self.generation);
        item.turn_id = Some(turn_id.into());
        item.status = "completed".into();
        item.title = Some("Turn Changes".into());
        item.normalized = projected.normalized;
        item.data = projected.data;
        if let Some(existing) = self.items.get(&item_id) {
            item.created_at = existing.created_at.clone();
        } else if let Some(existing) = self
            .deps
            .store
            .agent_chat_item(&self.header.chat_id, &item_id)
            .await
            .map_err(|error| error.to_string())?
        {
            if let Some(created) = existing.get("createdAt").and_then(Value::as_str) {
                item.created_at = created.into();
            }
        }
        self.insert_item(item);
        self.set_item_payload(&item_id, projected.payload.as_deref())
            .await
    }

    pub(super) fn record_request_history(
        &mut self,
        request: &ChatRequest,
        status: &str,
        response: Option<&Value>,
        actor: Option<&str>,
    ) {
        let item = request_history_item(request, status, response, actor, &now(), self.generation);
        self.pending.item(&item.item_id);
        self.items.insert(item.item_id.clone(), item);
        self.has_items = true;
    }

    pub(super) async fn approval_history(
        &mut self,
        before: Option<&str>,
        limit: usize,
    ) -> HostResult<Value> {
        self.flush().await.map_err(HostError::state)?;
        let mut before = history_before(before)?;
        let limit = limit.clamp(1, HISTORY_MAX_ITEMS);
        let mut items = Vec::new();
        let mut next = None;
        let mut bytes = 0;
        let mut scan_limited = false;
        for page_index in 0..HISTORY_SCAN_MAX_PAGES {
            let page = self
                .deps
                .store
                .agent_chat_history(&self.header.chat_id, before, (limit - items.len()) as i64)
                .await
                .map_err(|error| HostError::state(error.to_string()))?;
            let mut matching = page
                .items
                .into_iter()
                .filter(is_request_history)
                .collect::<Vec<_>>();
            let page_bytes = serde_json::to_vec(&matching)
                .map_err(|error| HostError::state(error.to_string()))?
                .len();
            if bytes + page_bytes > HISTORY_REPLY_MAX_BYTES {
                next = Some(before);
                scan_limited = true;
                break;
            }
            bytes += page_bytes;
            matching.append(&mut items);
            items = matching;
            next = page.history_before;
            if items.len() == limit || next.is_none() {
                break;
            }
            let older = next.expect("checked above");
            if older >= before {
                return Err(HostError::state("The history cursor did not advance."));
            }
            before = older;
            scan_limited = page_index + 1 == HISTORY_SCAN_MAX_PAGES;
        }
        Ok(json!({
            "items": items,
            "historyBefore": next.map(|seq| format!("seq:{seq}")),
            "scanLimited": scan_limited,
        }))
    }

    pub(super) async fn turn_diff(&mut self, turn_id: &str) -> HostResult<Value> {
        self.flush().await.map_err(HostError::state)?;
        let turn = self
            .deps
            .store
            .agent_chat_turn(&self.header.chat_id, turn_id)
            .await
            .map_err(|error| HostError::state(error.to_string()))?
            .ok_or_else(|| {
                HostError::conflict("turnNotFound", "The turn no longer exists.", json!({}))
            })?;
        let mut before = i64::MAX;
        let mut items = Vec::new();
        let mut bytes = 0;
        let mut truncated = false;
        for page_index in 0..HISTORY_SCAN_MAX_PAGES {
            let page = self
                .deps
                .store
                .agent_chat_history(&self.header.chat_id, before, HISTORY_MAX_ITEMS as i64)
                .await
                .map_err(|error| HostError::state(error.to_string()))?;
            let mut matching = Vec::new();
            for item in page
                .items
                .iter()
                .filter_map(|item| provider_diff(item, turn_id))
            {
                let size = serde_json::to_vec(&item)
                    .map_err(|error| HostError::state(error.to_string()))?
                    .len();
                if bytes + size > HISTORY_REPLY_MAX_BYTES {
                    truncated = true;
                    continue;
                }
                bytes += size;
                matching.push(item);
            }
            matching.append(&mut items);
            items = matching;
            let Some(older) = page.history_before else {
                break;
            };
            if older >= before {
                return Err(HostError::state("The history cursor did not advance."));
            }
            before = older;
            truncated |= page_index + 1 == HISTORY_SCAN_MAX_PAGES;
        }
        let available = !items.is_empty();
        let reason = if truncated {
            Some("The provider history exceeded the bounded scan or response limit.")
        } else if !available {
            Some("The provider did not report exact changes for this turn.")
        } else {
            None
        };
        Ok(json!({
            "turnId": turn_id, "source": "provider", "available": available,
            "settled": turn["status"] != "running", "items": items,
            "truncated": truncated, "reason": reason,
        }))
    }
}

#[cfg(test)]
#[path = "session_history_tests.rs"]
mod tests;
