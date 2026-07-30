use std::path::PathBuf;

use crate::cli::TerminalHostArgs;
use crate::terminal_host::diagnostics;
use crate::terminal_host::protocol::TerminalHostConfig;
use crate::terminal_host::server::{run_terminal_host_server, TerminalHostExit};

const USAGE_EXIT_CODE: i32 = 64;

pub(crate) async fn run(args: TerminalHostArgs) -> i32 {
    let runtime_dir = args.runtime_dir.trim().to_string();
    let control_file = args.control_file.trim().to_string();
    let token = args.token.trim().to_string();
    if required_option_error(&runtime_dir, "runtime-dir")
        || required_option_error(&control_file, "control-file")
        || required_option_error(&token, "token")
    {
        return USAGE_EXIT_CODE;
    }

    // Diagnostics come up before the server so a startup failure is recorded.
    // The guard must outlive the server so Sentry flushes when it drops.
    diagnostics::init(
        diagnostics::DiagnosticsConfig::new(&runtime_dir).with_level(args.log_level.clone()),
    );
    let _crash_reporting = diagnostics::sentry_reporting::init(args.crash_reporting);
    diagnostics::redaction::register_secret(&token);

    let config = TerminalHostConfig {
        empty_shutdown_delay_seconds: args.empty_shutdown_delay_seconds,
        detached_session_shutdown_delay_seconds: args.detached_session_shutdown_delay_seconds,
        scrollback_bytes: args.scrollback_bytes,
        // Standalone host: the app overrides this in its `configure`.
        restore_snapshot_bytes: args.restore_snapshot_bytes.unwrap_or(args.scrollback_bytes),
        persistent: args.persistent,
        login_shell: args
            .login_shell
            .unwrap_or_else(crate::terminal_host::protocol::default_login_shell),
    };

    match run_terminal_host_server(
        PathBuf::from(runtime_dir),
        PathBuf::from(control_file),
        token,
        config,
    )
    .await
    {
        Ok(TerminalHostExit::Shutdown) => 0,
        Ok(TerminalHostExit::Restart(config)) => {
            match crate::terminal_host::restart::spawn_replacement_runtime_host(&args, config) {
                Ok(()) => 0,
                Err(error) => {
                    tracing::error!(
                        target: "alera.host",
                        "failed to restart runtime host: {error}"
                    );
                    1
                }
            }
        }
        Err(error) => {
            tracing::error!(target: "alera.host", "runtime host exited with an error: {error}");
            eprintln!("{error}");
            1
        }
    }
}

fn required_option_error(value: &str, name: &str) -> bool {
    if value.is_empty() {
        eprintln!("Missing required option --{name}.");
        true
    } else {
        false
    }
}
