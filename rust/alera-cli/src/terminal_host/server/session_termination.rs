use serde_json::json;

use crate::terminal_host::protocol::{error_response, event, ok_response};
use crate::terminal_host::session::workspace_shutdown::WorkspaceShutdown;

use super::runtime_mutations::{
    RuntimeMutationEffect, RuntimeMutationFinished, RuntimeMutationOutcome,
};
use super::ServerActor;

impl ServerActor {
    pub(super) async fn terminate_session_request(
        &mut self,
        session_id: String,
    ) -> crate::terminal_host::host_error::HostResult<()> {
        let attached_clients = self
            .sessions
            .get(&session_id)
            .map(|session| session.clients.iter().copied().collect::<Vec<_>>())
            .unwrap_or_default();
        self.abandon_home_inject(&session_id);
        self.queue_terminal_exit_push(&session_id, None).await;
        self.cleanup_orchestration_for_closed_session(
            &session_id,
            "terminal was explicitly terminated",
        )
        .await;
        if !self.remove_terminal_session_tab(&session_id).await? {
            self.hold_history_barrier(&session_id);
            self.flush_all_output(&session_id).await;
            if !self.await_output_writes(&session_id).await {
                return Err(crate::terminal_host::host_error::HostError::state(
                    "Terminal history could not be persisted; the session remains open for retry.",
                ));
            }
            let store = self.store.clone();
            if let Some(mut session) = self.sessions.remove(&session_id) {
                self.inbox.resume_pty_session(&session_id);
                session.terminate(true, &store).await;
            }
        }
        for client in attached_clients {
            self.client_write(
                client,
                event("terminalSessionRemoved", json!({"sessionId": session_id})),
            );
        }
        self.schedule_shutdown_if_idle();
        Ok(())
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
        self.prepare_workspace_session_shutdown(request, false)
            .await
    }

    pub(super) async fn prepare_workspace_session_shutdown(
        &mut self,
        request: &crate::managed_workspace::ManagedWorkspaceRemoveRequest,
        cancel_owned_operations: bool,
    ) -> crate::terminal_host::host_error::HostResult<WorkspaceShutdown> {
        self.prepare_workspace_session_shutdown_with_capture(request, cancel_owned_operations, None)
            .await
    }

