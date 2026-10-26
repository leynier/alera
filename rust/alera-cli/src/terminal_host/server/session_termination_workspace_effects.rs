use serde_json::json;

use crate::terminal_host::protocol::event;

use super::runtime_mutations::RuntimeMutationEffect;
use super::ServerActor;

impl ServerActor {
    pub(super) async fn apply_runtime_mutation_effect(&mut self, effect: RuntimeMutationEffect) {
        self.record_workspace_lifecycle(&effect).await;
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
                self.apply_agent_chat_workspace_op(
                    &workspace_id,
                    super::agent_chat_runtime::commands::ChatOp::Close,
                )
                .await;
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
                for workspace_id in &workspace_ids {
                    self.apply_agent_chat_workspace_op(
                        workspace_id,
                        super::agent_chat_runtime::commands::ChatOp::Close,
                    )
                    .await;
                }
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
                self.apply_agent_chat_workspace_op(
                    &workspace_id,
                    super::agent_chat_runtime::commands::ChatOp::Close,
                )
                .await;
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
                self.apply_agent_chat_workspace_op(
                    &workspace_id,
                    super::agent_chat_runtime::commands::ChatOp::Stop,
                )
                .await;
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
                self.apply_agent_chat_workspace_op(
                    &workspace_id,
                    super::agent_chat_runtime::commands::ChatOp::Close,
                )
                .await;
                if let Some(server) = self.codex.as_ref() {
                    server.clear_thread_hydrations().await;
                }
                self.terminate_terminal_sessions_for_workspace(&workspace_id)
                    .await;
                self.broadcast_workspace_tabs_changed(Some(&workspace_id));
                self.broadcast_authenticated(event("workbenchLayoutsChanged", json!({})));
            }
            RuntimeMutationEffect::WorkspaceSlept { workspace_id } => {
                self.apply_agent_chat_workspace_op(
                    &workspace_id,
                    super::agent_chat_runtime::commands::ChatOp::Stop,
                )
                .await;
                if let Some(server) = self.codex.as_ref() {
                    server.clear_thread_hydrations().await;
                }
                self.terminate_slept_workspace_sessions(&workspace_id).await;
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
                self.apply_agent_chat_workspace_op(
                    &workspace_id,
                    super::agent_chat_runtime::commands::ChatOp::Stop,
                )
                .await;
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
}
