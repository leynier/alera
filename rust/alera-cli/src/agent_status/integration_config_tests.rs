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
fn omits_the_matcher_key_for_events_without_a_matcher() {
    let definition = managed_hook_definition(None, "/home/user/hook.sh");

    assert_eq!(
        definition,
        json!({ "hooks": [{ "type": "command", "command": "/home/user/hook.sh" }] })
    );
    assert!(definition.get("matcher").is_none());
}

#[test]
fn keeps_the_matcher_key_for_tool_scoped_events() {
    let definition = managed_hook_definition(Some("*"), "/home/user/hook.sh");

    assert_eq!(definition["matcher"], json!("*"));
}

fn agy_bundle(config: &Map<String, Value>) -> &Map<String, Value> {
    config["alera-status"].as_object().expect("bundle object")
}

#[test]
fn agy_bundle_uses_the_documented_lifecycle_and_tool_schemas() {
    let mut config = Map::new();

    apply_agy_bundle(
        &mut config,
        Path::new("/home/user/.alera/agent-hooks/hook.sh"),
    );

    let bundle = agy_bundle(&config);
    for event in ["PreInvocation", "PostInvocation", "Stop"] {
        let definition = bundle[event].as_array().expect("array")[0].clone();
        assert_eq!(definition["type"], json!("command"));
        assert_eq!(definition["timeout"], json!(10));
        assert!(definition.get("hooks").is_none(), "{event} must stay flat");
    }
    let tool = bundle["PostToolUse"].as_array().expect("array")[0].clone();
    assert_eq!(tool["matcher"], json!("*"));
    let handler = tool["hooks"].as_array().expect("array")[0].clone();
    assert_eq!(handler["type"], json!("command"));
    // Without this the handler inherits Antigravity's documented 30s default.
    assert_eq!(handler["timeout"], json!(10));
    // Antigravity requires a permission decision from PreToolUse, so Alera's
    // observational hook must not register it.
    assert!(bundle.get("PreToolUse").is_none());
}

#[test]
fn agy_bundle_keeps_user_entries_and_drops_alera_ones() {
    let mut config = Map::from_iter([(
        "alera-status".to_string(),
        json!({
            "enabled": false,
            "Stop": [
                { "type": "command", "command": "echo user" },
                { "type": "command", "command": "/home/user/.alera/agent-hooks/alera-agy-hook.sh" },
                { "type": "command", "command": "/home/user/.alera/agent-hooks/alera-runtime-agent-hook.sh" }
            ]
        }),
    )]);

    apply_agy_bundle(
        &mut config,
        Path::new("/home/user/.alera/agent-hooks/hook.sh"),
    );

    let bundle = agy_bundle(&config);
    // Installing is an explicit enable, so the documented opt-out cannot stay.
    assert!(bundle.get("enabled").is_none());
    let stop = bundle["Stop"].as_array().expect("array");
    assert_eq!(stop.len(), 2, "one user handler plus one Alera handler");
    assert_eq!(stop[0]["command"], json!("echo user"));
    assert!(stop[1]["command"]
        .as_str()
        .expect("command")
        .contains("hook.sh"));
}

#[cfg(windows)]
#[test]
fn agy_bundle_drops_desktop_windows_wrapper_handlers() {
    let mut config = Map::from_iter([(
        "alera-status".to_string(),
        json!({
            "Stop": [
                { "type": "command", "command": "C:\\Users\\u\\.alera\\agent-hooks\\alera-agy-stop.cmd" }
            ]
        }),
    )]);

    apply_agy_bundle(
        &mut config,
        Path::new("C:\\Users\\u\\.alera\\agent-hooks\\hook.cmd"),
    );

    assert_eq!(
        agy_bundle(&config)["Stop"].as_array().expect("array").len(),
        1
    );
}

#[test]
fn claude_cleanup_removes_alera_definitions_and_keeps_the_users_own() {
    let home = tempfile::tempdir().unwrap();
    let path = home.path().join(".claude/settings.json");
    write_json_object(
        &path,
        &Map::from_iter([
            ("model".to_string(), json!("opus")),
            (
                "hooks".to_string(),
                json!({
                    "PreToolUse": [
                        {
                            "matcher": "*",
                            "hooks": [{
                                "type": "command",
                                "command": "/home/user/.orca/agent-hooks/claude-hook.sh"
                            }]
                        },
                        {
                            "matcher": "*",
                            "hooks": [{
                                "type": "command",
                                "command": "if [ -x '/home/user/.alera/agent-hooks/alera-claude-hook.sh' ]; then ALERA_AGENT_HOOK_EVENT='PreToolUse' /bin/sh '/home/user/.alera/agent-hooks/alera-claude-hook.sh'; fi"
                            }]
                        }
                    ],
                    "Stop": [
                        {
                            "hooks": [{
                                "type": "command",
                                "command": "ALERA_AGENT_TYPE='claude' ALERA_AGENT_HOOK_EVENT='Stop' /bin/sh '/home/user/.alera/agent-hooks/alera-runtime-agent-hook.sh'"
                            }]
                        }
                    ]
                }),
            ),
        ]),
    )
    .unwrap();

    user_hooks::cleanup_claude_user_hooks(home.path()).unwrap();

    let config = read_json_object(&path).unwrap().unwrap();
    assert_eq!(config["model"], json!("opus"));
    let hooks = config["hooks"].as_object().unwrap();
    assert_eq!(hooks["PreToolUse"].as_array().unwrap().len(), 1);
    assert!(hooks["PreToolUse"]
        .to_string()
        .contains(".orca/agent-hooks"));
    assert!(!hooks["PreToolUse"]
        .to_string()
        .contains("alera-claude-hook"));
    assert!(!hooks.contains_key("Stop"));
}

