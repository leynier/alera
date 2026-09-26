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
        self.refuse_hub_only_payload_fields(client_id, payload)?;
        // The reverse channel runs before every local handler: on a satellite,
        // a hub-owned verb such as `project.hosts.add` must reach the hub
        // instead of the handler below that would act on this runtime's copies.
        match self.try_handle_hub_reverse_request(client_id, request_id, request_type, payload)? {
            Some(super::hub_reverse_requests::ReverseOutcome::Answer(value)) => {
                self.client_write(
                    client_id,
                    crate::terminal_host::protocol::ok_response(request_id, value),
                );
                return Ok(true);
            }
            Some(super::hub_reverse_requests::ReverseOutcome::Deferred) => return Ok(true),
            None => {}
        }
        if self
            .try_forward_to_hub(client_id, request_id, request_type, payload)
            .await?
        {
            return Ok(true);
        }
        if self
            .try_start_remote_ai_assist(client_id, request_id, request_type, payload)
            .await?
        {
            return Ok(true);
        }
        if self
            .try_start_project_hosts_request(client_id, request_id, request_type, payload)
            .await?
        {
            return Ok(true);
        }
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
        if self.try_start_satellite_mirror_request(client_id, request_id, request_type, payload)? {
            return Ok(true);
        }
        if self.try_start_host_link_request(client_id, request_id, request_type, payload)? {
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
            "voice.turn" | "mobile.voice.turn" => {
                self.require_auth(client_id)?;
                self.require_request_allowed(client_id, request_type)?;
                if payload.get("audioBase64").is_some() {
                    self.start_voice_turn(client_id, request_id, payload)?;
                    Ok(true)
                } else {
                    Ok(false)
                }
            }
            "voice.synthesize" | "mobile.voice.synthesize" => {
                self.require_auth(client_id)?;
                self.require_request_allowed(client_id, request_type)?;
                self.start_voice_synthesize(client_id, request_id, payload)?;
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
            | "workspace.files.read"
            | "workspace.files.write"
            | "workspace.files.create"
            | "workspace.files.rename"
            | "workspace.files.copy"
            | "workspace.files.move"
            | "workspace.files.delete" => {
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
            verb if super::workspace_git_requests::is_workspace_git_verb(verb)
                || verb == super::host_process_requests::HOST_PROCESS_RUN =>
            {
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
