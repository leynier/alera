use std::path::Path;

use serde_json::{json, Map};

use super::{
    cleanup_cursor_user_hooks, install_cursor_user_hooks, read_jsonc_object, write_json_object,
    CURSOR_HOOK_EVENTS, CURSOR_HOOK_TIMEOUT_SECONDS,
};

fn script() -> &'static Path {
    Path::new("/home/user/.alera/agent-hooks/alera-runtime-agent-hook.sh")
}

#[test]
fn install_writes_every_event_with_a_timeout_and_keeps_user_entries() {
    let home = tempfile::tempdir().unwrap();
    let path = home.path().join(".cursor/hooks.json");
    write_json_object(
        &path,
        &Map::from_iter([
            ("version".to_string(), json!(1)),
            (
                "hooks".to_string(),
                json!({
                    "preToolUse": [{"command": "/home/user/audit.sh"}],
                    "sessionStart": [{"command": "/home/user/start.sh"}],
                }),
            ),
        ]),
    )
    .unwrap();

    install_cursor_user_hooks(home.path(), script()).unwrap();

    let config = read_jsonc_object(&path).unwrap().unwrap();
    assert_eq!(config["version"], json!(1));
    let hooks = config["hooks"].as_object().unwrap();
    assert_eq!(
        hooks["sessionStart"],
        json!([{"command": "/home/user/start.sh"}])
    );
    for event in CURSOR_HOOK_EVENTS {
        let definitions = hooks[event].as_array().unwrap();
        let alera = definitions
            .iter()
            .find(|definition| definition.to_string().contains("alera-runtime-agent-hook"))
            .unwrap();
        assert_eq!(alera["timeout"], json!(CURSOR_HOOK_TIMEOUT_SECONDS));
        assert!(alera["command"].as_str().unwrap().contains(event));
        assert!(alera.get("permission").is_none());
    }
    assert!(hooks["preToolUse"]
        .to_string()
        .contains("/home/user/audit.sh"));
}

#[test]
fn install_does_not_register_session_start() {
    let home = tempfile::tempdir().unwrap();

    install_cursor_user_hooks(home.path(), script()).unwrap();

    let config = read_jsonc_object(&home.path().join(".cursor/hooks.json"))
        .unwrap()
        .unwrap();
    assert!(!config["hooks"]
        .as_object()
        .unwrap()
        .contains_key("sessionStart"));
}

#[test]
fn install_leaves_an_up_to_date_file_untouched() {
    let home = tempfile::tempdir().unwrap();
    let path = home.path().join(".cursor/hooks.json");
    install_cursor_user_hooks(home.path(), script()).unwrap();
    let before = std::fs::metadata(&path).unwrap().modified().unwrap();

    install_cursor_user_hooks(home.path(), script()).unwrap();

    assert_eq!(
        std::fs::metadata(&path).unwrap().modified().unwrap(),
        before
    );
}

#[test]
fn cleanup_removes_alera_definitions_and_keeps_the_users_own() {
    let home = tempfile::tempdir().unwrap();
    let path = home.path().join(".cursor/hooks.json");
    write_json_object(
        &path,
        &Map::from_iter([
            ("version".to_string(), json!(1)),
            (
                "hooks".to_string(),
                json!({
                    "preToolUse": [
                        {"command": "/home/user/audit.sh"},
                        {"command": "/home/user/.alera/agent-hooks/alera-runtime-agent-hook.sh"},
                    ],
                    "stop": [
                        {"command": "/home/user/.alera/agent-hooks/alera-cursor-hook.sh"},
                    ],
                }),
            ),
        ]),
    )
    .unwrap();

    cleanup_cursor_user_hooks(home.path()).unwrap();

    let config = read_jsonc_object(&path).unwrap().unwrap();
    let hooks = config["hooks"].as_object().unwrap();
    assert_eq!(
        hooks["preToolUse"],
        json!([{"command": "/home/user/audit.sh"}])
    );
    assert!(!hooks.contains_key("stop"));
    assert_eq!(config["version"], json!(1));
}

#[test]
fn cleanup_leaves_a_file_without_alera_definitions_untouched() {
    let home = tempfile::tempdir().unwrap();
    let path = home.path().join(".cursor/hooks.json");
    write_json_object(
        &path,
        &Map::from_iter([(
            "hooks".to_string(),
            json!({ "stop": [{"command": "/home/user/audit.sh"}] }),
        )]),
    )
    .unwrap();
    let before = std::fs::read_to_string(&path).unwrap();

    cleanup_cursor_user_hooks(home.path()).unwrap();

    assert_eq!(std::fs::read_to_string(&path).unwrap(), before);
}

#[test]
fn cleanup_is_a_no_op_when_the_user_has_no_hooks_file() {
    let home = tempfile::tempdir().unwrap();

    cleanup_cursor_user_hooks(home.path()).unwrap();

    assert!(!home.path().join(".cursor/hooks.json").exists());
}
