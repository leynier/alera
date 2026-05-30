mod cli;
mod terminal_host;

use std::path::PathBuf;

use clap::Parser;

use crate::cli::{Cli, Command, TerminalHostArgs};
use crate::terminal_host::protocol::TerminalHostConfig;
use crate::terminal_host::server::run_terminal_host_server;

/// Usage-error exit code, matching the Dart CLI (`_usageExitCode`).
const USAGE_EXIT_CODE: i32 = 64;

#[tokio::main]
async fn main() {
    std::process::exit(run().await);
}

async fn run() -> i32 {
    let cli = match Cli::try_parse() {
        Ok(cli) => cli,
        Err(error) => {
            let _ = error.print();
            // Help/version requests exit cleanly; real usage errors use code 64.
            return if error.use_stderr() {
                USAGE_EXIT_CODE
            } else {
                0
            };
        }
    };

    match cli.command {
        Command::TerminalHost(args) => run_terminal_host(args).await,
    }
}

async fn run_terminal_host(args: TerminalHostArgs) -> i32 {
    let runtime_dir = args.runtime_dir.trim().to_string();
    let control_file = args.control_file.trim().to_string();
    let token = args.token.trim().to_string();
    if let Some(code) = required_option_error(&runtime_dir, "runtime-dir")
        .or_else(|| required_option_error(&control_file, "control-file"))
        .or_else(|| required_option_error(&token, "token"))
    {
        return code;
    }

    let config = TerminalHostConfig {
        empty_shutdown_delay_seconds: args.empty_shutdown_delay_seconds,
        detached_session_shutdown_delay_seconds: args.detached_session_shutdown_delay_seconds,
        scrollback_bytes: args.scrollback_bytes,
    };

    match run_terminal_host_server(
        PathBuf::from(runtime_dir),
        PathBuf::from(control_file),
        token,
        config,
    )
    .await
    {
        Ok(()) => 0,
        Err(error) => {
            eprintln!("{error}");
            1
        }
    }
}

fn required_option_error(value: &str, name: &str) -> Option<i32> {
    if value.is_empty() {
        eprintln!("Missing required option --{name}.");
        Some(USAGE_EXIT_CODE)
    } else {
        None
    }
}
