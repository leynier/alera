use clap::{Args, Subcommand};

use crate::cli::{OutputArgs, RuntimeDirArgs};
pub use crate::cli_orchestration_runs::*;
pub use crate::cli_orchestration_tasks::*;
pub use crate::cli_orchestration_terminal::*;
use crate::cli_orchestration_timeouts::parse_wait_timeout_ms;

/// `alera orchestration ...` - runs, delegated tasks, the worker protocol,
/// messages between agents, gates, and recipes. All verbs are RPC calls to
/// the running runtime-host; there is no direct-store fallback because
/// waiters, presence, and the coordinator are in-process host state.
#[derive(Debug, Args)]
pub struct OrchestrationCommand {
    #[command(flatten)]
    pub runtime: RuntimeDirArgs,
    #[command(flatten)]
    pub output: OutputArgs,
    #[command(subcommand)]
    pub action: OrchestrationAction,
}

#[derive(Debug, Subcommand)]
pub enum OrchestrationAction {
    /// Create a task and start a declared profile on it, or hand it to an
    /// existing terminal with --terminal.
    Delegate(Box<OrchestrationDelegateArgs>),
    /// Create, inspect, control, and clean up runs.
    #[command(subcommand)]
    Run(RunAction),
    /// Read a run's planning context, propose its plan, or show a plan.
    #[command(subcommand)]
    Plan(PlanAction),
    /// List, show, resolve, or create gates.
    #[command(subcommand)]
    Gate(GateAction),
    /// Read the active dispatch context for this terminal. The first worker
    /// command also accepts the dispatch.
    Context,
    /// Record the active dispatch's result, exactly once. Only --summary is required.
    Complete(OrchestrationCompleteArgs),
    /// Report a blocker through the active dispatch context.
    Escalate(OrchestrationEscalateArgs),
    /// Ask another agent a question and wait for the answer.
    Ask(OrchestrationAskArgs),
    /// Reply to a message or question by id.
    Reply(OrchestrationReplyArgs),
    /// Send a message to a terminal handle or @group address.
    Send(OrchestrationSendArgs),
    /// Read messages for a terminal (unread by default; marks them read).
    Check(OrchestrationCheckArgs),
    /// List recent messages across all recipients, or one terminal's.
    Messages(OrchestrationMessagesArgs),
    /// Show, wait for, cancel, or recover a task.
    #[command(subcommand)]
    Task(TaskAction),
    /// Transfer task or run coordinator ownership.
    #[command(name = "transfer-coordinator")]
    TransferCoordinator(OrchestrationTransferCoordinatorArgs),
    /// Show a task's dispatch or interrupt a worker turn.
    #[command(subcommand)]
    Dispatch(DispatchAction),
    /// List, show, wait for, or prune terminals.
    #[command(subcommand)]
    Terminal(OrchestrationTerminalAction),
    /// List the user-declared agent profiles available for delegation.
    #[command(name = "agent-profiles")]
    AgentProfiles,
    /// Show the workspace and terminal inferred from this environment.
    Current,
    /// Clear orchestration state (default: everything).
    Reset(OrchestrationResetArgs),
    /// Inspect, validate, and save portable run recipes.
    #[command(subcommand)]
    Recipe(crate::cli_run_recipes::RecipeAction),
}

#[derive(Debug, Subcommand)]
pub enum OrchestrationTerminalAction {
    /// List live terminals with agent presence.
    List(OrchestrationTerminalListArgs),
    /// Show one terminal with explicit startup and agent state.
    Show(OrchestrationTerminalShowArgs),
    /// Wait for a terminal lifecycle state without caller-side polling.
    Wait(OrchestrationTerminalWaitArgs),
    /// List or remove stopped terminal sessions.
    Prune(OrchestrationTerminalPruneArgs),
}

#[derive(Debug, Args)]
pub struct OrchestrationSendArgs {
    /// Recipient terminal handle or @group (@all, @idle, @workspace:<id>, @claude, ...).
    #[arg(long = "to", value_name = "handle|@group")]
    pub to: String,

