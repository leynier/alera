//! ACP v2 native child sessions: the sub-agents an agent runs as sessions of
//! their own (Claude Agent's experimental `subagent_update` on the parent and
//! `session_message` on the child, after T3 Code). A child is linked to the
//! Agent/Task call that delegated to it; its own frames stream as items of
//! the session under that call, and its state becomes `task.*` events keyed
//! by the call, so it reads like a Claude or Codex sub-agent.

use alera_provider_protocol::{EventKind, NativeTask};
use serde_json::{json, Map, Value};
use std::collections::{HashMap, HashSet, VecDeque};

/// Frames a child may send before the delegation that links it arrives.
const MAX_PENDING_FRAMES: usize = 256;
/// Child sessions tracked at once; frames of any more are dropped.
const MAX_CHILDREN: usize = 256;
/// The most of a child's final answer its task result carries.
const MAX_RESULT_BYTES: usize = 64 * 1024;

#[derive(Debug, Clone, Copy, Default, PartialEq, Eq)]
pub(crate) enum ChildStatus {
    #[default]
    Running,
    Completed,
    Failed,
    Cancelled,
}

impl ChildStatus {
    fn wire(self) -> &'static str {
        match self {
            Self::Running => "running",
            Self::Completed => "completed",
            Self::Failed => "failed",
            Self::Cancelled => "cancelled",
        }
    }

    /// ACP v2 `SessionState`: `running`/`requires_action` work, an idle
    /// state ends by its stop reason. Claude reports a lost child as
    /// `unknown`.
    pub(crate) fn from_state(state: &Value) -> Self {
        match state.get("state").and_then(Value::as_str) {
            Some("running" | "requires_action") => Self::Running,
            Some("unknown") => Self::Cancelled,
            _ => match state.get("stopReason").and_then(Value::as_str) {
                Some("error") => Self::Failed,
                Some("cancelled") => Self::Cancelled,
                _ => Self::Completed,
            },
        }
    }
}

/// What the agent asked an Agent/Task call to do.
#[derive(Debug, Clone, Default)]
struct SpawnCall {
    prompt: Option<String>,
    description: Option<String>,
    model: Option<String>,
}

#[derive(Debug, Default)]
struct Child {
    parent: Option<String>,
    /// The native item id of the call that delegated to the child: the task
    /// id of every event about it.
    call: Option<String>,
    status: ChildStatus,
    reported: Option<ChildStatus>,
    error: Option<String>,
    result: String,
    answer_id: Option<String>,
    pending: VecDeque<Value>,
    prompts: HashSet<String>,
}

/// One child event the provider turns into a provider event.
pub(crate) enum ChildEvent {
    /// A `task.*` payload.
    Task(EventKind, Value),
    /// A child frame to project under `call`, from session `session`.
    Frame {
        session: String,
        call: String,
        params: Value,
    },
    /// A later delegation's prompt, shown in the child's transcript.
    Prompt {
        item_id: String,
        call: String,
        text: String,
    },
}

#[derive(Debug, Default)]
pub(crate) struct NativeChildren {
    children: HashMap<String, Child>,
    calls: HashMap<String, SpawnCall>,
    /// ACP v2 accepted the running prompt.
    pub(crate) accepted: bool,
    /// The root session reported work since the prompt was sent.
    pub(crate) running_seen: bool,
}

/// A child's native item id. Root items keep their ids; a child's are
/// scoped to its session, as Claude reuses message ids across sessions.
pub(crate) fn scoped_id(root: &str, session: &str, id: &str) -> String {
    if session == root {
        id.to_owned()
    } else {
        format!("{session}/{id}")
    }
}

fn text(value: Option<&Value>) -> Option<String> {
    value
        .and_then(Value::as_str)
        .map(str::trim)
        .filter(|value| !value.is_empty())
        .map(str::to_owned)
}

impl NativeChildren {
    pub(crate) fn clear(&mut self) {
        *self = Self::default();
    }

    pub(crate) fn reset_turn(&mut self) {
        self.accepted = false;
        self.running_seen = false;
    }

    /// Whether any linked child still works, so a failed root turn leaves
    /// its children running.
    pub(crate) fn any_running(&self) -> bool {
        self.children
            .values()
            .any(|child| child.call.is_some() && child.status == ChildStatus::Running)
    }

