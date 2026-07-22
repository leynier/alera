use super::*;

#[test]
fn removes_current_and_legacy_alera_definitions_only() {
    let definitions = vec![
        json!({"command": "/home/user/custom-hook.sh"}),
        json!({"command": "/home/user/.alera/agent-hooks/alera-claude-hook.sh"}),
        json!({"command": "/home/user/.alera/agent-hooks/alera-runtime-agent-hook.sh"}),
        json!({"command": "/home/user/.orca/agent-hooks/claude-hook.sh"}),
    ];

    let cleaned = clean_managed_definitions(Some(Value::Array(definitions)));

    assert_eq!(cleaned.len(), 2);
    assert!(cleaned[0].to_string().contains("custom-hook.sh"));
    assert!(cleaned[1].to_string().contains(".orca/agent-hooks"));
}

#[test]
fn managed_scripts_can_derive_the_current_runtime_endpoint() {
    assert!(POSIX_HOOK_SCRIPT.contains("$ALERA_RUNTIME_DIR/agent-hooks/endpoint.env"));
}

#[cfg(windows)]
#[test]
fn windows_managed_script_can_derive_the_current_runtime_endpoint() {
    assert!(WINDOWS_HOOK_SCRIPT.contains("%ALERA_RUNTIME_DIR%\\agent-hooks\\endpoint.cmd"));
}
