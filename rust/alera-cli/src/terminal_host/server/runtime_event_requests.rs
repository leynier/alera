//! The runtime event journal: recording domain events and reading them back.
//!
//! Every event carries identifiers and states only, never prompts, terminal
//! output, source code, or message text, so it is safe to forward to a client
//! or a webhook. Readers page with `runtimeEvents.list` and a cursor; local
//! clients also receive `runtimeEventsAppended` as a hint to read again.

use alera_core::runtime::{RuntimeEventFilter, RuntimeStore};
use serde_json::{json, Map, Value};

use super::ServerActor;
use crate::terminal_host::host_error::{HostError, HostResult};
use crate::terminal_host::protocol::event;

/// Every kind the journal records, with the only data keys it may carry.
pub(crate) const EVENT_KINDS: &[(&str, &[&str])] = &[
    (
        "inbox.reply",
        &[
            "inbox",
            "threadId",
            "questionId",
            "messageId",
            "originClientId",
        ],
    ),
    (
        "inbox.question.status",
        &["inbox", "threadId", "questionId", "status"],
    ),
    (
        "agent.status",
        &["tabId", "sessionId", "agentType", "state"],
    ),
    ("terminal.exit", &["tabId", "sessionId", "exitCode"]),
    ("orchestration.task.state", &["taskId", "runId", "state"]),
    ("orchestration.gate.created", &["gateId", "taskId", "runId"]),
    (
        "orchestration.escalation",
        &["taskId", "runId", "messageId"],
    ),
    ("automation.run.state", &["automationId", "runId", "status"]),
    ("workspace.start.state", &["operationId", "status", "phase"]),
    ("workspace.lifecycle", &["action"]),
    ("pullRequest.watch", &["number", "action"]),
];

/// Keeps only the keys the kind allows, so a caller can never put text
/// beyond identifiers and states into the journal.
pub(crate) fn allowed_event_data(kind: &str, data: &Value) -> Option<Value> {
    let (_, keys) = EVENT_KINDS.iter().find(|(name, _)| *name == kind)?;
    let mut allowed = Map::new();
    for key in *keys {
        if let Some(value) = data.get(*key).filter(|value| is_scalar(value)) {
            allowed.insert((*key).to_owned(), value.clone());
        }
    }
    Some(Value::Object(allowed))
}

/// `(workspaceId, projectId, action)` for each workspace a mutation changed.
fn lifecycle_events(
    effect: &super::runtime_mutations::RuntimeMutationEffect,
) -> Vec<(String, Option<String>, &'static str)> {
    use super::runtime_mutations::RuntimeMutationEffect as Effect;
    match effect {
        Effect::WorkspaceRemoved { workspace_id } => {
            vec![(workspace_id.clone(), None, "removed")]
        }
        Effect::ManagedWorkspaceRemoved {
            project_id,
            workspace_id,
        } => vec![(workspace_id.clone(), Some(project_id.clone()), "removed")],
        Effect::ProjectRemoved {
            project_id,
            workspace_ids,
        }
        | Effect::ProjectWorkspacesRemoved {
            project_id,
            workspace_ids,
        } => workspace_ids
            .iter()
            .map(|id| (id.clone(), Some(project_id.clone()), "removed"))
            .collect(),
        Effect::WorkspaceRelocated {
            project_id,
            workspace_id,
            ..
        } => vec![(workspace_id.clone(), Some(project_id.clone()), "relocated")],
        Effect::WorkspaceSlept { workspace_id } => vec![(workspace_id.clone(), None, "slept")],
        Effect::WorkspaceArchived { workspace_id } => {
            vec![(workspace_id.clone(), None, "archived")]
        }
        Effect::SetupFinished | Effect::TabRemoved { .. } | Effect::WorkspaceTabsRemoved { .. } => {
            Vec::new()
        }
    }
}

fn is_scalar(value: &Value) -> bool {
    match value {
        Value::String(text) => text.len() <= 256,
        Value::Number(_) | Value::Bool(_) | Value::Null => true,
        _ => false,
    }
}

/// Appends one event; a write failure only logs, it never fails the action
/// that produced the event.
pub(crate) async fn record_runtime_event(
    store: &RuntimeStore,
    kind: &str,
    workspace_id: Option<&str>,
    project_id: Option<&str>,
    data: &Value,
) -> Option<i64> {
    let Some(data) = allowed_event_data(kind, data) else {
        tracing::warn!(kind, "unknown runtime event kind");
        return None;
    };
    match store
        .append_runtime_event(kind, workspace_id, project_id, &data)
        .await
    {
        Ok(seq) => Some(seq),
        Err(error) => {
            tracing::warn!(kind, "could not record runtime event: {error}");
            None
        }
    }
}

impl ServerActor {
    /// Records an event and tells local clients to read the journal again.
    pub(super) async fn record_event(
        &self,
        kind: &str,
        workspace_id: Option<&str>,
        project_id: Option<&str>,
        data: Value,
    ) {
        if let Some(seq) =
            record_runtime_event(&self.runtime_store, kind, workspace_id, project_id, &data).await
        {
            self.broadcast_runtime_events_appended(seq, kind);
        }
    }

