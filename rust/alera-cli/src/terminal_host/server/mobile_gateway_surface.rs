//! What the mobile gateway advertises to a phone and what it admits from one.
//!
//! Kept separate from terminal requests as the mobile surface grows.

use crate::terminal_host::agent_profile_capabilities::{
    RUNTIME_HOST_AGENT_PROFILE_LAUNCH_IDEMPOTENCY_CAPABILITY,
    RUNTIME_HOST_AGENT_PROFILE_SESSION_RESUME_CAPABILITY,
};
use crate::terminal_host::ai_assist_capabilities::{
    RUNTIME_HOST_AI_ASSIST_AGENT_TITLE_CAPABILITY, RUNTIME_HOST_AI_ASSIST_CHATGPT_CAPABILITY,
    RUNTIME_HOST_AI_ASSIST_CHATGPT_OPTIONS_CAPABILITY,
    RUNTIME_HOST_AI_ASSIST_COMMIT_MESSAGE_CAPABILITY,
    RUNTIME_HOST_AI_ASSIST_OPENCODE_GO_CAPABILITY,
    RUNTIME_HOST_AI_ASSIST_PULL_REQUEST_DETAILS_CAPABILITY,
    RUNTIME_HOST_AI_ASSIST_SPEECH_MESSAGE_CAPABILITY,
    RUNTIME_HOST_AI_ASSIST_WORKSPACE_IDENTITY_CAPABILITY,
};
use crate::terminal_host::ai_dictation_capabilities::RUNTIME_HOST_REMOTE_AI_DICTATION_CAPABILITY;
use crate::terminal_host::protocol::{
    RUNTIME_HOST_AGENT_PROFILES_CAPABILITY, RUNTIME_HOST_AGENT_PROFILE_PROMPT_LAUNCH_CAPABILITY,
    RUNTIME_HOST_AGENT_QUOTA_CLAUDE_TUI_CAPABILITY, RUNTIME_HOST_AGENT_STATUS_CAPABILITY,
    RUNTIME_HOST_AI_DICTATION_BACKENDS_CAPABILITY, RUNTIME_HOST_AI_DICTATION_CAPABILITY,
    RUNTIME_HOST_AI_DICTATION_MODELS_CAPABILITY, RUNTIME_HOST_AUTOMATIONS_CAPABILITY,
    RUNTIME_HOST_BINARY_FRAMES_CAPABILITY, RUNTIME_HOST_CAPABILITY,
    RUNTIME_HOST_CODEX_RESET_CREDITS_CAPABILITY, RUNTIME_HOST_LIFECYCLE_CAPABILITY,
    RUNTIME_HOST_LINKED_ISSUES_CAPABILITY, RUNTIME_HOST_MANAGED_WORKSPACE_CAPABILITY,
    RUNTIME_HOST_MOBILE_AGENT_QUOTA_CAPABILITY, RUNTIME_HOST_MOBILE_CAPABILITY,
    RUNTIME_HOST_MOBILE_CLOUD_ENROLLMENT_CAPABILITY,
    RUNTIME_HOST_MOBILE_CODEX_WORKSPACE_FILES_CAPABILITY, RUNTIME_HOST_MOBILE_EXPLORER_CAPABILITY,
    RUNTIME_HOST_MOBILE_HOST_TOOLS_CAPABILITY, RUNTIME_HOST_MOBILE_MUTATIONS_CAPABILITY,
    RUNTIME_HOST_MOBILE_PORTABLE_SETTINGS_CAPABILITY,
    RUNTIME_HOST_MOBILE_PROJECT_MANAGEMENT_CAPABILITY,
    RUNTIME_HOST_MOBILE_PROMPT_ATTACHMENT_READ_CAPABILITY,
    RUNTIME_HOST_MOBILE_PROMPT_FILE_UPLOAD_CAPABILITY,
    RUNTIME_HOST_MOBILE_PROMPT_IMAGE_UPLOAD_CAPABILITY,
    RUNTIME_HOST_MOBILE_PULL_REQUEST_CAPABILITY,
    RUNTIME_HOST_MOBILE_PULL_REQUEST_SUMMARIES_CAPABILITY,
    RUNTIME_HOST_MOBILE_SIDEBAR_PARITY_CAPABILITY, RUNTIME_HOST_MOBILE_SOURCE_CONTROL_CAPABILITY,
    RUNTIME_HOST_MOBILE_SOURCE_CONTROL_WRITES_CAPABILITY,
    RUNTIME_HOST_MOBILE_TAB_RENAME_CAPABILITY, RUNTIME_HOST_MOBILE_TERMINAL_TITLES_CAPABILITY,
    RUNTIME_HOST_MOBILE_WORKSPACE_REPLACE_CAPABILITY,
    RUNTIME_HOST_MOBILE_WORKSPACE_SEARCH_CAPABILITY, RUNTIME_HOST_PULL_REQUEST_WATCH_CAPABILITY,
    RUNTIME_HOST_PULL_REQUEST_WATCH_EXECUTION_CAPABILITY, RUNTIME_HOST_RESTART_CAPABILITY,
    RUNTIME_HOST_TERMINAL_DEFERRED_INPUT_CAPABILITY, RUNTIME_HOST_TERMINAL_DRIVER_CAPABILITY,
    RUNTIME_HOST_TERMINAL_RESTART_CAPABILITY, RUNTIME_HOST_WORKSPACE_ARCHIVE_CAPABILITY,
    RUNTIME_HOST_WORKSPACE_SECTIONS_CAPABILITY,
};

