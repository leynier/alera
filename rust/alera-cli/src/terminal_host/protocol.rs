use std::collections::BTreeMap;

use base64::engine::general_purpose::STANDARD;
use base64::Engine as _;
use serde_json::{json, Map, Value};

use crate::terminal_host::host_error::{HostError, HostResult};

/// Wire protocol version. Must stay in lockstep with the Flutter client
/// (`aleraTerminalHostProtocolVersion`).
pub const PROTOCOL_VERSION: i64 = 4;
pub const ORCHESTRATION_PROTOCOL_VERSION: i64 = 2;
pub const DISPATCH_PREAMBLE_VERSION: i64 = 2;
pub const ORCHESTRATION_SKILL_VERSION: i64 = 2;
pub const RUNTIME_HOST_CAPABILITY: &str = "runtimeStore";
pub const RUNTIME_HOST_BOOTSTRAP_CAPABILITY: &str = "sshTargetBootstrap";
pub const RUNTIME_HOST_MANAGED_WORKSPACE_CAPABILITY: &str = "managedWorkspaceLifecycle";
pub const RUNTIME_HOST_MOBILE_CAPABILITY: &str = "mobileCompanionAccess";
// Advertised once mobile clients may call workspace mutations (pin, link,
// create/remove managed, tab removal). Mobile apps feature-check this instead
// of the strict-equality mobile protocol version.
pub const RUNTIME_HOST_MOBILE_MUTATIONS_CAPABILITY: &str = "mobileWorkspaceMutations";
pub const RUNTIME_HOST_MOBILE_SIDEBAR_PARITY_CAPABILITY: &str = "mobileWorkspaceSidebarParityV1";
// Advertised additively: older hosts stay usable for non-orchestration verbs,
// so clients must feature-check this capability instead of the protocol version.
pub const RUNTIME_HOST_ORCHESTRATION_CAPABILITY: &str = "orchestration";
// Advertised once the host tracks terminal viewport drivers (mobile presence
// lock): `terminalDriverChanged` events, `terminal.reclaim`, and
// `terminal.driver.list`.
pub const RUNTIME_HOST_TERMINAL_DRIVER_CAPABILITY: &str = "terminalDriverPresence";

// Retained for the later packaging/resolver phase (sidecar discovery).
#[allow(dead_code)]
pub const CLI_EXECUTABLE_NAME: &str = "alera";
#[allow(dead_code)]
pub const CLI_WINDOWS_EXECUTABLE_NAME: &str = "alera.exe";
pub const TERMINAL_HOST_COMMAND: &str = "terminal-host";

pub const DEFAULT_EMPTY_SHUTDOWN_DELAY_SECONDS: u64 = 30;
pub const DEFAULT_DETACHED_SESSION_SHUTDOWN_DELAY_SECONDS: u64 = 60 * 60;
pub const DEFAULT_SCROLLBACK_BYTES: u64 = 10 * 1000 * 1000;

/// Host-side lifecycle and retention configuration. Mirrors `TerminalHostConfig`.
#[derive(Debug, Clone, Copy)]
pub struct TerminalHostConfig {
    pub empty_shutdown_delay_seconds: u64,
    pub detached_session_shutdown_delay_seconds: u64,
    pub scrollback_bytes: u64,
}

impl Default for TerminalHostConfig {
    fn default() -> Self {
        TerminalHostConfig {
            empty_shutdown_delay_seconds: DEFAULT_EMPTY_SHUTDOWN_DELAY_SECONDS,
            detached_session_shutdown_delay_seconds:
                DEFAULT_DETACHED_SESSION_SHUTDOWN_DELAY_SECONDS,
            scrollback_bytes: DEFAULT_SCROLLBACK_BYTES,
        }
    }
}

impl TerminalHostConfig {
    /// Parse a `configure` payload, matching `TerminalHostConfig.fromJson`
    /// (every field must be a positive integer).
    pub fn from_json(value: &Value) -> HostResult<Self> {
        Ok(TerminalHostConfig {
            empty_shutdown_delay_seconds: positive_int(
                value.get("emptyShutdownDelaySeconds"),
                "emptyShutdownDelaySeconds",
            )?,
            detached_session_shutdown_delay_seconds: positive_int(
                value.get("detachedSessionShutdownDelaySeconds"),
                "detachedSessionShutdownDelaySeconds",
            )?,
            scrollback_bytes: positive_int(value.get("scrollbackBytes"), "scrollbackBytes")?,
        })
    }

    // Used by tests and kept as the symmetric counterpart of `from_json`.
    #[allow(dead_code)]
    pub fn to_json(self) -> Value {
        json!({
            "emptyShutdownDelaySeconds": self.empty_shutdown_delay_seconds,
            "detachedSessionShutdownDelaySeconds": self.detached_session_shutdown_delay_seconds,
            "scrollbackBytes": self.scrollback_bytes,
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
        };
        let parsed = TerminalHostConfig::from_json(&config.to_json()).unwrap();
        assert_eq!(parsed.empty_shutdown_delay_seconds, 5);
        assert_eq!(parsed.detached_session_shutdown_delay_seconds, 6);
        assert_eq!(parsed.scrollback_bytes, 7);
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
