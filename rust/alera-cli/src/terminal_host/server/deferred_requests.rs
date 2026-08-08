use serde_json::Value;

use crate::managed_workspace::{ManagedWorkspaceCreateRequest, ManagedWorkspaceRemoveRequest};
use crate::terminal_host::host_error::HostResult;

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
            "aiText.workspaceIdentity.generate" => {
                self.require_auth(client_id)?;
                self.require_request_allowed(client_id, request_type)?;
                self.start_ai_text_workspace_identity(client_id, request_id, payload)?;
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
            "workspace.removeManaged" => {
                self.require_auth(client_id)?;
                self.require_request_allowed(client_id, request_type)?;
                let request: ManagedWorkspaceRemoveRequest = parse_payload(payload)?;
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
            "agentQuota.snapshot" => {
                self.require_auth(client_id)?;
                self.require_request_allowed(client_id, request_type)?;
                self.start_agent_quota_request(client_id, request_id, payload)?;
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
