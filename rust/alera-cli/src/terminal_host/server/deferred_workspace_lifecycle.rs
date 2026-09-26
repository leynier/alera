use serde_json::Value;

use crate::managed_workspace::ManagedWorkspaceRemoveRequest;
use crate::managed_workspace_handoff::{
    ManagedWorkspaceHandOffRequest, ManagedWorkspaceHandOnRequest,
};
use crate::terminal_host::host_error::{HostError, HostResult};

use super::request_payloads::parse_payload;
use super::requests::require_string_key;
use super::runtime_mutations::RuntimeMutationRequest;
use super::ServerActor;

impl ServerActor {
    pub(super) async fn try_start_deferred_workspace_lifecycle(
        &mut self,
        client_id: u64,
        request_id: i64,
        request_type: &str,
        payload: &Value,
    ) -> HostResult<bool> {
        match request_type {
            "workspace.handOff" => {
                self.require_auth(client_id)?;
                self.require_request_allowed(client_id, request_type)?;
                let mut request: ManagedWorkspaceHandOffRequest = parse_payload(payload)?;
                request.setup_script_directory = self.setup_script_directory();
                if payload
                    .get("sharedImpactConfirmed")
                    .and_then(Value::as_bool)
                    != Some(true)
                {
                    return Err(HostError::state(
                        "Confirm the shared checkout impact with sharedImpactConfirmed before Hand Off",
                    ));
                }
                let move_changes = payload.get("moveChanges").and_then(Value::as_bool).ok_or_else(|| HostError::state("Choose whether to move all transferable changes or leave them in the project folder with moveChanges"))?;
                let replacement_branch = payload
                    .get("replacementBranch")
                    .and_then(Value::as_str)
                    .map(str::trim)
                    .filter(|value| !value.is_empty())
                    .map(str::to_string);
                let buffer_guard = self.claim_checkout_buffer_guard(
                    client_id,
                    request_id,
                    &request.id,
                    "handOff",
                    payload,
                )?;
                self.start_runtime_mutation(
                    client_id,
                    request_id,
                    RuntimeMutationRequest::HandOffWorkspace {
                        request,
                        move_changes,
                        replacement_branch,
                        buffer_guard,
                    },
                );
                Ok(true)
            }
            "workspace.handOn" => {
                self.require_auth(client_id)?;
                self.require_request_allowed(client_id, request_type)?;
                let request: ManagedWorkspaceHandOnRequest = parse_payload(payload)?;
                let has_active_automation =
                    crate::managed_workspace::workspace_has_active_automation_owner(
                        &self.runtime_store,
                        &request.id,
                    )
                    .await
                    .map_err(|error| HostError::state(error.to_string()))?;
                if has_active_automation {
                    return Err(HostError::state(
                        "Workspace is owned by an active automation",
                    ));
                }
                if payload
                    .get("sharedImpactConfirmed")
                    .and_then(Value::as_bool)
                    != Some(true)
                {
                    return Err(HostError::state(
                        "Confirm the impact on other workspaces with sharedImpactConfirmed before Hand On",
                    ));
                }
                let buffer_guard = self.claim_checkout_buffer_guard(
                    client_id,
                    request_id,
                    &request.id,
                    "handOn",
                    payload,
                )?;
                self.start_runtime_mutation(
                    client_id,
                    request_id,
                    RuntimeMutationRequest::HandOnWorkspace {
                        request,
                        buffer_guard,
                    },
                );
                Ok(true)
            }
            "workspace.storageImpact" => {
                self.require_auth(client_id)?;
                self.require_request_allowed(client_id, request_type)?;
                let workspace_id = require_string_key(payload, "id")?;
                let active_workspace_id = payload
                    .get("activeWorkspaceId")
                    .and_then(Value::as_str)
                    .filter(|value| !value.trim().is_empty())
                    .map(str::to_string);
                self.start_workspace_storage_measurement(
                    client_id,
                    request_id,
                    workspace_id,
                    active_workspace_id,
                    payload
                        .get("closeSessions")
                        .and_then(Value::as_bool)
                        .unwrap_or(false),
                );
                Ok(true)
            }
            "workspace.removeShared" => {
                self.require_auth(client_id)?;
                self.require_request_allowed(client_id, request_type)?;
                let request = parse_payload(payload)?;
                crate::shared_workspace_removal::validate_shared_workspace_removal_target(
                    &self.runtime_store,
                    &request,
                )
                .await
                .map_err(|error| HostError::state(error.to_string()))?;
                let remote_automation_cleanup = self
                    .requested_remote_automation_cleanup(client_id, &request.id, payload)
                    .await?;
                let automation_cleanup = self
                    .requested_automation_shared_cleanup(&request.id, payload)
                    .await?;
                let buffer_guard = self.claim_checkout_buffer_guard(
                    client_id,
                    request_id,
                    &request.id,
                    "removeShared",
                    payload,
                )?;
                self.start_runtime_mutation(
                    client_id,
                    request_id,
                    RuntimeMutationRequest::RemoveSharedWorkspace {
                        remote_automation_cleanup,
                        automation_cleanup,
                        remote_retirement: None,
                        request,
                        buffer_guard,
                    },
                );
                Ok(true)
            }
            "workspace.removeManaged" => {
                self.require_auth(client_id)?;
                self.require_request_allowed(client_id, request_type)?;
                let request: ManagedWorkspaceRemoveRequest = parse_payload(payload)?;
                if !request.close_sessions
                    && request.active_workspace_id.as_deref() == Some(request.id.as_str())
                {
                    return Err(HostError::state("Workspace is active in the workbench"));
                }
                if !request.close_sessions
                    && self
                        .sessions
                        .values()
                        .any(|session| session.workspace_id == request.id && session.running())
                {
                    return Err(HostError::state(
                        "Workspace has a live terminal session or process",
                    ));
                }
                let has_active_automation =
                    crate::managed_workspace::workspace_has_active_automation_owner(
                        &self.runtime_store,
                        &request.id,
                    )
                    .await
                    .map_err(|error| HostError::state(error.to_string()))?;
                if has_active_automation {
                    return Err(HostError::state(
                        "Workspace is owned by an active automation",
                    ));
                }
                crate::managed_workspace::validate_managed_workspace_removal(
                    &self.runtime_store,
                    &request,
                )
                .await
                .map_err(|error| HostError::state(error.to_string()))?;
                self.start_runtime_mutation(
                    client_id,
                    request_id,
                    RuntimeMutationRequest::RemoveManagedWorkspace { request },
                );
                Ok(true)
            }
            "project.remove" => {
                self.require_auth(client_id)?;
                self.require_request_allowed(client_id, request_type)?;
                let project_id = require_string_key(payload, "id")?;
                self.start_runtime_mutation(
                    client_id,
                    request_id,
                    RuntimeMutationRequest::RemoveProject { project_id },
                );
                Ok(true)
            }
            "workspace.remove" => {
                self.require_auth(client_id)?;
                self.require_request_allowed(client_id, request_type)?;
                let workspace_id = require_string_key(payload, "id")?;
                let cascade_tabs = payload
                    .get("cascadeTabs")
                    .and_then(Value::as_bool)
                    .unwrap_or(true);
                self.start_runtime_mutation(
                    client_id,
                    request_id,
                    RuntimeMutationRequest::RemoveWorkspace {
                        workspace_id,
                        cascade_tabs,
                    },
                );
                Ok(true)
            }
            "workspace.removeForProject" => {
                self.require_auth(client_id)?;
                self.require_request_allowed(client_id, request_type)?;
                let project_id = require_string_key(payload, "projectId")?;
                self.start_runtime_mutation(
                    client_id,
                    request_id,
                    RuntimeMutationRequest::RemoveProjectWorkspaces { project_id },
                );
                Ok(true)
            }
            "workspace.sleep" => {
                self.require_auth(client_id)?;
                self.require_request_allowed(client_id, request_type)?;
                let workspace_id = require_string_key(payload, "workspaceId")?;
                self.start_runtime_mutation(
                    client_id,
                    request_id,
                    RuntimeMutationRequest::SleepWorkspace { workspace_id },
                );
                Ok(true)
            }
            "workspace.archive" => {
                self.require_auth(client_id)?;
                self.require_request_allowed(client_id, request_type)?;
                let workspace_id = require_string_key(payload, "workspaceId")?;
                self.start_runtime_mutation(
                    client_id,
                    request_id,
                    RuntimeMutationRequest::ArchiveWorkspace { workspace_id },
                );
                Ok(true)
            }
            "tab.remove" => {
                self.require_auth(client_id)?;
                self.require_request_allowed(client_id, request_type)?;
                let tab_id = require_string_key(payload, "id")?;
                if self
                    .runtime_store
                    .workflow_launch_for_terminal(&tab_id)
                    .await
                    .map_err(|error| HostError::state(error.to_string()))?
                    .is_some()
                {
                    return Err(HostError::state(
                        "Workflow terminals remain available until reviewed cleanup.",
                    ));
                }
                self.cancel_agent_title_job(&tab_id);
                self.start_runtime_mutation(
                    client_id,
                    request_id,
                    RuntimeMutationRequest::RemoveTab { tab_id },
                );
                Ok(true)
            }
            "tab.removeForWorkspace" => {
                self.require_auth(client_id)?;
                self.require_request_allowed(client_id, request_type)?;
                let workspace_id = require_string_key(payload, "workspaceId")?;
                self.start_runtime_mutation(
                    client_id,
                    request_id,
                    RuntimeMutationRequest::RemoveWorkspaceTabs { workspace_id },
                );
                Ok(true)
            }
            _ => Ok(false),
        }
    }
}
