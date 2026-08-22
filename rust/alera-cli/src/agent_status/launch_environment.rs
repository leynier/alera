use std::collections::BTreeMap;
use std::path::Path;

use alera_core::runtime::RuntimeAgentStatusHookSettings;

use super::fx_herdr_receiver::fx_herdr_socket_path;
use super::integration_config::prepare_enabled_integrations;

pub fn prepare_launch_environment(
    runtime_dir: &Path,
    session_id: &str,
    workspace_id: &str,
    tab_id: &str,
    settings: &RuntimeAgentStatusHookSettings,
    environment: &mut BTreeMap<String, String>,
) -> anyhow::Result<()> {
    restore_or_strip_managed_overlay(
        environment,
        "OPENCODE_CONFIG_DIR",
        "ALERA_OPENCODE_CONFIG_DIR",
        "ALERA_OPENCODE_SOURCE_CONFIG_DIR",
    );
    restore_or_strip_managed_overlay(
        environment,
        "HERDR_SOCKET_PATH",
        "ALERA_FX_HERDR_SOCKET_PATH",
        "ALERA_FX_SOURCE_HERDR_SOCKET_PATH",
    );
    restore_or_strip_managed_overlay(
        environment,
        "HERDR_PANE_ID",
        "ALERA_FX_HERDR_PANE_ID",
        "ALERA_FX_SOURCE_HERDR_PANE_ID",
    );
    restore_or_strip_managed_overlay(
        environment,
        "PI_CODING_AGENT_DIR",
        "ALERA_PI_CODING_AGENT_DIR",
        "ALERA_PI_SOURCE_AGENT_DIR",
    );
    restore_or_strip_managed_overlay(
        environment,
        "COPILOT_HOME",
        "ALERA_COPILOT_HOME",
        "ALERA_COPILOT_SOURCE_HOME",
    );
    strip_managed_primary(environment, "CODEX_HOME", "ALERA_CODEX_HOME");
    strip_managed_primary(environment, "CLAUDE_CONFIG_DIR", "ALERA_CLAUDE_CONFIG_DIR");
    strip_managed_wrapper_path(environment);
    environment.retain(|key, _| !is_managed_hook_key(key));
    environment.insert(
        "ALERA_TERMINAL_SESSION_ID".to_string(),
        session_id.to_string(),
    );
    environment.insert("ALERA_WORKSPACE_ID".to_string(), workspace_id.to_string());
    environment.insert("ALERA_TAB_ID".to_string(), tab_id.to_string());
    environment.insert(
        "ALERA_RUNTIME_DIR".to_string(),
        runtime_dir.to_string_lossy().into_owned(),
    );
    // Grok scans ~/.claude/settings.json and ~/.cursor/hooks.json by default.
    // Those files carry other agents' Alera hooks, which would POST as claude
    // or cursor for a Grok turn and steal the sidebar identity.
    environment.insert("GROK_CLAUDE_HOOKS_ENABLED".to_string(), "false".to_string());
    environment.insert("GROK_CURSOR_HOOKS_ENABLED".to_string(), "false".to_string());
    prepend_sidecar_directory(environment);
    #[cfg(unix)]
    if settings.fx {
        install_fx_herdr_environment(runtime_dir, session_id, environment);
    }
    if settings.enabled_agents().is_empty() {
        return Ok(());
    }
    let endpoint = runtime_dir.join("agent-hooks").join(if cfg!(windows) {
        "endpoint.cmd"
    } else {
        "endpoint.env"
    });
    environment.insert(
        "ALERA_AGENT_HOOK_ENDPOINT".to_string(),
        endpoint.to_string_lossy().into_owned(),
    );
    environment.insert("ALERA_AGENT_HOOK_VERSION".to_string(), "1".to_string());
    let _ = prepare_enabled_integrations(runtime_dir, Some(session_id), settings, environment);
    // Runs after the integrations because they are what mints the wrapper
    // directory; the strip above only removes values inherited from a parent
    // Alera terminal.
    prepend_managed_wrapper_path(environment);
    Ok(())
}

#[cfg(unix)]
fn install_fx_herdr_environment(
    runtime_dir: &Path,
    session_id: &str,
    environment: &mut BTreeMap<String, String>,
) {
    preserve_source_value(
        environment,
        "HERDR_SOCKET_PATH",
        "ALERA_FX_SOURCE_HERDR_SOCKET_PATH",
    );
    preserve_source_value(
        environment,
        "HERDR_PANE_ID",
        "ALERA_FX_SOURCE_HERDR_PANE_ID",
    );
    let socket_path = fx_herdr_socket_path(runtime_dir)
        .to_string_lossy()
        .into_owned();
    environment.insert("HERDR_SOCKET_PATH".to_string(), socket_path.clone());
    environment.insert("ALERA_FX_HERDR_SOCKET_PATH".to_string(), socket_path);
    environment.insert("HERDR_PANE_ID".to_string(), session_id.to_string());
    environment.insert("ALERA_FX_HERDR_PANE_ID".to_string(), session_id.to_string());
}

