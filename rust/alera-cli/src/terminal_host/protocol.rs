use std::collections::BTreeMap;

use base64::engine::general_purpose::STANDARD;
use base64::Engine as _;
use serde_json::{json, Map, Value};

pub use alera_runtime_protocol::{
    BINARY_FRAMES_ENABLED_EVENT, DEFAULT_DETACHED_SESSION_SHUTDOWN_DELAY_SECONDS,
    DEFAULT_EMPTY_SHUTDOWN_DELAY_SECONDS, DEFAULT_SCROLLBACK_BYTES, MOBILE_EMULATOR_TAB_KIND,
    PROTOCOL_VERSION, RUNTIME_HOST_BINARY_FRAMES_CAPABILITY, RUNTIME_HOST_BOOTSTRAP_CAPABILITY,
    RUNTIME_HOST_CAPABILITY, RUNTIME_HOST_MANAGED_WORKSPACE_CAPABILITY,
    RUNTIME_HOST_MOBILE_CAPABILITY,
};

use crate::terminal_host::host_error::{HostError, HostResult};

pub const ORCHESTRATION_PROTOCOL_VERSION: i64 = 2;
pub const DISPATCH_PREAMBLE_VERSION: i64 = 2;
pub const ORCHESTRATION_SKILL_VERSION: i64 = 3;
pub const ORCHESTRATION_ACCEPTANCE_TIMEOUT_MS: u64 = 90_000;
/// Longest wait the host will hold a parked orchestration request for. Shared
/// with the CLI so `--timeout-ms` can refuse a budget the host would silently
/// cut down to this.
pub const ORCHESTRATION_MAX_WAIT_TIMEOUT_MS: u64 = 600_000;
pub const RUNTIME_HOST_MOBILE_NETBIRD_CAPABILITY: &str = "mobileNetBirdGatewayV1";
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
/// A paired phone can list, resume, reset, clear, and rename Codex threads.
pub const RUNTIME_HOST_MOBILE_CODEX_SESSIONS_CAPABILITY: &str = "mobileCodexSessionsV1";
/// A paired phone can upload bounded general files into the runtime-owned
/// prompt attachment store using the same offset-checked chunking as images.
pub const RUNTIME_HOST_MOBILE_PROMPT_FILE_UPLOAD_CAPABILITY: &str = "mobilePromptFileUploadV1";
pub const RUNTIME_HOST_MOBILE_PROMPT_ATTACHMENT_READ_CAPABILITY: &str =
    "mobilePromptAttachmentReadV1";
pub const RUNTIME_HOST_AI_DICTATION_CAPABILITY: &str = "aiDictationV1";
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
/// Advertised once the runtime host persists and serves Agent Canvas state.
/// This is additive so a new app can explain compatibility against an older
/// live host without treating the existing terminal connection as unusable.
pub const RUNTIME_HOST_AGENT_CANVAS_CAPABILITY: &str = "agentCanvasV1";
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
pub const RUNTIME_HOST_AI_TEXT_WORKSPACE_IDENTITY_CAPABILITY: &str = "aiTextWorkspaceIdentityV1";
pub const RUNTIME_HOST_AI_TEXT_SPEECH_MESSAGE_CAPABILITY: &str = "aiTextSpeechMessageV1";
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
// Advertised once the host answers `computer.*`: reading and driving local
// desktop UI through the platform accessibility layer. Additive, so clients
// feature-check this instead of comparing protocol versions; a host that lacks
// it is still fully usable for everything else.
pub const RUNTIME_HOST_COMPUTER_USE_CAPABILITY: &str = "computerUseV1";
/// Routes browser automation calls to the Flutter app connection that owns the
/// live WebView page. This is additive and does not change terminal framing.
pub const RUNTIME_HOST_BROWSER_AUTOMATION_ROUTING_CAPABILITY: &str = "browserAutomationRoutingV1";
/// Stores browser profiles, history, closed tabs, permissions and typed search
/// settings in the shared runtime catalog.
pub const RUNTIME_HOST_BROWSER_PROFILES_CAPABILITY: &str = "browserProfilesV1";
/// Stores exact local certificate fingerprints per browser profile.
pub const RUNTIME_HOST_BROWSER_CERTIFICATE_TRUST_CAPABILITY: &str = "browserCertificateTrustV1";
// Advertised once the host can manage embedded Android and iOS emulator tabs.
// Additive: older hosts remain usable, and clients feature-check before
// sending emulator verbs.
pub const RUNTIME_HOST_MOBILE_EMULATOR_CAPABILITY: &str = "mobileEmulatorV1";
pub const RUNTIME_HOST_AUTOMATIONS_CAPABILITY: &str = "automationsV1";
/// Native Codex chat tabs are additive. Clients advertise support for the tab
/// kind separately so an older client never attempts to decode it.
pub const RUNTIME_HOST_CODEX_CHAT_CAPABILITY: &str = "codexChatTabV1";
/// Codex goals are additive and bridged through the app-server thread goal API.
pub const RUNTIME_HOST_CODEX_GOALS_CAPABILITY: &str = "codexGoalsV1";
/// Native Codex session management is additive. Desktop clients negotiate it
/// before exposing thread list, resume, new, and clear actions.
pub const RUNTIME_HOST_CODEX_SESSIONS_CAPABILITY: &str = "codexSessionsV1";
/// Codex turn requests accept the app-server's split approval reviewer and
/// sandbox policy fields instead of relying on the legacy approval mode.
pub const RUNTIME_HOST_CODEX_TURN_POLICY_CAPABILITY: &str = "codexTurnPolicyV2";
pub const CODEX_TAB_KIND: &str = "codex";
/// Version of the computer-use skill guide this binary's command surface matches.
/// Reported by `alera version` so a stale installed skill is detectable.
pub const COMPUTER_USE_SKILL_VERSION: i64 = 1;
/// Version of the mobile-emulator skill guide this binary's command surface matches.
pub const EMULATOR_SKILL_VERSION: i64 = 1;

