use clap::{Args, Subcommand};

use crate::cli::{OutputArgs, RuntimeDirArgs};

/// `alera orchestration ...` — inter-agent messaging, task DAG, dispatch,
/// decision gates, and the coordinator loop. All verbs are RPC calls to the
/// running runtime-host; there is no direct-store fallback because waiters,
/// presence, and the coordinator are in-process host state.
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
    /// Send a message to a terminal handle or @group address.
    Send(OrchestrationSendArgs),
    /// Read messages for a terminal (unread by default; marks them read).
    Check(OrchestrationCheckArgs),
    /// Reply to a message by id.
    Reply(OrchestrationReplyArgs),
    /// List recent messages across all recipients.
    Inbox(OrchestrationInboxArgs),
    /// Ask another agent a question and block until it answers.
    Ask(OrchestrationAskArgs),
    /// Create a task in the orchestration DAG.
    #[command(name = "task-create")]
    TaskCreate(OrchestrationTaskCreateArgs),
    /// List tasks, optionally filtered by status.
    #[command(name = "task-list")]
    TaskList(OrchestrationTaskListArgs),
    /// Update a task's status.
    #[command(name = "task-update")]
    TaskUpdate(OrchestrationTaskUpdateArgs),
    /// Dispatch a ready task to a terminal.
    Dispatch(OrchestrationDispatchArgs),
    /// Show the dispatch state and preamble for a task.
    #[command(name = "dispatch-show")]
    DispatchShow(OrchestrationDispatchShowArgs),
    /// Create a decision gate that blocks a task until resolved.
    #[command(name = "gate-create")]
    GateCreate(OrchestrationGateCreateArgs),
    /// Resolve a pending decision gate.
    #[command(name = "gate-resolve")]
    GateResolve(OrchestrationGateResolveArgs),
    /// List decision gates.
    #[command(name = "gate-list")]
    GateList(OrchestrationGateListArgs),
    /// Start the background coordinator loop.
    Run(OrchestrationRunArgs),
    /// Stop the active coordinator loop.
    #[command(name = "run-stop")]
    RunStop,
    /// List live terminals with agent presence.
    #[command(name = "terminal-list")]
    TerminalList,
    /// Clear orchestration state (default: everything).
    Reset(OrchestrationResetArgs),
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
    #[arg(long = "body", value_name = "text")]
    pub body: Option<String>,

    /// Message type: status|dispatch|worker_done|merge_ready|escalation|handoff|decision_gate|heartbeat.
    #[arg(long = "type", value_name = "type")]
    pub message_type: Option<String>,

    /// Priority: normal|high|urgent.
    #[arg(long = "priority", value_name = "level")]
    pub priority: Option<String>,

    /// Thread id to attach this message to.
    #[arg(long = "thread-id", value_name = "id")]
    pub thread_id: Option<String>,

    /// Raw JSON payload. Prefer the structured flags below on Windows shells.
    #[arg(long = "payload", value_name = "json", conflicts_with_all = ["task_id", "dispatch_id", "files_modified", "report_path", "phase"])]
    pub payload: Option<String>,

    /// Structured payload: task id (for worker_done/heartbeat/escalation).
    #[arg(long = "task-id", value_name = "id")]
    pub task_id: Option<String>,

    /// Structured payload: dispatch context id (for worker_done/heartbeat/escalation).
    #[arg(long = "dispatch-id", value_name = "id")]
    pub dispatch_id: Option<String>,

    /// Structured payload: comma-separated modified file paths.
    #[arg(long = "files-modified", value_name = "csv")]
    pub files_modified: Option<String>,

    /// Structured payload: path to a long-form artifact.
    #[arg(long = "report-path", value_name = "path")]
    pub report_path: Option<String>,

    /// Structured payload: current work phase (heartbeats).
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
    #[arg(long = "timeout-ms", value_name = "ms")]
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
    #[arg(long = "body", value_name = "text")]
    pub body: String,
}

#[derive(Debug, Args)]
pub struct OrchestrationInboxArgs {
    /// Restrict to one terminal handle.
    #[arg(long = "terminal", value_name = "handle")]
    pub terminal: Option<String>,

    /// Maximum messages returned (default 50).
    #[arg(long = "limit", value_name = "n")]
    pub limit: Option<i64>,
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
    #[arg(long = "timeout-ms", value_name = "ms")]
    pub timeout_ms: Option<u64>,
}