    pub(super) async fn prepare_workspace_session_shutdown_with_capture(
        &mut self,
        request: &crate::managed_workspace::ManagedWorkspaceRemoveRequest,
        cancel_owned_operations: bool,
        captured_shutdown: Option<WorkspaceShutdown>,
    ) -> crate::terminal_host::host_error::HostResult<WorkspaceShutdown> {
        use crate::terminal_host::host_error::HostError;
        let mut completions = Vec::new();
        if request.close_sessions
            && self
                .mutation_queue
                .pending_workspace_shutdowns
                .contains_key(&request.id)
            && self.sessions.values().any(|session| {
                session.workspace_id == request.id && session.termination_requested()
            })
        {
            self.terminate_terminal_sessions_for_workspace(&request.id)
                .await;
            if self
                .sessions
                .values()
                .any(|session| session.workspace_id == request.id)
            {
                return Err(history_pending_error(&request.id));
            }
            return Ok(self
                .mutation_queue
                .pending_workspace_shutdowns
                .remove(&request.id)
                .expect("pending shutdown remains owned"));
        }
        if let Some(workspace) = self
            .runtime_store
            .find_workspace(&request.id)
            .await
            .map_err(|error| HostError::state(error.to_string()))?
        {
            let registry = super::ai_assist_operation_registry::active_generations();
            if cancel_owned_operations && request.close_sessions {
                completions = registry.cancel_workspace_operations(&workspace)?;
            } else {
                registry.require_workspace_idle(&workspace, "workspace removal")?;
            }
        }
        if request.close_sessions {
            let mut shutdown = match captured_shutdown {
                Some(mut shutdown) => {
                    shutdown.closed_tab_ids = self
                        .sessions
                        .values()
                        .filter(|session| session.workspace_id == request.id)
                        .map(|session| session.tab_id.clone())
                        .collect();
                    shutdown
                }
                None => {
                    WorkspaceShutdown::capture(
                        self.sessions
                            .values()
                            .filter(|session| session.workspace_id == request.id),
                    )
                    .await?
                }
            };
            shutdown.wait_for_operations(completions);
            if let Some(pending) = self
                .mutation_queue
                .pending_workspace_shutdowns
                .remove(&request.id)
            {
                shutdown.merge(pending);
            }
            self.terminate_terminal_sessions_for_workspace(&request.id)
                .await;
            if self
                .sessions
                .values()
                .any(|session| session.workspace_id == request.id)
            {
                self.mutation_queue
                    .pending_workspace_shutdowns
                    .insert(request.id.clone(), shutdown);
                return Err(history_pending_error(&request.id));
            }
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
        let mutation_committed = outcome.result.is_ok() || outcome.completion_on_error.is_some();
        self.finish_checkout_buffer_guard(client_id, request_id, mutation_committed);
        let RuntimeMutationOutcome {
            result,
            completion_on_error,
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
        }
        if !stopped_workspace_tab_ids.is_empty() {
            self.broadcast_workspace_tabs_changed(None);
        }
        let _ = ended_pointer_tab_ids;
        closed_session_tab_ids.extend(committed_tab_ids);
        closed_session_tab_ids.sort_unstable();
        closed_session_tab_ids.dedup();
        let _ = closed_session_tab_ids;
        if let Some(completion) = completion_on_error {
            let _ = self.apply_runtime_mutation_completion(completion).await;
        }
        match result {
            Ok(completion) => {
                let response = self.apply_runtime_mutation_completion(completion).await;
                if let Some(error) = stopped_tab_cleanup_error {
                    self.client_write(client_id, error_response(request_id, &error));
                } else {
                    self.client_write(client_id, ok_response(request_id, response));
                }
            }
            Err(error) => {
                self.reconcile_transferred_session_owners().await;
                self.broadcast_workspaces_changed(None);
                self.broadcast_workspace_tabs_changed(None);
                if let Some(effect) = effect_on_error {
                    self.apply_runtime_mutation_effect(effect).await;
                }
                self.client_write(client_id, error_response(request_id, &error));
            }
        }
        self.broadcast_authenticated(event("workbenchLayoutsChanged", json!({})));
        self.broadcast_authenticated(event("workspaceActivityChanged", json!({})));
        self.complete_runtime_mutation();
        self.schedule_shutdown_if_idle();
    }

    pub(super) async fn apply_runtime_mutation_effect(&mut self, effect: RuntimeMutationEffect) {
        match effect {
            RuntimeMutationEffect::SetupFinished => {}
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
            RuntimeMutationEffect::WorkspaceRelocated {
                project_id,
                workspace_id,
                source_path,
            } => {
                if let Some(server) = self.codex.as_ref() {
                    server.clear_thread_hydrations().await;
                }
                self.reconcile_relocated_stopped_sessions(&workspace_id, &source_path)
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
                self.broadcast_workspace_sleep_changed(&workspace_id);
            }
            RuntimeMutationEffect::WorkspaceArchived { workspace_id } => {
                if let Some(server) = self.codex.as_ref() {
                    server.clear_thread_hydrations().await;
                }
                self.terminate_terminal_sessions_for_workspace(&workspace_id)
                    .await;
                self.broadcast_workspaces_changed(None);
                self.broadcast_workspace_tabs_changed(Some(&workspace_id));
                self.broadcast_authenticated(event(
                    "workbenchLayoutsChanged",
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

    pub(super) async fn terminate_sessions(&mut self, session_ids: Vec<String>) {
        if session_ids.is_empty() {
            return;
        }
        let store = self.store.clone();
        for session_id in session_ids {
            let already_requested = self
                .sessions
                .get(&session_id)
                .is_some_and(crate::terminal_host::session::Session::termination_requested);
            if !already_requested {
                self.disarm_terminal_pulse(&session_id);
                self.queue_terminal_exit_push(&session_id, None).await;
                self.abandon_home_inject(&session_id);
                self.cleanup_orchestration_for_closed_session(
                    &session_id,
                    "terminal was explicitly terminated",
                )
                .await;
            }
            self.hold_history_barrier(&session_id);
            self.flush_all_output(&session_id).await;
            if !self.await_output_writes(&session_id).await {
                if let Some(session) = self.sessions.get_mut(&session_id) {
                    session.request_termination();
                }
                self.spawn_durable_output_batch_timer(
                    session_id.clone(),
                    self.sessions[&session_id].durable_output_batch_generation(),
                );
                tracing::error!(
                    session_id,
                    "skipping terminal removal because history persistence failed"
                );
                continue;
            }
            let retained_workflow_history =
                self.retains_workflow_terminal_history(&session_id).await;
            if let Some(mut session) = self.sessions.remove(&session_id) {
                self.inbox.resume_pty_session(&session_id);
                let clients: Vec<_> = session.clients.iter().copied().collect();
                session.terminate(!retained_workflow_history, &store).await;
                for client in clients {
                    self.client_write(
                        client,
                        event("terminalSessionRemoved", json!({"sessionId":session_id})),
                    );
                }
            }
            self.settle_closed_workflow_terminal(
                &session_id,
                "The terminal was explicitly terminated. Retry in a new attempt.",
            )
            .await;
        }
        self.schedule_shutdown_if_idle();
    }
}

fn history_pending_error(workspace_id: &str) -> crate::terminal_host::host_error::HostError {
    crate::terminal_host::host_error::HostError::conflict(
        "terminalHistoryPending",
        "Terminal history is still being persisted before workspace cleanup.",
        json!({"workspaceId": workspace_id}),
    )
}
