use serde_json::Value;

use crate::managed_workspace::{ManagedWorkspaceCreateRequest, ManagedWorkspaceRemoveRequest};
use crate::terminal_host::host_error::{HostError, HostResult};

use super::request_payloads::parse_payload;
use super::requests::require_string_key;
use super::runtime_mutations::RuntimeMutationRequest;
use super::ServerActor;

impl ServerActor {
    pub(super) async fn try_start_deferred_request(
        &mut self,
        client_id: u64,
        request_id: i64,
        request_type: &str,
        payload: &Value,
    ) -> HostResult<bool> {
        if self.try_start_account_request(client_id, request_id, request_type, payload)? {
            return Ok(true);
        }
        match request_type {
            "orchestration.boardSnapshot" | "orchestration.runSnapshot" => {
                self.start_orchestration_board_read(client_id, request_id, request_type, payload)?;
                Ok(true)
            }
            "aiDictation.transcribe" => {
                self.require_authenticated_local_request(client_id, request_type)?;
                self.start_ai_dictation(client_id, request_id, payload)
                    .await?;
                Ok(true)
            }
            "mobile.aiDictation.transcribe" => {
                self.require_auth(client_id)?;
                self.require_request_allowed(client_id, request_type)?;
                self.try_start_mobile_ai_dictation(client_id, request_id, payload)
                    .await
            }
            "aiText.workspaceIdentity.generate" => {
                self.require_auth(client_id)?;
                self.require_request_allowed(client_id, request_type)?;
                self.start_ai_assist_workspace_identity(client_id, request_id, payload)?;
                Ok(true)
            }
            "aiText.speechMessage.generate" => {
                self.require_auth(client_id)?;
                self.require_request_allowed(client_id, request_type)?;
                self.start_ai_assist_speech_message(client_id, request_id, payload)?;
                Ok(true)
            }
            "mobile.workspaceQuickOpen.start"
            | "mobile.workspaceQuickOpen.search"
            | "mobile.workspaceFile.read"
            | "mobile.promptAttachment.read"
            | "mobile.codexSavedPrompts.list" => {
                self.require_auth(client_id)?;
                self.require_request_allowed(client_id, request_type)?;
                self.start_mobile_workspace_file_request(
                    client_id,
                    request_id,
                    request_type,
                    payload,
                )?;
                Ok(true)
            }
            "mobile.promptFile.start"
            | "mobile.promptFile.chunk"
            | "mobile.promptFile.complete"
            | "mobile.promptFile.cancel" => {
                self.require_auth(client_id)?;
                self.require_request_allowed(client_id, request_type)?;
                self.start_mobile_prompt_file_request(client_id, request_id, request_type, payload);
                Ok(true)
            }
            "workspace.createManaged" => {
                self.require_auth(client_id)?;
                self.require_request_allowed(client_id, request_type)?;
                let mut request: ManagedWorkspaceCreateRequest = parse_payload(payload)?;
                request.setup_script_directory = self.setup_script_directory();
                self.start_managed_workspace_create(client_id, request_id, request);
                Ok(true)
            }
            "workspace.runSetup" => {
                self.require_auth(client_id)?;
                self.require_request_allowed(client_id, request_type)?;
                let workspace_id = require_string_key(payload, "id")?;
                let copies_only = payload
                    .get("copiesOnly")
                    .and_then(Value::as_bool)
                    .unwrap_or(false);
                self.start_workspace_setup(client_id, request_id, workspace_id, copies_only);
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
                );
                Ok(true)
            }
            "workspace.removeManaged" => {
                self.require_auth(client_id)?;
                self.require_request_allowed(client_id, request_type)?;
                let request: ManagedWorkspaceRemoveRequest = parse_payload(payload)?;
                if request.active_workspace_id.as_deref() == Some(request.id.as_str()) {
                    return Err(HostError::state("Workspace is active in the workbench"));
                }
                if self
                    .sessions
                    .values()
                    .any(|session| session.workspace_id == request.id && session.running())
                {
                    return Err(HostError::state(
                        "Workspace has a live terminal session or process",
                    ));
                }
                if self.browser.has_pages_for_workspace(&request.id) {
                    return Err(HostError::state("Workspace has a live browser session"));
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
                crate::managed_workspace::validate_workspace_storage_path(
                    &self.runtime_store,
                    &request.id,
                )
                .await
                .map_err(|error| HostError::state(error.to_string()))?;
                let cleanup = self.plan_codex_workspace_cleanup(&request.id).await?;
                self.start_runtime_mutation_after_codex_cleanup(
                    client_id,
                    request_id,
                    RuntimeMutationRequest::RemoveManagedWorkspace { request },
                    cleanup,
                );
                Ok(true)
            }
            "project.remove" => {
                self.require_auth(client_id)?;
                self.require_request_allowed(client_id, request_type)?;
                let project_id = require_string_key(payload, "id")?;
                let cleanup = self.plan_codex_project_cleanup(&project_id).await?;
                self.start_runtime_mutation_after_codex_cleanup(
                    client_id,
                    request_id,
                    RuntimeMutationRequest::RemoveProject { project_id },
                    cleanup,
                );
                Ok(true)
            }
            "workspace.remove" => {
                self.require_auth(client_id)?;
                self.require_request_allowed(client_id, request_type)?;
                let workspace_id = require_string_key(payload, "id")?;
                let cleanup = self.plan_codex_workspace_cleanup(&workspace_id).await?;
                let cascade_tabs = payload
                    .get("cascadeTabs")
                    .and_then(Value::as_bool)
                    .unwrap_or(true);
                self.start_runtime_mutation_after_codex_cleanup(
                    client_id,
                    request_id,
                    RuntimeMutationRequest::RemoveWorkspace {
                        workspace_id,
                        cascade_tabs,
                    },
                    cleanup,
                );
                Ok(true)
            }
            "workspace.removeForProject" => {
                self.require_auth(client_id)?;
                self.require_request_allowed(client_id, request_type)?;
                let project_id = require_string_key(payload, "projectId")?;
                let cleanup = self.plan_codex_project_cleanup(&project_id).await?;
                self.start_runtime_mutation_after_codex_cleanup(
                    client_id,
                    request_id,
                    RuntimeMutationRequest::RemoveProjectWorkspaces { project_id },
                    cleanup,
                );
                Ok(true)
            }
            "workspace.sleep" => {
                self.require_auth(client_id)?;
                self.require_request_allowed(client_id, request_type)?;
                let workspace_id = require_string_key(payload, "workspaceId")?;
                let cleanup = self.plan_codex_workspace_cleanup(&workspace_id).await?;
                self.start_runtime_mutation_after_codex_cleanup(
                    client_id,
                    request_id,
                    RuntimeMutationRequest::SleepWorkspace { workspace_id },
                    cleanup,
                );
                Ok(true)
            }
            "tab.remove" => {
                self.require_auth(client_id)?;
                self.require_request_allowed(client_id, request_type)?;
                let tab_id = require_string_key(payload, "id")?;
                let cleanup = self.plan_codex_tab_cleanup(&tab_id).await?;
                self.start_runtime_mutation_after_codex_cleanup(
                    client_id,
                    request_id,
                    RuntimeMutationRequest::RemoveTab { tab_id },
                    cleanup,
                );
                Ok(true)
            }
            "tab.removeForWorkspace" => {
                self.require_auth(client_id)?;
                self.require_request_allowed(client_id, request_type)?;
                let workspace_id = require_string_key(payload, "workspaceId")?;
                let cleanup = self.plan_codex_workspace_cleanup(&workspace_id).await?;
                self.start_runtime_mutation_after_codex_cleanup(
                    client_id,
                    request_id,
                    RuntimeMutationRequest::RemoveWorkspaceTabs { workspace_id },
                    cleanup,
                );
                Ok(true)
            }
            "write" => {
                self.require_auth(client_id)?;
                self.require_request_allowed(client_id, request_type)?;
                self.queue_terminal_input(client_id, request_id, payload)
            }
            "terminal.pulse.configure" => {
                self.require_auth(client_id)?;
                self.require_request_allowed(client_id, request_type)?;
                self.start_terminal_pulse_configuration(client_id, request_id, payload)
                    .await?;
                Ok(true)
            }
            "agentQuota.snapshot" => {
                self.require_auth(client_id)?;
                self.require_request_allowed(client_id, request_type)?;
                self.start_agent_quota_request(client_id, request_id, payload)?;
                Ok(true)
            }
            "agentUsage.snapshot" => {
                self.require_auth(client_id)?;
                self.require_request_allowed(client_id, request_type)?;
                self.start_agent_usage_request(client_id, request_id, payload)?;
                Ok(true)
            }
            "agentQuota.fetchClaudeTui" => {
                self.require_auth(client_id)?;
                self.require_request_allowed(client_id, request_type)?;
                self.start_agent_quota_claude_tui_request(client_id, request_id, payload)?;
                Ok(true)
            }
            "agentQuota.consumeCodexResetCredit" => {
                self.require_auth(client_id)?;
                self.require_request_allowed(client_id, request_type)?;
                self.start_agent_quota_codex_reset_request(client_id, request_id, payload);
                Ok(true)
            }
            "cliRegistration.status" | "cliRegistration.install" => {
                self.require_auth(client_id)?;
                self.require_request_allowed(client_id, request_type)?;
                self.start_cli_registration_request(
                    client_id,
                    request_id,
                    request_type.ends_with("install"),
                );
                Ok(true)
            }
            "agentSkill.install" => {
                self.require_auth(client_id)?;
                self.require_request_allowed(client_id, request_type)?;
                self.start_skill_install_request(client_id, request_id, payload)?;
                Ok(true)
            }
            _ if request_type.starts_with("emulator.") => {
                self.require_auth(client_id)?;
                self.require_request_allowed(client_id, request_type)?;
                self.start_emulator_request(
                    client_id,
                    request_id,
                    request_type.to_string(),
                    payload.clone(),
                );
                Ok(true)
            }
            _ => Ok(false),
        }
    }
}