/// What `mobile.hello` tells a phone this host can do.
///
/// A different list from the one `status.get` answers with, and the one the app
/// feature-detects against. Named rather than inlined so a test can assert a
/// capability is in it: the runtime enforces an exact `MOBILE_PROTOCOL_VERSION`
/// match, so an omission here is invisible and silently leaves every phone on
/// the older code path with no version to blame.
pub(super) const MOBILE_HELLO_CAPABILITIES: &[&str] = &[
    "agentChatV1",
    "agentChatDeferredStartV1",
    "agentChatUnselectedDraftV1",
    "agentChatPreferencesV1",
    "agentChatProviderSettingsV1",
    "agentChatEffortV1",
    "agentChatQueueSteerV1",
    "agentChatQueueEditV1",
    "agentChatForkV1",
    "agentChatRewindV1",
    "agentChatDeleteV1",
    "agentChatApprovalHistoryV1",
    "agentChatTurnDiffV1",
    "agentChatReadCursorV1",
    "agentChatProviderSetupV1",
    "agentChatNativeRewindV1",
    "agentChatRewindFilesV1",
    "agentChatFileCheckpointsV1",
    "agentChatNativeHistoryV1",
    "chatOrchestrationV1",
    "chatOrchestrationPersonParentV1",
    "chatOrchestrationEffortV1",
    "configurationSyncV1",
    "relayAuthorizationRenewalV1",
    RUNTIME_HOST_CAPABILITY,
    RUNTIME_HOST_MANAGED_WORKSPACE_CAPABILITY,
    crate::terminal_host::protocol::RUNTIME_HOST_SAFE_HANDOFF_CAPABILITY,
    crate::terminal_host::protocol::RUNTIME_HOST_SHARED_CHECKOUT_CAPABILITY,
    crate::terminal_host::protocol::RUNTIME_HOST_REMOTE_SSH_WORKSPACES_CAPABILITY,
    crate::terminal_host::protocol::RUNTIME_HOST_MOBILE_REMOTE_WORKSPACES_CAPABILITY,
    RUNTIME_HOST_MOBILE_CAPABILITY,
    RUNTIME_HOST_MOBILE_CLOUD_ENROLLMENT_CAPABILITY,
    RUNTIME_HOST_MOBILE_MUTATIONS_CAPABILITY,
    RUNTIME_HOST_MOBILE_PROJECT_MANAGEMENT_CAPABILITY,
    RUNTIME_HOST_WORKSPACE_SECTIONS_CAPABILITY,
    RUNTIME_HOST_WORKSPACE_ARCHIVE_CAPABILITY,
    crate::terminal_host::protocol::RUNTIME_HOST_PROMPT_WORKSPACE_SERVICE_CAPABILITY,
    RUNTIME_HOST_LINKED_ISSUES_CAPABILITY,
    RUNTIME_HOST_PULL_REQUEST_WATCH_CAPABILITY,
    RUNTIME_HOST_PULL_REQUEST_WATCH_EXECUTION_CAPABILITY,
    crate::terminal_host::protocol::RUNTIME_HOST_PULL_REQUEST_WATCH_EXECUTION_V2_CAPABILITY,
    crate::terminal_host::protocol::RUNTIME_HOST_PULL_REQUEST_FORGES_CAPABILITY,
    crate::terminal_host::protocol::RUNTIME_HOST_PULL_REQUEST_AGENT_DISPATCH_CAPABILITY,
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
    crate::terminal_host::protocol::RUNTIME_HOST_INBOX_CAPABILITY,
    crate::terminal_host::protocol::RUNTIME_HOST_INBOX_DELIVERY_CAPABILITY,
    crate::terminal_host::protocol::RUNTIME_HOST_RUNS_CAPABILITY,
    crate::terminal_host::protocol::RUNTIME_HOST_RECIPES_CAPABILITY,
    RUNTIME_HOST_AI_ASSIST_WORKSPACE_IDENTITY_CAPABILITY,
    RUNTIME_HOST_AI_ASSIST_AGENT_TITLE_CAPABILITY,
    RUNTIME_HOST_AI_ASSIST_SPEECH_MESSAGE_CAPABILITY,
    RUNTIME_HOST_AI_ASSIST_COMMIT_MESSAGE_CAPABILITY,
    RUNTIME_HOST_AI_ASSIST_PULL_REQUEST_DETAILS_CAPABILITY,
    RUNTIME_HOST_AI_ASSIST_OPENCODE_GO_CAPABILITY,
    RUNTIME_HOST_AI_ASSIST_CHATGPT_CAPABILITY,
    RUNTIME_HOST_AI_ASSIST_CHATGPT_OPTIONS_CAPABILITY,
    RUNTIME_HOST_AGENT_PROFILE_PROMPT_LAUNCH_CAPABILITY,
    RUNTIME_HOST_AGENT_PROFILE_LAUNCH_IDEMPOTENCY_CAPABILITY,
    RUNTIME_HOST_AGENT_PROFILE_SESSION_RESUME_CAPABILITY,
    RUNTIME_HOST_BINARY_FRAMES_CAPABILITY,
    RUNTIME_HOST_MOBILE_PROMPT_IMAGE_UPLOAD_CAPABILITY,
    RUNTIME_HOST_MOBILE_PROMPT_FILE_UPLOAD_CAPABILITY,
    RUNTIME_HOST_MOBILE_PROMPT_ATTACHMENT_READ_CAPABILITY,
    RUNTIME_HOST_MOBILE_CODEX_WORKSPACE_FILES_CAPABILITY,
    RUNTIME_HOST_MOBILE_EXPLORER_CAPABILITY,
    RUNTIME_HOST_MOBILE_WORKSPACE_SEARCH_CAPABILITY,
    RUNTIME_HOST_MOBILE_WORKSPACE_REPLACE_CAPABILITY,
    RUNTIME_HOST_MOBILE_SOURCE_CONTROL_CAPABILITY,
    RUNTIME_HOST_MOBILE_SOURCE_CONTROL_WRITES_CAPABILITY,
    crate::terminal_host::protocol::RUNTIME_HOST_MOBILE_SOURCE_CONTROL_ROOT_CAPABILITY,
    RUNTIME_HOST_MOBILE_PULL_REQUEST_CAPABILITY,
    crate::terminal_host::protocol::RUNTIME_HOST_MOBILE_PULL_REQUEST_ACTIONS_CAPABILITY,
    crate::terminal_host::protocol::RUNTIME_HOST_MOBILE_PULL_REQUEST_SHIP_CAPABILITY,
    RUNTIME_HOST_MOBILE_PULL_REQUEST_SUMMARIES_CAPABILITY,
    RUNTIME_HOST_AUTOMATIONS_CAPABILITY,
    crate::terminal_host::protocol::RUNTIME_HOST_AUTOMATIONS_AUTHORING_CAPABILITY,
    crate::terminal_host::protocol::RUNTIME_HOST_AUTOMATION_TERMINAL_OBSERVE_CAPABILITY,
    crate::terminal_host::protocol::RUNTIME_HOST_AUTOMATION_REUSE_CAPABILITY,
    RUNTIME_HOST_AI_DICTATION_CAPABILITY,
    RUNTIME_HOST_AI_DICTATION_MODELS_CAPABILITY,
    RUNTIME_HOST_AI_DICTATION_BACKENDS_CAPABILITY,
    RUNTIME_HOST_REMOTE_AI_DICTATION_CAPABILITY,
    crate::terminal_host::protocol::RUNTIME_HOST_VOICE_HOME_AGENT_CAPABILITY,
];
pub(super) fn mobile_hello_capabilities(renewal_enabled: bool) -> Vec<&'static str> {
    MOBILE_HELLO_CAPABILITIES
        .iter()
        .copied()
        .filter(|capability| renewal_enabled || *capability != "relayAuthorizationRenewalV1")
        .collect()
}

