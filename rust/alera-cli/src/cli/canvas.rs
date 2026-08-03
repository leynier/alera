use clap::{Args, Subcommand};

use super::{OutputArgs, RuntimeDirArgs};

#[derive(Debug, Args)]
pub struct CanvasCommand {
    #[command(flatten)]
    pub runtime: RuntimeDirArgs,
    #[command(flatten)]
    pub output: OutputArgs,
    #[command(subcommand)]
    pub action: CanvasAction,
}

#[derive(Debug, Subcommand)]
pub enum CanvasAction {
    /// Report the Agent Canvas contract supported by the runtime host.
    Capabilities,
    /// List the canvases for a workspace.
    Catalog(CanvasCatalogArgs),
    /// Print small Agent Canvas component examples.
    Examples,
    /// Publish a JSON or JSON-lines document from the current terminal.
    Publish(CanvasPublishArgs),
    /// Wait for a durable decision to resolve or time out.
    Wait(CanvasWaitArgs),
    /// Read durable Agent Canvas events, optionally following new events.
    Events(CanvasEventsArgs),
    /// Mark a canvas complete and freeze its final revision.
    Complete(CanvasIdentityArgs),
    /// Close a canvas while preserving its retained history.
    Close(CanvasIdentityArgs),
}

#[derive(Debug, Args)]
pub struct CanvasCatalogArgs {
    #[arg(long = "workspace-id")]
    pub workspace_id: Option<String>,
    #[arg(long = "history")]
    pub include_history: bool,
}

#[derive(Debug, Args)]
pub struct CanvasPublishArgs {
    #[arg(long = "workspace-id")]
    pub workspace_id: Option<String>,
    #[arg(long = "terminal-session-id")]
    pub terminal_session_id: Option<String>,
    #[arg(long = "tab-id")]
    pub tab_id: Option<String>,
    #[arg(long = "agent-type")]
    pub agent_type: Option<String>,
    #[arg(long)]
    pub title: Option<String>,
    #[arg(long = "canvas-id")]
    pub canvas_id: Option<String>,
    #[arg(long = "expected-revision")]
    pub expected_revision: Option<i64>,
    #[arg(long)]
    pub state: Option<String>,
    #[arg(long, conflicts_with_all = ["stdin", "document"])]
    pub file: Option<String>,
    #[arg(long, conflicts_with_all = ["file", "document"])]
    pub stdin: bool,
    #[arg(long, conflicts_with_all = ["file", "stdin"])]
    pub document: Option<String>,
}

#[derive(Debug, Args)]
pub struct CanvasWaitArgs {
    #[arg(long = "decision-id")]
    pub decision_id: String,
    #[arg(long = "timeout-ms", default_value_t = 600_000)]
    pub timeout_ms: u64,
}

#[derive(Debug, Args)]
pub struct CanvasEventsArgs {
    #[arg(long = "workspace-id")]
    pub workspace_id: Option<String>,
    #[arg(long, default_value_t = 0)]
    pub since: i64,
    #[arg(long, default_value_t = 200)]
    pub limit: i64,
    #[arg(long)]
    pub follow: bool,
    #[arg(long = "timeout-ms", default_value_t = 600_000)]
    pub timeout_ms: u64,
}

#[derive(Debug, Args)]
pub struct CanvasIdentityArgs {
    #[arg(long = "canvas-id")]
    pub canvas_id: Option<String>,
    #[arg(long = "workspace-id")]
    pub workspace_id: Option<String>,
    #[arg(long = "terminal-session-id")]
    pub terminal_session_id: Option<String>,
}
