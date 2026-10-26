//! Native sub-agent threads under the session's thread, at any depth, and the
//! `task.*` payloads their notifications become.

use crate::provider::CodexProvider;
use alera_provider_protocol::NativeTask;
use serde_json::{Map, Value};

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
        for child in &task.child_native_thread_ids {
            self.native_child_parents
                .insert(child.clone(), parent.clone());
            if let Some(label) = &label {
                self.child_labels.insert(child.clone(), label.clone());
            }
        }
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
            }
            "item/completed" => {
                if let Some(text) = final_answer(params) {
                    self.child_results.insert(child.to_owned(), text);
                }
            }
            _ if terminal => {
                self.active_child_turns.remove(child);
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
