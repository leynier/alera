use clap::{Args, Subcommand};

use crate::cli::{OutputArgs, RuntimeDirArgs};
pub use crate::cli_orchestration_runs::*;
pub use crate::cli_orchestration_terminal::*;
use crate::cli_orchestration_timeouts::parse_wait_timeout_ms;

/// `alera orchestration ...` - inter-agent messaging, task DAG, dispatch,
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
    /// Create or select a worker terminal and dispatch once the agent is ready.
    #[command(name = "agent-spawn")]
    AgentSpawn(OrchestrationAgentSpawnArgs),
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
    /// Show one task with its active dispatch.
    #[command(name = "task-show")]
    TaskShow(OrchestrationTaskIdArgs),
    /// Wait until a task reaches one of the requested states.
    #[command(name = "task-wait")]
    TaskWait(OrchestrationTaskWaitArgs),
    /// Cancel a task and its not-yet-started descendants.
    #[command(name = "task-cancel")]
    TaskCancel(OrchestrationTaskCancelArgs),
    /// Resolve a stalled task through an audited administrative action.
    #[command(name = "task-recover")]
    TaskRecover(OrchestrationTaskRecoverArgs),
    /// Transfer task or run coordinator ownership.
    #[command(name = "transfer-coordinator")]
    TransferCoordinator(OrchestrationTransferCoordinatorArgs),
    /// Dispatch a ready task to a terminal.
    Dispatch(OrchestrationDispatchArgs),
    /// Show the dispatch state and preamble for a task.
    #[command(name = "dispatch-show")]
    DispatchShow(OrchestrationDispatchShowArgs),
    /// Accept the active dispatch installed for this worker terminal.
    #[command(name = "dispatch-accept")]
    DispatchAccept,
    /// Interrupt an active worker turn without terminating the terminal.
    #[command(name = "dispatch-interrupt")]
    DispatchInterrupt(OrchestrationDispatchInterruptArgs),
    /// Inspect the active dispatch context for this terminal.
    Context,
    /// Record semantic worker activity for the active dispatch.
    Heartbeat(OrchestrationHeartbeatArgs),
    /// Escalate a blocker through the active dispatch context.
    Escalate(OrchestrationEscalateArgs),
    /// Atomically complete the active dispatch.
    Complete(OrchestrationCompleteArgs),
    /// Idempotent explicit completion for recovery and automation.
    #[command(name = "worker-done")]
    WorkerDone(OrchestrationWorkerDoneArgs),
    /// Print the compact worker lifecycle command reference.
    #[command(name = "worker-help")]
    WorkerHelp,
    /// Create a decision gate that blocks a task until resolved.
    #[command(name = "gate-create")]
    GateCreate(OrchestrationGateCreateArgs),
    /// Resolve a pending decision gate.
    #[command(name = "gate-resolve")]
    GateResolve(OrchestrationGateResolveArgs),
    /// List decision gates.
    #[command(name = "gate-list")]
    GateList(OrchestrationGateListArgs),
    /// List the user-declared agent profiles available for dispatch.
    #[command(name = "agent-profiles")]
    AgentProfiles,
    /// Propose a stage plan for a run. Holds scheduling until it is resolved.
    #[command(name = "run-policy-propose")]
    RunPolicyPropose(OrchestrationRunPolicyProposeArgs),
    /// Show a run's execution policy and its approval state.
    #[command(name = "run-policy-show")]
    RunPolicyShow(OrchestrationRunPolicyShowArgs),
    /// Approve a proposed execution policy so the run may schedule.
    #[command(name = "run-policy-approve")]
    RunPolicyApprove(OrchestrationRunPolicyShowArgs),
    /// Reject a proposed execution policy.
    #[command(name = "run-policy-reject")]
    RunPolicyReject(OrchestrationRunPolicyRejectArgs),
    /// Start the background coordinator loop.
    Run(OrchestrationRunArgs),
    /// List durable coordinator runs.
    #[command(name = "run-list")]
    RunList(OrchestrationRunListArgs),
    /// Show a coordinator run.
    #[command(name = "run-show")]
    RunShow(OrchestrationRunIdArgs),
    /// Aggregate run, task, worker, and escalation state.
    Status(OrchestrationRunIdArgs),
    /// Stop the active coordinator loop.
    #[command(name = "run-stop")]
    RunStop(OrchestrationRunStopArgs),
    /// List live terminals with agent presence.
    #[command(name = "terminal-list")]
    TerminalList(OrchestrationTerminalListArgs),
    /// Show one terminal with explicit startup and agent state.
    #[command(name = "terminal-show")]
    TerminalShow(OrchestrationTerminalShowArgs),
    /// Wait for a terminal lifecycle state without caller-side polling.
    #[command(name = "terminal-wait")]
    TerminalWait(OrchestrationTerminalWaitArgs),
    /// List or remove stopped terminal sessions.
    #[command(name = "terminal-prune")]
    TerminalPrune(OrchestrationTerminalPruneArgs),
    /// Show the workspace and terminal inferred from this environment.
    Current,
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
    #[arg(long = "body", value_name = "text", conflicts_with_all = ["body_file", "body_stdin"])]
    pub body: Option<String>,
    #[arg(long = "body-file", value_name = "path", conflicts_with_all = ["body", "body_stdin"])]
    pub body_file: Option<String>,
    #[arg(long = "body-stdin", conflicts_with_all = ["body", "body_file"])]
    pub body_stdin: bool,

    /// Message type: status|dispatch|merge_ready|escalation|handoff|decision_gate.
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
    #[arg(long = "timeout-ms", value_name = "ms", value_parser = parse_wait_timeout_ms)]
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

    /// Workspace that owns the task.
    #[arg(long = "workspace", value_name = "workspace_id")]
    pub workspace: Option<String>,

    /// Coordinator run for a coordinated task.
    #[arg(long = "run", value_name = "run_id")]
    pub run: Option<String>,

    /// Execution-policy stage this task belongs to. Must be declared by the
    /// run's policy, which is what resolves the profile and fallbacks.
    #[arg(long = "stage", value_name = "stage_id")]
    pub stage: Option<String>,

    /// Coordinator terminal for a manual task. Defaults to ALERA_TERMINAL_HANDLE.
    #[arg(long = "coordinator", value_name = "handle")]
    pub coordinator: Option<String>,

    /// Optional JSON Schema applied to structured completion results.
    #[arg(long = "result-schema", value_name = "json")]
    pub result_schema: Option<String>,
}