#[test]
fn claude_cleanup_also_strips_settings_local_json() {
    let home = tempfile::tempdir().unwrap();
    let path = home.path().join(".claude/settings.local.json");
    write_json_object(
        &path,
        &Map::from_iter([(
            "hooks".to_string(),
            json!({
                "UserPromptSubmit": [
                    {"hooks": [{"type": "command", "command": "/home/user/.alera/agent-hooks/alera-claude-hook.sh"}]}
                ]
            }),
        )]),
    )
    .unwrap();

    user_hooks::cleanup_claude_user_hooks(home.path()).unwrap();

    let config = read_json_object(&path).unwrap().unwrap();
    assert!(!config.contains_key("hooks"));
}

#[test]
fn claude_cleanup_is_a_no_op_when_the_user_has_no_settings_file() {
    let home = tempfile::tempdir().unwrap();

    user_hooks::cleanup_claude_user_hooks(home.path()).unwrap();

    assert!(!home.path().join(".claude/settings.json").exists());
}

#[test]
fn claude_cleanup_continues_after_an_unparseable_settings_file() {
    let home = tempfile::tempdir().unwrap();
    let invalid = home.path().join(".claude/settings.json");
    std::fs::create_dir_all(invalid.parent().unwrap()).unwrap();
    std::fs::write(&invalid, "{not json").unwrap();
    let local = home.path().join(".claude/settings.local.json");
    write_json_object(
        &local,
        &Map::from_iter([(
            "hooks".to_string(),
            json!({
                "Stop": [
                    {"hooks": [{"type": "command", "command": "/home/user/.alera/agent-hooks/alera-claude-hook.sh"}]}
                ]
            }),
        )]),
    )
    .unwrap();

    let error = user_hooks::cleanup_claude_user_hooks(home.path()).unwrap_err();
    assert!(error.to_string().contains("settings.json"));

    let config = read_json_object(&local).unwrap().unwrap();
    assert!(!config.contains_key("hooks"));
    assert_eq!(std::fs::read_to_string(&invalid).unwrap(), "{not json");
}

#[test]
fn claude_cleanup_strips_alera_hooks_from_jsonc_settings() {
    let home = tempfile::tempdir().unwrap();
    let path = home.path().join(".claude/settings.json");
    std::fs::create_dir_all(path.parent().unwrap()).unwrap();
    std::fs::write(
        &path,
        r#"{
  // keep this file loadable
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "*",
        "hooks": [{ "type": "command", "command": "/home/user/audit.sh" }]
      },
      {
        "matcher": "*",
        "hooks": [{
          "type": "command",
          "command": "/home/user/.alera/agent-hooks/alera-claude-hook.sh"
        }]
      }
    ]
  }
}
"#,
    )
    .unwrap();

    user_hooks::cleanup_claude_user_hooks(home.path()).unwrap();

    let config = read_json_object(&path).unwrap().unwrap();
    let hooks = config["hooks"].as_object().unwrap();
    assert_eq!(hooks["PreToolUse"].as_array().unwrap().len(), 1);
    assert!(hooks["PreToolUse"].to_string().contains("audit.sh"));
    assert!(!hooks["PreToolUse"]
        .to_string()
        .contains("alera-claude-hook"));
}

#[test]
fn claude_cleanup_leaves_ccs_files_alone() {
    let home = tempfile::tempdir().unwrap();
    let shared = home.path().join(".ccs/shared/settings.json");
    write_json_object(
        &shared,
        &Map::from_iter([(
            "hooks".to_string(),
            json!({
                "Stop": [
                    {"hooks": [{"type": "command", "command": "/home/user/.alera/agent-hooks/alera-claude-hook.sh"}]}
                ]
            }),
        )]),
    )
    .unwrap();
    let instance = home.path().join(".ccs/instances/profile-a");
    std::fs::create_dir_all(&instance).unwrap();
    write_json_object(
        &instance.join("settings.local.json"),
        &Map::from_iter([(
            "hooks".to_string(),
            json!({
                "Stop": [
                    {"hooks": [{"type": "command", "command": "/home/user/.alera/agent-hooks/alera-runtime-agent-hook.sh"}]}
                ]
            }),
        )]),
    )
    .unwrap();

    user_hooks::cleanup_claude_user_hooks(home.path()).unwrap();

    let shared_config = read_json_object(&shared).unwrap().unwrap();
    assert!(shared_config["hooks"]
        .to_string()
        .contains("alera-claude-hook"));
    let local_config = read_json_object(&instance.join("settings.local.json"))
        .unwrap()
        .unwrap();
    assert!(local_config["hooks"]
        .to_string()
        .contains("alera-runtime-agent-hook"));
}

