use clap::Parser;

use crate::cli::{Cli, Command, TerminalHostArgs};

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