    /// Message subject.
    #[arg(long = "subject", value_name = "text")]
    pub subject: String,

    /// Sender handle. Defaults to ALERA_TERMINAL_HANDLE.
    #[arg(long = "from", value_name = "handle")]
    pub from: Option<String>,

    /// Message body.
    #[arg(long = "body", value_name = "text", conflicts_with_all = ["body_file", "body_stdin"])]
    pub body: Option<String>,
    #[arg(long = "body-file", value_name = "path", conflicts_with_all = ["body", "body_stdin"])]
    pub body_file: Option<String>,
    #[arg(long = "body-stdin", conflicts_with_all = ["body", "body_file"])]
    pub body_stdin: bool,

    /// Message type: status|dispatch|merge_ready|escalation|handoff|decision_gate|question.
    #[arg(long = "type", value_name = "type")]
    pub message_type: Option<String>,

    /// When the message may reach a working agent: now (if its agent queues
    /// input mid-turn) or turn-end (default).
    #[arg(long = "delivery", value_parser = ["now", "turn-end"])]
    pub delivery: Option<String>,

    /// Priority: normal|high|urgent.
    #[arg(long = "priority", value_name = "level")]
    pub priority: Option<String>,

    /// Thread id to attach this message to.
    #[arg(long = "thread-id", value_name = "id")]
    pub thread_id: Option<String>,

    /// Raw JSON payload. Prefer the structured flags below on Windows shells.
    #[arg(long = "payload", value_name = "json", conflicts_with_all = ["task_id", "dispatch_id", "files_modified", "report_path", "phase"])]
    pub payload: Option<String>,

    /// Structured payload: task id for an application-defined message.
    #[arg(long = "task-id", value_name = "id")]
    pub task_id: Option<String>,

    /// Structured payload: dispatch id for an application-defined message.
    #[arg(long = "dispatch-id", value_name = "id")]
    pub dispatch_id: Option<String>,

    /// Structured payload: comma-separated modified file paths.
    #[arg(long = "files-modified", value_name = "csv")]
    pub files_modified: Option<String>,

    /// Structured payload: path to a long-form artifact.
    #[arg(long = "report-path", value_name = "path")]
    pub report_path: Option<String>,

    /// Structured payload: application-defined work phase.
    #[arg(long = "phase", value_name = "text")]
    pub phase: Option<String>,
}

#[derive(Debug, Args)]
pub struct OrchestrationCheckArgs {
    /// Terminal handle to check. Defaults to ALERA_TERMINAL_HANDLE.
    #[arg(long = "terminal", value_name = "handle")]
    pub terminal: Option<String>,

    /// Return all messages (read and unread) without marking anything read.
    #[arg(long = "all")]
    pub all: bool,

    /// Comma-separated message types to filter by.
    #[arg(long = "types", value_name = "type,...")]
    pub types: Option<String>,

    /// Format messages as injectable banners.
    #[arg(long = "inject")]
    pub inject: bool,

    /// Block until a matching message arrives or the timeout expires.
    #[arg(long = "wait")]
    pub wait: bool,

    /// Wait timeout in milliseconds (default 120000).
    #[arg(long = "timeout-ms", value_name = "ms", value_parser = parse_wait_timeout_ms)]
    pub timeout_ms: Option<u64>,

    /// Maximum messages returned with --all.
    #[arg(long = "limit", value_name = "n")]
    pub limit: Option<i64>,
}

#[derive(Debug, Args)]
pub struct OrchestrationReplyArgs {
    /// Message id to reply to.
    #[arg(long = "id", value_name = "msg_id")]
    pub id: String,

