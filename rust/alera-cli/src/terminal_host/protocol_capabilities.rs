pub const RUNTIME_HOST_CAPABILITY: &str = "runtimeStore";
pub const RUNTIME_HOST_BOOTSTRAP_CAPABILITY: &str = "sshTargetBootstrap";
pub const RUNTIME_HOST_MANAGED_WORKSPACE_CAPABILITY: &str = "managedWorkspaceLifecycle";
pub const RUNTIME_HOST_SAFE_HANDOFF_CAPABILITY: &str = "safeWorkspaceHandoffV1";
pub const RUNTIME_HOST_REMOTE_AUTOMATION_CLEANUP_CAPABILITY: &str = "remoteAutomationCleanupV1";
pub const RUNTIME_HOST_OWNER_PRECHECK_CAPABILITY: &str = "ownerAutomationPrecheckV1";
pub const RUNTIME_HOST_LINKED_OWNER_PRECHECK_CAPABILITY: &str = "linkedOwnerAutomationPrecheckV1";
pub const RUNTIME_HOST_SHARED_CHECKOUT_CAPABILITY: &str = "sharedCheckoutWorkspacesV1";
/// Home Runtime can create a Git worktree on a bootstrapped SSH target and
/// attach terminals/files over SSH. Additive: older hosts ignore `hostId` on
/// `workspace.createManaged` and would create a local worktree instead, so
/// callers must feature-check this rather than the protocol version.
pub const RUNTIME_HOST_REMOTE_SSH_WORKSPACES_CAPABILITY: &str = "remoteSshWorkspacesV1";
pub const RUNTIME_HOST_MOBILE_CAPABILITY: &str = "mobileCompanionAccess";
pub const RUNTIME_HOST_MOBILE_NETBIRD_CAPABILITY: &str = "mobileNetBirdGatewayV1";
pub const RUNTIME_HOST_WORKSPACE_SECTIONS_CAPABILITY: &str = "workspaceSectionsV1";
/// The host stores one linked issue per workspace (`linkedIssue.*`), fetches
/// issues through `issue.fetch`, and links one from `workspace.createManaged`
/// when it carries `issueUrl`. Additive: an older host rejects the verbs and
/// ignores `issueUrl`, so clients feature-check this capability.
pub const RUNTIME_HOST_LINKED_ISSUES_CAPABILITY: &str = "linkedIssuesV1";
// Advertised once mobile clients may call workspace mutations (pin, link,
// create/remove managed, tab removal). Mobile apps feature-check this instead
// of the strict-equality mobile protocol version.
pub const RUNTIME_HOST_MOBILE_MUTATIONS_CAPABILITY: &str = "mobileWorkspaceMutations";
pub const RUNTIME_HOST_MOBILE_SIDEBAR_PARITY_CAPABILITY: &str = "mobileWorkspaceSidebarParityV1";
pub const RUNTIME_HOST_MOBILE_PROJECT_MANAGEMENT_CAPABILITY: &str = "mobileProjectManagementV1";
pub const RUNTIME_HOST_MOBILE_TAB_RENAME_CAPABILITY: &str = "mobileTabRenameV1";
pub const RUNTIME_HOST_MOBILE_TERMINAL_TITLES_CAPABILITY: &str = "mobileTerminalTitlesV1";
pub const RUNTIME_HOST_MOBILE_PORTABLE_SETTINGS_CAPABILITY: &str = "mobilePortableSettingsV1";
pub const RUNTIME_HOST_MOBILE_AGENT_QUOTA_CAPABILITY: &str = "mobileAgentQuotaV1";
pub const RUNTIME_HOST_AGENT_QUOTA_CLAUDE_TUI_CAPABILITY: &str = "agentQuotaClaudeTuiV1";
pub const RUNTIME_HOST_CODEX_RESET_CREDITS_CAPABILITY: &str = "codexResetCreditsV1";
pub const RUNTIME_HOST_MOBILE_HOST_TOOLS_CAPABILITY: &str = "mobileHostToolsV1";
/// Advertised once authenticated mobile clients may stream prompt images into
/// the runtime-owned image store for New Workspace From Prompt.
pub const RUNTIME_HOST_MOBILE_PROMPT_IMAGE_UPLOAD_CAPABILITY: &str = "mobilePromptImageUploadV1";
/// A paired phone can search and read bounded workspace files and list saved
/// Codex prompts without receiving unrestricted host filesystem access.
pub const RUNTIME_HOST_MOBILE_CODEX_WORKSPACE_FILES_CAPABILITY: &str =
    "mobileCodexWorkspaceFilesV1";