    /// The child a task id names, while it runs.
    pub(crate) fn running_child_of(&self, task_id: &str) -> Result<Option<String>, ()> {
        let Some((session, child)) = self
            .children
            .iter()
            .find(|(_, child)| child.call.as_deref() == Some(task_id))
        else {
            return Err(());
        };
        Ok((child.status == ChildStatus::Running).then(|| session.clone()))
    }

    fn is_known(&self, root: &str, session: &str) -> bool {
        session == root
            || self
                .children
                .get(session)
                .is_some_and(|child| child.call.is_some())
    }

    fn child(&mut self, session: &str) -> Option<&mut Child> {
        if !self.children.contains_key(session) && self.children.len() >= MAX_CHILDREN {
            return None;
        }
        Some(self.children.entry(session.to_owned()).or_default())
    }

    /// Remembers an Agent/Task call of session `session`, so the task its
    /// child becomes can say what it was asked.
    pub(crate) fn observe_call(&mut self, root: &str, session: &str, update: &Value) {
        let Some(id) = update.get("toolCallId").and_then(Value::as_str) else {
            return;
        };
        let key = scoped_id(root, session, id);
        let named = matches!(
            update.get("name").and_then(Value::as_str),
            Some("Agent" | "Task")
        );
        if !named && !self.calls.contains_key(&key) {
            return;
        }
        let call = self.calls.entry(key).or_default();
        if let Some(input) = update.get("rawInput").filter(|input| input.is_object()) {
            call.prompt = text(input.get("prompt")).or(call.prompt.take());
            call.description = text(input.get("description")).or(call.description.take());
            call.model = text(input.get("model")).or(call.model.take());
        }
    }

    /// `subagent_update` on session `parent`: a child's state.
    pub(crate) fn child_state(
        &mut self,
        root: &str,
        parent: &str,
        update: &Value,
    ) -> Vec<ChildEvent> {
        let Some(session) = text(update.get("sessionId")) else {
            return Vec::new();
        };
        if !self.is_known(root, parent) || session == root {
            return Vec::new();
        }
        let state = update.get("state").cloned().unwrap_or(Value::Null);
        let Some(child) = self.child(&session) else {
            return Vec::new();
        };
        child.parent.get_or_insert_with(|| parent.to_owned());
        self.set_status(root, &session, ChildStatus::from_state(&state), &state)
    }

    /// A child's own `state_update`.
    pub(crate) fn own_state(
        &mut self,
        root: &str,
        session: &str,
        update: &Value,
    ) -> Vec<ChildEvent> {
        if self.child(session).is_none() {
            return Vec::new();
        }
        self.set_status(root, session, ChildStatus::from_state(update), update)
    }

    fn set_status(
        &mut self,
        root: &str,
        session: &str,
        status: ChildStatus,
        state: &Value,
    ) -> Vec<ChildEvent> {
        let Some(child) = self.children.get_mut(session) else {
            return Vec::new();
        };
        if status == ChildStatus::Running && child.status != ChildStatus::Running {
            // A new run replaces the last one's answer.
            child.result.clear();
            child.answer_id = None;
            child.error = None;
        }
        child.status = status;
        if status != ChildStatus::Running {
            child.error = text(state.pointer("/error/message")).or(child.error.take());
        }
        self.report(root, session).into_iter().collect()
    }

