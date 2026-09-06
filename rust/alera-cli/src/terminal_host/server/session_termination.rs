use serde_json::json;

use crate::terminal_host::protocol::{error_response, event, ok_response};
use crate::terminal_host::session::workspace_shutdown::WorkspaceShutdown;

use super::runtime_mutations::{
    RuntimeMutationEffect, RuntimeMutationFinished, RuntimeMutationOutcome, RuntimeMutationRequest,
};
use super::ServerActor;

impl ServerActor {
    pub(super) async fn prepare_runtime_mutation(
        &mut self,
        request: &RuntimeMutationRequest,
    ) -> crate::terminal_host::host_error::HostResult<WorkspaceShutdown> {
        use crate::terminal_host::host_error::HostError;

        if let RuntimeMutationRequest::RemoveManagedWorkspace { request } = request {
            return self.prepare_managed_workspace_removal(request).await;
        }
        // Check when the queued operation starts, not when it was enqueued:
        // an earlier removal may have just failed and retained a shutdown.
        for workspace_id in self.mutation_queue.pending_workspace_shutdowns.keys() {
            let removes_owner = match request {
                RuntimeMutationRequest::RemoveWorkspace {
                    workspace_id: target,
                    ..
                } => target == workspace_id,
                RuntimeMutationRequest::RemoveProject { project_id }
                | RuntimeMutationRequest::RemoveProjectWorkspaces { project_id } => {
                    let workspace = self
                        .runtime_store
                        .find_workspace(workspace_id)
                        .await
                        .map_err(|error| HostError::state(error.to_string()))?;
                    workspace.is_none_or(|workspace| workspace.project_id == *project_id)
                }
                _ => false,
            };
            if removes_owner {
                return Err(HostError::state("Workspace has unfinished process shutdown. Retry confirmed workspace cleanup before removing its records or project."));
            }
        }
        Ok(WorkspaceShutdown::default())
    }

    pub(super) async fn prepare_managed_workspace_removal(
        &mut self,
        request: &crate::managed_workspace::ManagedWorkspaceRemoveRequest,
    ) -> crate::terminal_host::host_error::HostResult<WorkspaceShutdown> {
        use crate::terminal_host::host_error::HostError;

        // Revalidate after queueing and before terminating anything. A rejected
        // path or automation owner must leave the user's running work intact.
        crate::managed_workspace::validate_managed_workspace_removal(&self.runtime_store, request)
            .await
            .map_err(|error| HostError::state(error.to_string()))?;
        if request.close_sessions {
            let mut shutdown = WorkspaceShutdown::capture(
                self.sessions
                    .values()
                    .filter(|session| session.workspace_id == request.id),
            )
            .await?;
            if let Some(pending) = self
                .mutation_queue
                .pending_workspace_shutdowns
                .remove(&request.id)
            {
                shutdown.merge(pending);
            }
            self.terminate_terminal_sessions_for_workspace(&request.id)
                .await;
            return Ok(shutdown);
        } else if self
            .mutation_queue
            .pending_workspace_shutdowns
            .contains_key(&request.id)
        {
            return Err(HostError::state(
                "Workspace has unfinished process shutdown. Confirm session cleanup to retry.",
            ));
        } else if self
            .sessions
            .values()
            .any(|session| session.workspace_id == request.id && session.running())
        {
            return Err(HostError::state("Workspace has live sessions"));
        }
        Ok(WorkspaceShutdown::default())
    }

