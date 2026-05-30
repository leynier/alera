use clap::{Args, Parser, Subcommand};

use crate::terminal_host::protocol::{
    DEFAULT_DETACHED_SESSION_SHUTDOWN_DELAY_SECONDS, DEFAULT_EMPTY_SHUTDOWN_DELAY_SECONDS,
    DEFAULT_SCROLLBACK_BYTES, TERMINAL_HOST_COMMAND,
};

/// Top-level CLI, mirroring the Dart `AleraCliCommandRunner`.
#[derive(Debug, Parser)]
#[command(
    name = "alera",
    about = "Alera command line tools.",
    disable_help_subcommand = true
)]
pub struct Cli {
    #[command(subcommand)]
    pub command: Command,
}

#[derive(Debug, Subcommand)]
pub enum Command {
    /// Run the persistent terminal host sidecar.
    #[command(name = TERMINAL_HOST_COMMAND)]
    TerminalHost(TerminalHostArgs),
}

/// Arguments for `alera terminal-host`. Names and defaults match the Dart
/// `AleraTerminalHostCommand` exactly so the app launcher needs no changes.
#[derive(Debug, Args)]
pub struct TerminalHostArgs {
    /// Directory used for host control and terminal checkpoints.
    #[arg(long = "runtime-dir", value_name = "path")]
    pub runtime_dir: String,

    /// JSON file where the host publishes its socket metadata.
    #[arg(long = "control-file", value_name = "path")]
    pub control_file: String,

    /// Shared authentication token expected by the host.
    #[arg(long = "token", value_name = "token")]
    pub token: String,

    /// Seconds to keep an empty host alive after the app disconnects.
    #[arg(
        long = "empty-shutdown-delay-seconds",
        value_name = "seconds",
        default_value_t = DEFAULT_EMPTY_SHUTDOWN_DELAY_SECONDS,
        value_parser = clap::value_parser!(u64).range(1..),
    )]
    pub empty_shutdown_delay_seconds: u64,

    /// Seconds to keep detached running terminal sessions alive after the app disconnects.
    #[arg(
        long = "detached-session-shutdown-delay-seconds",
        value_name = "seconds",
        default_value_t = DEFAULT_DETACHED_SESSION_SHUTDOWN_DELAY_SECONDS,
        value_parser = clap::value_parser!(u64).range(1..),
    )]
    pub detached_session_shutdown_delay_seconds: u64,

    /// Maximum host-side output bytes retained per terminal session.
    #[arg(
        long = "scrollback-bytes",
        value_name = "bytes",
        default_value_t = DEFAULT_SCROLLBACK_BYTES,
        value_parser = clap::value_parser!(u64).range(1..),
    )]
    pub scrollback_bytes: u64,
}