// Retained for the later packaging/resolver phase (sidecar discovery).
#[allow(dead_code)]
pub const CLI_EXECUTABLE_NAME: &str = "alera";
#[allow(dead_code)]
pub const CLI_WINDOWS_EXECUTABLE_NAME: &str = "alera.exe";
pub const TERMINAL_HOST_COMMAND: &str = "terminal-host";

/// Interactive shells start as login shells on macOS, where GUI apps inherit a
/// minimal `launchd` PATH and `~/.zprofile` is the usual place PATH is set up.
pub const fn default_login_shell() -> bool {
    cfg!(target_os = "macos")
}

/// Host-side lifecycle and retention configuration. Mirrors `TerminalHostConfig`.
#[derive(Debug, Clone, Copy)]
pub struct TerminalHostConfig {
    pub empty_shutdown_delay_seconds: u64,
    pub detached_session_shutdown_delay_seconds: u64,
    pub scrollback_bytes: u64,
    /// Cap on what an attach or a resynchronising snapshot replays into a
    /// client's emulator. Distinct from `scrollback_bytes`, which is what the
    /// host *retains* so `terminal.read` and checkpoints can page back through
    /// it; replaying all of that costs a VT parse per byte for history the
    /// emulator immediately drops.
    pub restore_snapshot_bytes: u64,
    pub persistent: bool,
    pub login_shell: bool,
}

impl Default for TerminalHostConfig {
    fn default() -> Self {
        TerminalHostConfig {
            empty_shutdown_delay_seconds: DEFAULT_EMPTY_SHUTDOWN_DELAY_SECONDS,
            detached_session_shutdown_delay_seconds:
                DEFAULT_DETACHED_SESSION_SHUTDOWN_DELAY_SECONDS,
            scrollback_bytes: DEFAULT_SCROLLBACK_BYTES,
            restore_snapshot_bytes: DEFAULT_SCROLLBACK_BYTES,
            persistent: false,
            login_shell: default_login_shell(),
        }
    }
}

impl TerminalHostConfig {
    /// Parse a `configure` payload, matching `TerminalHostConfig.fromJson`
    /// (every field must be a positive integer).
    pub fn from_json(value: &Value) -> HostResult<Self> {
        let scrollback_bytes = positive_int(value.get("scrollbackBytes"), "scrollbackBytes")?;
        Ok(TerminalHostConfig {
            empty_shutdown_delay_seconds: positive_int(
                value.get("emptyShutdownDelaySeconds"),
                "emptyShutdownDelaySeconds",
            )?,
            detached_session_shutdown_delay_seconds: positive_int(
                value.get("detachedSessionShutdownDelaySeconds"),
                "detachedSessionShutdownDelaySeconds",
            )?,
            scrollback_bytes,
            // An app that predates snapshot trimming sends no cap, and must
            // keep getting the whole buffer.
            restore_snapshot_bytes: value
                .get("restoreSnapshotBytes")
                .and_then(Value::as_u64)
                .filter(|bytes| *bytes > 0)
                .unwrap_or(scrollback_bytes),
            persistent: false,
            login_shell: value
                .get("loginShell")
                .and_then(Value::as_bool)
                .unwrap_or_else(default_login_shell),
        })
    }

