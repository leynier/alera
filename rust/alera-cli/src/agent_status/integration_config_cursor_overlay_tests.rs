use std::path::PathBuf;

use super::super::read_json_object;
use super::*;

fn overlay_for(runtime: &Path, session: &str) -> BTreeMap<String, String> {
    let script = runtime.join("alera-runtime-agent-hook.sh");
    std::fs::write(&script, "#!/bin/sh\n").unwrap();
    let mut environment = BTreeMap::new();
    prepare_cursor(runtime, session, &script, &mut environment).unwrap();
    environment
}

#[test]
fn builds_a_plugin_the_cursor_cli_can_resolve() {
    let runtime = tempfile::tempdir().unwrap();

    let environment = overlay_for(runtime.path(), "session-1");

    let plugin_root = PathBuf::from(&environment["ALERA_CURSOR_PLUGIN_DIR"]);
    let manifest = read_json_object(&plugin_root.join(".cursor-plugin/plugin.json"))
        .unwrap()
        .unwrap();
    assert_eq!(manifest["hooks"], json!("hooks/hooks.json"));
    assert_eq!(manifest["name"], json!("alera-agent-status"));
    assert!(plugin_root.join("hooks/hooks.json").is_file());
    assert!(PathBuf::from(&environment["ALERA_AGENT_WRAPPER_PATH"])
        .join(wrapper_file_name())
        .is_file());
}

#[test]
fn registers_every_event_with_a_timeout() {
    let runtime = tempfile::tempdir().unwrap();

    let environment = overlay_for(runtime.path(), "session-1");

    let config = read_json_object(
        &PathBuf::from(&environment["ALERA_CURSOR_PLUGIN_DIR"]).join("hooks/hooks.json"),
    )
    .unwrap()
    .unwrap();
    assert_eq!(config["version"], json!(1));
    let hooks = config["hooks"].as_object().unwrap();
    assert_eq!(hooks.len(), CURSOR_HOOK_EVENTS.len());
    for event in CURSOR_HOOK_EVENTS {
        let definitions = hooks[event].as_array().unwrap();
        assert_eq!(definitions.len(), 1);
        assert_eq!(
            definitions[0]["timeout"],
            json!(CURSOR_HOOK_TIMEOUT_SECONDS)
        );
        assert!(definitions[0]["command"].as_str().unwrap().contains(event));
    }
    // sessionStart would mark a freshly opened CLI as working.
    assert!(!hooks.contains_key("sessionStart"));
}

#[test]
fn the_shell_wrapper_drops_its_own_directory_before_resolving_cursor_agent() {
    let runtime = tempfile::tempdir().unwrap();

    let environment = overlay_for(runtime.path(), "session-1");

    let wrapper_directory = PathBuf::from(&environment["ALERA_AGENT_WRAPPER_PATH"]);
    let source = std::fs::read_to_string(wrapper_directory.join(wrapper_file_name())).unwrap();
    assert!(source.contains("--plugin-dir"));
    #[cfg(not(windows))]
    assert!(source.contains(&path_string(&wrapper_directory)));
    #[cfg(windows)]
    assert!(source.contains("%~f0"));
}

#[test]
fn a_relaunch_replaces_the_previous_overlay_for_the_same_session() {
    let runtime = tempfile::tempdir().unwrap();
    let environment = overlay_for(runtime.path(), "session-1");
    let plugin_root = PathBuf::from(&environment["ALERA_CURSOR_PLUGIN_DIR"]);
    let stale = plugin_root.join("hooks/stale.json");
    std::fs::write(&stale, "{}").unwrap();

    overlay_for(runtime.path(), "session-1");

    assert!(!stale.exists());
    assert!(plugin_root.join("hooks/hooks.json").is_file());
}

#[test]
fn startup_drops_every_session_overlay() {
    let runtime = tempfile::tempdir().unwrap();
    let overlay = overlay_for(runtime.path(), "session-1");
    let plugin_root = PathBuf::from(&overlay["ALERA_CURSOR_PLUGIN_DIR"]);
    overlay_for(runtime.path(), "session-2");

    // The host owns no PTY at start, so every session directory here is dead.
    clear_stale_state(runtime.path(), &tempfile::tempdir().unwrap().keep()).unwrap();

    assert!(!plugin_root.exists());
    assert!(!overlay_root(runtime.path()).exists());
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

    cleanup_user_hooks(home.path()).unwrap();

    let config = read_json_object(&path).unwrap().unwrap();
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

    cleanup_user_hooks(home.path()).unwrap();

    assert_eq!(std::fs::read_to_string(&path).unwrap(), before);
}

#[test]
fn cleanup_is_a_no_op_when_the_user_has_no_hooks_file() {
    let home = tempfile::tempdir().unwrap();

    cleanup_user_hooks(home.path()).unwrap();

    assert!(!home.path().join(".cursor/hooks.json").exists());
}