#[cfg(unix)]
fn preserve_source_value(environment: &mut BTreeMap<String, String>, primary: &str, source: &str) {
    if let Some(value) = environment
        .get(primary)
        .filter(|value| !value.is_empty())
        .cloned()
    {
        environment.insert(source.to_string(), value);
    }
}

fn restore_or_strip_managed_overlay(
    environment: &mut BTreeMap<String, String>,
    primary: &str,
    overlay: &str,
    source: &str,
) {
    let source_value = environment
        .get(source)
        .filter(|value| !value.is_empty())
        .cloned();
    let overlay_value = environment.get(overlay).cloned();
    if let Some(source_value) = source_value {
        environment.insert(primary.to_string(), source_value);
    } else if overlay_value.as_ref() == environment.get(primary) {
        environment.remove(primary);
    }
    environment.remove(overlay);
    environment.remove(source);
}

fn strip_managed_primary(environment: &mut BTreeMap<String, String>, primary: &str, overlay: &str) {
    if environment.get(overlay) == environment.get(primary) {
        environment.remove(primary);
    }
    environment.remove(overlay);
}

fn strip_managed_wrapper_path(environment: &mut BTreeMap<String, String>) {
    let Some(wrapper_path) = environment.remove("ALERA_AGENT_WRAPPER_PATH") else {
        return;
    };
    let wrappers = std::env::split_paths(&wrapper_path).collect::<Vec<_>>();
    let Some(path) = environment.get("PATH") else {
        return;
    };
    let entries = std::env::split_paths(path)
        .filter(|entry| !wrappers.iter().any(|wrapper| same_path(entry, wrapper)))
        .collect::<Vec<_>>();
    if let Ok(path) = std::env::join_paths(entries) {
        environment.insert("PATH".to_string(), path.to_string_lossy().into_owned());
    }
}

fn prepend_managed_wrapper_path(environment: &mut BTreeMap<String, String>) {
    let Some(wrapper_path) = environment.get("ALERA_AGENT_WRAPPER_PATH").cloned() else {
        return;
    };
    let wrappers = std::env::split_paths(&wrapper_path).collect::<Vec<_>>();
    if wrappers.is_empty() {
        return;
    }
    let mut entries = wrappers.clone();
    if let Some(current) = environment.get("PATH") {
        entries.extend(
            std::env::split_paths(current)
                .filter(|entry| !wrappers.iter().any(|wrapper| same_path(entry, wrapper))),
        );
    }
    if let Ok(path) = std::env::join_paths(entries) {
        environment.insert("PATH".to_string(), path.to_string_lossy().into_owned());
    }
}

fn prepend_sidecar_directory(environment: &mut BTreeMap<String, String>) {
    let Some(directory) = std::env::current_exe()
        .ok()
        .and_then(|executable| executable.parent().map(Path::to_path_buf))
    else {
        return;
    };
    let mut entries = vec![directory.clone()];
    if let Some(current) = environment.get("PATH") {
        entries
            .extend(std::env::split_paths(current).filter(|entry| !same_path(entry, &directory)));
    }
    if let Ok(path) = std::env::join_paths(entries) {
        environment.insert("PATH".to_string(), path.to_string_lossy().into_owned());
    }
}

fn same_path(left: &Path, right: &Path) -> bool {
    if cfg!(windows) {
        left.to_string_lossy()
            .eq_ignore_ascii_case(&right.to_string_lossy())
    } else {
        left == right
    }
}

