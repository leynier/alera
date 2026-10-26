//! Provider-native sub-agents. A sub-agent runs under one tool call of the
//! main agent (Claude's Task tool, Codex's collab agent call). Its items name
//! that call through `normalized.parentItemId`, and the provider's task
//! events keep the call's `normalized.subagent` status current, so clients
//! can show each sub-agent under the call that started it.

use alera_provider_protocol::{EventKind, ProviderEvent};
use serde_json::{json, Value};

use super::ids::{native_key, now};
use super::session::ChatSession;

const MAX_SUBAGENT_TEXT: usize = 512;

fn nonempty(value: Option<&Value>) -> Option<&str> {
    value
        .and_then(Value::as_str)
        .map(str::trim)
        .filter(|value| !value.is_empty())
}

fn bounded(text: &str) -> String {
    text.chars().take(MAX_SUBAGENT_TEXT).collect()
}

fn subagent_status(event: &ProviderEvent) -> &'static str {
    let reported = nonempty(event.payload.get("status")).unwrap_or_default();
    match reported {
        "failed" | "error" => "failed",
        "stopped" | "cancelled" | "canceled" | "interrupted" | "aborted" => "stopped",
        "completed" | "complete" | "done" => "completed",
        _ if event.kind == EventKind::TaskCompleted => "completed",
        _ => "running",
    }
}

impl ChatSession {
    /// Points a sub-agent's item at the tool call that started it.
    pub(super) async fn link_subagent_item(&mut self, item_id: &str, event: &ProviderEvent) {
        let Some(native_call) = nonempty(event.payload.get("parentToolUseId")) else {
            return;
        };
        if event.item_id.as_deref() == Some(native_call) {
            return;
        }
        let native_call = native_call.to_owned();
        let parent = self.app_item_id(&native_call).await;
        if parent == item_id {
            return;
        }
        self.load_item(&parent).await;
        // A sub-agent that outlives its parent's turn (Codex background
        // children) still belongs to the turn that started it.
        let call_turn = self
            .items
            .get(&parent)
            .and_then(|call| call.turn_id.clone());
        if let Some(item) = self.items.get_mut(item_id) {
            let mut changed = false;
            if item.normalized.get("parentItemId") != Some(&json!(parent)) {
                item.normalized
                    .insert("parentItemId".into(), json!(parent.clone()));
                changed = true;
            }
            if call_turn.is_some() && item.turn_id != call_turn {
                item.turn_id = call_turn;
                changed = true;
            }
            if changed {
                self.pending.item(item_id);
            }
        }
        // A call with work under it is a sub-agent even before the provider
        // reports the task itself.
        if let Some(call) = self.items.get_mut(&parent) {
            if !call.normalized.contains_key("subagent") {
                call.normalized.insert(
                    "subagent".into(),
                    json!({"status": "running", "startedAt": now()}),
                );
                call.updated_at = now();
                self.pending.item(&parent);
            }
        }
    }

    /// Remembers which collab call spawned which child threads, so the child
    /// threads' task events find the call (Codex).
    pub(super) async fn record_subagent_threads(&mut self, item_id: &str, event: &ProviderEvent) {
        let Some(task) = event.payload.get("nativeTask") else {
            return;
        };
        if nonempty(task.get("nativeToolCallId")) != event.item_id.as_deref() {
            return;
        }
        let children: Vec<String> = task
            .get("childNativeThreadIds")
            .and_then(Value::as_array)
            .into_iter()
            .flatten()
            .filter_map(Value::as_str)
            .filter(|id| !id.is_empty())
            .map(str::to_owned)
            .collect();
        for child in children {
            // The spawning call keeps the child; later calls that name it
            // (`wait`, completion activity) only report on it.
            let key = native_key(
                &self.epoch_kind("subagentThread"),
                &Value::String(child.clone()),
            );
            if self.native_ids.contains_key(&key) {
                continue;
            }
            self.map_native("subagentThread", Value::String(child), item_id)
                .await;
        }
    }

    /// Folds a provider task event into the status of the call that owns it.
    pub(super) async fn apply_subagent_task(&mut self, event: &ProviderEvent) {
        let task = event.payload.get("nativeTask");
        // Claude names the tool call; Codex names the child thread.
        let parent =
            if let Some(call) = nonempty(task.and_then(|task| task.get("nativeToolCallId"))) {
                let call = call.to_owned();
                Some(self.app_item_id(&call).await)
            } else {
                task.and_then(|task| task.get("childNativeThreadIds"))
                    .and_then(Value::as_array)
                    .and_then(|ids| ids.first())
                    .and_then(Value::as_str)
                    .and_then(|child| {
                        self.native_ids
                            .get(&native_key(
                                &self.epoch_kind("subagentThread"),
                                &Value::String(child.into()),
                            ))
                            .cloned()
                    })
            };
        // A later event may name only the task (a stop's outcome).
        let task_id = nonempty(event.payload.get("taskId")).map(str::to_owned);
        let task_key = task_id.as_ref().map(|task| {
            native_key(
                &self.epoch_kind("subagentTask"),
                &Value::String(task.clone()),
            )
        });
        let parent = parent.or_else(|| {
            task_key
                .as_ref()
                .and_then(|key| self.native_ids.get(key).cloned())
        });
        let Some(parent) = parent else {
            return;
        };
        if let (Some(task), Some(key)) = (task_id, task_key) {
            if !self.native_ids.contains_key(&key) {
                self.map_native("subagentTask", Value::String(task), &parent)
                    .await;
            }
        }
        self.load_item(&parent).await;
        let status = subagent_status(event);
        let Some(call) = self.items.get_mut(&parent) else {
            return;
        };
        let mut subagent = call
            .normalized
            .get("subagent")
            .filter(|value| value.is_object())
            .cloned()
            .unwrap_or_else(|| json!({}));
        let previous = subagent
            .get("status")
            .and_then(Value::as_str)
            .map(str::to_owned);
        if status == "running" {
            // A settled sub-agent that runs again (a Codex child's next
            // turn) restarts its clock.
            if previous
                .as_deref()
                .is_some_and(|previous| previous != "running")
                || subagent.get("startedAt").is_none()
            {
                subagent["startedAt"] = json!(now());
            }
            if let Some(object) = subagent.as_object_mut() {
                object.remove("completedAt");
            }
        } else if previous.as_deref() != Some(status) || subagent.get("completedAt").is_none() {
            if subagent.get("startedAt").is_none() {
                subagent["startedAt"] = json!(call.created_at.clone());
            }
            subagent["completedAt"] = json!(now());
        }
        subagent["status"] = json!(status);
        for key in [
            "taskId",
            "description",
            "summary",
            "taskType",
            "model",
            "reasoningEffort",
        ] {
            if let Some(text) = nonempty(event.payload.get(key)) {
                subagent[key] = json!(bounded(text));
            }
        }
        if call.normalized.get("subagent") == Some(&subagent) {
            return;
        }
        call.normalized.insert("subagent".into(), subagent);
        call.updated_at = now();
        self.pending.item(&parent);
    }
}