pub(super) fn mobile_request_allowed(request_type: &str) -> bool {
    matches!(
        request_type,
        "status.get"
            | "host.restart"
            | "mobile.status.get"
            | "mobile.relayAuthorization.renew"
            | "project.list"
            | "agentChat.providers"
            | "agentChat.list"
            | "agentChat.create"
            | "agentChat.snapshot"
            | "agentChat.payload"
            | "agentChat.history"
            | "agentChat.send"
            | "agentChat.interrupt"
            | "agentChat.respond"
            | "agentChat.configure"
            | "agentChat.rename"
            | "agentChat.recover"
            | "agentChat.close"
            | "agentChat.reopen"
            | "agentChat.queueCancel"
            | "agentChat.queueSteer"
            | "agentChat.queueEdit"
            | "agentChat.fork"
            | "agentChat.rewind"
            | "agentChat.delete"
            | "agentChat.approvalHistory"
            | "agentChat.turnDiff"
            | "agentChat.markRead"
            | "agentChat.rewindFiles"
            | "agentChat.fileCheckpoints.configure"
            | "agentChat.nativeHistory.operation"
            | "agentChat.nativeHistory.reconcile"
            | "agentChat.preferences.get"
            | "agentChat.preferences.update"
            | "agentChat.providerInstances.get"
            | "agentChat.providerInstances.upsert"
            | "agentChat.providerInstances.remove"
            | "agentChat.providerInstances.removalImpact"
            | "agentChat.secrets.set"
            | "agentChat.secrets.clear"
            | "chatOrchestration.capabilities"
            | "chatOrchestration.delegate"
            | "chatOrchestration.send"
            | "chatOrchestration.task"
            | "chatOrchestration.tasks.list"
            | "chatOrchestration.wait"
            | "chatOrchestration.cancel"
            | "chatOrchestration.interrupt"
            | "chatOrchestration.requests"
            | "chatOrchestration.respond"
            | "chatOrchestration.configure"
            | "chatOrchestration.read"
            | "chatOrchestration.list"
            | "mobile.hosts.list"
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
            | "workspace.retirementReceipt"
            | "workspaceSidebar.snapshot"
            | "workbenchViewPrefs.get"
            | "workbenchViewPrefs.update"
            | "agentPresence.list"
            | "workspace.setPinned"
            | "workspace.rename"
            | "workspace.sleep"
            | "workspace.archive"
            | "workspace.unarchive"
            | "workspace.repositoryWebUrl"
            | "workspace.createManaged"
            | "workspace.createShared"
            | "workspace.promptStart.start"
            | "workspace.promptStart.get"
            | "workspace.promptStart.list"
            | "workspace.promptStart.cancel"
            | "workspace.promptStart.retryLaunch"
            | "checkout.list"
            | "workspace.bufferGuard.acquire"
            | "workspace.bufferGuard.status"
            | "workspace.bufferGuard.release"
            | "checkout.quickOpen.start"
            | "workspace.checkout"
            | "workspace.relocationRecovery"
            | "workspace.sshRelocationRecovery"
            | "workspace.runSetup"
            | "workspace.prepareRelocationSetup"
            | "workspace.recoverRelocationSetup"
            | "workspace.cancelRelocationSetup"
            | "workspace.removalDependencies"
            | "project.removalDependencies"
            | "workspace.handOff"
            | "workspace.handOn"
            | "workspace.storageImpact"
            | "workspace.removeManaged"
            | "workspace.removeShared"
            | "agentProfile.list"
            | "agentProfile.launch"
            | "agentProfile.launchIdempotent"
            | "aiText.agentTitle.generate"
            | "aiText.workspaceIdentity.generate"
            | "aiText.speechMessage.generate"
            | "aiText.commitMessage.generate"
            | "aiText.pullRequestDetails.generate"
            | "aiText.cancel"
            | "aiAssist.complete"
            | "aiAssist.opencodeGo.models"
            | "mobile.promptImage.start"
            | "mobile.promptImage.chunk"
            | "mobile.promptImage.complete"
            | "mobile.promptImage.cancel"
            | "mobile.workspaceQuickOpen.start"
            | "mobile.workspaceQuickOpen.search"
            | "mobile.workspaceQuickOpen.stop"
            | "mobile.workspaceFile.read"
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
            | "pullRequest.agentDispatch"
            | "mobile.promptFile.start"
            | "mobile.promptFile.chunk"
            | "mobile.promptFile.complete"
            | "mobile.promptFile.cancel"
            | "mobile.promptAttachment.read"
            | "mobile.aiDictation.transcribe"
            | "mobile.aiDictation.cancel"
            | "mobile.aiDictation.capabilities"
            | "mobile.voice.ensure"
            | "mobile.voice.status"
            | "mobile.voice.start"
            | "mobile.voice.stop"
            | "mobile.voice.turn"
            | "mobile.voice.synthesize"
            | "mobile.voice.spoken"
            | "mobile.voice.audio"
            | "mobile.voice.activity"
            | "mobile.voice.credentials.status"
            | "mobile.voice.credentials.save"
            | "mobile.voice.credentials.clear"
            | "tab.list"
            | "tab.find"
            | "tab.rename"
            | "tab.remove"
            | "configuration.transfer.start"
            | "configuration.transfer.read"
            | "configuration.transfer.chunk"
            | "configuration.transfer.commit"
            | "configuration.transfer.cancel"
            | "configuration.snapshot"
            | "configuration.apply"
            | "configuration.published"
            | "mobile.runtimeSettings.get"
            | "mobile.runtimeSettings.update"
            | "mobile.cloudEnrollment.create"
            | "mobile.cloudSubscriptions.refresh"
            | "agentQuota.snapshot"
            | "agentQuota.fetchClaudeTui"
            | "agentQuota.consumeCodexResetCredit"
            | "cliRegistration.status"
            | "cliRegistration.install"
            | "agentSkill.install"
            | "linkedReview.find"
            | "linkedIssue.list"
            | "linkedIssue.find"
            | "linkedIssue.link"
            | "linkedIssue.refresh"
            | "linkedIssue.remove"
            | "issue.fetch"
            | "pullRequestWatch.list"
            | "pullRequestWatch.find"
            | "pullRequestWatch.start"
            | "pullRequestWatch.stop"
            | "layout.find"
            | "workspaceSection.list"
            | "workspaceSection.create"
            | "workspaceSection.setForWorkspace"
            | "workspaceSection.remove"
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
            | "terminal.observe"
            | "terminal.restart"
            | "terminal.driver.list"
            | "write"
            | "resize"
            | "setOutputPaused"
            | "detach"
            | "terminate"
            | "automation.create"
            | "automation.patch"
            | "automation.previewSchedule"
            | "automation.readiness"
            | "automation.takeOver"
            | "automation.list"
            | "automation.show"
            | "automation.upsert"
            | "automation.approve"
            | "automation.pause"
            | "automation.unbind"
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
            | "inbox.summary"
            | "inbox.threads"
            | "inbox.thread"
            | "inbox.targets"
            | "inbox.ask"
            | "inbox.cancel"
            | "inbox.markRead"
            | "inbox.purge"
    ) || MOBILE_RUN_VERBS.contains(&request_type)
}