    /// Reply body.
    #[arg(long = "body", value_name = "text", conflicts_with_all = ["body_file", "body_stdin"])]
    pub body: Option<String>,
    /// Read the reply body from a file.
    #[arg(long = "body-file", value_name = "path", conflicts_with_all = ["body", "body_stdin"])]
    pub body_file: Option<String>,
    /// Read the reply body from standard input.
    #[arg(long = "body-stdin", conflicts_with_all = ["body", "body_file"])]
    pub body_stdin: bool,
}

#[derive(Debug, Args)]
pub struct OrchestrationMessagesArgs {
    /// Restrict to one terminal handle.
    #[arg(long = "terminal", value_name = "handle")]
    pub terminal: Option<String>,

    /// Maximum messages returned (default 50).
    #[arg(long = "limit", value_name = "n")]
    pub limit: Option<i64>,
    /// Message direction relative to --terminal.
    #[arg(long, default_value = "inbox", value_parser = ["inbox", "outbox"])]
    pub direction: String,
}

#[derive(Debug, Args)]
pub struct OrchestrationAskArgs {
    /// Terminal handle to ask (single handle, not a group).
    #[arg(long = "to", value_name = "handle")]
    pub to: String,

    /// The question text.
    #[arg(long = "question", value_name = "text")]
    pub question: String,

    /// Asker handle. Defaults to ALERA_TERMINAL_HANDLE.
    #[arg(long = "from", value_name = "handle")]
    pub from: Option<String>,

    /// Optional comma-separated answer options.
    #[arg(long = "options", value_name = "csv")]
    pub options: Option<String>,

    /// Wait timeout in milliseconds (default 120000).
    #[arg(long = "timeout-ms", value_name = "ms", value_parser = parse_wait_timeout_ms, conflicts_with = "no_wait")]
    pub timeout_ms: Option<u64>,

    /// Return the question id at once. The answer reaches this terminal on its
    /// next turn, or read it with `alera inbox wait --question <id>`.
    #[arg(long = "no-wait")]
    pub no_wait: bool,

    /// When the question reaches a working agent: now (default; pasted at once
    /// when its agent queues input mid-turn) or turn-end.
    #[arg(long = "delivery", value_parser = ["now", "turn-end"])]
    pub delivery: Option<String>,
}

#[derive(Debug, Args)]
pub struct OrchestrationEscalateArgs {
    #[arg(long, value_name = "text")]
    pub subject: String,
    #[arg(long, value_name = "text", conflicts_with_all = ["body_file", "body_stdin"])]
    pub body: Option<String>,
    #[arg(long = "body-file", conflicts_with_all = ["body", "body_stdin"])]
    pub body_file: Option<String>,
    #[arg(long = "body-stdin", conflicts_with_all = ["body", "body_file"])]
    pub body_stdin: bool,
}

#[derive(Debug, Args)]
pub struct OrchestrationCompleteArgs {
    /// What was completed and what remains.
    #[arg(long, value_name = "text")]
    pub summary: String,
    /// success (the default) or failure.
    #[arg(long = "kind", value_parser = ["success", "failure"])]
    pub kind: Option<String>,
    /// JSON array of artifacts, when the task's contract asks for them.
    #[arg(long = "artifacts", value_name = "json")]
    pub artifacts: Option<String>,
    /// Comma-separated paths of the files the task changed.
    #[arg(long = "files", value_name = "csv")]
    pub files: Option<String>,
    /// JSON array of validation results, when the task's contract asks for them.
    #[arg(long = "validation", value_name = "json")]
    pub validation: Option<String>,
    /// Additional JSON object fields required by the task result schema.
    #[arg(long = "result-extra", value_name = "json_object")]
    pub result_extra: Option<String>,
}

#[derive(Debug, Args)]
pub struct OrchestrationResetArgs {
    /// Clear everything (default when no scope flag is given).
    #[arg(long = "all")]
    pub all: bool,

    /// Clear tasks, dispatch contexts, gates, and coordinator runs.
    #[arg(long = "tasks")]
    pub tasks: bool,

    /// Clear messages.
    #[arg(long = "messages")]
    pub messages: bool,
}