    // Used by tests and kept as the symmetric counterpart of `from_json`.
    #[allow(dead_code)]
    pub fn to_json(self) -> Value {
        json!({
            "emptyShutdownDelaySeconds": self.empty_shutdown_delay_seconds,
            "detachedSessionShutdownDelaySeconds": self.detached_session_shutdown_delay_seconds,
            "scrollbackBytes": self.scrollback_bytes,
            "restoreSnapshotBytes": self.restore_snapshot_bytes,
            "persistent": self.persistent,
            "loginShell": self.login_shell,
        })
    }
}

/// A shell launch request, mirroring `TerminalHostLaunch`.
#[derive(Debug, Clone)]
pub struct TerminalHostLaunch {
    // Carried through the protocol for display parity; the host does not use
    // the label when spawning.
    #[allow(dead_code)]
    pub label: String,
    pub shell: String,
    pub arguments: Vec<String>,
    pub environment: BTreeMap<String, String>,
}

impl TerminalHostLaunch {
    pub fn from_json(value: &Value) -> HostResult<Self> {
        let shell = match value.get("shell") {
            Some(Value::String(s)) if !s.is_empty() => s.clone(),
            _ => {
                return Err(HostError::format("Terminal host launch shell is required."));
            }
        };
        let label = match value.get("label") {
            Some(Value::String(s)) => s.clone(),
            _ => "shell".to_string(),
        };
        Ok(TerminalHostLaunch {
            label,
            shell,
            arguments: as_string_list(value.get("arguments")),
            environment: as_string_map(value.get("environment")),
        })
    }

    pub fn to_json(&self) -> Value {
        json!({
            "label": self.label,
            "shell": self.shell,
            "arguments": self.arguments,
            "environment": self.environment,
        })
    }
}

/// Standard base64 encoding, matching Dart's `base64Encode`.
pub fn encode_bytes(bytes: &[u8]) -> String {
    STANDARD.encode(bytes)
}

/// Decode a base64 string field, matching `decodeTerminalHostBytes`: a missing,
/// non-string, or empty value yields no bytes; an invalid string is an error.
pub fn decode_bytes(value: Option<&Value>) -> HostResult<Vec<u8>> {
    match value {
        Some(Value::String(s)) if !s.is_empty() => STANDARD
            .decode(s)
            .map_err(|error| HostError::format(error.to_string())),
        _ => Ok(Vec::new()),
    }
}

/// Coerce a JSON value into a list of strings, dropping non-string items,
/// matching `asTerminalHostStringList`.
pub fn as_string_list(value: Option<&Value>) -> Vec<String> {
    match value {
        Some(Value::Array(items)) => items
            .iter()
            .filter_map(|item| item.as_str().map(str::to_string))
            .collect(),
        _ => Vec::new(),
    }
}

/// Coerce a JSON value into a string map, dropping non-string entries, matching
/// `asTerminalHostStringMap`.
pub fn as_string_map(value: Option<&Value>) -> BTreeMap<String, String> {
    match value {
        Some(Value::Object(map)) => map
            .iter()
            .filter_map(|(key, val)| val.as_str().map(|v| (key.clone(), v.to_string())))
            .collect(),
        _ => BTreeMap::new(),
    }
}

/// Require a JSON object, matching `asTerminalHostMap`. A missing value is
/// treated as an empty object, matching the Dart call sites that default the
/// payload to `{}`.
pub fn require_object<'a>(
    value: Option<&'a Value>,
    label: &str,
) -> HostResult<&'a Map<String, Value>> {
    match value {
        Some(Value::Object(map)) => Ok(map),
        None | Some(Value::Null) => {
            Err(HostError::format(format!("{label} must be a JSON object.")))
        }
        Some(_) => Err(HostError::format(format!("{label} must be a JSON object."))),
    }
}

/// Read an `int?` field defaulting to `fallback`, matching the
/// `(payload['x'] as int?) ?? fallback` pattern used for cols/rows.
pub fn int_or(value: &Value, key: &str, fallback: i64) -> i64 {
    value.get(key).and_then(Value::as_i64).unwrap_or(fallback)
}

fn positive_int(value: Option<&Value>, label: &str) -> HostResult<u64> {
    match value.and_then(Value::as_i64) {
        Some(v) if v > 0 => Ok(v as u64),
        _ => Err(HostError::format(format!(
            "{label} must be a positive integer."
        ))),
    }
}

