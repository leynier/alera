//! Native background work the agent resumes from: what keeps a chat working
//! after its turn ends, the background commands the agent says it waits on
//! (`chat_background_wait`), and the parent turn that resumes when a native
//! child finishes after the turn that started it.

use std::time::Duration;

use alera_provider_protocol::{EventKind, ProviderError, ProviderEvent};
use serde_json::{json, Value};

use crate::terminal_host::host_error::{HostError, HostResult};

use super::commands::{conflict, CallerCtx, SendInput};
use super::ids::new_id;
use super::session::ChatSession;

/// A provider that does not answer in time must not hold the chat actor.
pub(super) const BACKGROUND_WAIT_TIMEOUT: Duration = Duration::from_secs(15);
/// The most of a child's result its parent's resume message carries.
const MAX_WAKE_RESULT_BYTES: usize = 64 * 1024;

/// One piece of awaited work (`task.*.awaited`, or a background command the
/// agent marked).
pub(crate) struct AwaitedTask {
    /// The app turn that started it. A failed or stopped turn ends its work
    /// unless the provider says the children continue.
    pub started_in: Option<String>,
    /// Whether its end may resume the parent. Children of a turn that did not
    /// complete keep the chat working but no longer resume it, as the user
    /// stopped or lost that turn.
    pub resumes_parent: bool,
}

fn task_id(event: &ProviderEvent) -> Option<String> {
    event
        .payload
        .get("taskId")
        .and_then(Value::as_str)
        .map(str::trim)
        .filter(|id| !id.is_empty())
        .map(str::to_owned)
}

fn background_wait_unavailable() -> HostError {
    conflict(
        "provider_unavailable",
        "This chat has no live provider session.",
    )
}

fn background_wait_failed() -> HostError {
    conflict(
        "background_wait_failed",
        "Failed to update the awaited background work.",
    )
}

impl ChatSession {
    /// Keeps `awaited_tasks` current, and returns the awaited work a
    /// `task.completed` ended. Only the event that starts a task can register
    /// it, so a late progress event never holds the chat again.
    pub(super) fn track_awaited_task(&mut self, event: &ProviderEvent) -> Option<AwaitedTask> {
        let task_id = task_id(event)?;
        match event.kind {
            EventKind::TaskStarted if event.task_awaited() => {
                let started_in = self.app_turn_id(event);
                self.awaited_tasks.insert(
                    task_id,
                    AwaitedTask {
                        started_in,
                        resumes_parent: true,
                    },
                );
                None
            }
            EventKind::TaskCompleted => {
                let ended = self.awaited_tasks.remove(&task_id)?;
                if self.header.session.active_turn_id.is_none()
                    && self.header.session.status == "running"
                {
                    self.set_status(self.idle_status());
                }
                Some(ended)
            }
            _ => None,
        }
    }