    pub(super) async fn handle_runtime_mutation_finished(
        &mut self,
        finished: RuntimeMutationFinished,
    ) {
        let RuntimeMutationFinished {
            client_id,
            request_id,
            outcome,
        } = finished;
        let RuntimeMutationOutcome {
            result,
            pending_codex_cleanup,
            ended_pointer_tab_ids,
            mut closed_session_tab_ids,
            committed_tab_ids,
            effect_on_error,
            stopped_workspace_tab_ids,
            pending_workspace_shutdown,
        } = outcome;
        if let Some(pending) = pending_workspace_shutdown {
            let (workspace_id, shutdown) = *pending;
            // Sessions are already gone. Keep their process ownership for the
            // next attempt instead of letting an empty recapture permit deletion.
            self.mutation_queue
                .pending_workspace_shutdowns
                .insert(workspace_id, shutdown);
        }
        // Teardown is irreversible even if a later Git operation fails. Retire
        // only those tabs whose resources were closed, and notify every client
        // so scrollback and transcript watches are released.
        let mut stopped_tab_cleanup_error = None;
        for tab_id in &stopped_workspace_tab_ids {
            if let Err(error) = self.runtime_store.remove_workspace_tab(tab_id).await {
                stopped_tab_cleanup_error =
                    Some(crate::terminal_host::host_error::HostError::state(format!(
                        "Failed to retire stopped workspace tab: {error}"
                    )));
            }
            self.remove_codex_presence(tab_id);
        }
        if !stopped_workspace_tab_ids.is_empty() {
            self.broadcast_workspace_tabs_changed(None);
        }
        let mut pending_tab_ids = pending_codex_cleanup
            .iter()
            .map(|entry| entry.tab_id.clone())
            .collect::<Vec<_>>();
        pending_tab_ids.sort_unstable();
        pending_tab_ids.dedup();
        for tab_id in pending_tab_ids {
            self.handle_codex_force_flush(&tab_id).await;
        }
        let cleanup_result = super::codex_runtime_cleanup::apply_cleanup_activity(
            &self.runtime_store,
            &pending_codex_cleanup,
        )
        .await;
        let cleaned_codex_tab_ids = match &cleanup_result {
            Ok(tab_ids) => tab_ids.clone(),
            Err(error) => {
                self.broadcast_codex_server_error(error.wire_message());
                Vec::new()
            }
        };
        let cleaned_codex_state = !cleaned_codex_tab_ids.is_empty();
        for tab_id in cleaned_codex_tab_ids {
            if let Ok(Some(tab)) = self.runtime_store.find_workspace_tab(&tab_id).await {
                self.refresh_codex_presence(&tab);
                self.broadcast_authenticated(event(
                    "codexThreadChanged",
                    json!({
                        "tabId": tab.id,
                        "workspaceId": tab.workspace_id,
                        "threadId": super::codex_state::tab_thread_id(&tab),
                        "snapshot": super::codex_state::snapshot(&tab),
                    }),
                ));
            }
        }
        if cleaned_codex_state {
            self.schedule_codex_presence_changed();
        }
        let _ = ended_pointer_tab_ids;
        closed_session_tab_ids.extend(committed_tab_ids);
        closed_session_tab_ids.sort_unstable();
        closed_session_tab_ids.dedup();
        let _ = closed_session_tab_ids;
        match result {
            Ok(completion) => {
                let _ = completion.closed_tab_ids;
                self.apply_runtime_mutation_effect(completion.effect).await;
                self.reconcile_codex_presence().await;
                self.schedule_codex_presence_changed();
                if let Some(error) = stopped_tab_cleanup_error.or_else(|| cleanup_result.err()) {
                    self.client_write(client_id, error_response(request_id, &error));
                } else {
                    self.client_write(client_id, ok_response(request_id, completion.response));
                }
            }
            Err(error) => {
                if let Some(effect) = effect_on_error {
                    self.apply_runtime_mutation_effect(effect).await;
                }
                self.client_write(client_id, error_response(request_id, &error));
            }
        }
        self.complete_runtime_mutation();
        for tab_id in self.codex_delivery_active.clone() {
            if self.codex_tab(&tab_id).await.is_ok() {
                self.schedule_codex_queue(&tab_id);
            } else {
                self.codex_delivery_active.remove(&tab_id);
            }
        }
        self.schedule_shutdown_if_idle();
    }

