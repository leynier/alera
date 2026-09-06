use clap::Parser;

use crate::cli::{Cli, Command, IdArgs, TerminalHostArgs, WorkspaceAction, WorkspaceCommand};
use crate::cli_orchestration::{OrchestrationAction, OrchestrationCommand};

#[test]
fn runtime_clear_parses_force_as_an_explicit_live_host_override() {
    let cli = Cli::try_parse_from([
        "alera",
        "runtime",
        "--runtime-dir",
        "/tmp/alera-runtime",
        "clear",
        "--force",
    ])
    .unwrap();

    assert!(matches!(
        cli.command,
        Command::Runtime(crate::cli::RuntimeCommand {
            action: crate::cli::RuntimeAction::Clear(crate::cli::RuntimeClearArgs { force: true }),
            ..
        })
    ));
}

#[test]
fn agent_profile_commands_parse_administrative_contract() {
    use crate::cli::{AgentProfileAction, AgentProfileLaunchModeArg};

    let create = Cli::try_parse_from([
        "alera",
        "agent-profile",
        "--runtime-dir",
        "/tmp/alera-runtime",
        "--json",
        "create",
        "--name",
        "Codex Sol",
        "--agent-type",
        "codex",
        "--launch-mode",
        "managed",
        "--managed-config",
        r#"{"model":"gpt-5.6-sol"}"#,
    ])
    .unwrap();

    assert!(matches!(
        create.command,
        Command::AgentProfile(crate::cli::AgentProfileCommand {
            action: AgentProfileAction::Create(args),
            ..
        }) if matches!(args.launch_mode, AgentProfileLaunchModeArg::Managed)
            && args.managed.managed_config.as_deref() == Some(r#"{"model":"gpt-5.6-sol"}"#)
    ));

    let update = Cli::try_parse_from([
        "alera",
        "agent-profile",
        "update",
        "--profile-name",
        "Codex Sol",
        "--expected-revision",
        "4",
        "--clear-quota-group",
    ])
    .unwrap();
    assert!(matches!(
        update.command,
        Command::AgentProfile(crate::cli::AgentProfileCommand {
            action: AgentProfileAction::Update(args),
            ..
        }) if args.target.selector.profile_name.as_deref() == Some("Codex Sol")
            && args.target.expected_revision == Some(4)
            && args.clear_quota_group
    ));
}

#[test]
fn agent_profile_cli_rejects_ambiguous_or_unconfirmed_input() {
    for args in [
        vec![
            "alera",
            "agent-profile",
            "show",
            "--profile-id",
            "prof_1",
            "--profile-name",
            "Codex",
        ],
        vec![
            "alera",
            "agent-profile",
            "create",
            "--name",
            "Codex",
            "--agent-type",
            "codex",
            "--launch-mode",
            "managed",
            "--managed-config",
            "{}",
            "--managed-config-file",
            "profile.json",
        ],
        vec!["alera", "agent-profile", "remove", "--profile-id", "prof_1"],
    ] {
        assert!(Cli::try_parse_from(args).is_err());
    }
}

#[test]
fn workspace_pin_commands_parse_workspace_ids() {
    let pin = Cli::try_parse_from(["alera", "workspace", "pin", "--id", "workspace-1"]).unwrap();
    let unpin =
        Cli::try_parse_from(["alera", "workspace", "unpin", "--id", "workspace-2"]).unwrap();

    assert!(matches!(
        pin.command,
        Command::Workspace(WorkspaceCommand {
            action: WorkspaceAction::Pin(IdArgs { id }),
            ..
        }) if id == "workspace-1"
    ));
    assert!(matches!(
        unpin.command,
        Command::Workspace(WorkspaceCommand {
            action: WorkspaceAction::Unpin(IdArgs { id }),
            ..
        }) if id == "workspace-2"
    ));
}

#[test]
fn replacement_runtime_host_arguments_preserve_effective_configuration() {
    let cli = Cli::try_parse_from([
        "alera",
        "runtime-host",
        "--runtime-dir",
        "/tmp/alera",
        "--control-file",
        "/tmp/alera/runtime-host.json",
        "--token",
        "replacement-token",
        "--empty-shutdown-delay-seconds",
        "41",
        "--detached-session-shutdown-delay-seconds",
        "73",
        "--scrollback-bytes",
        "4096",
        "--restore-snapshot-bytes",
        "2048",
        "--login-shell",
        "false",
        "--persistent",
        "--crash-reporting",
        "--handoff-owner-pid",
        "1234",
        "--handoff-owner-start-marker",
        "5678",
    ])
    .unwrap();

    assert!(matches!(
        cli.command,
        Command::RuntimeHost(TerminalHostArgs {
            empty_shutdown_delay_seconds: 41,
            detached_session_shutdown_delay_seconds: 73,
            scrollback_bytes: 4096,
            restore_snapshot_bytes: Some(2048),
            login_shell: Some(false),
            persistent: true,
            crash_reporting: true,
            handoff_owner_pid: Some(1234),
            handoff_owner_start_marker: Some(5678),
            ..
        })
    ));
}

#[test]
fn replacement_runtime_host_arguments_require_a_complete_owner_identity() {
    for incomplete in [
        ["--handoff-owner-pid", "1234"],
        ["--handoff-owner-start-marker", "5678"],
    ] {
        let error = Cli::try_parse_from(
            [
                "alera",
                "runtime-host",
                "--runtime-dir",
                "/tmp/alera",
                "--control-file",
                "/tmp/alera/runtime-host.json",
                "--token",
                "replacement-token",
            ]
            .into_iter()
            .chain(incomplete),
        )
        .expect_err("a partial owner identity must be rejected");

        assert_eq!(
            error.kind(),
            clap::error::ErrorKind::MissingRequiredArgument
        );
    }
}

#[test]
fn task_wait_defaults_include_every_terminal_task_state() {
    let default =
        Cli::try_parse_from(["alera", "orchestration", "task-wait", "--task", "task-1"]).unwrap();
    let explicit = Cli::try_parse_from([
        "alera",
        "orchestration",
        "task-wait",
        "--task",
        "task-1",
        "--for",
        "completed",
    ])
    .unwrap();

    assert!(matches!(
        default.command,
        Command::Orchestration(OrchestrationCommand {
            action: OrchestrationAction::TaskWait(args),
            ..
        }) if args.targets == "completed,failed,stalled,cancelled"
    ));
    assert!(matches!(
        explicit.command,
        Command::Orchestration(OrchestrationCommand {
            action: OrchestrationAction::TaskWait(args),
            ..
        }) if args.targets == "completed"
    ));
}

#[test]
fn browser_open_and_capture_commands_parse_page_contracts() {
    use crate::cli::{BrowserAction, BrowserCommand};

    let open = Cli::try_parse_from([
        "alera",
        "browser",
        "open",
        "--workspace-id",
        "workspace-1",
        "--url",
        "https://example.com",
        "--profile-id",
        "work",
    ])
    .unwrap();
    assert!(matches!(
        open.command,
        Command::Browser(BrowserCommand {
            action: BrowserAction::Open(args),
            ..
        }) if args.workspace_id == "workspace-1"
            && args.url == "https://example.com"
            && args.profile_id == "work"
    ));

    let capture = Cli::try_parse_from([
        "alera",
        "browser",
        "full-screenshot",
        "--page-id",
        "page-1",
        "--output",
        "capture.png",
    ])
    .unwrap();
    assert!(matches!(
        capture.command,
        Command::Browser(BrowserCommand {
            action: BrowserAction::FullScreenshot(args),
            ..
        }) if args.page.page_id == "page-1"
            && args.output.as_deref() == Some("capture.png")
    ));
}

#[test]
fn browser_search_engine_rejects_arbitrary_templates() {
    assert!(Cli::try_parse_from([
        "alera",
        "browser",
        "settings",
        "set",
        "--search-engine",
        "https://example.com/?q={query}",
    ])
    .is_err());
}

#[test]
fn browser_profile_mutation_requires_the_in_app_coordinator() {
    for action in ["upsert", "remove"] {
        assert!(Cli::try_parse_from(["alera", "browser", "profiles", action]).is_err());
    }
}
