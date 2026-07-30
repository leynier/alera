use std::sync::Arc;

use serde_json::json;
use tokio::sync::Mutex;

use crate::terminal_host::emulator::EmulatorManager;
use crate::terminal_host::protocol::{error_response, event, ok_response};

use super::runtime_mutations::{
    RuntimeMutationEffect, RuntimeMutationFinished, RuntimeMutationOutcome,
};
use super::ServerActor;

impl ServerActor {
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
            ended_pointer_tab_ids,
            mut closed_session_tab_ids,
            committed_tab_ids,
            effect_on_error,
        } = outcome;
        for tab_id in ended_pointer_tab_ids {
            self.emulator_requests.active_pointers.remove(&tab_id);
        }
        closed_session_tab_ids.extend(committed_tab_ids);
        closed_session_tab_ids.sort_unstable();
        closed_session_tab_ids.dedup();
        for tab_id in &closed_session_tab_ids {
            self.emulator_requests.active_pointers.remove(tab_id);
            self.broadcast_mobile_emulator_changed(Some(tab_id), None, "shutdown");
        }
        match result {
            Ok(completion) => {
                for tab_id in completion.closed_tab_ids {
                    self.emulator_requests.active_pointers.remove(&tab_id);
                    if !closed_session_tab_ids.contains(&tab_id) {
                        self.broadcast_mobile_emulator_changed(Some(&tab_id), None, "shutdown");
                    }
                }
                self.apply_runtime_mutation_effect(completion.effect).await;
                self.client_write(client_id, ok_response(request_id, completion.response));
            }
            Err(error) => {
                if let Some(effect) = effect_on_error {
                    self.apply_runtime_mutation_effect(effect).await;
                }
                self.client_write(client_id, error_response(request_id, &error));
            }
        }
        self.complete_runtime_mutation();
    }

    async fn apply_runtime_mutation_effect(&mut self, effect: RuntimeMutationEffect) {
        match effect {
            RuntimeMutationEffect::ProjectRemoved {
                project_id,
                workspace_ids,
            } => {
                self.terminate_terminal_sessions_for_workspaces(&workspace_ids)
                    .await;
                self.broadcast_authenticated(event("projectsChanged", json!({})));
                self.broadcast_workspaces_changed(Some(&project_id));
                self.broadcast_workspace_tabs_changed(None);
                self.broadcast_authenticated(event("projectConfigsChanged", json!({})));
            }
            RuntimeMutationEffect::WorkspaceRemoved { workspace_id } => {
                self.terminate_terminal_sessions_for_workspace(&workspace_id)
                    .await;
                self.broadcast_workspaces_changed(None);
                self.broadcast_workspace_tabs_changed(Some(&workspace_id));
            }
            RuntimeMutationEffect::ProjectWorkspacesRemoved {
                project_id,
                workspace_ids,
            } => {
                self.terminate_terminal_sessions_for_workspaces(&workspace_ids)
                    .await;
                self.broadcast_workspaces_changed(Some(&project_id));
                self.broadcast_workspace_tabs_changed(None);
            }
            RuntimeMutationEffect::ManagedWorkspaceRemoved {
                project_id,
                workspace_id,
            } => {
                self.terminate_terminal_sessions_for_workspace(&workspace_id)
                    .await;
                self.broadcast_workspaces_changed(Some(&project_id));
                self.broadcast_workspace_tabs_changed(Some(&workspace_id));
            }
            RuntimeMutationEffect::TabRemoved {
                tab_id,
                workspace_id,
            } => {
                self.handle_browser_tab_removed(&tab_id);
                self.terminate_terminal_sessions_for_tab(&tab_id).await;
                self.broadcast_workspace_tabs_changed(workspace_id.as_deref());
            }
            RuntimeMutationEffect::WorkspaceTabsRemoved { workspace_id } => {
                self.terminate_terminal_sessions_for_workspace(&workspace_id)
                    .await;
                self.broadcast_workspace_tabs_changed(Some(&workspace_id));
                self.broadcast_authenticated(event("workbenchLayoutsChanged", json!({})));
            }
            RuntimeMutationEffect::WorkspaceSlept { workspace_id } => {
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
        close_emulator_tab_deferred(self.emulators.clone(), tab_id.to_string());
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

fn close_emulator_tab_deferred(emulators: Option<Arc<Mutex<EmulatorManager>>>, tab_id: String) {
    let Some(emulators) = emulators else {
        return;
    };
    tokio::spawn(async move {
        for warning in emulators.lock().await.close_tab(&tab_id).await {
            tracing::warn!("alera emulator cleanup warning: {warning}");
        }
    });
}