    /// Workspace and tab of a live session, for events about it.
    fn session_place(&self, session_id: &str) -> (Option<String>, Option<String>) {
        self.sessions
            .get(session_id)
            .map_or((None, None), |session| {
                (
                    Some(session.workspace_id.clone()),
                    Some(session.tab_id.clone()),
                )
            })
    }

    pub(super) async fn journal_agent_status(
        &self,
        session_id: &str,
        agent_type: &str,
        state: &str,
    ) {
        let (workspace_id, tab_id) = self.session_place(session_id);
        let data = json!({ "sessionId": session_id, "tabId": tab_id, "agentType": agent_type, "state": state });
        self.record_event("agent.status", workspace_id.as_deref(), None, data)
            .await;
    }

    pub(super) async fn journal_terminal_exit(&self, session_id: &str, exit_code: Option<i32>) {
        let (workspace_id, tab_id) = self.session_place(session_id);
        let data = json!({ "sessionId": session_id, "tabId": tab_id, "exitCode": exit_code });
        self.record_event("terminal.exit", workspace_id.as_deref(), None, data)
            .await;
    }

    pub(super) async fn journal_task_attention(&self, kind: &str, task_id: &str) {
        let task = self
            .runtime_store
            .orchestration_task_by_id(task_id)
            .await
            .ok()
            .flatten();
        let (workspace_id, run_id) =
            task.map_or((None, None), |task| (Some(task.workspace_id), task.run_id));
        let data = json!({ "taskId": task_id, "runId": run_id });
        self.record_event(kind, workspace_id.as_deref(), None, data)
            .await;
    }

    pub(super) async fn journal_inbox_reply(
        &self,
        message: &alera_core::runtime::OrchestrationMessage,
    ) {
        if !alera_core::runtime::is_external_inbox(&message.to_handle) {
            return;
        }
        let data = json!({
            "inbox": message.to_handle,
            "threadId": message.thread_id.clone().unwrap_or_else(|| message.id.clone()),
            "questionId": message.reply_to_id,
            "messageId": message.id,
        });
        self.record_event("inbox.reply", None, None, data).await;
    }

    pub(super) async fn journal_automation_run(
        &self,
        run: &alera_core::runtime::AutomationRun,
        status: alera_core::runtime::AutomationRunStatus,
    ) {
        let data = json!({ "automationId": run.automation_id, "runId": run.id, "status": status });
        self.record_event(
            "automation.run.state",
            run.workspace_id.as_deref(),
            None,
            data,
        )
        .await;
    }

    /// Journals the workspace lifecycle change a runtime mutation applied.
    pub(super) async fn record_workspace_lifecycle(
        &self,
        effect: &super::runtime_mutations::RuntimeMutationEffect,
    ) {
        for (workspace_id, project_id, action) in lifecycle_events(effect) {
            self.record_event(
                "workspace.lifecycle",
                Some(&workspace_id),
                project_id.as_deref(),
                json!({ "action": action }),
            )
            .await;
        }
    }

    pub(super) fn broadcast_runtime_events_appended(&self, seq: i64, kind: &str) {
        self.broadcast_authenticated_local(event(
            "runtimeEventsAppended",
            json!({ "seq": seq, "kind": kind }),
        ));
    }

    pub(super) async fn runtime_events_list_request(&self, payload: &Value) -> HostResult<Value> {
        let kinds = payload
            .get("kinds")
            .and_then(Value::as_array)
            .map(|kinds| {
                kinds
                    .iter()
                    .filter_map(Value::as_str)
                    .map(str::to_owned)
                    .collect::<Vec<_>>()
            })
            .unwrap_or_default();
        if let Some(unknown) = kinds
            .iter()
            .find(|kind| !EVENT_KINDS.iter().any(|(name, _)| name == kind))
        {
            return Err(HostError::format(format!("Unknown event kind: {unknown}")));
        }
        let filter = RuntimeEventFilter {
            after: payload
                .get("after")
                .and_then(Value::as_i64)
                .unwrap_or(0)
                .max(0),
            kinds,
            workspace_id: payload
                .get("workspaceId")
                .and_then(Value::as_str)
                .map(str::to_owned),
            limit: payload.get("limit").and_then(Value::as_i64).unwrap_or(100),
        };
        let page = self
            .runtime_store
            .list_runtime_events(&filter)
            .await
            .map_err(|error| HostError::state(error.to_string()))?;
        serde_json::to_value(page).map_err(|error| HostError::state(error.to_string()))
    }
}

#[cfg(test)]
mod tests {
    use serde_json::json;

    use super::{allowed_event_data, EVENT_KINDS};

    #[test]
    fn event_data_keeps_only_allowed_scalar_keys() {
        let data = allowed_event_data(
            "inbox.reply",
            &json!({
                "threadId": "t-1",
                "questionId": "q-1",
                "body": "the reply text",
                "messageId": { "nested": true },
            }),
        )
        .unwrap();
        assert_eq!(data, json!({ "threadId": "t-1", "questionId": "q-1" }));
        assert!(allowed_event_data("made.up", &json!({})).is_none());
    }

    #[test]
    fn no_kind_allows_text_payload_keys() {
        for (kind, keys) in EVENT_KINDS {
            for key in *keys {
                let lower = key.to_lowercase();
                for forbidden in ["prompt", "body", "text", "output", "command", "subject"] {
                    assert!(!lower.contains(forbidden), "{kind} allows {key}");
                }
            }
        }
    }
}
