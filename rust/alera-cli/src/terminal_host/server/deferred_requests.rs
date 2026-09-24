use serde_json::Value;

use crate::managed_workspace::ManagedWorkspaceCreateRequest;
use crate::terminal_host::host_error::{HostError, HostResult};

use super::request_payloads::parse_payload;
use super::requests::require_string_key;
use super::ServerActor;

impl ServerActor {
    pub(super) async fn try_start_deferred_request(
        &mut self,
        client_id: u64,
        request_id: i64,
        request_type: &str,
        payload: &Value,
    ) -> HostResult<bool> {
        self.require_shared_checkout_support(client_id, request_type)?;
        if self
            .try_start_remote_terminal_lifecycle(client_id, request_id, request_type, payload)
            .await?
        {
            return Ok(true);
        }
        if self
            .try_start_remote_setup_control(client_id, request_id, request_type, payload)
            .await?
        {
            return Ok(true);
        }
        if self.try_start_configuration_cloud(client_id, request_id, request_type, payload)? {
            return Ok(true);
        }
        if self.try_start_account_request(client_id, request_id, request_type, payload)? {
            return Ok(true);
        }
        if self.try_start_deferred_workspace_setup(client_id, request_id, request_type, payload)? {
            return Ok(true);
        }
        if self
            .try_start_deferred_workspace_lifecycle(client_id, request_id, request_type, payload)
            .await?
        {
            return Ok(true);
        }
        match request_type {
            "workflows.prepareWorkspace" | "workflows.workspaces" => {
                self.start_workflow_workspace_request(
                    client_id,
                    request_id,
                    request_type,
                    payload,
                )?;
                Ok(true)
            }
            "workflows.preparePlan"
            | "workflows.plan"
            | "workflows.approvalChallenge"
            | "workflows.decide" => {
                self.start_workflow_plan_request(client_id, request_id, request_type, payload)?;
                Ok(true)
            }
            "workflows.catalog"
            | "workflows.recipe"
            | "workflows.validateRecipe"
            | "workflows.savePersonalRecipe" => {
                self.start_workflow_catalog_request(client_id, request_id, request_type, payload)?;
                Ok(true)
            }
            "orchestration.boardSnapshot"
            | "orchestration.runSnapshot"
            | "orchestration.taskInspection" => {
                self.start_orchestration_board_read(client_id, request_id, request_type, payload)?;
                Ok(true)
            }
            "terminal.ownerLifecycle" => {
                self.start_owner_terminal_lifecycle(client_id, request_id, payload)
                    .await?;
                Ok(true)
            }
            "workspace.sshRelocationRecovery" => {
                self.require_auth(client_id)?;
                self.require_request_allowed(client_id, request_type)?;
                let id = require_string_key(payload, "id")?;
                let limit = super::remote_recovery_requests::recovery_limit(payload)?;
                self.start_remote_relocation_recovery(
                    client_id,
                    request_id,
                    id,
                    limit,
                    crate::ssh_remote::LiveSshRemoteHost,
                );
                Ok(true)
            }
            "mobile.status.get"
                if payload.get("includeNetworkStatus").and_then(Value::as_bool) != Some(false) =>
            {
                self.require_auth(client_id)?;
                self.require_request_allowed(client_id, request_type)?;
                self.start_mobile_network_snapshot(client_id, request_id)
                    .await?;
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
            "aiText.agentTitle.generate" => {
                self.require_auth(client_id)?;
                self.require_request_allowed(client_id, request_type)?;
                self.request_agent_title(client_id, request_id, payload)
                    .await?;
                Ok(true)
            }
            "aiText.workspaceIdentity.generate" => {
                self.require_auth(client_id)?;
                self.require_request_allowed(client_id, request_type)?;
                self.start_ai_assist_workspace_identity(client_id, request_id, payload)?;
                Ok(true)
            }
            "aiText.commitMessage.generate" => {
                self.require_auth(client_id)?;
                self.require_request_allowed(client_id, request_type)?;
                self.start_ai_assist_commit_message(client_id, request_id, payload)?;
                Ok(true)
            }
            "aiText.pullRequestDetails.generate" => {
                self.require_auth(client_id)?;
                self.require_request_allowed(client_id, request_type)?;
                self.start_ai_assist_pull_request_details(client_id, request_id, payload)?;
                Ok(true)
            }
            "aiText.speechMessage.generate" => {
                self.require_auth(client_id)?;
                self.require_request_allowed(client_id, request_type)?;
                self.start_ai_assist_speech_message(client_id, request_id, payload)
                    .await?;
                Ok(true)
            }
            "aiAssist.complete" => {
                self.require_auth(client_id)?;
                self.require_request_allowed(client_id, request_type)?;
                self.start_ai_assist_complete(client_id, request_id, payload)?;
                Ok(true)
            }
            "aiAssist.opencodeGo.models" => {
                self.require_auth(client_id)?;
                self.require_request_allowed(client_id, request_type)?;
                self.start_opencode_go_models(client_id, request_id)?;
                Ok(true)
            }
            "project.branches.list"
            | "checkout.quickOpen.start"
            | "mobile.workspaceQuickOpen.start"
            | "mobile.workspaceQuickOpen.search"
            | "mobile.workspaceFile.read"
            | "mobile.promptAttachment.read"
            | "mobile.workspaceExplorer.list"
            | "mobile.workspaceSearch.run"
            | "mobile.workspaceSearch.replace"
            | "mobile.workspaceSearch.cancel"
            | "mobile.git.status"
            | "mobile.git.diff"
            | "mobile.git.stage"
            | "mobile.git.unstage"
            | "mobile.git.discard"
            | "mobile.git.commit"
            | "mobile.git.fetch"
            | "mobile.git.pull"
            | "mobile.git.push"
            | "mobile.git.sync"
            | "mobile.git.stash"
            | "mobile.git.stashPop"
            | "mobile.git.branches"
            | "mobile.git.checkout"
            | "mobile.git.createBranch"
            | "mobile.pullRequest.snapshot"
            | "mobile.pullRequest.summaries"
            | "mobile.pullRequest.comment"
            | "mobile.pullRequest.commentUpdate"
            | "mobile.pullRequest.merge"
            | "mobile.pullRequest.draftStatus"
            | "mobile.pullRequest.close"
            | "mobile.pullRequest.link"
            | "mobile.pullRequest.unlink"
            | "mobile.pullRequest.create"
            | "mobile.pullRequest.ship"
            | "workspace.files.list"
            | "workspace.files.read" => {
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
            "project.checkout.register" => {
                self.require_auth(client_id)?;
                self.require_request_allowed(client_id, request_type)?;
                self.start_project_checkout_registration(
                    client_id,
                    request_id,
                    parse_payload(payload)?,
                );
                Ok(true)
            }
            "workspace.createShared" => {
                self.require_auth(client_id)?;
                self.require_request_allowed(client_id, request_type)?;
                let issue_url = super::requests::optional_string_key(payload, "issueUrl")
                    .filter(|url| !url.trim().is_empty());
                if let Some(url) = issue_url.as_deref() {
                    crate::issue_tracking::parse_issue_reference(url)
                        .map_err(|error| HostError::format(error.to_string()))?;
                }
                self.start_shared_workspace_create(
                    client_id,
                    request_id,
                    parse_payload(payload)?,
                    issue_url,
                );
                Ok(true)
            }
            "issue.fetch" | "linkedIssue.link" | "linkedIssue.refresh" => {
                self.require_auth(client_id)?;
                self.require_request_allowed(client_id, request_type)?;
                self.start_linked_issue_request(client_id, request_id, request_type, payload)?;
                Ok(true)
            }
            "workspace.createManaged" => {
                self.require_auth(client_id)?;
                self.require_request_allowed(client_id, request_type)?;
                let mut request: ManagedWorkspaceCreateRequest = parse_payload(payload)?;
                request.setup_script_directory = self.setup_script_directory();
                // Validated before the worktree exists, so a typo cannot leave
                // a workspace behind with a link that was never stored.
                let issue_url = super::requests::optional_string_key(payload, "issueUrl")
                    .filter(|url| !url.trim().is_empty());
                if let Some(url) = issue_url.as_deref() {
                    crate::issue_tracking::parse_issue_reference(url)
                        .map_err(|error| HostError::format(error.to_string()))?;
                }
                self.start_managed_workspace_create(client_id, request_id, request, issue_url);
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
            _ => Ok(false),
        }
    }
}