/// A paired phone can browse a workspace directory tree through
/// `mobile.workspaceExplorer.list`. Additive: older phones ignore the capability.
pub const RUNTIME_HOST_MOBILE_EXPLORER_CAPABILITY: &str = "mobileExplorerV1";
/// A paired phone can run workspace text search through `mobile.workspaceSearch.run`.
pub const RUNTIME_HOST_MOBILE_WORKSPACE_SEARCH_CAPABILITY: &str = "mobileWorkspaceSearchV1";
/// A paired phone can preview replacements through `mobile.workspaceSearch.run`,
/// apply them through `mobile.workspaceSearch.replace`, and cancel a running
/// search through `mobile.workspaceSearch.cancel`. Additive: older phones ignore it.
pub const RUNTIME_HOST_MOBILE_WORKSPACE_REPLACE_CAPABILITY: &str = "mobileWorkspaceReplaceV1";
/// A paired phone can read git dirty status and a per-file diff.
pub const RUNTIME_HOST_MOBILE_SOURCE_CONTROL_CAPABILITY: &str = "mobileSourceControlV1";
/// A paired phone can stage, discard, commit, sync, stash and switch branches
/// through the `mobile.git.*` write verbs, and `mobile.git.status` carries the
/// actions the runtime allows. Additive: older phones stay read-only.
pub const RUNTIME_HOST_MOBILE_SOURCE_CONTROL_WRITES_CAPABILITY: &str =
    "mobileSourceControlWritesV1";
/// A paired phone can load a usable current-branch pull-request snapshot.
pub const RUNTIME_HOST_MOBILE_PULL_REQUEST_CAPABILITY: &str = "mobilePullRequestV1";
/// A paired phone can comment, reply, edit its own comments, merge, change
/// draft status, close, link, unlink and create GitHub pull requests through
/// the `mobile.pullRequest.*` write verbs. Additive to `mobilePullRequestV1`.
pub const RUNTIME_HOST_MOBILE_PULL_REQUEST_ACTIONS_CAPABILITY: &str = "mobilePullRequestActionsV1";
/// Retained name. Codex chat sessions are gone; older phones still feature-detect this string.
#[allow(dead_code)]
pub const RUNTIME_HOST_MOBILE_CODEX_SESSIONS_CAPABILITY: &str = "mobileCodexSessionsV1";
/// A paired phone can upload bounded general files into the runtime-owned
/// prompt attachment store using the same offset-checked chunking as images.
pub const RUNTIME_HOST_MOBILE_PROMPT_FILE_UPLOAD_CAPABILITY: &str = "mobilePromptFileUploadV1";
pub const RUNTIME_HOST_MOBILE_PROMPT_ATTACHMENT_READ_CAPABILITY: &str =
    "mobilePromptAttachmentReadV1";
pub const RUNTIME_HOST_AI_DICTATION_CAPABILITY: &str = "aiDictationV1";
pub const RUNTIME_HOST_AI_DICTATION_MODELS_CAPABILITY: &str = "aiDictationModelsV2";
pub const RUNTIME_HOST_AI_DICTATION_BACKENDS_CAPABILITY: &str = "aiDictationBackendsV3";
/// Desktop account management backed by the Alera cloud identity service.
/// Account verbs remain unavailable to paired mobile clients.
pub const RUNTIME_HOST_ACCOUNT_CAPABILITY: &str = "aleraAccountV1";
/// A paired phone may exchange its authenticated runtime connection for a
/// short-lived cloud enrollment code without learning the runtime credential.
pub const RUNTIME_HOST_MOBILE_CLOUD_ENROLLMENT_CAPABILITY: &str = "mobileCloudEnrollmentV1";
/// The runtime can deliver idempotent attention, done, and terminal-exit
/// events to account-owned mobile subscriptions.
pub const RUNTIME_HOST_CLOUD_PUSH_CAPABILITY: &str = "cloudPushNotificationsV1";
// Advertised additively: older hosts stay usable for non-orchestration verbs,
// so clients must feature-check this capability instead of the protocol version.
pub const RUNTIME_HOST_ORCHESTRATION_CAPABILITY: &str = "orchestration";
pub const RUNTIME_HOST_ORCHESTRATION_TERMINAL_INSPECTION_CAPABILITY: &str =
    "orchestrationTerminalInspectionV1";
