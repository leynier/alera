use super::*;

#[test]
fn host_accessible_path_resolves_relative_paths_against_current_dir() {
    let current_dir = std::env::temp_dir().join("alera-cli-path-test");
    let resolved = host_accessible_path("runtime/archive.json".to_string(), &current_dir);

    assert_eq!(resolved, current_dir.join("runtime/archive.json"));
}

#[test]
fn host_accessible_path_keeps_absolute_paths() {
    let current_dir = Path::new("ignored");
    let absolute_path = std::env::temp_dir().join("alera-runtime.tar.gz");
    let resolved = host_accessible_path(absolute_path.to_string_lossy().into_owned(), current_dir);

    assert_eq!(resolved, absolute_path);
}

#[test]
fn workspace_path_value_trims_empty_arguments() {
    assert_eq!(normalized_workspace_path_value(" \t "), None);
    assert_eq!(
        normalized_workspace_path_value(" relative-worktree "),
        Some("relative-worktree".to_string())
    );
}

#[test]
fn host_accessible_path_resolves_relative_workspace_paths_for_rpc() {
    let current_dir = std::env::temp_dir().join("alera-cli-workspace-path-test");
    let resolved = host_accessible_path(
        normalized_workspace_path_value("relative-worktree").unwrap(),
        &current_dir,
    );

    assert_eq!(resolved, current_dir.join("relative-worktree"));
}

#[test]
fn terminal_actions_require_the_capability_for_their_rpc_surface() {
    use crate::cli::{TerminalReadArgs, TerminalWriteArgs};
    use crate::cli_orchestration::{
        OrchestrationTerminalListArgs, OrchestrationTerminalPruneArgs,
        OrchestrationTerminalShowArgs, OrchestrationTerminalWaitArgs,
    };
    use crate::terminal_host::protocol::{
        RUNTIME_HOST_ORCHESTRATION_TERMINAL_INSPECTION_CAPABILITY,
        RUNTIME_HOST_ORCHESTRATION_WAIT_CAPABILITY,
        RUNTIME_HOST_TERMINAL_DEFERRED_INPUT_CAPABILITY,
    };

    let list = TerminalAction::List(OrchestrationTerminalListArgs { workspace: None });
    let show = TerminalAction::Show(OrchestrationTerminalShowArgs {
        handle: "term-1".to_string(),
    });
    let prune = TerminalAction::Prune(OrchestrationTerminalPruneArgs {
        workspace: None,
        apply: false,
    });
    let wait = TerminalAction::Wait(OrchestrationTerminalWaitArgs {
        terminal: "term-1".to_string(),
        target: "agent-ready".to_string(),
        timeout_ms: 30_000,
    });
    let read = TerminalAction::Read(TerminalReadArgs {
        handle: "term-1".to_string(),
        cursor: None,
        max_bytes: 1024,
    });
    let write = |enter, submit| {
        TerminalAction::Write(TerminalWriteArgs {
            handle: "term-1".to_string(),
            text: Some("input".to_string()),
            file: None,
            stdin: false,
            enter,
            submit,
        })
    };

    for action in [&list, &show, &prune] {
        assert_eq!(
            terminal_alias_commands::required_capability(action),
            Some(RUNTIME_HOST_ORCHESTRATION_TERMINAL_INSPECTION_CAPABILITY)
        );
    }
    assert_eq!(
        terminal_alias_commands::required_capability(&wait),
        Some(RUNTIME_HOST_ORCHESTRATION_WAIT_CAPABILITY)
    );
    assert_eq!(terminal_alias_commands::required_capability(&read), None);
    assert_eq!(
        terminal_alias_commands::required_capability(&write(false, false)),
        None
    );
    assert_eq!(
        terminal_alias_commands::required_capability(&write(true, false)),
        Some(RUNTIME_HOST_TERMINAL_DEFERRED_INPUT_CAPABILITY)
    );
    assert_eq!(
        terminal_alias_commands::required_capability(&write(false, true)),
        Some(RUNTIME_HOST_TERMINAL_DEFERRED_INPUT_CAPABILITY)
    );
}

#[test]
fn browser_tab_creation_never_carries_terminal_spawn_metadata() {
    let tab = tab_from_args(crate::cli::TabCreateArgs {
        workspace_id: "workspace-1".to_string(),
        title: "Browser".to_string(),
        kind: "browser".to_string(),
        command: None,
        spawn: false,
    })
    .unwrap();

    assert_eq!(tab.kind, "browser");
    assert_eq!(tab.payload["browserProfileId"], "default");
    assert_eq!(tab.payload["browserUrl"], "about:blank");
    assert_eq!(tab.payload.get("terminalSessionId"), None);
    assert_eq!(tab.payload.get("spawnOnCreate"), None);
}
