//! Root-session tool calls of the running turn, so a permission request that
//! names its tool call by id only keeps the call's command, after T3 Code
//! `b2871029c9` (`withTrackedPermissionToolCall`).

use crate::mapping_values::tool_status;
use crate::AcpProvider;
use agent_client_protocol::AcpIncoming;
use alera_agent_transport::JsonTransport;
use alera_provider_protocol::{ItemStatus, ProviderSession};
use serde_json::{Map, Value};
use std::collections::VecDeque;

const TRACKED_CALL_LIMIT: usize = 256;

#[derive(Debug, Clone, Default, PartialEq)]
struct TrackedCall {
    title: Option<String>,
    kind: Option<String>,
    raw_input: Option<Value>,
}

#[derive(Debug, Default)]
pub(crate) struct TrackedToolCalls {
    scope: Option<(String, Option<String>)>,
    calls: VecDeque<(String, TrackedCall)>,
}

impl TrackedToolCalls {
    pub(crate) fn reset(&mut self) {
        self.scope = None;
        self.calls.clear();
    }

    fn in_scope(&self, session: &str, turn: Option<&str>) -> bool {
        self.scope.as_ref().is_some_and(|(scoped, scoped_turn)| {
            scoped == session && scoped_turn.as_deref() == turn
        })
    }

    /// Records a root `tool_call` or `tool_call_update`; a terminal status
    /// drops the call.
    pub(crate) fn observe(&mut self, session: &str, turn: Option<&str>, update: &Value) {
        if !self.in_scope(session, turn) {
            self.calls.clear();
            self.scope = Some((session.to_owned(), turn.map(str::to_owned)));
        }
        let Some(id) = update.get("toolCallId").and_then(Value::as_str) else {
            return;
        };
        let position = self.calls.iter().position(|(tracked, _)| tracked == id);
        if matches!(
            tool_status(update),
            Some(ItemStatus::Completed | ItemStatus::Failed | ItemStatus::Declined)
        ) {
            if let Some(position) = position {
                self.calls.remove(position);
            }
            return;
        }
        let call = match position {
            Some(position) => &mut self.calls[position].1,
            None => {
                if self.calls.len() >= TRACKED_CALL_LIMIT {
                    self.calls.pop_front();
                }
                self.calls
                    .push_back((id.to_owned(), TrackedCall::default()));
                &mut self.calls.back_mut().expect("tracked call").1
            }
        };
        if let Some(title) = update
            .get("title")
            .and_then(Value::as_str)
            .filter(|title| !title.trim().is_empty())
        {
            call.title = Some(title.to_owned());
        }
        if let Some(kind) = update.get("kind").and_then(Value::as_str) {
            call.kind = Some(kind.to_owned());
        }
        if let Some(raw_input) = update.get("rawInput").filter(|value| !value.is_null()) {
            call.raw_input = Some(raw_input.clone());
        }
    }

    /// Fills the absent `title`, `rawInput` and command `kind` of a
    /// permission request's `toolCall` from the tracked call of the same
    /// session and turn. Fields the agent sent, even as null, are kept; only
    /// an `execute` or `command` kind is filled, so an untracked kind can
    /// never grant command execution.
    pub(crate) fn enrich(&self, session: &str, turn: Option<&str>, params: &mut Value) {
        if !self.in_scope(session, turn) {
            return;
        }
        let Some(tool_call) = params.get_mut("toolCall").and_then(Value::as_object_mut) else {
            return;
        };
        let Some(id) = tool_call.get("toolCallId").and_then(Value::as_str) else {
            return;
        };
        let Some((_, tracked)) = self.calls.iter().find(|(tracked, _)| tracked == id) else {
            return;
        };
        fill(tool_call, "title", tracked.title.clone().map(Value::String));
        fill(tool_call, "rawInput", tracked.raw_input.clone());
        let command_kind = tracked
            .kind
            .clone()
            .filter(|kind| matches!(kind.as_str(), "execute" | "command"));
        fill(tool_call, "kind", command_kind.map(Value::String));
    }
}

impl<T: JsonTransport> AcpProvider<T> {
    /// Tracks the root session's tool calls and fills an id-only permission
    /// request of the root session from them.
    pub(crate) fn track_tool_calls(
        &mut self,
        incoming: &mut AcpIncoming,
        session: &ProviderSession,
    ) {
        let root = session.native_thread_id.as_str();
        let turn = session.active_turn_id.as_deref();
        match incoming {
            AcpIncoming::Notification { params, .. } => {
                if params.get("sessionId").and_then(Value::as_str) != Some(root) {
                    return;
                }
                let Some(update) = params.get("update") else {
                    return;
                };
                if matches!(
                    update.get("sessionUpdate").and_then(Value::as_str),
                    Some("tool_call" | "tool_call_update")
                ) {
                    self.tracked_tool_calls.observe(root, turn, update);
                }
            }
            AcpIncoming::Request(request)
                if request.method == "session/request_permission"
                    && request.params.get("sessionId").and_then(Value::as_str) == Some(root) =>
            {
                self.tracked_tool_calls
                    .enrich(root, turn, &mut request.params);
            }
            _ => {}
        }
    }
}

fn fill(tool_call: &mut Map<String, Value>, key: &str, value: Option<Value>) {
    if let (false, Some(value)) = (tool_call.contains_key(key), value) {
        tool_call.insert(key.to_owned(), value);
    }
}

#[cfg(test)]
#[path = "tracked_tool_calls_tests.rs"]
mod tests;
