//! Recover delivery state and release idle-host retention after an app-server exit.

use super::codex_queue::store_error;
use super::codex_state::{is_codex_tab, tab_thread_id};
use super::ServerActor;
use crate::terminal_host::host_error::HostResult;
use crate::terminal_host::protocol::event;
use serde_json::json;

impl ServerActor {
    pub(super) async fn handle_codex_process_exited(&mut self, reason: String) {
        let pending_ids = self
            .codex_pending_messages
            .keys()
            .cloned()
            .collect::<Vec<_>>();
        for tab_id in pending_ids {
            self.handle_codex_force_flush(&tab_id).await;
        }
        self.codex = None;
        self.codex_starting = None;
        let workspaces = match self.runtime_store.list_all_workspaces().await {
            Ok(workspaces) => workspaces,
            Err(error) => {
                self.broadcast_codex_server_error(format!(
                    "{reason} Workspace state could not be reconciled: {error}"
                ));
                return;
            }
        };
        for workspace in workspaces {
            let tabs = match self.runtime_store.list_workspace_tabs(&workspace.id).await {
                Ok(tabs) => tabs,
                Err(_) => continue,
            };
            for tab in tabs.into_iter().filter(is_codex_tab) {
                let mut failed = tab;
                let next_snapshot = super::codex_state::mark_server_failure(&mut failed, &reason);
                if let Ok(saved) = self.runtime_store.upsert_workspace_tab(failed).await {
                    self.refresh_codex_presence(&saved);
                    self.broadcast_authenticated(event(
                        "codexThreadChanged",
                        json!({
                            "tabId": saved.id,
                            "workspaceId": saved.workspace_id,
                            "threadId": tab_thread_id(&saved),
                "historyRevision": saved.payload.get("codexHistoryRevision").cloned().unwrap_or(json!(0)),
                            "snapshot": next_snapshot,
                        }),
                    ));
                }
            }
        }
        if let Err(error) = self.pause_codex_queues_after_exit(&reason).await {
            tracing::warn!("Codex queue exit recovery failed: {error}");
        }
        self.schedule_codex_presence_changed();
        self.broadcast_codex_server_error(reason);
    }

    pub(super) async fn pause_codex_queues_after_exit(&mut self, reason: &str) -> HostResult<()> {
        for mut state in self
            .runtime_store
            .list_codex_chat_states()
            .await
            .map_err(store_error)?
        {
            if state.has_pending() || state.history_locked() {
                state.paused = true;
            }
            for entry in &mut state.messages {
                if entry.status == "sending" {
                    entry.status = "uncertain".into();
                    entry.error = Some(reason.into());
                    entry.revision += 1;
                }
            }
            for operation in &mut state.operations {
                if operation.kind == "edit"
                    && matches!(
                        operation.phase.as_str(),
                        "interrupting" | "rollingBack" | "resending"
                    )
                {
                    operation.payload["uncertainPhase"] = json!(operation.phase);
                    operation.payload["lastError"] = json!(reason);
                    operation.phase = "uncertain".into();
                }
            }
            // Snapshots have already lost their active turn. Persist before releasing liveness.
            self.save_codex_delivery(&mut state).await?;
        }
        Ok(())
    }
}