#[derive(Debug, Args)]
pub struct OrchestrationTaskListArgs {
    /// Filter by status: pending|ready|dispatched|completed|failed|blocked.
    #[arg(long = "status", value_name = "status", conflicts_with = "ready")]
    pub status: Option<String>,

    /// Shorthand for --status ready.
    #[arg(long = "ready")]
    pub ready: bool,
    #[arg(long = "run", value_name = "run_id")]
    pub run: Option<String>,
    #[arg(long = "workspace", value_name = "workspace_id")]
    pub workspace: Option<String>,
}

#[derive(Debug, Args)]
pub struct OrchestrationTaskIdArgs {
    #[arg(long = "id", value_name = "task_id")]
    pub id: String,
}

#[derive(Debug, Args)]
pub struct OrchestrationTaskWaitArgs {
    #[arg(long = "task", value_name = "task_id")]
    pub task: String,
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
pub struct OrchestrationTaskCancelArgs {
    #[arg(long = "id", value_name = "task_id")]
    pub id: String,
    #[arg(long, value_name = "text")]
    pub reason: String,
    /// Bypass coordinator ownership for audited administrative recovery.
    #[arg(long)]
    pub force: bool,
}

#[derive(Debug, Args)]
pub struct OrchestrationTaskRecoverArgs {
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

#[derive(Debug, Args)]
pub struct OrchestrationHeartbeatArgs {
    #[arg(long, value_name = "text")]
    pub phase: Option<String>,
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
    #[arg(long, value_name = "text")]
    pub summary: String,
    #[arg(long = "completion-kind", default_value = "success", value_parser = ["success", "failure"])]
    pub completion_kind: String,
    #[arg(long = "artifacts", value_name = "json")]
    pub artifacts: Option<String>,
    #[arg(long = "files-modified", value_name = "csv")]
    pub files_modified: Option<String>,
    #[arg(long = "validation", value_name = "json")]
    pub validation: Option<String>,
    /// Additional JSON object fields required by the task result schema.
    #[arg(long = "result-extra", value_name = "json_object")]
    pub result_extra: Option<String>,
}

#[derive(Debug, Args)]
pub struct OrchestrationWorkerDoneArgs {
    #[arg(long = "task")]
    pub task: String,
    #[arg(long = "dispatch")]
    pub dispatch: String,
    #[arg(long)]
    pub summary: String,
    /// Additional JSON object fields required by the task result schema.
    #[arg(long = "result-extra", value_name = "json_object")]
    pub result_extra: Option<String>,
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

    /// Audited manual override when hooks cannot report an already-running agent.
    #[arg(long = "assume-agent", value_name = "agent_type", requires = "inject")]
    pub assume_agent: Option<String>,

    /// Build the preamble without mutating any state.
    #[arg(long = "dry-run")]
    pub dry_run: bool,

    /// Include the full preamble text in the response.
    #[arg(long = "return-preamble")]
    pub return_preamble: bool,

    /// Allow a deliberate coordinator-to-self protocol test.
    #[arg(long = "allow-self-dispatch")]
    pub allow_self_dispatch: bool,

    /// Worker completion acknowledgement policy.
    #[arg(long = "completion-policy", default_value = "return-immediately", value_parser = ["return-immediately"])]
    pub completion_policy: String,

    /// Terminal lifecycle after successful completion.
    #[arg(long = "terminal-policy", default_value = "keep-open", value_parser = ["keep-open", "close-on-success", "return-to-shell"])]
    pub terminal_policy: String,
}

#[derive(Debug, Args)]
pub struct OrchestrationDispatchShowArgs {
    /// Task id to inspect.
    #[arg(long = "task", value_name = "task_id")]
    pub task: String,
}

#[derive(Debug, Args)]
pub struct OrchestrationDispatchInterruptArgs {
    #[arg(long = "id", value_name = "dispatch_id")]
    pub id: String,
    #[arg(long)]
    pub reason: String,
    /// Bypass coordinator ownership for an audited administrative interrupt.
    #[arg(long)]
    pub force: bool,
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