pub const RUNTIME_HOST_ORCHESTRATION_WAIT_CAPABILITY: &str = "orchestrationWaitV1";
// Advertised once dispatch honors the explicit agent adapter override. Older
// hosts ignore assumeAgent, so callers must negotiate this capability first.
pub const RUNTIME_HOST_ORCHESTRATION_ASSUME_AGENT_CAPABILITY: &str = "orchestrationAssumeAgentV1";
// Advertised once the host stores the user-declared agent profile catalog.
// Purely additive: older hosts simply do not answer agentProfile.* verbs, so
// callers negotiate this instead of comparing protocol versions.
pub const RUNTIME_HOST_AGENT_PROFILES_CAPABILITY: &str = "orchestrationAgentProfilesV1";
// Advertised once the host persists the user-defined order of agent profiles.
// This is additive so a newer app can remain attached to an older host.
pub const RUNTIME_HOST_AGENT_PROFILE_ORDERING_CAPABILITY: &str =
    "orchestrationAgentProfileOrderingV1";
// Advertised once agent profiles may carry validated, adapter-specific launch
// configuration. This is additive so a new app can fall back to Command when
// attached to an older live host.
pub const RUNTIME_HOST_MANAGED_AGENT_PROFILES_CAPABILITY: &str =
    "orchestrationManagedAgentProfilesV1";
pub const RUNTIME_HOST_AGENT_PROFILE_PROMPT_LAUNCH_CAPABILITY: &str = "agentProfilePromptLaunchV1";
// Advertised once runs carry a user-approved execution policy. A run without a
// policy schedules exactly as before, so this stays a feature check.
pub const RUNTIME_HOST_RUN_POLICY_CAPABILITY: &str = "orchestrationRunPolicyV1";
// Advertised once terminal.write supports host-sequenced bracketed paste and
// deferred Enter. Older hosts ignore those fields, so CLI callers must require
// this capability before relying on --enter or --submit.
pub const RUNTIME_HOST_TERMINAL_DEFERRED_INPUT_CAPABILITY: &str = "terminalDeferredInputV1";
// Advertised once the host tracks terminal viewport drivers (mobile presence
// lock): `terminalDriverChanged` events, `terminal.reclaim`, and
// `terminal.driver.list`.
pub const RUNTIME_HOST_TERMINAL_DRIVER_CAPABILITY: &str = "terminalDriverPresence";
// Advertised once callers can explicitly replace a terminal process while
// preserving its handle and scrollback. Older hosts remain attachable.
pub const RUNTIME_HOST_TERMINAL_RESTART_CAPABILITY: &str = "terminalRestartV1";
pub const RUNTIME_HOST_TERMINAL_PULSE_CAPABILITY: &str = "terminalPulseV1";
/// The client may ask, in its `hello`, to switch this connection to
/// length-prefixed binary frames. Negotiated per client, so an older app and
/// the `alera` CLI keep getting newline-delimited JSON from the same host.
pub const RUNTIME_HOST_BINARY_FRAMES_CAPABILITY: &str = "binaryFrames";
/// Last line before the connection switches to frames. Everything after it is
/// framed, so a reader can flip on seeing it without any out-of-band signal.
pub const BINARY_FRAMES_ENABLED_EVENT: &str = "binaryFramesEnabled";
pub const RUNTIME_HOST_LIFECYCLE_CAPABILITY: &str = "runtimeHostLifecycleV1";
/// The host can replace its own sidecar process through `host.restart`.
///
/// This is separate from the older lifecycle capability because older hosts
/// advertise that capability but only implement shutdown.
pub const RUNTIME_HOST_RESTART_CAPABILITY: &str = "runtimeHostRestartV1";
// Advertised once the host samples per-session CPU and memory and answers
// `resources.snapshot`. Additive: older hosts simply do not offer the verb, so
// clients feature-check this instead of the protocol version.
pub const RUNTIME_HOST_RESOURCE_MONITOR_CAPABILITY: &str = "resourceMonitorV1";
pub const RUNTIME_HOST_AGENT_STATUS_CAPABILITY: &str = "runtimeAgentStatusV1";
// Advertised once the host writes a rotated log file and reports its directory
// through `status.get`, so the desktop can collect runtime logs into a
// diagnostics bundle. Additive: a host without it simply reports no directory,
// so clients feature-check this instead of comparing protocol versions.
pub const RUNTIME_HOST_DIAGNOSTICS_LOGS_CAPABILITY: &str = "hostDiagnosticsLogsV1";
// Advertised once the host answers `shellEnvironment.reload`: re-probing the
// user's login shell so a tool installed mid-session resolves without a host
// restart. Additive, so clients feature-check this instead of the protocol
// version; a host that lacks it is still fully usable.
pub const RUNTIME_HOST_SHELL_ENVIRONMENT_RELOAD_CAPABILITY: &str = "shellEnvironmentReloadV1";
pub const RUNTIME_HOST_AUTOMATIONS_CAPABILITY: &str = "automationsV1";
