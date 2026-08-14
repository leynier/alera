//! Mobile terminal tab creation and attachment: the gateway-facing requests
//! that mint terminal tabs for phones, attach them to sessions, and claim the
//! viewport driver seat right after.

use serde_json::{json, Value};

use crate::terminal_host::host_error::{HostError, HostResult};
use crate::terminal_host::protocol::{
    int_or, RUNTIME_HOST_AGENT_PROFILES_CAPABILITY,
    RUNTIME_HOST_AGENT_PROFILE_PROMPT_LAUNCH_CAPABILITY,
    RUNTIME_HOST_AGENT_QUOTA_CLAUDE_TUI_CAPABILITY, RUNTIME_HOST_AGENT_STATUS_CAPABILITY,
    RUNTIME_HOST_AI_DICTATION_CAPABILITY, RUNTIME_HOST_AI_TEXT_SPEECH_MESSAGE_CAPABILITY,
    RUNTIME_HOST_AI_TEXT_WORKSPACE_IDENTITY_CAPABILITY, RUNTIME_HOST_AUTOMATIONS_CAPABILITY,
    RUNTIME_HOST_BINARY_FRAMES_CAPABILITY, RUNTIME_HOST_CAPABILITY,
    RUNTIME_HOST_CODEX_CHAT_CAPABILITY, RUNTIME_HOST_CODEX_GOALS_CAPABILITY,
    RUNTIME_HOST_CODEX_RESET_CREDITS_CAPABILITY, RUNTIME_HOST_CODEX_TURN_POLICY_CAPABILITY,
    RUNTIME_HOST_LIFECYCLE_CAPABILITY, RUNTIME_HOST_MANAGED_WORKSPACE_CAPABILITY,
    RUNTIME_HOST_MOBILE_AGENT_QUOTA_CAPABILITY, RUNTIME_HOST_MOBILE_CAPABILITY,
    RUNTIME_HOST_MOBILE_CLOUD_ENROLLMENT_CAPABILITY, RUNTIME_HOST_MOBILE_CODEX_SESSIONS_CAPABILITY,
    RUNTIME_HOST_MOBILE_CODEX_WORKSPACE_FILES_CAPABILITY,
    RUNTIME_HOST_MOBILE_HOST_TOOLS_CAPABILITY, RUNTIME_HOST_MOBILE_MUTATIONS_CAPABILITY,
    RUNTIME_HOST_MOBILE_PORTABLE_SETTINGS_CAPABILITY,
    RUNTIME_HOST_MOBILE_PROJECT_MANAGEMENT_CAPABILITY,
    RUNTIME_HOST_MOBILE_PROMPT_ATTACHMENT_READ_CAPABILITY,
    RUNTIME_HOST_MOBILE_PROMPT_FILE_UPLOAD_CAPABILITY,
    RUNTIME_HOST_MOBILE_PROMPT_IMAGE_UPLOAD_CAPABILITY,
    RUNTIME_HOST_MOBILE_SIDEBAR_PARITY_CAPABILITY, RUNTIME_HOST_MOBILE_TAB_RENAME_CAPABILITY,
    RUNTIME_HOST_MOBILE_TERMINAL_TITLES_CAPABILITY, RUNTIME_HOST_RESTART_CAPABILITY,
    RUNTIME_HOST_TERMINAL_DEFERRED_INPUT_CAPABILITY, RUNTIME_HOST_TERMINAL_DRIVER_CAPABILITY,
    RUNTIME_HOST_TERMINAL_RESTART_CAPABILITY,
};
use alera_core::runtime::{Workspace, WorkspaceTabRecord};
use chrono::Utc;
use uuid::Uuid;

use super::requests::{optional_string_key, require_string_key, terminal_session_id_from_tab};
use super::terminal_launch_defaults::default_terminal_launch;
use super::ServerActor;

