use std::io::Write as _;
use std::path::{Path, PathBuf};

use chrono::{SecondsFormat, Utc};
use serde_json::json;

use alera_core::runtime::{
    create_private_runtime_file, prepare_private_runtime_directory, set_private_file_permissions,
};

use crate::terminal_host::protocol::{
    PROTOCOL_VERSION, RUNTIME_HOST_ACCOUNT_CAPABILITY, RUNTIME_HOST_AGENT_PROFILES_CAPABILITY,
    RUNTIME_HOST_AGENT_PROFILE_PROMPT_LAUNCH_CAPABILITY,
    RUNTIME_HOST_AGENT_QUOTA_CLAUDE_TUI_CAPABILITY, RUNTIME_HOST_AGENT_STATUS_CAPABILITY,
    RUNTIME_HOST_AI_TEXT_WORKSPACE_IDENTITY_CAPABILITY, RUNTIME_HOST_BINARY_FRAMES_CAPABILITY,
    RUNTIME_HOST_BOOTSTRAP_CAPABILITY, RUNTIME_HOST_BROWSER_AUTOMATION_ROUTING_CAPABILITY,
    RUNTIME_HOST_BROWSER_CERTIFICATE_TRUST_CAPABILITY, RUNTIME_HOST_BROWSER_PROFILES_CAPABILITY,
    RUNTIME_HOST_CAPABILITY, RUNTIME_HOST_CLOUD_PUSH_CAPABILITY,
    RUNTIME_HOST_COMPUTER_USE_CAPABILITY, RUNTIME_HOST_LIFECYCLE_CAPABILITY,
    RUNTIME_HOST_MANAGED_AGENT_PROFILES_CAPABILITY, RUNTIME_HOST_MANAGED_WORKSPACE_CAPABILITY,
    RUNTIME_HOST_MOBILE_AGENT_QUOTA_CAPABILITY, RUNTIME_HOST_MOBILE_CAPABILITY,
    RUNTIME_HOST_MOBILE_CLOUD_ENROLLMENT_CAPABILITY, RUNTIME_HOST_MOBILE_EMULATOR_CAPABILITY,
    RUNTIME_HOST_MOBILE_HOST_TOOLS_CAPABILITY, RUNTIME_HOST_MOBILE_MUTATIONS_CAPABILITY,
    RUNTIME_HOST_MOBILE_NETBIRD_CAPABILITY, RUNTIME_HOST_MOBILE_PORTABLE_SETTINGS_CAPABILITY,
    RUNTIME_HOST_MOBILE_PROJECT_MANAGEMENT_CAPABILITY,
    RUNTIME_HOST_MOBILE_SIDEBAR_PARITY_CAPABILITY, RUNTIME_HOST_MOBILE_TAB_RENAME_CAPABILITY,
    RUNTIME_HOST_MOBILE_TERMINAL_TITLES_CAPABILITY,
    RUNTIME_HOST_ORCHESTRATION_ASSUME_AGENT_CAPABILITY, RUNTIME_HOST_ORCHESTRATION_CAPABILITY,
    RUNTIME_HOST_ORCHESTRATION_TERMINAL_INSPECTION_CAPABILITY,
    RUNTIME_HOST_ORCHESTRATION_WAIT_CAPABILITY, RUNTIME_HOST_RESOURCE_MONITOR_CAPABILITY,
    RUNTIME_HOST_RESTART_CAPABILITY, RUNTIME_HOST_RUN_POLICY_CAPABILITY,
    RUNTIME_HOST_TERMINAL_DEFERRED_INPUT_CAPABILITY, RUNTIME_HOST_TERMINAL_DRIVER_CAPABILITY,
    RUNTIME_HOST_TERMINAL_RESTART_CAPABILITY,
};

