use std::io::Write as _;
use std::path::{Path, PathBuf};

use chrono::{SecondsFormat, Utc};
use serde_json::json;

use crate::terminal_host::protocol::{
    PROTOCOL_VERSION, RUNTIME_HOST_BOOTSTRAP_CAPABILITY, RUNTIME_HOST_CAPABILITY,
    RUNTIME_HOST_MANAGED_WORKSPACE_CAPABILITY, RUNTIME_HOST_MOBILE_CAPABILITY,
    RUNTIME_HOST_ORCHESTRATION_CAPABILITY,
};

/// Publishes the host's socket metadata to the control file the app reads.
///
/// The JSON is written to a sibling `<path>.tmp` and atomically renamed into
/// place so the app never observes a partially written file.
pub fn write_control_file(path: &Path, port: u16, token: &str) -> std::io::Result<()> {
    let body = json!({
        "protocolVersion": PROTOCOL_VERSION,
        "pid": std::process::id(),
        "port": port,
        "token": token,
        "runtimeCapabilities": [
            RUNTIME_HOST_CAPABILITY,
            RUNTIME_HOST_BOOTSTRAP_CAPABILITY,
            RUNTIME_HOST_MANAGED_WORKSPACE_CAPABILITY,
            RUNTIME_HOST_MOBILE_CAPABILITY,
            RUNTIME_HOST_ORCHESTRATION_CAPABILITY,
        ],
        "startedAt": Utc::now().to_rfc3339_opts(SecondsFormat::Millis, true),
    });
    let temp = temp_path(path);
    {
        let mut file = std::fs::File::create(&temp)?;
        file.write_all(serde_json::to_string(&body)?.as_bytes())?;
        file.sync_all()?;
    }
    std::fs::rename(&temp, path)
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
        write_control_file(&path, 54321, "secret-token").unwrap();

        let contents = std::fs::read_to_string(&path).unwrap();
        let value: Value = serde_json::from_str(&contents).unwrap();
        assert_eq!(value["protocolVersion"], json!(PROTOCOL_VERSION));
        assert_eq!(value["port"], json!(54321));
        assert_eq!(value["token"], json!("secret-token"));
        assert_eq!(
            value["runtimeCapabilities"],
            json!([
                RUNTIME_HOST_CAPABILITY,
                RUNTIME_HOST_BOOTSTRAP_CAPABILITY,
                RUNTIME_HOST_MANAGED_WORKSPACE_CAPABILITY,
                RUNTIME_HOST_MOBILE_CAPABILITY,
                RUNTIME_HOST_ORCHESTRATION_CAPABILITY,
            ])
        );
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
        write_control_file(&path, 1, "t").unwrap();
        delete_control_file(&path);
        assert!(!path.exists());
    }
}
