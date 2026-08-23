use clap::Parser;

use crate::cli::{Cli, Command, IdArgs, TerminalHostArgs, WorkspaceAction, WorkspaceCommand};
use crate::cli::{
    EmulatorAction, EmulatorCommand, EmulatorLogLevelArg, EmulatorPermissionOperationArg,
    EmulatorPlatformArg,
};
use crate::cli_orchestration::{OrchestrationAction, OrchestrationCommand};

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
fn emulator_json_and_attach_scope_parse_at_the_group_level() {
    let cli = Cli::try_parse_from([
        "alera",
        "emulator",
        "--json",
        "attach",
        "--tab-id",
        "tab-1",
        "--workspace-id",
        "workspace-1",
        "--platform",
        "ios",
        "--device-id",
        "simulator-1",
    ])
    .unwrap();

    assert!(matches!(
        cli.command,
        Command::Emulator(EmulatorCommand {
            output,
            action: EmulatorAction::Attach(args),
            ..
        }) if output.json
            && args.target.tab_id.as_deref() == Some("tab-1")
            && args.target.workspace_id.as_deref() == Some("workspace-1")
            && args.platform == EmulatorPlatformArg::Ios
            && args.device_id == "simulator-1"
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

#[test]
fn emulator_android_development_commands_parse_bounded_filters() {
    let permission = Cli::try_parse_from([
        "alera",
        "emulator",
        "permission",
        "--workspace-id",
        "workspace-1",
        "--bundle-id",
        "dev.alera.demo",
        "--permission",
        "android.permission.CAMERA",
        "--operation",
        "grant",
    ])
    .unwrap();
    let logcat = Cli::try_parse_from([
        "alera",
        "emulator",
        "logcat",
        "--workspace-id",
        "workspace-1",
        "--max-lines",
        "25",
        "--tag",
        "flutter",
        "--tag",
        "ActivityManager",
        "--level",
        "warn",
    ])
    .unwrap();

    assert!(matches!(
        permission.command,
        Command::Emulator(EmulatorCommand {
            action: EmulatorAction::Permission(args),
            ..
        }) if args.operation == EmulatorPermissionOperationArg::Grant
    ));
    assert!(matches!(
        logcat.command,
        Command::Emulator(EmulatorCommand {
            action: EmulatorAction::Logcat(args),
            ..
        }) if args.max_lines == 25
            && args.tag == ["flutter", "ActivityManager"]
            && args.level == Some(EmulatorLogLevelArg::Warn)
    ));
}

#[test]
fn emulator_logcat_rejects_unbounded_line_counts() {
    let error = Cli::try_parse_from([
        "alera",
        "emulator",
        "logcat",
        "--workspace-id",
        "workspace-1",
        "--max-lines",
        "1001",
    ])
    .unwrap_err();

    assert!(error.to_string().contains("1000"));
}

#[test]
fn emulator_input_rejects_coordinates_outside_the_normalized_viewport() {
    let error = Cli::try_parse_from([
        "alera",
        "emulator",
        "tap",
        "--workspace-id",
        "workspace-1",
        "--snapshot-id",
        "snapshot-1",
        "--x",
        "120",
        "--y",
        "0.5",
    ])
    .unwrap_err();

    assert!(error.to_string().contains("between 0 and 1"));
}
