//! Native sub-agent threads under the session's thread, at any depth, and the
//! `task.*` payloads their notifications become. A child's own items stream as
//! items of the session, linked to the call that spawned the child, so its
//! transcript can be read on its own.

use crate::provider::CodexProvider;
use alera_agent_transport::JsonTransport;
use alera_provider_protocol::{NativeTask, ProviderError};
use serde_json::{json, Map, Value};
use std::collections::HashMap;

/// What the session knows about each descendant thread beyond its parent.
#[derive(Debug, Default)]
pub(crate) struct ChildThreads {
    /// The native call that spawned each child, first seen wins: later calls
    /// that name the child (`wait`, `subAgentActivity` completions) only
    /// report on it.
    calls: HashMap<String, String>,
    /// The model and reasoning effort the spawn asked for.
    settings: HashMap<String, (Option<String>, Option<String>)>,
    /// Each child's running native turn, which a stop interrupts.
    turns: HashMap<String, String>,
}

impl ChildThreads {
    pub(crate) fn clear_turns(&mut self) {
        self.turns.clear();
    }
}

impl<T> CodexProvider<T> {
    /// Registers the children a spawn names when their parent is the session
    /// thread or one of its descendants, so grandchildren are tracked too.
    pub(crate) fn register_children(&mut self, task: &NativeTask, params: &Value) {
        let Some(parent) = &task.parent_native_thread_id else {
            return;
        };
        let known = self
            .session
            .as_ref()
            .is_some_and(|session| &session.native_thread_id == parent)
            || self.native_child_parents.contains_key(parent);
        if !known {
            return;
        }
        let label = spawn_label(params);
        let item = params.get("item");
        let setting = |key: &str| {
            item.and_then(|item| item.get(key))
                .and_then(Value::as_str)
                .map(str::trim)
                .filter(|value| !value.is_empty())
                .map(str::to_owned)
        };
        let settings = (setting("model"), setting("reasoningEffort"));
        for child in &task.child_native_thread_ids {
            self.native_child_parents
                .insert(child.clone(), parent.clone());
            if let Some(label) = &label {
                self.child_labels.insert(child.clone(), label.clone());
            }
            if let Some(call) = &task.native_tool_call_id {
                self.child_threads
                    .calls
                    .entry(child.clone())
                    .or_insert_with(|| call.clone());
            }
            if settings.0.is_some() || settings.1.is_some() {
                self.child_threads
                    .settings
                    .entry(child.clone())
                    .or_insert_with(|| settings.clone());
            }
        }
    }

    /// The payload of a child's own item or delta, linked to the call that
    /// spawned the child. `None` when the spawning call is unknown or the item
    /// is the child's prompt, which the spawning call already carries.
    pub(crate) fn child_item_payload(&self, child: &str, mut payload: Value) -> Option<Value> {
        if payload.get("itemType") == Some(&json!("user_message")) {
            return None;
        }
        let call = self.child_threads.calls.get(child)?;
        payload["parentToolUseId"] = Value::String(call.clone());
        payload["subagentThreadId"] = Value::String(child.to_owned());
        Some(payload)
    }

