//! Argument shapes for `task`, `dispatch`, and `transfer-coordinator`.

use clap::{Args, Subcommand};

use crate::cli_orchestration_timeouts::parse_wait_timeout_ms;

#[derive(Debug, Subcommand)]
pub enum TaskAction {
    /// Show a task with its active dispatch, or with --run its result and history.
    Show(TaskShowArgs),
    /// Wait until a task reaches one of the requested states.
    Wait(TaskWaitArgs),
    /// Cancel a task and its not-yet-started descendants.
    Cancel(TaskCancelArgs),
    /// Resolve a stalled task through an audited administrative action.
    Recover(TaskRecoverArgs),
}

#[derive(Debug, Args)]
pub struct TaskShowArgs {
    #[arg(long = "id", value_name = "task_id")]
    pub id: String,
    /// The task's run: adds its result, attempt, gates, and dispatch history.
    #[arg(long = "run", value_name = "run_id")]
    pub run: Option<String>,
    /// With --run: the history cursor JSON object of a previous page.
    #[arg(long = "cursor", value_name = "json", requires = "run")]
    pub cursor: Option<String>,
    /// With --run: maximum history entries.
    #[arg(long = "limit", value_name = "n", requires = "run")]
    pub limit: Option<u32>,
}

#[derive(Debug, Args)]
pub struct TaskWaitArgs {
    #[arg(long = "id", value_name = "task_id")]
    pub id: String,
    #[arg(
        long = "for",
        value_name = "status_csv",
        default_value = "completed,failed,stalled,cancelled"
    )]
    pub targets: String,
    #[arg(long = "timeout-ms", default_value_t = 120_000, value_parser = parse_wait_timeout_ms)]
    pub timeout_ms: u64,
}

#[derive(Debug, Args)]
pub struct TaskCancelArgs {
    #[arg(long = "id", value_name = "task_id")]
    pub id: String,
    #[arg(long, value_name = "text")]
    pub reason: String,
    /// Bypass coordinator ownership for audited administrative recovery.
    #[arg(long)]
    pub force: bool,
}

#[derive(Debug, Args)]
pub struct TaskRecoverArgs {
    #[arg(long = "id", value_name = "task_id")]
    pub id: String,
    #[arg(long, value_parser = ["ready", "failed", "cancelled"])]
    pub status: String,
    #[arg(long)]
    pub reason: String,
    /// Bypass coordinator ownership for audited administrative recovery.
    #[arg(long)]
    pub force: bool,
}

#[derive(Debug, Args)]
pub struct OrchestrationTransferCoordinatorArgs {
    #[arg(long, conflicts_with = "run", required_unless_present = "run")]
    pub task: Option<String>,
    #[arg(long, conflicts_with = "task", required_unless_present = "task")]
    pub run: Option<String>,
    #[arg(long = "to")]
    pub to: String,
    #[arg(long)]
    pub reason: String,
    #[arg(long)]
    pub force: bool,
}

#[derive(Debug, Subcommand)]
pub enum DispatchAction {
    /// Show the dispatch state and preamble for a task.
    Show(DispatchShowArgs),
    /// Interrupt an active worker turn without terminating the terminal.
    Interrupt(DispatchInterruptArgs),
}

#[derive(Debug, Args)]
pub struct DispatchShowArgs {
    /// Task id to inspect.
    #[arg(long = "task", value_name = "task_id")]
    pub task: String,
}

#[derive(Debug, Args)]
pub struct DispatchInterruptArgs {
    #[arg(long = "id", value_name = "dispatch_id")]
    pub id: String,
    #[arg(long)]
    pub reason: String,
    /// Bypass coordinator ownership for an audited administrative interrupt.
    #[arg(long)]
    pub force: bool,
}