/// Every `runs.*` verb and the read-only recipe verbs. Recipe writes, every
/// `orchestration.*` verb, `host.process.run`, `inbox.wait` and the agent
/// conversation reads (`inbox.conversations`, `inbox.conversation`, replaced on
/// the phone by run timelines) stay local-only.
pub(super) const MOBILE_RUN_VERBS: &[&str] = &[
    "runs.board",
    "runs.snapshot",
    "runs.task",
    "runs.timeline",
    "runs.source",
    "runs.create",
    "runs.plan",
    "runs.gates",
    "runs.gate",
    "runs.resolveGate",
    "runs.control",
    "runs.retryTask",
    "runs.retryIntegration",
    "runs.retryCancellation",
    "runs.resources",
    "runs.cleanups",
    "runs.previewCleanup",
    "runs.cleanup",
    "runs.applyCleanup",
    "runs.retryCleanup",
    "runs.abandonCleanup",
    "runs.integrations",
    "runs.integration",
    "recipes.catalog",
    "recipes.recipe",
];

#[cfg(test)]
#[path = "mobile_gateway_surface_tests.rs"]
mod tests;

#[cfg(test)]
#[path = "mobile_gateway_surface_codex_tests.rs"]
mod mobile_codex_file_surface_tests;
#[cfg(test)]
#[path = "mobile_gateway_surface_setup_tests.rs"]
mod mobile_setup_surface_tests;
#[cfg(test)]
#[path = "mobile_gateway_surface_runs_tests.rs"]
mod runs_mobile_tests;