/// The install target is the file a CCS instance's `settings.json` resolves to,
/// because CCS overrides `CLAUDE_CONFIG_DIR` and Claude reads only
/// `settings.json` from a config directory.
#[cfg(unix)]
#[test]
fn claude_user_hooks_reach_every_ccs_account_through_the_shared_symlink() {
    let home = tempfile::tempdir().unwrap();
    let user_settings = home.path().join(".claude/settings.json");
    write_json_object(
        &user_settings,
        &Map::from_iter([("model".to_string(), json!("opus"))]),
    )
    .unwrap();
    let shared = home.path().join(".ccs/shared/settings.json");
    std::fs::create_dir_all(shared.parent().unwrap()).unwrap();
    std::os::unix::fs::symlink(&user_settings, &shared).unwrap();
    let instance = home.path().join(".ccs/instances/educup");
    std::fs::create_dir_all(&instance).unwrap();
    std::os::unix::fs::symlink(&shared, instance.join("settings.json")).unwrap();

    user_hooks::install_claude_user_hooks(
        home.path(),
        Path::new("/home/user/.alera/agent-hooks/alera-runtime-agent-hook.sh"),
    )
    .unwrap();

    let through_the_instance = read_json_object(&instance.join("settings.json"))
        .unwrap()
        .unwrap();
    assert_eq!(through_the_instance["model"], json!("opus"));
    for (event, _) in CLAUDE_HOOK_EVENTS {
        assert!(
            through_the_instance["hooks"][event]
                .to_string()
                .contains("alera-runtime-agent-hook"),
            "{event} is missing from the CCS instance view"
        );
    }
}

#[test]
fn claude_user_hooks_install_keeps_the_users_own_definitions() {
    let home = tempfile::tempdir().unwrap();
    let user_settings = home.path().join(".claude/settings.json");
    write_json_object(
        &user_settings,
        &Map::from_iter([(
            "hooks".to_string(),
            json!({
                "Stop": [
                    {"hooks": [{"type": "command", "command": "echo user"}]}
                ],
                "SessionStart": [
                    {"hooks": [{"type": "command", "command": "echo start"}]}
                ]
            }),
        )]),
    )
    .unwrap();

    user_hooks::install_claude_user_hooks(
        home.path(),
        Path::new("/home/user/.alera/agent-hooks/alera-runtime-agent-hook.sh"),
    )
    .unwrap();

    let settings = read_json_object(&user_settings).unwrap().unwrap();
    assert!(settings["hooks"]["Stop"].to_string().contains("echo user"));
    assert!(settings["hooks"]["Stop"]
        .to_string()
        .contains("alera-runtime-agent-hook"));
    assert!(settings["hooks"]["SessionStart"]
        .to_string()
        .contains("echo start"));
    assert!(!settings["hooks"]["SessionStart"]
        .to_string()
        .contains("alera-runtime-agent-hook"));
}

/// The file belongs to the user and every reconcile passes through here, so a
/// second install must not rewrite it.
#[test]
fn claude_user_hooks_install_leaves_an_up_to_date_file_untouched() {
    let home = tempfile::tempdir().unwrap();
    let user_settings = home.path().join(".claude/settings.json");
    let script = Path::new("/home/user/.alera/agent-hooks/alera-runtime-agent-hook.sh");
    user_hooks::install_claude_user_hooks(home.path(), script).unwrap();
    let after_install = std::fs::read(&user_settings).unwrap();
    std::fs::write(&user_settings, &after_install).unwrap();
    let before = std::fs::metadata(&user_settings)
        .unwrap()
        .modified()
        .unwrap();

    user_hooks::install_claude_user_hooks(home.path(), script).unwrap();

    assert_eq!(
        std::fs::metadata(&user_settings)
            .unwrap()
            .modified()
            .unwrap(),
        before
    );
}

#[test]
fn claude_user_hooks_install_refreshes_a_stale_script_path() {
    let home = tempfile::tempdir().unwrap();
    let user_settings = home.path().join(".claude/settings.json");
    user_hooks::install_claude_user_hooks(
        home.path(),
        Path::new("/old/alera-runtime-agent-hook.sh"),
    )
    .unwrap();

    user_hooks::install_claude_user_hooks(
        home.path(),
        Path::new("/new/alera-runtime-agent-hook.sh"),
    )
    .unwrap();

    let settings = read_json_object(&user_settings).unwrap().unwrap();
    let hooks = settings["hooks"].to_string();
    assert!(hooks.contains("/new/alera-runtime-agent-hook.sh"));
    assert!(!hooks.contains("/old/alera-runtime-agent-hook.sh"));
}