#[derive(Debug, Args)]
pub struct OrchestrationTaskCreateArgs {
    /// The task brief the dispatched worker receives.
    #[arg(long = "spec", value_name = "text")]
    pub spec: String,

    /// Short title for listings.
    #[arg(long = "task-title", value_name = "text")]
    pub task_title: Option<String>,

    /// JSON array of task ids this task depends on.
    #[arg(long = "deps", value_name = "json_array")]
    pub deps: Option<String>,

    /// Parent task id.
    #[arg(long = "parent", value_name = "task_id")]
    pub parent: Option<String>,
}

#[derive(Debug, Args)]
pub struct OrchestrationTaskListArgs {
    /// Filter by status: pending|ready|dispatched|completed|failed|blocked.
    #[arg(long = "status", value_name = "status", conflicts_with = "ready")]
    pub status: Option<String>,

    /// Shorthand for --status ready.
    #[arg(long = "ready")]
    pub ready: bool,
}

#[derive(Debug, Args)]
pub struct OrchestrationTaskUpdateArgs {
    /// Task id.
    #[arg(long = "id", value_name = "task_id")]
    pub id: String,

    /// New status: pending|ready|dispatched|completed|failed|blocked.
    #[arg(long = "status", value_name = "status")]
    pub status: String,

    /// JSON result blob to store with the task.
    #[arg(long = "result", value_name = "json")]
    pub result: Option<String>,
}

#[derive(Debug, Args)]
pub struct OrchestrationDispatchArgs {
    /// Task id to dispatch (must be ready).
    #[arg(long = "task", value_name = "task_id")]
    pub task: String,

    /// Target terminal handle.
    #[arg(long = "to", value_name = "handle")]
    pub to: String,

    /// Coordinator handle embedded in the preamble. Defaults to ALERA_TERMINAL_HANDLE.
    #[arg(long = "from", value_name = "handle")]
    pub from: Option<String>,

    /// Inject the preamble into the target terminal (requires a running agent).
    #[arg(long = "inject")]
    pub inject: bool,

    /// Build the preamble without mutating any state.
    #[arg(long = "dry-run")]
    pub dry_run: bool,

    /// Include the full preamble text in the response.
    #[arg(long = "return-preamble")]
    pub return_preamble: bool,
}

#[derive(Debug, Args)]
pub struct OrchestrationDispatchShowArgs {
    /// Task id to inspect.
    #[arg(long = "task", value_name = "task_id")]
    pub task: String,
}

#[derive(Debug, Args)]
pub struct OrchestrationGateCreateArgs {
    /// Task id the gate blocks.
    #[arg(long = "task", value_name = "task_id")]
    pub task: String,

    /// The question for the human/coordinator.
    #[arg(long = "question", value_name = "text")]
    pub question: String,

    /// JSON array of options.
    #[arg(long = "options", value_name = "json_array")]
    pub options: Option<String>,
}

#[derive(Debug, Args)]
pub struct OrchestrationGateResolveArgs {
    /// Gate id.
    #[arg(long = "id", value_name = "gate_id")]
    pub id: String,

    /// The resolution text fed into the next dispatch preamble.
    #[arg(long = "resolution", value_name = "text")]
    pub resolution: String,
}

#[derive(Debug, Args)]
pub struct OrchestrationGateListArgs {
    /// Filter by task id.
    #[arg(long = "task", value_name = "task_id")]
    pub task: Option<String>,

    /// Filter by status: pending|resolved|timeout.
    #[arg(long = "status", value_name = "status")]
    pub status: Option<String>,
}

#[derive(Debug, Args)]
pub struct OrchestrationRunArgs {
    /// Run objective recorded on the coordinator run.
    #[arg(long = "spec", value_name = "text")]
    pub spec: String,

    /// Coordinator handle. Defaults to ALERA_TERMINAL_HANDLE.
    #[arg(long = "from", value_name = "handle")]
    pub from: Option<String>,

    /// Poll interval in milliseconds (default 2000).
    #[arg(long = "poll-interval-ms", value_name = "ms")]
    pub poll_interval_ms: Option<u64>,

    /// Maximum concurrent dispatches (default 4).
    #[arg(long = "max-concurrent", value_name = "n")]
    pub max_concurrent: Option<u64>,

    /// Workspace id that scopes worker terminals and drift checks.
    #[arg(long = "workspace", value_name = "workspace_id")]
    pub workspace: Option<String>,
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