/// Publishes the host's socket metadata to the control file the app reads.
///
/// The JSON is written to a sibling `<path>.tmp` and atomically renamed into
/// place so the app never observes a partially written file.
pub fn write_control_file(
    path: &Path,
    port: u16,
    token: &str,
    persistent: bool,
) -> std::io::Result<()> {
    if let Some(parent) = path.parent() {
        prepare_private_runtime_directory(parent)?;
    }
    let body = json!({
        "protocolVersion": PROTOCOL_VERSION,
        "pid": std::process::id(),
        "port": port,
        "token": token,
        "runtimeCapabilities": [
            RUNTIME_HOST_CAPABILITY,
            RUNTIME_HOST_ACCOUNT_CAPABILITY,
            RUNTIME_HOST_CLOUD_PUSH_CAPABILITY,
            RUNTIME_HOST_BOOTSTRAP_CAPABILITY,
            RUNTIME_HOST_MANAGED_WORKSPACE_CAPABILITY,
            RUNTIME_HOST_MOBILE_CAPABILITY,
            RUNTIME_HOST_MOBILE_NETBIRD_CAPABILITY,
            RUNTIME_HOST_MOBILE_CLOUD_ENROLLMENT_CAPABILITY,
            RUNTIME_HOST_MOBILE_MUTATIONS_CAPABILITY,
            RUNTIME_HOST_MOBILE_PROJECT_MANAGEMENT_CAPABILITY,
            RUNTIME_HOST_MOBILE_SIDEBAR_PARITY_CAPABILITY,
            RUNTIME_HOST_MOBILE_TAB_RENAME_CAPABILITY,
            RUNTIME_HOST_MOBILE_TERMINAL_TITLES_CAPABILITY,
            RUNTIME_HOST_MOBILE_PORTABLE_SETTINGS_CAPABILITY,
            RUNTIME_HOST_MOBILE_AGENT_QUOTA_CAPABILITY,
            RUNTIME_HOST_AGENT_QUOTA_CLAUDE_TUI_CAPABILITY,
            RUNTIME_HOST_MOBILE_HOST_TOOLS_CAPABILITY,
            RUNTIME_HOST_ORCHESTRATION_CAPABILITY,
            RUNTIME_HOST_AGENT_PROFILES_CAPABILITY,
            RUNTIME_HOST_MANAGED_AGENT_PROFILES_CAPABILITY,
            RUNTIME_HOST_AI_TEXT_WORKSPACE_IDENTITY_CAPABILITY,
            RUNTIME_HOST_AGENT_PROFILE_PROMPT_LAUNCH_CAPABILITY,
            RUNTIME_HOST_ORCHESTRATION_ASSUME_AGENT_CAPABILITY,
            RUNTIME_HOST_ORCHESTRATION_TERMINAL_INSPECTION_CAPABILITY,
            RUNTIME_HOST_ORCHESTRATION_WAIT_CAPABILITY,
            RUNTIME_HOST_RUN_POLICY_CAPABILITY,
            RUNTIME_HOST_TERMINAL_DEFERRED_INPUT_CAPABILITY,
            RUNTIME_HOST_TERMINAL_DRIVER_CAPABILITY,
            RUNTIME_HOST_TERMINAL_RESTART_CAPABILITY,
            RUNTIME_HOST_LIFECYCLE_CAPABILITY,
            RUNTIME_HOST_RESTART_CAPABILITY,
            RUNTIME_HOST_AGENT_STATUS_CAPABILITY,
            RUNTIME_HOST_BINARY_FRAMES_CAPABILITY,
            RUNTIME_HOST_RESOURCE_MONITOR_CAPABILITY,
            RUNTIME_HOST_COMPUTER_USE_CAPABILITY,
            RUNTIME_HOST_BROWSER_AUTOMATION_ROUTING_CAPABILITY,
            RUNTIME_HOST_BROWSER_CERTIFICATE_TRUST_CAPABILITY,
            RUNTIME_HOST_BROWSER_PROFILES_CAPABILITY,
            RUNTIME_HOST_MOBILE_EMULATOR_CAPABILITY,
        ],
        "persistent": persistent,
        "startedAt": Utc::now().to_rfc3339_opts(SecondsFormat::Millis, true),
    });
    write_value(path, &body)
}