    /// The status of a live provider with no turn running: working while the
    /// agent still waits on its background work.
    pub(super) fn idle_status(&self) -> &'static str {
        if self.awaited_tasks.is_empty() && !self.goal_continuing {
            "ready"
        } else {
            "running"
        }
    }

    /// Child work survives a completed turn, and a failed one whose provider
    /// says its children continue, though those no longer resume the parent.
    /// A failed or stopped turn otherwise takes its children down with it.
    pub(super) fn end_awaited_work_of(
        &mut self,
        turn_id: &str,
        status: &str,
        child_turns_continue: bool,
    ) {
        if status == "completed" {
            return;
        }
        let of_turn = |task: &AwaitedTask| task.started_in.as_deref() == Some(turn_id);
        if child_turns_continue {
            for task in self.awaited_tasks.values_mut().filter(|task| of_turn(task)) {
                task.resumes_parent = false;
            }
        } else {
            self.awaited_tasks.retain(|_, task| !of_turn(task));
        }
    }

    /// Marks or unmarks background tasks the agent waits on, by the ids it
    /// saw. The provider says which ids name running background work; the
    /// rest come back unmatched and change nothing.
    pub(super) async fn await_background_tasks(
        &mut self,
        task_ids: Vec<String>,
        awaited: bool,
    ) -> HostResult<Value> {
        let provider = self
            .provider
            .as_mut()
            .ok_or_else(background_wait_unavailable)?;
        let matched = match tokio::time::timeout(
            BACKGROUND_WAIT_TIMEOUT,
            provider.await_background_tasks(&task_ids, awaited),
        )
        .await
        {
            Ok(Ok(matched)) => matched,
            Ok(Err(ProviderError::Unsupported(_))) => {
                // Worded so MCP clients classify it as an invalid request.
                return Err(conflict(
                    "unsupported",
                    "Invalid request: this chat's provider cannot mark background work as awaited.",
                ));
            }
            Ok(Err(ProviderError::InvalidState(_) | ProviderError::Closed)) => {
                return Err(background_wait_unavailable());
            }
            Ok(Err(error)) => {
                tracing::warn!(chat_id = %self.header.chat_id, error = %error, "awaiting background tasks failed");
                return Err(background_wait_failed());
            }
            Err(_) => return Err(background_wait_failed()),
        };
        // An adapter can only confirm ids the agent named, once each.
        let mut confirmed: Vec<String> = Vec::new();
        for task_id in matched {
            if task_ids.contains(&task_id) && !confirmed.contains(&task_id) {
                confirmed.push(task_id);
            }
        }
        for task_id in &confirmed {
            if awaited {
                // A background command outlives a failed turn, and the agent
                // resumes from its own notification, so it never wakes it.
                self.awaited_tasks
                    .entry(task_id.clone())
                    .or_insert(AwaitedTask {
                        started_in: None,
                        resumes_parent: false,
                    });
            } else {
                self.awaited_tasks.remove(task_id);
            }
        }
        if self.header.session.active_turn_id.is_none()
            && matches!(self.header.session.status.as_str(), "ready" | "running")
        {
            self.set_status(self.idle_status());
        }
        let unmatched: Vec<&String> = task_ids
            .iter()
            .filter(|task_id| !confirmed.contains(task_id))
            .collect();
        Ok(json!({"matched": confirmed, "unmatched": unmatched}))
    }

    /// Starts a parent turn when a native child the provider does not report
    /// back on its own finishes while nothing runs. A running turn receives
    /// the result natively, and a queued message, pending request or
    /// starting provider means the next turn will.
    pub(super) async fn resume_parent_after_child(
        &mut self,
        event: &ProviderEvent,
        ended: AwaitedTask,
    ) {
        if !ended.resumes_parent
            || !event.task_wakes_parent()
            || self.header.archived
            || self.provider.is_none()
            || self.is_busy()
        {
            return;
        }
        let Some(task_id) = task_id(event) else {
            return;
        };
        let input = SendInput {
            client_message_id: new_id("subagent-wake"),
            text: child_result_text(event, &task_id),
            attachments: Vec::new(),
            delivery: "auto".into(),
            model: None,
            reasoning_effort: None,
            interaction_mode: None,
            runtime_mode_ceiling: None,
            origin: Some(json!({"kind": "subagentWake", "taskIds": [task_id]})),
        };
        if let Err(error) = self.send(input, &CallerCtx::runtime()).await {
            tracing::warn!(chat_id = %self.header.chat_id, error = %error, "resuming the parent after its sub-agent failed");
        }
        let _ = self.flush().await;
    }
}

/// `Subagent <status>: <label>`, then the child's final answer when it gave
/// one. The message is the whole wake, so it carries the result itself.
fn child_result_text(event: &ProviderEvent, task_id: &str) -> String {
    let text = |key: &str| {
        event
            .payload
            .get(key)
            .and_then(Value::as_str)
            .map(str::trim)
            .filter(|value| !value.is_empty())
    };
    let status = match text("status") {
        Some("failed") => "failed",
        _ => "completed",
    };
    let header = format!(
        "Subagent {status}: {}",
        text("description").unwrap_or(task_id)
    );
    match text("summary") {
        Some(result) => format!("{header}\n\nResult:\n{}", bounded(result)),
        None => header,
    }
}

fn bounded(text: &str) -> String {
    if text.len() <= MAX_WAKE_RESULT_BYTES {
        return text.to_owned();
    }
    let mut end = MAX_WAKE_RESULT_BYTES;
    while !text.is_char_boundary(end) {
        end -= 1;
    }
    format!("{}\n[truncated]", &text[..end])
}
