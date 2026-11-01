//! Live output of a running foreground Bash command, as T3 Code a5d97921f6,
//! and Bash items completed from their user-frame tool results.

#[path = "command_output_tail.rs"]
pub(super) mod tail;

use super::*;
use claude_agent_sdk::UserMessage;

impl ClaudeProvider {
    /// Tails a foreground `local_bash` task that runs a Bash tool call.
    pub(super) fn start_command_output(&mut self, task_id: &str, payload: &Value) {
        let field = |keys: &[&str]| canonical_payload::text_field(payload, keys);
        if field(&["task_type", "taskType"]).as_deref() != Some("local_bash")
            || payload.get("is_backgrounded") == Some(&Value::Bool(true))
        {
            return;
        }
        let Some(tool_use_id) = field(&["tool_use_id", "toolUseId"]) else {
            return;
        };
        if self.open_items.get(&tool_use_id).map(String::as_str) != Some("command_execution") {
            return;
        }
        let Some(session_id) = field(&["session_id", "sessionId"]).or_else(|| {
            self.session
                .as_ref()
                .map(|session| session.native_thread_id.clone())
        }) else {
            return;
        };
        self.command_output
            .start(&tool_use_id, &session_id, task_id);
    }

    /// Stops the tail of a task that finished or moved to the background.
    pub(super) fn stop_task_output(&mut self, task_id: &str) -> Vec<ProviderEvent> {
        let Some(tool_use_id) = self.command_output.tool_use_of(task_id) else {
            return Vec::new();
        };
        self.stop_command_output(&tool_use_id)
    }

    pub(super) fn stop_all_command_output(&mut self) -> Vec<ProviderEvent> {
        self.command_output
            .running()
            .into_iter()
            .flat_map(|id| self.stop_command_output(&id))
            .collect()
    }

    pub(super) fn poll_command_output(&mut self) -> Vec<ProviderEvent> {
        self.command_output
            .poll()
            .into_iter()
            .map(|(id, chunk)| self.command_output_delta(id, chunk))
            .collect()
    }

    pub(super) fn stop_command_output_of(&mut self, tool_use_id: &str) -> Vec<ProviderEvent> {
        self.stop_command_output(tool_use_id)
    }

    fn stop_command_output(&mut self, tool_use_id: &str) -> Vec<ProviderEvent> {
        self.command_output
            .stop(tool_use_id)
            .map(|chunk| self.command_output_delta(tool_use_id.to_owned(), chunk))
            .into_iter()
            .collect()
    }

    fn command_output_delta(&self, tool_use_id: String, chunk: String) -> ProviderEvent {
        let raw = self.raw("task_output", json!({ "toolUseId": tool_use_id }));
        self.content_event(StreamKind::CommandOutput, chunk, raw, Some(tool_use_id))
    }

    /// Completes the Bash items whose results a user frame carries, after
    /// their tail's last read.
    pub(super) fn tool_result_events(&mut self, message: &UserMessage) -> Vec<ProviderEvent> {
        let blocks = message
            .content
            .as_array()
            .into_iter()
            .flatten()
            .filter(|block| block["type"] == "tool_result")
            .collect::<Vec<_>>();
        let structured = message
            .tool_use_result
            .as_ref()
            .filter(|_| blocks.len() == 1);
        let mut events = Vec::new();
        for block in blocks {
            let Some(id) = block["tool_use_id"].as_str() else {
                continue;
            };
            events.extend(self.stop_command_output(id));
            if self.open_items.get(id).map(String::as_str) != Some("command_execution") {
                continue;
            }
            self.open_items.remove(id);
            let failed = block["is_error"] == true;
            let output = claude_command_output_text(structured, &block["content"]);
            let mut event = self.event(
                EventKind::ItemCompleted,
                json!({
                    "itemType": "command_execution",
                    "status": if failed { "failed" } else { "completed" },
                    "data": {
                        "type": "tool_result",
                        "content": block["content"],
                        "isError": failed,
                        "output": output,
                    },
                }),
                self.raw("user", message.raw.clone()),
            );
            event.item_id = Some(id.to_owned());
            event.provider_refs = Some(alera_provider_protocol::ProviderRefs {
                provider_turn_id: None,
                provider_item_id: event.item_id.clone(),
                provider_request_id: None,
            });
            if let Some(parent) = &message.parent_tool_use_id {
                event.payload["parentToolUseId"] = json!(parent);
                event.payload["nativeTask"] = json!(alera_provider_protocol::NativeTask {
                    native_tool_call_id: Some(parent.clone()),
                    ..Default::default()
                });
            }
            events.push(event);
        }
        events
    }
}

/// A command's output: its non-blank stdout and stderr, joined by a newline
/// when stdout does not end with one, else the result block's text.
pub(super) fn claude_command_output_text(structured: Option<&Value>, content: &Value) -> String {
    let stream = |key: &str| {
        structured
            .and_then(|result| result.get(key))
            .and_then(Value::as_str)
            .filter(|text| !text.trim().is_empty())
    };
    match (stream("stdout"), stream("stderr")) {
        (Some(stdout), Some(stderr)) if stdout.ends_with('\n') => format!("{stdout}{stderr}"),
        (Some(stdout), Some(stderr)) => format!("{stdout}\n{stderr}"),
        (Some(text), None) | (None, Some(text)) => text.to_owned(),
        (None, None) => match content {
            Value::String(text) => text.clone(),
            Value::Array(parts) => parts
                .iter()
                .filter_map(|part| part["text"].as_str())
                .collect(),
            _ => String::new(),
        },
    }
}

#[cfg(test)]
#[path = "command_output_tests.rs"]
mod tests;
