use clap::{Args, Subcommand};

use super::{OutputArgs, RuntimeDirArgs};

/// The runtime event journal: inbox replies, agent states, task and run
/// changes, and workspace starts, as identifiers and states only.
#[derive(Debug, Args)]
pub struct EventsCommand {
    #[command(flatten)]
    pub runtime: RuntimeDirArgs,
    #[command(flatten)]
    pub output: OutputArgs,
    #[command(subcommand)]
    pub action: EventsAction,
}

#[derive(Debug, Subcommand)]
pub enum EventsAction {
    /// List events after a cursor, oldest first.
    List(EventsListArgs),
    /// Wait for events after a cursor, then list them.
    Wait(EventsWaitArgs),
}

#[derive(Debug, Args)]
pub struct EventsFilterArgs {
    /// Cursor from a previous result; 0 reads from the oldest retained event.
    #[arg(long, default_value_t = 0)]
    pub after: i64,
    /// Only these kinds, such as inbox.reply. Repeat or separate with commas.
    #[arg(long = "kind", value_delimiter = ',')]
    pub kinds: Vec<String>,
    #[arg(long)]
    pub workspace_id: Option<String>,
    #[arg(long, default_value_t = 100, value_parser = clap::value_parser!(i64).range(1..=500))]
    pub limit: i64,
}

#[derive(Debug, Args)]
pub struct EventsListArgs {
    #[command(flatten)]
    pub filter: EventsFilterArgs,
}

#[derive(Debug, Args)]
pub struct EventsWaitArgs {
    #[command(flatten)]
    pub filter: EventsFilterArgs,
    /// Seconds to wait for a matching event before returning an empty page.
    #[arg(long, default_value_t = 30, value_parser = clap::value_parser!(u64).range(1..=600))]
    pub timeout_seconds: u64,
}
