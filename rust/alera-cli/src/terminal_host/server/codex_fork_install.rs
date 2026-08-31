use super::codex_fork_jobs::CodexForkJob;
use super::codex_queue::store_error;
use super::codex_state::{set_thread_and_snapshot, snapshot, CodexTurnHistoryPage};
use super::codex_tab_lifecycle::{
    active_cwd, configuration, set_active_cwd, set_configuration, set_thread_owned_by_alera,
};
use super::ServerActor;
use crate::terminal_host::host_error::{HostError, HostResult};
use alera_core::runtime::WorkspaceTabRecord;
use chrono::Utc;
use serde_json::{json, Value};

impl ServerActor {
    pub(super) async fn install_codex_fork(
        &mut self,
        job: &CodexForkJob,
        response: &Value,
        page: Option<CodexTurnHistoryPage>,
    ) -> HostResult<Value> {
        let mut state = self.validate_codex_fork(job).await?;
        let tab = &job.tab;
        let operation_id = job.operation_id.clone();
        let thread_id = response
            .pointer("/thread/id")
            .and_then(Value::as_str)
            .ok_or_else(|| HostError::state("Codex returned no fork identity."))?;
        let now = Utc::now();
        let mut fork = WorkspaceTabRecord {
            id: state
                .operations
                .iter()
                .find(|op| op.id == operation_id)
                .unwrap()
                .payload["forkTabId"]
                .as_str()
                .ok_or_else(|| HostError::state("The fork tab identity is unavailable."))?
                .to_string(),
            workspace_id: tab.workspace_id.clone(),
            kind: tab.kind.clone(),
            title: format!("{} (Fork)", tab.title),
            created_at: now,
            updated_at: now,
            payload: json!({}),
        };
        if let Some(config) = configuration(tab) {
            set_configuration(&mut fork, config);
        }
        if let Some(cwd) = active_cwd(tab) {
            set_active_cwd(&mut fork, &cwd);
        }
        let next_snapshot = page
            .as_ref()
            .map(|page| page.snapshot.clone())
            .unwrap_or_else(|| json!({"timelineCells": [], "pendingRequests": []}));
        let operation = state
            .operations
            .iter()
            .find(|op| op.id == operation_id)
            .unwrap();
        let surviving_turns: std::collections::HashSet<&str> = operation.payload["forkedTurnIds"]
            .as_array()
            .into_iter()
            .flatten()
            .filter_map(Value::as_str)
            .collect();
        let mut presentation = snapshot(tab);
        if let Some(cells) = presentation["timelineCells"].as_array_mut() {
            cells.retain(|cell| {
                cell["kind"] == "userMessage"
                    && cell["turnId"]
                        .as_str()
                        .is_some_and(|id| surviving_turns.contains(id))
            });
        }
        let receipts = super::codex_history_edit::delivery_presentation_snapshot(
            tab,
            &state,
            &surviving_turns,
        );
        let next_snapshot = super::codex_state::merge_resume_snapshot(&receipts, next_snapshot);
        let next_snapshot = super::codex_state::merge_resume_snapshot(&presentation, next_snapshot);
        set_thread_and_snapshot(&mut fork, thread_id, next_snapshot);
        set_thread_owned_by_alera(&mut fork, true);
        fork.payload["forkedFromId"] = json!(state.thread_id);
        fork.payload["codexSnapshot"]["title"] = json!(fork.title);
        let saved = self
            .runtime_store
            .upsert_workspace_tab(fork)
            .await
            .map_err(store_error)?;
        let result = json!({"tabId": saved.id, "workspaceId": saved.workspace_id, "threadId": thread_id, "tab": saved, "snapshot": snapshot(&saved)});
        let operation = state
            .operations
            .iter_mut()
            .find(|op| op.id == operation_id)
            .unwrap();
        operation.phase = "completed".into();
        operation.result = Some(result.clone());
        self.save_codex_delivery(&mut state).await?;
        self.broadcast_workspace_tabs_changed(Some(&saved.workspace_id));
        Ok(result)
    }
}