    /// The payload of a descendant thread's notification, as a task of the
    /// session. A direct child that completes or fails wakes its parent,
    /// because Codex does not resume a root turn that already ended; a
    /// grandchild reports to its own parent, which is a child.
    pub(crate) fn child_task_payload(
        &mut self,
        child: &str,
        parent: &str,
        method: &str,
        params: &Value,
        detail: Value,
    ) -> Value {
        let terminal = matches!(method, "turn/completed" | "turn/aborted" | "thread/closed");
        match method {
            "turn/started" => {
                self.active_child_turns.insert(child.to_owned());
                self.child_results.remove(child);
                if let Some(turn) = params.pointer("/turn/id").and_then(Value::as_str) {
                    self.child_threads
                        .turns
                        .insert(child.to_owned(), turn.to_owned());
                }
            }
            "item/completed" => {
                if let Some(text) = final_answer(params) {
                    self.child_results.insert(child.to_owned(), text);
                }
            }
            _ if terminal => {
                self.active_child_turns.remove(child);
                self.child_threads.turns.remove(child);
            }
            _ => {}
        }
        let direct = self
            .session
            .as_ref()
            .is_some_and(|session| session.native_thread_id == parent);
        let status = if terminal {
            terminal_status(method, params)
        } else {
            "running"
        };
        let mut payload = Map::new();
        payload.insert("taskId".into(), child.into());
        payload.insert("status".into(), status.into());
        payload.insert("awaited".into(), Value::Bool(true));
        if !direct {
            payload.insert("parentTaskId".into(), parent.into());
        }
        if let Some(label) = self.child_labels.get(child) {
            payload.insert("description".into(), label.clone().into());
        }
        if let Some((model, effort)) = self.child_threads.settings.get(child) {
            if let Some(model) = model {
                payload.insert("model".into(), model.clone().into());
            }
            if let Some(effort) = effort {
                payload.insert("reasoningEffort".into(), effort.clone().into());
            }
        }
        if terminal {
            if let Some(result) = self.child_results.remove(child) {
                payload.insert("summary".into(), result.into());
            }
            if direct && method == "turn/completed" && matches!(status, "completed" | "failed") {
                payload.insert("wakesParent".into(), Value::Bool(true));
            }
        }
        payload.insert(
            "nativeTask".into(),
            serde_json::to_value(NativeTask {
                parent_native_thread_id: Some(parent.to_owned()),
                child_native_thread_ids: vec![child.to_owned()],
                status: Some(method.into()),
                ..Default::default()
            })
            .expect("native task is serializable"),
        );
        payload.insert("detail".into(), detail);
        Value::Object(payload)
    }

    pub(crate) fn clear_children(&mut self) {
        self.active_child_turns.clear();
        self.child_results.clear();
        self.child_threads.clear_turns();
    }
}

impl<T: JsonTransport> CodexProvider<T> {
    /// Interrupts the running turn of one descendant thread, leaving the
    /// session's own turn and every other child running.
    pub(crate) async fn stop_child(&mut self, task_id: &str) -> Result<(), ProviderError> {
        if !self.native_child_parents.contains_key(task_id) {
            return Err(ProviderError::Validation(
                "the task is not a sub-agent of this session".into(),
            ));
        }
        let turn = self
            .child_threads
            .turns
            .get(task_id)
            .cloned()
            .ok_or_else(|| ProviderError::InvalidState("the sub-agent is not running".into()))?;
        self.call(
            "turn/interrupt",
            json!({ "threadId": task_id, "turnId": turn }),
        )
        .await?;
        Ok(())
    }
}

/// What the spawning call calls the child: its prompt, else its agent path.
/// Codex accepts a spawn without a prompt, which arrives as an empty string.
fn spawn_label(params: &Value) -> Option<String> {
    let item = params.get("item")?;
    ["prompt", "agentPath"]
        .iter()
        .filter_map(|key| item.get(*key).and_then(Value::as_str))
        .map(str::trim)
        .find(|label| !label.is_empty())
        .map(str::to_owned)
}

fn final_answer(params: &Value) -> Option<String> {
    let item = params.get("item")?;
    if item.get("type").and_then(Value::as_str) != Some("agentMessage")
        || item.get("phase").and_then(Value::as_str) == Some("commentary")
    {
        return None;
    }
    item.get("text")
        .and_then(Value::as_str)
        .filter(|text| !text.trim().is_empty())
        .map(str::to_owned)
}

fn terminal_status(method: &str, params: &Value) -> &'static str {
    match method {
        "turn/aborted" => "stopped",
        "turn/completed" => match params.pointer("/turn/status").and_then(Value::as_str) {
            Some("failed") => "failed",
            Some("interrupted") => "stopped",
            _ => "completed",
        },
        _ => "completed",
    }
}