/// What `mobile.hello` tells a phone this host can do.
///
/// A different list from the one `status.get` answers with, and the one the app
/// feature-detects against. Named rather than inlined so a test can assert a
/// capability is in it: the runtime enforces an exact `MOBILE_PROTOCOL_VERSION`
/// match, so an omission here is invisible and silently leaves every phone on
/// the older code path with no version to blame.
pub(super) const MOBILE_HELLO_CAPABILITIES: &[&str] = &[
    RUNTIME_HOST_CAPABILITY,
    RUNTIME_HOST_MANAGED_WORKSPACE_CAPABILITY,
    RUNTIME_HOST_MOBILE_CAPABILITY,
    RUNTIME_HOST_MOBILE_CLOUD_ENROLLMENT_CAPABILITY,
    RUNTIME_HOST_MOBILE_MUTATIONS_CAPABILITY,
    RUNTIME_HOST_MOBILE_PROJECT_MANAGEMENT_CAPABILITY,
    RUNTIME_HOST_MOBILE_SIDEBAR_PARITY_CAPABILITY,
    RUNTIME_HOST_MOBILE_TAB_RENAME_CAPABILITY,
    RUNTIME_HOST_MOBILE_TERMINAL_TITLES_CAPABILITY,
    RUNTIME_HOST_MOBILE_PORTABLE_SETTINGS_CAPABILITY,
    RUNTIME_HOST_MOBILE_AGENT_QUOTA_CAPABILITY,
    RUNTIME_HOST_AGENT_QUOTA_CLAUDE_TUI_CAPABILITY,
    RUNTIME_HOST_CODEX_RESET_CREDITS_CAPABILITY,
    RUNTIME_HOST_MOBILE_HOST_TOOLS_CAPABILITY,
    RUNTIME_HOST_TERMINAL_DEFERRED_INPUT_CAPABILITY,
    RUNTIME_HOST_TERMINAL_DRIVER_CAPABILITY,
    RUNTIME_HOST_TERMINAL_RESTART_CAPABILITY,
    RUNTIME_HOST_LIFECYCLE_CAPABILITY,
    RUNTIME_HOST_RESTART_CAPABILITY,
    RUNTIME_HOST_AGENT_STATUS_CAPABILITY,
    RUNTIME_HOST_AGENT_PROFILES_CAPABILITY,
    RUNTIME_HOST_AI_TEXT_WORKSPACE_IDENTITY_CAPABILITY,
    RUNTIME_HOST_AI_TEXT_SPEECH_MESSAGE_CAPABILITY,
    RUNTIME_HOST_AGENT_PROFILE_PROMPT_LAUNCH_CAPABILITY,
    RUNTIME_HOST_BINARY_FRAMES_CAPABILITY,
    RUNTIME_HOST_MOBILE_PROMPT_IMAGE_UPLOAD_CAPABILITY,
    RUNTIME_HOST_MOBILE_PROMPT_FILE_UPLOAD_CAPABILITY,
    RUNTIME_HOST_MOBILE_PROMPT_ATTACHMENT_READ_CAPABILITY,
    RUNTIME_HOST_MOBILE_CODEX_WORKSPACE_FILES_CAPABILITY,
    RUNTIME_HOST_MOBILE_CODEX_SESSIONS_CAPABILITY,
    RUNTIME_HOST_CODEX_CHAT_CAPABILITY,
    RUNTIME_HOST_CODEX_GOALS_CAPABILITY,
    RUNTIME_HOST_CODEX_TURN_POLICY_CAPABILITY,
    RUNTIME_HOST_AUTOMATIONS_CAPABILITY,
    RUNTIME_HOST_AI_DICTATION_CAPABILITY,
];

impl ServerActor {
    pub(super) fn mobile_workspace_tabs_payload(&self, tabs: Vec<WorkspaceTabRecord>) -> Value {
        Value::Array(
            tabs.into_iter()
                .map(|tab| {
                    let runtime_title = self
                        .sessions
                        .values()
                        .find(|session| session.tab_id == tab.id)
                        .and_then(|session| session.runtime_title())
                        .map(str::to_string);
                    let mut value = json!(tab);
                    if let (Some(title), Some(object)) = (runtime_title, value.as_object_mut()) {
                        object.insert("runtimeTitle".to_string(), Value::String(title));
                    }
                    value
                })
                .collect(),
        )
    }

