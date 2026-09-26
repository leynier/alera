use crate::terminal_host::session::workspace_shutdown::WorkspaceShutdown;

use super::runtime_mutations::RuntimeMutationRequest;
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
        if let RuntimeMutationRequest::RemoveSharedWorkspace {
            remote_automation_cleanup,
            automation_cleanup,
            request,
            buffer_guard,
            remote_retirement,
        } = request
        {
            self.start_checkout_buffer_guard(buffer_guard).await?;
            let workspace =
                crate::shared_workspace_removal::validate_shared_workspace_removal_target(
                    &self.runtime_store,
                    request,
                )
                .await
                .map_err(|error| HostError::state(error.to_string()))?;
            if let Some(scope) = remote_automation_cleanup {
                self.runtime_store
                    .require_remote_automation_cleanup(scope, &workspace)
                    .await
                    .map_err(|error| HostError::state(error.to_string()))?;
            }
            if let Some(run) = automation_cleanup {
                self.runtime_store
                    .require_automation_shared_workspace_cleanup(run, &workspace)
                    .await
                    .map_err(|error| HostError::state(error.to_string()))?;
            }
            if workspace.host_id != alera_core::runtime::LOCAL_HOST_ID {
                self.runtime_store
                    .require_workspace_process_closure(&workspace.id)
                    .await
                    .map_err(|error| HostError::state(error.to_string()))?;
                super::ai_assist_operation_registry::active_generations()
                    .require_workspace_idle(&workspace, "workspace removal")?;
                if !request.close_sessions {
                    return Err(HostError::state(
                        "Confirm closing this task's remote sessions before retirement",
                    ));
                }
                let Some(proof) = remote_retirement else {
                    return Ok(WorkspaceShutdown::default());
                };
                proof
                    .verify(&workspace)
                    .map_err(|error| HostError::state(error.to_string()))?;
            }
            return self
                .prepare_workspace_session_shutdown(
                    request,
                    workspace.host_id == alera_core::runtime::LOCAL_HOST_ID,
                )
                .await;
        }
        let relocation = match request {
            RuntimeMutationRequest::HandOnWorkspace {
                request,
                buffer_guard,
            } => Some((&request.id, buffer_guard, "Hand On")),
            RuntimeMutationRequest::HandOffWorkspace {
                request,
                buffer_guard,
                ..
            } => Some((&request.id, buffer_guard, "Hand Off")),
            _ => None,
        };
        if let Some((workspace_id, buffer_guard, operation)) = relocation {
            self.start_checkout_buffer_guard(buffer_guard).await?;
            let mut source = self
                .runtime_store
                .find_workspace(workspace_id)
                .await
                .map_err(|error| HostError::state(error.to_string()))?
                .ok_or_else(|| HostError::state("Workspace no longer exists"))?;
            if source.kind == alera_core::runtime::WorkspaceKind::Linked
                && source.host_id == alera_core::runtime::LOCAL_HOST_ID
            {
                crate::managed_workspace::validate_workspace_storage_path(
                    &self.runtime_store,
                    workspace_id,
                )
                .await
                .map_err(|error| HostError::state(error.to_string()))?;
            }
            if source.host_id != alera_core::runtime::LOCAL_HOST_ID {
                let checkout = self
                    .runtime_store
                    .find_workspace_checkout(workspace_id)
                    .await
                    .map_err(|error| HostError::state(error.to_string()))?
                    .ok_or_else(|| HostError::state("SSH checkout binding is missing"))?;
                let project_checkout = self
                    .runtime_store
                    .find_project_checkout(&source.project_id, &source.host_id)
                    .await
                    .map_err(|error| HostError::state(error.to_string()))?
                    .ok_or_else(|| {
                        HostError::state(
                            "Register the project checkout on its SSH host before relocating",
                        )
                    })?;
                if checkout.path != source.path
                    || (source.kind == alera_core::runtime::WorkspaceKind::Linked
                        && checkout.repository_path.as_deref()
                            != Some(project_checkout.path.as_str()))
                {
                    return Err(HostError::state(
                        "The SSH task uses a different repository origin; its existing worktree was preserved",
                    ));
                }
            }
            if let Some(pending) = self
                .runtime_store
                .active_workspace_relocation(&source.project_id, &source.host_id)
                .await
                .map_err(|error| HostError::state(error.to_string()))?
            {
                if pending.source.id == source.id {
                    source = pending.source;
                }
            }
            super::ai_assist_operation_registry::active_generations()
                .require_workspace_idle(&source, operation)?;
            self.runtime_store
                .require_workspace_process_closure(workspace_id)
                .await
                .map_err(|error| HostError::state(error.to_string()))?;
            let workspace_hosts: std::collections::HashMap<_, _> = self
                .runtime_store
                .list_all_workspaces()
                .await
                .map_err(|error| HostError::state(error.to_string()))?
                .into_iter()
                .map(|workspace| (workspace.id, workspace.host_id))
                .collect();
            let running: Vec<_> = self
                .sessions
                .iter()
                .filter(|(_, session)| {
                    session.running()
                        && (session.workspace_id == *workspace_id
                            || (source.kind == alera_core::runtime::WorkspaceKind::Linked
                                && workspace_hosts
                                    .get(&session.workspace_id)
                                    .is_none_or(|host_id| host_id == &source.host_id)
                                && alera_core::runtime::relocated_workspace_path(
                                    &session.working_directory,
                                    &source.path,
                                    &source.path,
                                )
                                .is_some()))
                })
                .map(|(id, _)| id.clone())
                .collect();
            if !running.is_empty() {
                return Err(HostError::state(format!(
                    "Stop these workspace processes before {operation} because their relocation cannot be verified: {}",
                    running.join(", ")
                )));
            }
            if crate::managed_workspace::workspace_has_active_automation_owner(
                &self.runtime_store,
                workspace_id,
            )
            .await
            .map_err(|error| HostError::state(error.to_string()))?
            {
                return Err(HostError::state(
                    "Workspace is owned by an active automation",
                ));
            }
            return Ok(WorkspaceShutdown::default());
        }
        if let RuntimeMutationRequest::RemoveWorkspace { workspace_id, .. } = request {
            let workspace = self
                .runtime_store
                .find_workspace(workspace_id)
                .await
                .map_err(|error| HostError::state(error.to_string()))?;
            if let Some(workspace) = &workspace {
                super::ai_assist_operation_registry::active_generations()
                    .require_workspace_idle(workspace, "workspace removal")?;
            }
            if workspace
                .is_some_and(|workspace| workspace.kind == alera_core::runtime::WorkspaceKind::Main)
            {
                return Err(HostError::state(
                    "Use workspace.removeShared to verify buffers and owned process shutdown before retiring a shared task",
                ));
            }
        }
        if let RuntimeMutationRequest::RemoveProject { project_id } = request {
            self.runtime_store
                .require_project_automation_idle(project_id)
                .await
                .map_err(|error| HostError::state(error.to_string()))?;
        }
        if let RuntimeMutationRequest::RemoveProject { project_id }
        | RuntimeMutationRequest::RemoveProjectWorkspaces { project_id } = request
        {
            for workspace in self
                .runtime_store
                .list_all_workspaces()
                .await
                .map_err(|error| HostError::state(error.to_string()))?
            {
                if workspace.project_id == *project_id {
                    if workspace.host_id != alera_core::runtime::LOCAL_HOST_ID {
                        return Err(HostError::state(format!(
                            "Remove SSH workspace '{}' on host '{}' first so its owner can verify process shutdown before project removal.",
                            workspace.name, workspace.host_id,
                        )));
                    }
                    super::ai_assist_operation_registry::active_generations()
                        .require_workspace_idle(&workspace, "project removal")?;
                }
            }
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
                return Err(HostError::state(
                    "Workspace has unfinished process shutdown. Retry confirmed workspace cleanup before removing its records or project.",
                ));
            }
        }
        Ok(WorkspaceShutdown::default())
    }
}