fn is_managed_hook_key(key: &str) -> bool {
    key == "ALERA_AGENT_HOOK_ENDPOINT"
        || key == "ALERA_AGENT_HOOK_PORT"
        || key == "ALERA_AGENT_HOOK_TOKEN"
        || key == "ALERA_AGENT_HOOK_VERSION"
        || key == "ALERA_TERMINAL_SESSION_ID"
        || key == "ALERA_WORKSPACE_ID"
        || key == "ALERA_TAB_ID"
        || key == "ALERA_RUNTIME_DIR"
        || key == "ALERA_CODEX_HOME"
        || key == "ALERA_CLAUDE_CONFIG_DIR"
        || key == "ALERA_COPILOT_HOME"
        || key == "ALERA_COPILOT_SOURCE_HOME"
        || key == "ALERA_OPENCODE_CONFIG_DIR"
        || key == "ALERA_OPENCODE_SOURCE_CONFIG_DIR"
        || key == "ALERA_PI_CODING_AGENT_DIR"
        || key == "ALERA_PI_SOURCE_AGENT_DIR"
        || key == "ALERA_CURSOR_PLUGIN_DIR"
        || key == "ALERA_AMP_CONFIG_DIR"
        || key == "ALERA_AMP_SOURCE_CONFIG_DIR"
        || key == "ALERA_AGENT_WRAPPER_PATH"
        || key == "ALERA_FX_HERDR_SOCKET_PATH"
        || key == "ALERA_FX_SOURCE_HERDR_SOCKET_PATH"
        || key == "ALERA_FX_HERDR_PANE_ID"
        || key == "ALERA_FX_SOURCE_HERDR_PANE_ID"
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn runtime_identity_and_sidecar_path_do_not_require_agent_hooks() {
        let runtime_dir = Path::new("/runtime/custom");
        let mut environment = BTreeMap::from([
            (
                "ALERA_RUNTIME_DIR".to_string(),
                "/runtime/stale".to_string(),
            ),
            (
                "PATH".to_string(),
                std::env::var("PATH").unwrap_or_default(),
            ),
        ]);

        prepare_launch_environment(
            runtime_dir,
            "session-1",
            "workspace-1",
            "tab-1",
            &RuntimeAgentStatusHookSettings::default(),
            &mut environment,
        )
        .unwrap();

        assert_eq!(environment["ALERA_RUNTIME_DIR"], "/runtime/custom");
        assert_eq!(environment["ALERA_TERMINAL_SESSION_ID"], "session-1");
        assert_eq!(environment["ALERA_WORKSPACE_ID"], "workspace-1");
        assert_eq!(environment["ALERA_TAB_ID"], "tab-1");
        let executable_dir = std::env::current_exe()
            .unwrap()
            .parent()
            .unwrap()
            .to_path_buf();
        assert_eq!(
            std::env::split_paths(&environment["PATH"]).next(),
            Some(executable_dir)
        );
        assert!(!environment.contains_key("ALERA_AGENT_HOOK_ENDPOINT"));
        assert_eq!(environment["GROK_CLAUDE_HOOKS_ENABLED"], "false");
        assert_eq!(environment["GROK_CURSOR_HOOKS_ENABLED"], "false");
    }

    #[test]
    fn login_merged_path_keeps_sidecar_first_and_preserves_login_only_entries() {
        let executable_dir = std::env::current_exe()
            .unwrap()
            .parent()
            .unwrap()
            .to_path_buf();
        let login_only = std::env::temp_dir().join("alera-login-only-bin");
        let path = std::env::join_paths([
            login_only.clone(),
            Path::new("/usr/bin").to_path_buf(),
            Path::new("/bin").to_path_buf(),
        ])
        .unwrap()
        .to_string_lossy()
        .into_owned();
        let mut environment = BTreeMap::from([("PATH".to_string(), path)]);

        prepare_launch_environment(
            Path::new("/runtime/custom"),
            "session-1",
            "workspace-1",
            "tab-1",
            &RuntimeAgentStatusHookSettings::default(),
            &mut environment,
        )
        .unwrap();

        let entries = std::env::split_paths(&environment["PATH"]).collect::<Vec<_>>();
        assert_eq!(entries.first(), Some(&executable_dir));
        assert!(entries.contains(&login_only));
    }

    // The strip above runs on every launch to clear values inherited from a
    // parent Alera terminal. An integration that mints a wrapper for this
    // launch does it afterwards, and its directory has to reach PATH or the
    // wrapper is never the one that runs.
    #[test]
    fn a_wrapper_minted_for_this_launch_leads_the_path() {
        let wrapper = std::env::temp_dir().join("alera-fresh-wrapper");
        let existing = std::env::temp_dir().join("alera-existing-entry");
        let mut environment = BTreeMap::from([
            (
                "PATH".to_string(),
                std::env::join_paths([existing.clone()])
                    .unwrap()
                    .to_string_lossy()
                    .into_owned(),
            ),
            (
                "ALERA_AGENT_WRAPPER_PATH".to_string(),
                wrapper.to_string_lossy().into_owned(),
            ),
        ]);

        prepend_managed_wrapper_path(&mut environment);

        let entries = std::env::split_paths(&environment["PATH"]).collect::<Vec<_>>();
        assert_eq!(entries, vec![wrapper, existing]);
    }

    #[test]
    fn a_wrapper_already_on_the_path_is_not_duplicated() {
        let wrapper = std::env::temp_dir().join("alera-fresh-wrapper");
        let mut environment = BTreeMap::from([
            (
                "PATH".to_string(),
                std::env::join_paths([wrapper.clone(), std::env::temp_dir()])
                    .unwrap()
                    .to_string_lossy()
                    .into_owned(),
            ),
            (
                "ALERA_AGENT_WRAPPER_PATH".to_string(),
                wrapper.to_string_lossy().into_owned(),
            ),
        ]);

        prepend_managed_wrapper_path(&mut environment);

        let entries = std::env::split_paths(&environment["PATH"]).collect::<Vec<_>>();
        assert_eq!(entries, vec![wrapper, std::env::temp_dir()]);
    }

    #[test]
    fn inherited_agent_overlays_are_restored_or_removed_before_launch() {
        let wrapper = std::env::temp_dir().join("alera-wrapper-test");
        let retained = std::env::temp_dir().join("alera-retained-test");
        let path = std::env::join_paths([wrapper.clone(), retained.clone()])
            .unwrap()
            .to_string_lossy()
            .into_owned();
        let mut environment = BTreeMap::from([
            ("PATH".to_string(), path),
            (
                "ALERA_AGENT_WRAPPER_PATH".to_string(),
                wrapper.to_string_lossy().into_owned(),
            ),
            ("CODEX_HOME".to_string(), "/managed/codex".to_string()),
            ("ALERA_CODEX_HOME".to_string(), "/managed/codex".to_string()),
            (
                "OPENCODE_CONFIG_DIR".to_string(),
                "/managed/opencode".to_string(),
            ),
            (
                "ALERA_OPENCODE_CONFIG_DIR".to_string(),
                "/managed/opencode".to_string(),
            ),
            (
                "ALERA_OPENCODE_SOURCE_CONFIG_DIR".to_string(),
                "/user/opencode".to_string(),
            ),
        ]);

        prepare_launch_environment(
            Path::new("/runtime/custom"),
            "session-1",
            "workspace-1",
            "tab-1",
            &RuntimeAgentStatusHookSettings::default(),
            &mut environment,
        )
        .unwrap();

        assert!(!environment.contains_key("CODEX_HOME"));
        assert!(!environment.contains_key("ALERA_CODEX_HOME"));
        assert_eq!(environment["OPENCODE_CONFIG_DIR"], "/user/opencode");
        assert!(!environment.contains_key("ALERA_OPENCODE_CONFIG_DIR"));
        let path_entries = std::env::split_paths(&environment["PATH"]).collect::<Vec<_>>();
        assert!(!path_entries.contains(&wrapper));
        assert!(path_entries.contains(&retained));
    }

    #[cfg(unix)]
    #[test]
    fn fx_herdr_overlay_uses_the_session_and_restores_inherited_values() {
        let runtime_dir = Path::new("/runtime/custom");
        let mut environment = BTreeMap::from([
            (
                "HERDR_SOCKET_PATH".to_string(),
                "/user/herdr.sock".to_string(),
            ),
            ("HERDR_PANE_ID".to_string(), "user-pane".to_string()),
        ]);

        prepare_launch_environment(
            runtime_dir,
            "session-1",
            "workspace-1",
            "tab-1",
            &RuntimeAgentStatusHookSettings {
                fx: true,
                ..RuntimeAgentStatusHookSettings::default()
            },
            &mut environment,
        )
        .unwrap();

        assert_eq!(
            environment["HERDR_SOCKET_PATH"],
            fx_herdr_socket_path(runtime_dir).to_string_lossy()
        );
        assert_eq!(environment["HERDR_PANE_ID"], "session-1");
        assert_eq!(
            environment["ALERA_FX_SOURCE_HERDR_SOCKET_PATH"],
            "/user/herdr.sock"
        );
        assert_eq!(environment["ALERA_FX_SOURCE_HERDR_PANE_ID"], "user-pane");

        prepare_launch_environment(
            runtime_dir,
            "session-2",
            "workspace-1",
            "tab-2",
            &RuntimeAgentStatusHookSettings::default(),
            &mut environment,
        )
        .unwrap();

        assert_eq!(environment["HERDR_SOCKET_PATH"], "/user/herdr.sock");
        assert_eq!(environment["HERDR_PANE_ID"], "user-pane");
        assert!(!environment.contains_key("ALERA_FX_HERDR_SOCKET_PATH"));
        assert!(!environment.contains_key("ALERA_FX_SOURCE_HERDR_SOCKET_PATH"));
        assert!(!environment.contains_key("ALERA_FX_HERDR_PANE_ID"));
        assert!(!environment.contains_key("ALERA_FX_SOURCE_HERDR_PANE_ID"));
    }
}