    pub(super) async fn create_mobile_terminal(
        &mut self,
        client_id: u64,
        payload: &Value,
    ) -> HostResult<Value> {
        let workspace_id = require_string_key(payload, "workspaceId")?;
        let workspace = self
            .runtime_store
            .find_workspace(&workspace_id)
            .await
            .map_err(|error| HostError::state(error.to_string()))?
            .ok_or_else(|| HostError::state(format!("Workspace not found: {workspace_id}")))?;
        let tab_id = Uuid::new_v4().to_string();
        let session_id = Uuid::new_v4().to_string();
        let title =
            optional_string_key(payload, "title").unwrap_or_else(|| "Mobile Terminal".into());
        let now = Utc::now();
        let auto_close_on_success =
            payload.get("autoCloseOnSuccess").and_then(Value::as_bool) == Some(true);
        let mut tab_payload = json!({
            "terminalSessionId": session_id,
            "source": "mobile",
        });
        if auto_close_on_success {
            tab_payload["autoCloseOnSuccess"] = Value::Bool(true);
        }
        let tab = WorkspaceTabRecord {
            id: tab_id.clone(),
            workspace_id: workspace.id.clone(),
            kind: "terminal".to_string(),
            title,
            created_at: now,
            updated_at: now,
            payload: tab_payload,
        };
        let tab = self
            .runtime_store
            .upsert_workspace_tab(tab)
            .await
            .map_err(|error| HostError::state(error.to_string()))?;
        let attachment_payload = mobile_terminal_attachment_payload(
            &workspace,
            &tab.id,
            &session_id,
            payload,
            self.config.login_shell,
        )
        .await;
        match self.create_or_attach(client_id, &attachment_payload).await {
            Ok(mut attachment) => {
                self.broadcast_workspace_tabs_changed(Some(&workspace.id));
                self.claim_mobile_terminal_viewport(
                    client_id,
                    &session_id,
                    payload,
                    &mut attachment,
                );
                Ok(self.terminal_tab_response_for_client(client_id, tab, attachment))
            }
            Err(error) => {
                let _ = self.runtime_store.remove_workspace_tab(&tab.id).await;
                Err(error)
            }
        }
    }

    /// Claims the driver seat for the phone right after a mobile attach or
    /// create, and refreshes the attachment's driver field so the response
    /// reflects the post-claim state.
    fn claim_mobile_terminal_viewport(
        &mut self,
        client_id: u64,
        session_id: &str,
        payload: &Value,
        attachment: &mut Value,
    ) {
        let cols = int_or(payload, "cols", 80) as u16;
        let rows = int_or(payload, "rows", 24) as u16;
        self.claim_mobile_driver(client_id, session_id, Some((cols, rows)));
        if let (Some(object), Some(session)) =
            (attachment.as_object_mut(), self.sessions.get(session_id))
        {
            object.insert("driver".to_string(), session.driver.payload());
        }
    }

    pub(super) async fn attach_mobile_terminal(
        &mut self,
        client_id: u64,
        payload: &Value,
    ) -> HostResult<Value> {
        let tab_id = require_string_key(payload, "tabId")?;
        let tab = self
            .runtime_store
            .find_workspace_tab(&tab_id)
            .await
            .map_err(|error| HostError::state(error.to_string()))?
            .ok_or_else(|| HostError::state(format!("Workspace tab not found: {tab_id}")))?;
        if tab.kind != "terminal" {
            return Err(HostError::state(format!(
                "Workspace tab is not a terminal: {}",
                tab.id
            )));
        }
        let workspace = self
            .runtime_store
            .find_workspace(&tab.workspace_id)
            .await
            .map_err(|error| HostError::state(error.to_string()))?
            .ok_or_else(|| {
                HostError::state(format!("Workspace not found: {}", tab.workspace_id))
            })?;
        let session_id = optional_string_key(payload, "sessionId")
            .or_else(|| terminal_session_id_from_tab(&tab))
            .unwrap_or_else(|| tab.id.clone());
        let attachment_payload = mobile_terminal_attachment_payload(
            &workspace,
            &tab.id,
            &session_id,
            payload,
            self.config.login_shell,
        )
        .await;
        let mut attachment = self
            .create_or_attach(client_id, &attachment_payload)
            .await?;
        self.claim_mobile_terminal_viewport(client_id, &session_id, payload, &mut attachment);
        Ok(self.terminal_tab_response_for_client(client_id, tab, attachment))
    }

