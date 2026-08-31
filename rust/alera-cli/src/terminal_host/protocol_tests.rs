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

#[test]
fn workflow_catalog_capability_does_not_change_the_strict_protocol() {
    assert_eq!(PROTOCOL_VERSION, 4);
    assert_eq!(
        RUNTIME_HOST_WORKFLOW_CATALOG_CAPABILITY,
        "workflowRecipeCatalogV1"
    );
}