    /// `session_message` on child `session`: the call that delegated to it.
    pub(crate) fn delegation(
        &mut self,
        root: &str,
        session: &str,
        update: &Value,
    ) -> Vec<ChildEvent> {
        let Some(message) = text(update.get("messageId")) else {
            return Vec::new();
        };
        let known_parent = self.children.get(session).and_then(|c| c.parent.clone());
        let Some(sender) = text(update.get("senderSessionId")).or(known_parent) else {
            return Vec::new();
        };
        if sender == session || !self.is_known(root, &sender) {
            return Vec::new();
        }
        let call = scoped_id(root, &sender, &message);
        let prompt: String = update
            .get("content")
            .and_then(Value::as_array)
            .into_iter()
            .flatten()
            .filter(|block| block.get("type").and_then(Value::as_str) == Some("text"))
            .filter_map(|block| block.get("text").and_then(Value::as_str))
            .collect::<Vec<_>>()
            .join("\n");
        if self.child(session).is_none() {
            return Vec::new();
        }
        let child = self.children.get_mut(session).expect("tracked above");
        child.parent = Some(sender);
        let Some(owner) = child.call.clone() else {
            child.call = Some(call.clone());
            child.prompts.insert(call.clone());
            let pending = std::mem::take(&mut child.pending);
            let running = child.status == ChildStatus::Running;
            self.calls
                .entry(call.clone())
                .or_default()
                .prompt
                .get_or_insert(prompt);
            let mut events = Vec::new();
            if running {
                events.extend(self.report(root, session));
            }
            events.extend(pending.into_iter().map(|params| ChildEvent::Frame {
                session: session.to_owned(),
                call: call.clone(),
                params,
            }));
            events.extend(self.report(root, session));
            return events;
        };
        // A later delegation (SendMessage) runs the child again under the
        // call that started it; its prompt joins the child's transcript.
        if !child.prompts.insert(call.clone()) || prompt.trim().is_empty() {
            return Vec::new();
        }
        vec![ChildEvent::Prompt {
            item_id: scoped_id(root, session, &format!("prompt:{message}")),
            call: owner,
            text: prompt,
        }]
    }

    /// Any other frame of a child session: projected once the child is
    /// linked, held until then.
    pub(crate) fn frame(&mut self, session: &str, params: Value) -> Vec<ChildEvent> {
        let Some(child) = self.child(session) else {
            return Vec::new();
        };
        match child.call.clone() {
            Some(call) => vec![ChildEvent::Frame {
                session: session.to_owned(),
                call,
                params,
            }],
            None => {
                if child.pending.len() < MAX_PENDING_FRAMES {
                    child.pending.push_back(params);
                }
                Vec::new()
            }
        }
    }

    /// Text a child said. Its latest message is its run's answer.
    pub(crate) fn record_answer(&mut self, session: &str, message: Option<&str>, delta: &str) {
        if let Some(child) = self.children.get_mut(session) {
            if child.answer_id.as_deref() != message {
                child.answer_id = message.map(str::to_owned);
                child.result.clear();
            }
            if child.result.len() + delta.len() <= MAX_RESULT_BYTES {
                child.result.push_str(delta);
            }
        }
    }

    /// The task event for a linked child whose status changed since the
    /// last one. A run that starts again is a new `task.started`, so the
    /// chat waits on it again.
    fn report(&mut self, root: &str, session: &str) -> Option<ChildEvent> {
        let child = self.children.get(session)?;
        let call = child.call.clone()?;
        let status = child.status;
        if child.reported == Some(status) {
            return None;
        }
        let spawn = self.calls.get(&call).cloned().unwrap_or_default();
        let mut payload = Map::new();
        payload.insert("taskId".into(), call.clone().into());
        payload.insert("status".into(), status.wire().into());
        payload.insert("childSessionId".into(), session.into());
        if let Some(label) = spawn.description.or(spawn.prompt) {
            payload.insert("description".into(), label.into());
        }
        if let Some(model) = spawn.model {
            payload.insert("model".into(), model.into());
        }
        let parent = child.parent.clone();
        if let Some(parent_call) = parent
            .as_deref()
            .filter(|parent| *parent != root)
            .and_then(|parent| self.children.get(parent))
            .and_then(|parent| parent.call.clone())
        {
            payload.insert("parentTaskId".into(), parent_call.into());
        }
        let kind = if status == ChildStatus::Running {
            payload.insert("awaited".into(), Value::Bool(true));
            EventKind::TaskStarted
        } else {
            let answer = child.result.trim();
            if let Some(summary) = (!answer.is_empty())
                .then(|| answer.to_owned())
                .or_else(|| child.error.clone())
            {
                payload.insert("summary".into(), summary.into());
            }
            EventKind::TaskCompleted
        };
        payload.insert(
            "nativeTask".into(),
            json!(NativeTask {
                native_task_id: Some(session.to_owned()),
                parent_native_thread_id: parent,
                child_native_thread_ids: vec![session.to_owned()],
                native_tool_call_id: Some(call),
                status: Some(status.wire().to_owned()),
            }),
        );
        self.children.get_mut(session)?.reported = Some(status);
        Some(ChildEvent::Task(kind, Value::Object(payload)))
    }
}