/// Promotes a live host's published lifecycle mode without changing its
/// identity, endpoint, token, capabilities, or start timestamp.
pub fn promote_persistent(path: &Path) -> std::io::Result<()> {
    let contents = std::fs::read_to_string(path)?;
    let mut body: serde_json::Value = serde_json::from_str(&contents)
        .map_err(|error| std::io::Error::new(std::io::ErrorKind::InvalidData, error))?;
    if body.get("persistent").and_then(serde_json::Value::as_bool) == Some(true) {
        return Ok(());
    }
    body["persistent"] = serde_json::Value::Bool(true);
    write_value(path, &body)
}

fn write_value(path: &Path, body: &serde_json::Value) -> std::io::Result<()> {
    let temp = temp_path(path);
    {
        let mut file = create_private_runtime_file(&temp)?;
        file.write_all(serde_json::to_string(&body)?.as_bytes())?;
        file.sync_all()?;
    }
    set_private_file_permissions(&temp)?;
    std::fs::rename(&temp, path)?;
    set_private_file_permissions(path)
}

/// Best-effort removal of the control file on shutdown; errors are swallowed.
pub fn delete_control_file(path: &Path) {
    let _ = std::fs::remove_file(path);
}

fn temp_path(path: &Path) -> PathBuf {
    let mut name = path.as_os_str().to_os_string();
    name.push(".tmp");
    PathBuf::from(name)
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::Value;

    #[test]
    fn writes_and_reads_back_metadata() {
        let dir = tempfile::tempdir().unwrap();
        let path = dir.path().join("host.json");
        write_control_file(&path, 54321, "secret-token", true).unwrap();

        let contents = std::fs::read_to_string(&path).unwrap();
        let value: Value = serde_json::from_str(&contents).unwrap();
        assert_eq!(value["protocolVersion"], json!(PROTOCOL_VERSION));
        assert_eq!(value["port"], json!(54321));
        assert_eq!(value["token"], json!("secret-token"));
        assert_eq!(
            value["runtimeCapabilities"],
            json!([
                RUNTIME_HOST_CAPABILITY,
                RUNTIME_HOST_ACCOUNT_CAPABILITY,
                RUNTIME_HOST_CLOUD_PUSH_CAPABILITY,
                RUNTIME_HOST_BOOTSTRAP_CAPABILITY,
                RUNTIME_HOST_MANAGED_WORKSPACE_CAPABILITY,
                RUNTIME_HOST_MOBILE_CAPABILITY,
                RUNTIME_HOST_MOBILE_NETBIRD_CAPABILITY,
                RUNTIME_HOST_MOBILE_CLOUD_ENROLLMENT_CAPABILITY,
                RUNTIME_HOST_MOBILE_MUTATIONS_CAPABILITY,
                RUNTIME_HOST_MOBILE_PROJECT_MANAGEMENT_CAPABILITY,
                RUNTIME_HOST_MOBILE_SIDEBAR_PARITY_CAPABILITY,
                RUNTIME_HOST_MOBILE_TAB_RENAME_CAPABILITY,
                RUNTIME_HOST_MOBILE_TERMINAL_TITLES_CAPABILITY,
                RUNTIME_HOST_MOBILE_PORTABLE_SETTINGS_CAPABILITY,
                RUNTIME_HOST_MOBILE_AGENT_QUOTA_CAPABILITY,
                RUNTIME_HOST_AGENT_QUOTA_CLAUDE_TUI_CAPABILITY,
                RUNTIME_HOST_MOBILE_HOST_TOOLS_CAPABILITY,
                RUNTIME_HOST_ORCHESTRATION_CAPABILITY,
                RUNTIME_HOST_AGENT_PROFILES_CAPABILITY,
                RUNTIME_HOST_MANAGED_AGENT_PROFILES_CAPABILITY,
                RUNTIME_HOST_AI_TEXT_WORKSPACE_IDENTITY_CAPABILITY,
                RUNTIME_HOST_AGENT_PROFILE_PROMPT_LAUNCH_CAPABILITY,
                RUNTIME_HOST_ORCHESTRATION_ASSUME_AGENT_CAPABILITY,
                RUNTIME_HOST_ORCHESTRATION_TERMINAL_INSPECTION_CAPABILITY,
                RUNTIME_HOST_ORCHESTRATION_WAIT_CAPABILITY,
                RUNTIME_HOST_RUN_POLICY_CAPABILITY,
                RUNTIME_HOST_TERMINAL_DEFERRED_INPUT_CAPABILITY,
                RUNTIME_HOST_TERMINAL_DRIVER_CAPABILITY,
                RUNTIME_HOST_TERMINAL_RESTART_CAPABILITY,
                RUNTIME_HOST_LIFECYCLE_CAPABILITY,
                RUNTIME_HOST_RESTART_CAPABILITY,
                RUNTIME_HOST_AGENT_STATUS_CAPABILITY,
                RUNTIME_HOST_BINARY_FRAMES_CAPABILITY,
                RUNTIME_HOST_RESOURCE_MONITOR_CAPABILITY,
                RUNTIME_HOST_COMPUTER_USE_CAPABILITY,
                RUNTIME_HOST_BROWSER_AUTOMATION_ROUTING_CAPABILITY,
                RUNTIME_HOST_BROWSER_CERTIFICATE_TRUST_CAPABILITY,
                RUNTIME_HOST_BROWSER_PROFILES_CAPABILITY,
                RUNTIME_HOST_MOBILE_EMULATOR_CAPABILITY,
            ])
        );
        assert_eq!(value["persistent"], json!(true));
        assert_eq!(value["pid"], json!(std::process::id()));
        assert!(value["startedAt"].as_str().unwrap().ends_with('Z'));

        // The temp file must not linger after an atomic rename.
        assert!(!temp_path(&path).exists());
    }

    #[test]
    fn delete_is_best_effort() {
        let dir = tempfile::tempdir().unwrap();
        let path = dir.path().join("host.json");
        // Deleting a missing file must not panic.
        delete_control_file(&path);
        write_control_file(&path, 1, "t", false).unwrap();
        delete_control_file(&path);
        assert!(!path.exists());
    }

    #[test]
    fn promotion_preserves_control_identity_and_is_idempotent() {
        let dir = tempfile::tempdir().unwrap();
        let path = dir.path().join("host.json");
        write_control_file(&path, 54321, "secret-token", false).unwrap();
        let before: Value = serde_json::from_str(&std::fs::read_to_string(&path).unwrap()).unwrap();

        promote_persistent(&path).unwrap();
        let promoted = std::fs::read_to_string(&path).unwrap();
        let after: Value = serde_json::from_str(&promoted).unwrap();
        assert_eq!(after["persistent"], json!(true));
        for key in ["pid", "port", "token", "startedAt", "runtimeCapabilities"] {
            assert_eq!(after[key], before[key], "{key} changed during promotion");
        }

        promote_persistent(&path).unwrap();
        assert_eq!(std::fs::read_to_string(path).unwrap(), promoted);
    }

    #[cfg(unix)]
    #[test]
    fn control_file_is_private() {
        use std::os::unix::fs::PermissionsExt as _;

        let dir = tempfile::tempdir().unwrap();
        let path = dir.path().join("runtime").join("host.json");
        write_control_file(&path, 1, "secret", false).unwrap();

        assert_eq!(
            std::fs::metadata(path).unwrap().permissions().mode() & 0o777,
            0o600
        );
    }
}
