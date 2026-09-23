use std::path::Path;

use serde_json::{json, Map};

use super::super::{read_json_object, write_json_object};
use super::*;

fn script() -> &'static Path {
    Path::new("/home/user/.alera/agent-hooks/alera-runtime-agent-hook.sh")
}

#[test]
fn install_writes_user_hooks_and_trust_without_a_runtime_home() {
    let root = tempfile::tempdir().unwrap();
    let hooks_path = root.path().join("hooks.json");
    write_json_object(
        &hooks_path,
        &Map::from_iter([(
            "hooks".to_string(),
            json!({
                "SessionStart": [{
                    "hooks": [{ "type": "command", "command": "echo user" }]
                }]
            }),
        )]),
    )
    .unwrap();

    install_codex(root.path(), script()).unwrap();

    assert!(!root.path().join("agent-runtime-homes").exists());
    let config = read_json_object(&hooks_path).unwrap().unwrap();
    let start = config["hooks"]["SessionStart"].as_array().unwrap();
    assert_eq!(start.len(), 2);
    assert!(start[0].to_string().contains("echo user"));
    assert!(start[1].to_string().contains("alera-runtime-agent-hook"));
    let toml = std::fs::read_to_string(root.path().join("config.toml")).unwrap();
    assert!(toml.contains("trusted_hash"));
    assert!(toml.contains("session_start"));
}

#[test]
fn install_is_idempotent() {
    let root = tempfile::tempdir().unwrap();
    install_codex(root.path(), script()).unwrap();
    let hooks_path = root.path().join("hooks.json");
    let before = std::fs::read(&hooks_path).unwrap();

    install_codex(root.path(), script()).unwrap();

    assert_eq!(std::fs::read(&hooks_path).unwrap(), before);
}

#[test]
fn cleanup_removes_alera_hooks_and_keeps_user_entries() {
    let root = tempfile::tempdir().unwrap();
    let hooks_path = root.path().join("hooks.json");
    write_json_object(
        &hooks_path,
        &Map::from_iter([(
            "hooks".to_string(),
            json!({
                "SessionStart": [{
                    "hooks": [{ "type": "command", "command": "echo user" }]
                }]
            }),
        )]),
    )
    .unwrap();
    install_codex(root.path(), script()).unwrap();

    cleanup_codex(root.path()).unwrap();

    let cleaned = read_json_object(&hooks_path).unwrap().unwrap();
    let start = cleaned["hooks"]["SessionStart"].as_array().unwrap();
    assert_eq!(start.len(), 1);
    assert!(start[0].to_string().contains("echo user"));
    assert!(!serde_json::Value::Object(cleaned)
        .to_string()
        .contains("alera-runtime-agent-hook"));
}

#[test]
fn cleanup_drops_legacy_runtime_home_trust_keys() {
    let root = tempfile::tempdir().unwrap();
    let toml_path = root.path().join("config.toml");
    std::fs::write(
        &toml_path,
        r#"
[hooks.state]
"/tmp/alera-runtime/agent-runtime-homes/codex/home/hooks.json:stop:0:0" = { enabled = true, trusted_hash = "sha256:old" }
"/other/hooks.json:stop:0:0" = { enabled = false, trusted_hash = "sha256:other" }
"#,
    )
    .unwrap();

    cleanup_codex(root.path()).unwrap();

    let toml = std::fs::read_to_string(&toml_path).unwrap();
    assert!(!toml.contains("agent-runtime-homes/codex"));
    assert!(toml.contains("/other/hooks.json"));
}

#[test]
fn cleanup_is_a_no_op_when_the_user_has_no_codex_config() {
    let root = tempfile::tempdir().unwrap();

    cleanup_codex(root.path()).unwrap();

    assert!(root.path().read_dir().unwrap().next().is_none());
}

#[test]
fn unparseable_config_toml_is_left_untouched() {
    let root = tempfile::tempdir().unwrap();
    let toml_path = root.path().join("config.toml");
    std::fs::write(&toml_path, "not = toml [").unwrap();

    let error = install_codex(root.path(), script()).unwrap_err();
    assert!(error.to_string().contains("config.toml"));
    assert_eq!(std::fs::read_to_string(&toml_path).unwrap(), "not = toml [");
}