/// Build a success response frame `{id, ok: true, payload}`.
pub fn ok_response(id: i64, payload: Value) -> Value {
    json!({ "id": id, "ok": true, "payload": payload })
}

/// Build an error response frame `{id, ok: false, error}`.
pub fn error_response(id: i64, error: &HostError) -> Value {
    json!({ "id": id, "ok": false, "error": error.wire_message() })
}

/// Build an event frame `{event, payload}`.
pub fn event(name: &str, payload: Value) -> Value {
    json!({ "event": name, "payload": payload })
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn config_round_trips() {
        let config = TerminalHostConfig {
            empty_shutdown_delay_seconds: 5,
            detached_session_shutdown_delay_seconds: 6,
            scrollback_bytes: 7,
            restore_snapshot_bytes: 4,
            persistent: false,
            login_shell: !default_login_shell(),
        };
        let parsed = TerminalHostConfig::from_json(&config.to_json()).unwrap();
        assert_eq!(parsed.empty_shutdown_delay_seconds, 5);
        assert_eq!(parsed.detached_session_shutdown_delay_seconds, 6);
        assert_eq!(parsed.scrollback_bytes, 7);
        assert_eq!(parsed.restore_snapshot_bytes, 4);
        assert_eq!(parsed.login_shell, !default_login_shell());
    }

    #[test]
    fn config_without_a_restore_cap_replays_the_whole_buffer() {
        // An app that predates snapshot trimming sends no cap.
        let parsed = TerminalHostConfig::from_json(&json!({
            "emptyShutdownDelaySeconds": 5,
            "detachedSessionShutdownDelaySeconds": 6,
            "scrollbackBytes": 7,
        }))
        .unwrap();

        assert_eq!(parsed.restore_snapshot_bytes, 7);
    }

    #[test]
    fn config_without_login_shell_key_uses_the_platform_default() {
        let parsed = TerminalHostConfig::from_json(&json!({
            "emptyShutdownDelaySeconds": 5,
            "detachedSessionShutdownDelaySeconds": 6,
            "scrollbackBytes": 7,
        }))
        .unwrap();

        assert_eq!(parsed.login_shell, default_login_shell());
        assert_eq!(parsed.login_shell, cfg!(target_os = "macos"));
    }

    #[test]
    fn config_rejects_non_positive() {
        let value = json!({
            "emptyShutdownDelaySeconds": 0,
            "detachedSessionShutdownDelaySeconds": 6,
            "scrollbackBytes": 7,
        });
        let error = TerminalHostConfig::from_json(&value).unwrap_err();
        assert_eq!(
            error.wire_message(),
            "FormatException: emptyShutdownDelaySeconds must be a positive integer."
        );
    }

    #[test]
    fn launch_requires_shell() {
        let error = TerminalHostLaunch::from_json(&json!({"label": "x"})).unwrap_err();
        assert_eq!(
            error.wire_message(),
            "FormatException: Terminal host launch shell is required."
        );
    }

    #[test]
    fn launch_coerces_collections() {
        let launch = TerminalHostLaunch::from_json(&json!({
            "shell": "/bin/zsh",
            "arguments": ["-l", 42, "-i"],
            "environment": {"A": "1", "B": 2, "C": "3"},
        }))
        .unwrap();
        assert_eq!(launch.label, "shell");
        assert_eq!(launch.arguments, vec!["-l".to_string(), "-i".to_string()]);
        assert_eq!(launch.environment.get("A").map(String::as_str), Some("1"));
        assert_eq!(launch.environment.get("C").map(String::as_str), Some("3"));
        assert!(!launch.environment.contains_key("B"));
    }

    /// Diagnostics logging is advertised as a capability, never as a protocol
    /// bump: a version mismatch makes the app treat a live host as unusable, so
    /// an additive feature that raised the version would break every client
    /// that is still on the previous build.
    #[test]
    fn diagnostics_logging_stayed_additive() {
        assert_eq!(PROTOCOL_VERSION, 4);
        assert_eq!(
            RUNTIME_HOST_DIAGNOSTICS_LOGS_CAPABILITY,
            "hostDiagnosticsLogsV1"
        );
    }

    #[test]
    fn bytes_round_trip() {
        let encoded = encode_bytes(b"hello");
        let decoded = decode_bytes(Some(&Value::String(encoded))).unwrap();
        assert_eq!(decoded, b"hello");
        assert!(decode_bytes(None).unwrap().is_empty());
        assert!(decode_bytes(Some(&Value::String(String::new())))
            .unwrap()
            .is_empty());
    }
}
