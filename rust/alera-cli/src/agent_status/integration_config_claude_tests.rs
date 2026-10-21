use super::super::{ccs, read_json_object, user_hooks, write_json_object};
use super::*;
use std::collections::BTreeMap;

fn mixed_definition() -> Value {
    json!({
        "matcher": "Read|Bash",
        "description": "User matcher metadata",
        "hooks": [
            {"type": "command", "command": "echo first", "timeout": 12},
            {"type": "command", "command": "cmd /c C:\\old\\alera-claude-hook.cmd"},
            {"type": "command", "command": "cmd /c C:\\old\\alera-runtime-agent-hook.cmd"},
            {"type": "command", "command": "powershell.exe -File 'C:\\old\\alera-runtime-agent-hook.ps1'"},
            {"type": "command", "command": "echo last", "async": true}
        ]
    })
}

fn user_definition() -> Value {
    let mut definition = mixed_definition();
    definition["hooks"] = json!([
        {"type": "command", "command": "echo first", "timeout": 12},
        {"type": "command", "command": "echo last", "async": true}
    ]);
    definition
}

#[test]
fn claude_migration_keeps_the_existing_events_and_matchers() {
    assert_eq!(
        CLAUDE_HOOK_EVENTS,
        &[
            ("SessionStart", None),
            ("SessionEnd", None),
            ("UserPromptSubmit", None),
            ("Stop", None),
            ("StopFailure", None),
            ("Notification", None),
            ("SubagentStart", None),
            ("SubagentStop", None),
            ("PreToolUse", Some("*")),
            ("PostToolUse", Some("*")),
            ("PostToolUseFailure", Some("*")),
            ("PermissionRequest", Some("*")),
        ]
    );
}

#[test]
fn claude_filter_preserves_matcher_metadata_and_handler_order() {
    let empty = json!({"matcher": "empty", "hooks": []});
    let unknown = json!({"future": true});
    let user_after = json!({"hooks": [{"type": "command", "command": "echo after"}]});
    let cleaned = clean_claude_definitions(Some(json!([
        mixed_definition(),
        {"hooks": [{"type": "command", "command": "alera-claude-hook.sh"}]},
        empty,
        unknown,
        user_after
    ])));

    assert_eq!(cleaned, vec![user_definition(), empty, unknown, user_after]);
}

#[test]
fn claude_filter_ignores_markers_in_user_metadata_and_prompt_text() {
    let definitions = json!([
        {"matcher": "alera-runtime-agent-hook", "hooks": [
            {"type": "prompt", "prompt": "Review alera-claude-hook.cmd"},
            {"type": "command", "command": "echo user", "description": "alera-runtime-agent-hook.ps1"}
        ]},
        {"hooks": {"future": "alera-runtime-agent-hook"}},
        {"hooks": []},
        "future"
    ]);

    assert_eq!(
        clean_claude_definitions(Some(definitions.clone())),
        definitions.as_array().unwrap().clone()
    );
}

#[test]
fn claude_install_migrates_mixed_handlers_without_losing_user_settings() {
    let home = tempfile::tempdir().unwrap();
    let path = home.path().join(".claude/settings.json");
    let unchanged_event = json!([{"hooks": [{"type": "command", "command": "echo future"}]}]);
    write_json_object(
        &path,
        &Map::from_iter([
            ("model".to_string(), json!("opus")),
            ("permissions".to_string(), json!({"allow": ["Read"]})),
            (
                "hooks".to_string(),
                json!({"PreToolUse": [mixed_definition()], "FutureEvent": unchanged_event}),
            ),
        ]),
    )
    .unwrap();
    let script = Path::new(r"C:\new home\alera-runtime-agent-hook.ps1");

    user_hooks::install_claude_user_hooks(home.path(), script).unwrap();

    let installed = read_json_object(&path).unwrap().unwrap();
    assert_eq!(installed["model"], json!("opus"));
    assert_eq!(installed["permissions"], json!({"allow": ["Read"]}));
    assert_eq!(installed["hooks"]["FutureEvent"], unchanged_event);
    assert_eq!(installed["hooks"]["PreToolUse"][0], user_definition());
    assert_eq!(
        installed["hooks"]["PreToolUse"].as_array().unwrap().len(),
        2
    );
    for (event, matcher) in CLAUDE_HOOK_EVENTS {
        let definition = installed["hooks"][event]
            .as_array()
            .unwrap()
            .last()
            .unwrap();
        assert_eq!(
            definition.get("matcher").cloned(),
            matcher.map(|matcher| json!(matcher))
        );
        let handler = &definition["hooks"][0];
        assert_eq!(handler["type"], "command");
        assert!(handler["command"].is_string());
        assert!(handler.get("args").is_none());
        assert!(handler.get("shell").is_none());
        assert!(!handler["command"].as_str().unwrap().contains("C:\\old"));
        if *event == "SessionEnd" {
            assert_eq!(handler["timeout"], 5);
        }
    }
    let first_bytes = std::fs::read(&path).unwrap();
    let modified = std::fs::metadata(&path).unwrap().modified().unwrap();

    user_hooks::install_claude_user_hooks(home.path(), script).unwrap();

    assert_eq!(std::fs::read(&path).unwrap(), first_bytes);
    assert_eq!(
        std::fs::metadata(&path).unwrap().modified().unwrap(),
        modified
    );
}

#[test]
fn claude_cleanup_persists_nested_removals_in_main_local_and_ccs_settings() {
    let home = tempfile::tempdir().unwrap();
    let paths = [
        ".claude/settings.json",
        ".claude/settings.local.json",
        ".ccs/shared/settings.json",
        ".ccs/instances/work/settings.json",
        ".ccs/instances/work/settings.local.json",
    ];
    for relative in paths {
        write_json_object(
            &home.path().join(relative),
            &Map::from_iter([
                ("model".to_string(), json!("opus")),
                ("hooks".to_string(), json!({
                    "PreToolUse": [mixed_definition()],
                    "Stop": [{"hooks": [{"type": "command", "command": "alera-runtime-agent-hook.ps1"}]}]
                })),
            ]),
        )
        .unwrap();
    }

    user_hooks::cleanup_claude_user_hooks(home.path()).unwrap();
    ccs::remove_ccs_claude_hooks(home.path(), &BTreeMap::new()).unwrap();

    for relative in paths {
        let path = home.path().join(relative);
        let settings = read_json_object(&path).unwrap().unwrap();
        assert_eq!(settings["model"], "opus");
        assert_eq!(
            settings["hooks"],
            json!({"PreToolUse": [user_definition()]})
        );
        let bytes = std::fs::read(&path).unwrap();
        let modified = std::fs::metadata(&path).unwrap().modified().unwrap();
        user_hooks::cleanup_claude_hooks_file(&path).unwrap();
        assert_eq!(std::fs::read(&path).unwrap(), bytes);
        assert_eq!(
            std::fs::metadata(&path).unwrap().modified().unwrap(),
            modified
        );
    }
}
