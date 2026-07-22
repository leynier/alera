use super::*;
use std::path::PathBuf;

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

#[test]
fn remaps_trusted_source_hook_records_to_runtime_hooks_path() {
    let source_hooks = PathBuf::from("/home/user/.codex/hooks.json");
    let runtime_hooks =
        PathBuf::from("/tmp/alera-runtime/agent-runtime-homes/codex/home/hooks.json");
    let source_key = format!("{}:session_start:0:0", source_hooks.display());
    let runtime_key = format!("{}:session_start:0:0", runtime_hooks.display());
    let mut state = toml::map::Map::new();
    let mut entry = toml::map::Map::new();
    entry.insert("enabled".to_string(), toml::Value::Boolean(true));
    entry.insert(
        "trusted_hash".to_string(),
        toml::Value::String("sha256:source-trusted".to_string()),
    );
    state.insert(source_key.clone(), toml::Value::Table(entry));

    remap_codex_source_hook_trust(&mut state, &source_hooks, &runtime_hooks);

    assert!(!state.contains_key(&source_key));
    let remapped = state
        .get(&runtime_key)
        .and_then(toml::Value::as_table)
        .expect("remapped trust entry");
    assert_eq!(
        remapped.get("enabled").and_then(toml::Value::as_bool),
        Some(true)
    );
    assert_eq!(
        remapped.get("trusted_hash").and_then(toml::Value::as_str),
        Some("sha256:source-trusted")
    );
}

#[test]
fn leaves_untrusted_source_hooks_without_runtime_trust_records() {
    let source_hooks = PathBuf::from("/home/user/.codex/hooks.json");
    let runtime_hooks =
        PathBuf::from("/tmp/alera-runtime/agent-runtime-homes/codex/home/hooks.json");
    let mut state = toml::map::Map::new();
    let unrelated_key = "/other/hooks.json:stop:0:0".to_string();
    let mut unrelated = toml::map::Map::new();
    unrelated.insert("enabled".to_string(), toml::Value::Boolean(false));
    unrelated.insert(
        "trusted_hash".to_string(),
        toml::Value::String("sha256:other".to_string()),
    );
    state.insert(unrelated_key.clone(), toml::Value::Table(unrelated));

    remap_codex_source_hook_trust(&mut state, &source_hooks, &runtime_hooks);

    assert_eq!(state.len(), 1);
    assert!(state.contains_key(&unrelated_key));
    assert!(!state
        .keys()
        .any(|key| { key.starts_with(&format!("{}:", runtime_hooks.display())) }));
}