    pub(super) async fn restart_mobile_terminal(
        &mut self,
        client_id: u64,
        payload: &Value,
    ) -> HostResult<Value> {
        let tab_id = require_string_key(payload, "tabId")?;
        let tab = self
            .runtime_store
            .find_workspace_tab(&tab_id)
            .await
            .map_err(|error| HostError::state(error.to_string()))?
            .ok_or_else(|| HostError::state(format!("Workspace tab not found: {tab_id}")))?;
        if tab.kind != "terminal" {
            return Err(HostError::state(format!(
                "Workspace tab is not a terminal: {}",
                tab.id
            )));
        }
        let workspace = self
            .runtime_store
            .find_workspace(&tab.workspace_id)
            .await
            .map_err(|error| HostError::state(error.to_string()))?
            .ok_or_else(|| {
                HostError::state(format!("Workspace not found: {}", tab.workspace_id))
            })?;
        let session_id = optional_string_key(payload, "sessionId")
            .or_else(|| terminal_session_id_from_tab(&tab))
            .unwrap_or_else(|| tab.id.clone());
        let attachment_payload = mobile_terminal_attachment_payload(
            &workspace,
            &tab.id,
            &session_id,
            payload,
            self.config.login_shell,
        )
        .await;
        let mut attachment = self
            .restart_terminal(client_id, &attachment_payload)
            .await?;
        self.claim_mobile_terminal_viewport(client_id, &session_id, payload, &mut attachment);
        Ok(self.terminal_tab_response_for_client(client_id, tab, attachment))
    }

    pub(super) fn terminal_tab_response_for_client(
        &self,
        client_id: u64,
        tab: WorkspaceTabRecord,
        attachment: Value,
    ) -> Value {
        let tab = self
            .workspace_tab_for_client(client_id, tab)
            .expect("terminal tabs are supported by every client");
        json!({
            "tab": tab,
            "attachment": attachment,
        })
    }
}

async fn mobile_terminal_attachment_payload(
    workspace: &Workspace,
    tab_id: &str,
    session_id: &str,
    payload: &Value,
    login_shell: bool,
) -> Value {
    json!({
        "sessionId": session_id,
        "workspaceId": workspace.id.clone(),
        "tabId": tab_id,
        "workingDirectory": workspace.path.clone(),
        "launch": default_terminal_launch(&workspace.path, login_shell)
            .await
            .launch
            .to_json(),
        "cols": int_or(payload, "cols", 80),
        "rows": int_or(payload, "rows", 24),
    })
}

