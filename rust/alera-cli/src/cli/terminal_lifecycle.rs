use clap::{Args, Subcommand};

#[derive(Debug, Args)]
pub struct TabRemoveArgs {
    #[arg(long)]
    pub id: String,
    /// Close the tab through the runtime host so its terminal session ends
    /// too, as closing it in the app does. Fails when no host is running.
    #[arg(long)]
    pub terminate: bool,
}

#[derive(Debug, Args)]
pub struct TabRenameArgs {
    #[arg(long)]
    pub id: String,
    #[arg(long)]
    pub title: String,
}

#[derive(Debug, Args)]
pub struct TabGenerateTitleArgs {
    /// Agent tab whose conversation names the title.
    #[arg(long)]
    pub id: String,
}

#[derive(Debug, Args)]
pub struct TerminalHandleArgs {
    #[arg(long)]
    pub handle: String,
}

#[derive(Debug, Args)]
pub struct TerminalPulseCommand {
    #[command(subcommand)]
    pub action: TerminalPulseAction,
}

#[derive(Debug, Subcommand)]
pub enum TerminalPulseAction {
    /// Show a terminal's Pulse input, delay, and whether it is armed.
    Show(TerminalHandleArgs),
    /// Change a terminal's Pulse, and arm or disarm it.
    Set(TerminalPulseSetArgs),
}

#[derive(Debug, Args)]
pub struct TerminalPulseSetArgs {
    #[arg(long)]
    pub handle: String,
    /// Text typed into the terminal after workspace files change. Keeps the
    /// saved input when omitted.
    #[arg(long, value_name = "text")]
    pub input: Option<String>,
    /// Whether Enter is pressed after the input.
    #[arg(long, value_name = "true|false")]
    pub enter: Option<bool>,
    /// Quiet time after the last file change before the input is typed.
    #[arg(
        long = "delay-ms",
        value_name = "ms",
        value_parser = clap::value_parser!(u64).range(100..=3_600_000),
    )]
    pub delay_ms: Option<u64>,
    /// Start watching the workspace files.
    #[arg(long, conflicts_with = "disarm")]
    pub arm: bool,
    /// Stop watching the workspace files.
    #[arg(long)]
    pub disarm: bool,
}
