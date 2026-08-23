//! What the mobile gateway advertises to a phone and what it admits from one.
//!
//! Separate from the terminal requests themselves: this is the surface a phone
//! is allowed to see, and it grows with every mobile feature, while the
//! terminal verbs below it do not.

use crate::terminal_host::protocol::{
    RUNTIME_HOST_AGENT_PROFILES_CAPABILITY, RUNTIME_HOST_AGENT_PROFILE_PROMPT_LAUNCH_CAPABILITY,
    RUNTIME_HOST_AGENT_QUOTA_CLAUDE_TUI_CAPABILITY, RUNTIME_HOST_AGENT_STATUS_CAPABILITY,
    RUNTIME_HOST_AI_DICTATION_BACKENDS_CAPABILITY, RUNTIME_HOST_AI_DICTATION_CAPABILITY,
    RUNTIME_HOST_AI_DICTATION_MODELS_CAPABILITY, RUNTIME_HOST_AI_TEXT_SPEECH_MESSAGE_CAPABILITY,
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
    RUNTIME_HOST_AI_DICTATION_MODELS_CAPABILITY,
    RUNTIME_HOST_AI_DICTATION_BACKENDS_CAPABILITY,
];
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
            | "mobile.aiDictation.capabilities"
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

    #[test]
    fn advertises_and_allows_speech_capabilities() {
        assert!(MOBILE_HELLO_CAPABILITIES.contains(&RUNTIME_HOST_AI_DICTATION_BACKENDS_CAPABILITY));
        assert!(mobile_request_allowed("mobile.aiDictation.capabilities"));
    }
}