    async fn apply_runtime_mutation_effect(&mut self, effect: RuntimeMutationEffect) {
        match effect {
            RuntimeMutationEffect::ProjectRemoved {
                project_id,
                workspace_ids,
            } => {
                if let Some(server) = self.codex.as_ref() {
                    server.clear_thread_hydrations().await;
                }
                self.terminate_terminal_sessions_for_workspaces(&workspace_ids)
                    .await;
                self.broadcast_authenticated(event("projectsChanged", json!({})));
                self.broadcast_workspaces_changed(Some(&project_id));
                self.broadcast_workspace_tabs_changed(None);
                self.broadcast_authenticated(event("projectConfigsChanged", json!({})));
            }
            RuntimeMutationEffect::WorkspaceRemoved { workspace_id } => {
                if let Some(server) = self.codex.as_ref() {
                    server.clear_thread_hydrations().await;
                }
                self.terminate_terminal_sessions_for_workspace(&workspace_id)
                    .await;
                self.broadcast_workspaces_changed(None);
                self.broadcast_workspace_tabs_changed(Some(&workspace_id));
            }
            RuntimeMutationEffect::ProjectWorkspacesRemoved {
                project_id,
                workspace_ids,
            } => {
                if let Some(server) = self.codex.as_ref() {
                    server.clear_thread_hydrations().await;
                }
                self.terminate_terminal_sessions_for_workspaces(&workspace_ids)
                    .await;
                self.broadcast_workspaces_changed(Some(&project_id));
                self.broadcast_workspace_tabs_changed(None);
            }
            RuntimeMutationEffect::ManagedWorkspaceRemoved {
                project_id,
                workspace_id,
            } => {
                if let Some(server) = self.codex.as_ref() {
                    server.clear_thread_hydrations().await;
                }
                self.terminate_terminal_sessions_for_workspace(&workspace_id)
                    .await;
                self.broadcast_workspaces_changed(Some(&project_id));
                self.broadcast_workspace_tabs_changed(Some(&workspace_id));
            }
            RuntimeMutationEffect::TabRemoved {
                tab_id,
                workspace_id,
            } => {
                if let Some(server) = self.codex.as_ref() {
                    server.forget_thread_hydration(&tab_id).await;
                }
                self.remove_codex_presence(&tab_id);
                self.terminate_terminal_sessions_for_tab(&tab_id).await;
                self.broadcast_workspace_tabs_changed(workspace_id.as_deref());
            }
            RuntimeMutationEffect::WorkspaceTabsRemoved { workspace_id } => {
                if let Some(server) = self.codex.as_ref() {
                    server.clear_thread_hydrations().await;
                }
                self.terminate_terminal_sessions_for_workspace(&workspace_id)
                    .await;
                self.broadcast_workspace_tabs_changed(Some(&workspace_id));
                self.broadcast_authenticated(event("workbenchLayoutsChanged", json!({})));
            }
            RuntimeMutationEffect::WorkspaceSlept { workspace_id } => {
                if let Some(server) = self.codex.as_ref() {
                    server.clear_thread_hydrations().await;
                }
                self.terminate_terminal_sessions_for_workspace(&workspace_id)
                    .await;
                self.broadcast_workspace_tabs_changed(Some(&workspace_id));
                self.broadcast_authenticated(event(
                    "workbenchLayoutsChanged",
                    json!({"workspaceId": workspace_id}),
                ));
                self.broadcast_authenticated(event(
                    "workspaceActivityChanged",
                    json!({"workspaceId": workspace_id}),
                ));
            }
        }
    }

    pub(super) async fn terminate_sessions_for_tab(&mut self, tab_id: &str) {
        self.cancel_agent_title_job(tab_id);
        self.terminate_terminal_sessions_for_tab(tab_id).await;
    }

    async fn terminate_terminal_sessions_for_tab(&mut self, tab_id: &str) {
        let session_ids = self
            .sessions
            .iter()
            .filter(|(_, session)| session.tab_id == tab_id)
            .map(|(session_id, _)| session_id.clone())
            .collect();
        self.terminate_sessions(session_ids).await;
    }

    async fn terminate_terminal_sessions_for_workspace(&mut self, workspace_id: &str) {
        let session_ids = self
            .sessions
            .iter()
            .filter(|(_, session)| session.workspace_id == workspace_id)
            .map(|(session_id, _)| session_id.clone())
            .collect();
        self.terminate_sessions(session_ids).await;
    }

    async fn terminate_terminal_sessions_for_workspaces(&mut self, workspace_ids: &[String]) {
        let session_ids = self
            .sessions
            .iter()
            .filter(|(_, session)| {
                workspace_ids
                    .iter()
                    .any(|workspace_id| workspace_id == &session.workspace_id)
            })
            .map(|(session_id, _)| session_id.clone())
            .collect();
        self.terminate_sessions(session_ids).await;
    }

    async fn terminate_sessions(&mut self, session_ids: Vec<String>) {
        if session_ids.is_empty() {
            return;
        }
        let store = self.store.clone();
        for session_id in session_ids {
            self.disarm_terminal_pulse(&session_id);
            self.queue_terminal_exit_push(&session_id, None).await;
            self.cleanup_orchestration_for_closed_session(
                &session_id,
                "terminal was explicitly terminated",
            )
            .await;
            self.flush_all_output(&session_id);
            self.await_output_writes(&session_id).await;
            if let Some(mut session) = self.sessions.remove(&session_id) {
                session.terminate(true, &store).await;
            }
        }
        self.schedule_shutdown_if_idle();
    }
}