pub(super) fn mobile_request_allowed(request_type: &str) -> bool {
    matches!(
        request_type,
        "status.get"
            | "host.restart"
            | "mobile.status.get"
            | "project.list"
            | "hostDirectory.roots"
            | "hostDirectory.list"
            | "project.register"
            | "project.rename"
            | "project.remove.preview"
            | "project.remove"
            | "project.clone.start"
            | "project.clone.list"
            | "project.clone.cancel"
            | "projectConfig.effective"
            | "projectConfig.upsert"
            | "projectConfig.remove"
            | "project.branches.list"
            | "workspace.list"
            | "workspace.listAll"
            | "workspace.find"
            | "workspaceSidebar.snapshot"
            | "workbenchViewPrefs.get"
            | "workbenchViewPrefs.update"
            | "agentPresence.list"
            | "workspace.setPinned"
            | "workspace.rename"
            | "workspace.sleep"
            | "workspace.repositoryWebUrl"
            | "workspace.createManaged"
            | "workspace.removeManaged"
            | "agentProfile.list"
            | "agentProfile.launch"
            | "aiText.workspaceIdentity.generate"
            | "aiText.speechMessage.generate"
            | "aiText.cancel"
            | "mobile.promptImage.start"
            | "mobile.promptImage.chunk"
            | "mobile.promptImage.complete"
            | "mobile.promptImage.cancel"
            | "mobile.workspaceQuickOpen.start"
            | "mobile.workspaceQuickOpen.search"
            | "mobile.workspaceQuickOpen.stop"
            | "mobile.workspaceFile.read"
            | "mobile.codexSavedPrompts.list"
            | "mobile.promptFile.start"
            | "mobile.promptFile.chunk"
            | "mobile.promptFile.complete"
            | "mobile.promptFile.cancel"
            | "mobile.promptAttachment.read"
            | "mobile.aiDictation.transcribe"
            | "mobile.aiDictation.cancel"
            | "tab.list"
            | "tab.find"
            | "tab.rename"
            | "tab.remove"
            | "mobile.runtimeSettings.get"
            | "mobile.runtimeSettings.update"
            | "mobile.cloudEnrollment.create"
            | "mobile.cloudSubscriptions.refresh"
            | "agentQuota.snapshot"
            | "agentUsage.snapshot"
            | "agentQuota.fetchClaudeTui"
            | "agentQuota.consumeCodexResetCredit"
            | "cliRegistration.status"
            | "cliRegistration.install"
            | "agentSkill.install"
            | "linkedReview.find"
            | "layout.find"
            | "workspaceTag.list"
            | "workspaceTag.create"
            | "workspaceTag.remove"
            | "workspaceTag.setForWorkspace"
            | "workspaceRelation.list"
            | "workspaceRelation.link"
            | "workspaceRelation.unlink"
            | "workspaceCascade.preview"
            | "terminal.create"
            | "terminal.attach"
            | "terminal.restart"
            | "terminal.driver.list"
            | "write"
            | "resize"
            | "setOutputPaused"
            | "detach"
            | "terminate"
            | "codex.thread.open"
            | "codex.thread.list"
            | "codex.threads.list"
            | "codex.session.list"
            | "codex.thread.resume"
            | "codex.session.resume"
            | "codex.thread.history"
            | "codex.thread.turns.list"
            | "codex.session.history"
            | "codex.thread.new"
            | "codex.session.new"
            | "codex.thread.clear"
            | "codex.session.clear"
            | "codex.tab.create"
            | "codex.tab.configure"
            | "codex.thread.recover"
            | "codex.thread.snapshot"
            | "codex.thread.items.list"
            | "codex.goal.get"
            | "codex.goal.set"
            | "codex.goal.clear"
            | "codex.model.list"
            | "codex.collaborationModes.list"
            | "codex.skills.list"
            | "codex.apps.list"
            | "codex.turn.start"
            | "codex.turn.interrupt"
            | "codex.turn.steer"
            | "codex.thread.rename"
            | "codex.thread.compact"
            | "codex.review.branches"
            | "codex.review.start"
            | "codex.response"
            | "codex.request.snooze"
            | "automation.list"
            | "automation.show"
            | "automation.upsert"
            | "automation.approve"
            | "automation.pause"
            | "automation.resume"
            | "automation.trash"
            | "automation.restore"
            | "automation.purge"
            | "automation.runNow"
            | "automation.runs"
            | "automation.runShow"
            | "automation.context"
            | "automation.heartbeat"
            | "automation.wait"
            | "automation.extend"
            | "automation.complete"
            | "automation.cancel"
            | "automation.templates"
            | "automation.tags"
            | "automation.export"
            | "automation.import"
            | "automation.policy"
    )
}

#[cfg(test)]
mod mobile_codex_file_surface_tests {
    use super::*;

    #[test]
    fn advertises_and_allows_mobile_codex_file_surfaces() {
        assert!(MOBILE_HELLO_CAPABILITIES
            .contains(&RUNTIME_HOST_MOBILE_CODEX_WORKSPACE_FILES_CAPABILITY));
        assert!(MOBILE_HELLO_CAPABILITIES.contains(&RUNTIME_HOST_MOBILE_CODEX_SESSIONS_CAPABILITY));
        assert!(
            MOBILE_HELLO_CAPABILITIES.contains(&RUNTIME_HOST_MOBILE_PROMPT_FILE_UPLOAD_CAPABILITY)
        );
        assert!(MOBILE_HELLO_CAPABILITIES
            .contains(&RUNTIME_HOST_MOBILE_PROMPT_ATTACHMENT_READ_CAPABILITY));
        for request in [
            "mobile.workspaceQuickOpen.start",
            "mobile.workspaceQuickOpen.search",
            "mobile.workspaceQuickOpen.stop",
            "mobile.workspaceFile.read",
            "mobile.codexSavedPrompts.list",
            "mobile.promptFile.start",
            "mobile.promptFile.chunk",
            "mobile.promptFile.complete",
            "mobile.promptFile.cancel",
            "mobile.promptAttachment.read",
        ] {
            assert!(mobile_request_allowed(request), "{request}");
        }
    }
}
