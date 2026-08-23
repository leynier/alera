use std::process::Stdio;

use alera_core::child_process::detached_windowless_async_command;
use uuid::Uuid;

use crate::cli::TerminalHostArgs;
use crate::terminal_host::protocol::TerminalHostConfig;

pub(crate) fn spawn_replacement_runtime_host(
    args: &TerminalHostArgs,
    config: TerminalHostConfig,
) -> anyhow::Result<()> {
    let executable = std::env::current_exe()?;
    let token = Uuid::new_v4().to_string();
    let owner = super::runtime_owner::current_owner_identity()?;
    let mut command = detached_windowless_async_command(executable);
    command
        .arg("runtime-host")
        .arg("--runtime-dir")
        .arg(&args.runtime_dir)
        .arg("--control-file")
        .arg(&args.control_file)
        .arg("--token")
        .arg(token)
        .arg("--empty-shutdown-delay-seconds")
        .arg(config.empty_shutdown_delay_seconds.to_string())
        .arg("--detached-session-shutdown-delay-seconds")
        .arg(config.detached_session_shutdown_delay_seconds.to_string())
        .arg("--scrollback-bytes")
        .arg(config.scrollback_bytes.to_string())
        .arg("--restore-snapshot-bytes")
        .arg(config.restore_snapshot_bytes.to_string())
        .arg("--login-shell")
        .arg(config.login_shell.to_string())
        .arg("--log-level")
        .arg(&args.log_level)
        .arg("--handoff-owner-pid")
        .arg(owner.pid.to_string())
        .arg("--handoff-owner-start-marker")
        .arg(owner.start_marker.to_string())
        .stdin(Stdio::null())
        .stdout(Stdio::null())
        .stderr(Stdio::null());
    if config.persistent {
        command.arg("--persistent");
    }
    if super::diagnostics::sentry_reporting::is_enabled() {
        command.arg("--crash-reporting");
    }
    command.spawn()?;
    Ok(())
}
