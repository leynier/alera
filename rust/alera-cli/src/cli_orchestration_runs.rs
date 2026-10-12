//! Argument shapes for `delegate`, `run`, `plan`, and `gate`. Kept beside the
//! orchestration CLI rather than inside it so that file stays navigable.

use clap::{Args, Subcommand};

use crate::cli::{AgentProfileSelectorArgs, SpecSourceArgs};
use crate::cli_orchestration_timeouts::parse_agent_spawn_timeout_ms;
use crate::terminal_host::protocol::ORCHESTRATION_STARTUP_DEADLINE_MS;

#[derive(Debug, Args)]
pub struct OrchestrationDelegateArgs {
    #[command(flatten)]
    pub selector: AgentProfileSelectorArgs,
    #[command(flatten)]
    pub spec: SpecSourceArgs,
    /// Short title for listings. Defaults to the first line of the spec.
    #[arg(long = "task-title", value_name = "text")]
    pub task_title: Option<String>,
    /// Existing workspace that owns the task. Defaults to ALERA_WORKSPACE_ID.
    #[arg(
        long = "workspace",
        value_name = "workspace_id",
        conflicts_with = "new_workspace"
    )]
    pub workspace: Option<String>,
    /// Hand the task to this running agent terminal instead of starting a new one.
    #[arg(
        long = "terminal",
        value_name = "handle",
        conflicts_with = "new_workspace"
    )]
    pub terminal: Option<String>,
    /// Add the task to this run. Without it the task joins the caller's
    /// delegated run in the workspace, or starts one.
    #[arg(long = "run", value_name = "run_id")]
    pub run: Option<String>,
    /// Stage of the run's plan the task belongs to.
    #[arg(long = "stage", value_name = "stage_id")]
    pub stage: Option<String>,
    /// Comma-separated task ids this task waits for.
    #[arg(long = "depends-on", value_name = "task_id,...", value_delimiter = ',')]
    pub depends_on: Vec<String>,
    /// Portable version 1 role contract JSON. Requires --contract-inputs.
    #[arg(long = "contract", value_name = "json", requires = "contract_inputs")]
    pub contract: Option<String>,
    /// Concrete JSON inputs to freeze with the role contract.
    #[arg(long = "contract-inputs", value_name = "json", requires = "contract")]
    pub contract_inputs: Option<String>,
    /// Create a child worktree, then delegate into it.
    #[arg(long = "new-workspace")]
    pub new_workspace: bool,
    #[arg(long, requires = "new_workspace")]
    pub id: Option<String>,
    #[arg(long = "project-id", requires = "new_workspace")]
    pub project_id: Option<String>,
    #[arg(long, requires = "new_workspace")]
    pub branch: Option<String>,
    #[arg(long = "source-branch", requires = "new_workspace")]
    pub source_branch: Option<String>,
    #[arg(long, requires = "new_workspace")]
    pub name: Option<String>,
    #[arg(
        long = "workspace-root",
        conflicts_with = "path",
        requires = "new_workspace"
    )]
    pub workspace_root: Option<String>,
    #[arg(long, conflicts_with = "workspace_root", requires = "new_workspace")]
    pub path: Option<String>,
    /// Workspace used to infer project, source branch, and parent when --new-workspace is set.
    #[arg(
        long = "from-workspace",
        value_name = "workspace_id",
        requires = "new_workspace"
    )]
    pub from_workspace: Option<String>,
    #[arg(
        long = "parent-workspace-id",
        conflicts_with = "no_parent",
        requires = "new_workspace"
    )]
    pub parent_workspace_id: Option<String>,
    /// Do not link the new workspace to the current workspace.
    #[arg(long = "no-parent", requires = "new_workspace")]
    pub no_parent: bool,
    /// Coordinator terminal. Defaults to ALERA_TERMINAL_HANDLE.
    #[arg(long = "from", value_name = "handle")]
    pub from: Option<String>,
    /// Preserve a newly-created worker terminal when startup fails.
    #[arg(long = "keep-on-failure")]
    pub keep_on_failure: bool,
    /// Maximum time to wait for the agent to become ready.
    #[arg(
        long = "timeout-ms",
        default_value_t = ORCHESTRATION_STARTUP_DEADLINE_MS,
        value_parser = parse_agent_spawn_timeout_ms
    )]
    pub timeout_ms: u64,
}

#[derive(Debug, Subcommand)]
pub enum RunAction {
    /// Start a run: a coordinator agent plans it, then workers carry it out.
    New(RunNewArgs),
    /// List runs, grouped as attention, active, or history.
    List(RunListArgs),
    /// Show a run with its pending gates and a page of its tasks.
    Show(RunShowArgs),
    /// Read a run's timeline of events and messages, newest first.
    Timeline(RunTimelineArgs),
    /// Cancel a run and its unfinished work.
    Cancel(RunControlArgs),
    /// Pause a running run. Dispatched workers keep going.
    Pause(RunControlArgs),
    /// Resume a paused run.
    Resume(RunControlArgs),
    /// Ask the coordinator for a new plan revision.
    Replan(RunReplanArgs),
    /// Retry a failed task attempt, an integration, or a cancellation.
    Retry(RunRetryArgs),
    /// List the worktrees and branches a run retains.
    Resources(RunPageArgs),
    /// List the integrations of an isolated run.
    Integrations(RunIntegrationsArgs),
    /// Preview, apply, and follow the cleanup of retained resources.
    #[command(subcommand)]
    Cleanup(RunCleanupAction),
}

#[derive(Debug, Args)]
pub struct RunNewArgs {
    /// The run objective (--spec, --spec-file or --spec-stdin).
    #[command(flatten)]
    pub spec: SpecSourceArgs,
    /// Coordinator profile.
    #[command(flatten)]
    pub coordinator: AgentProfileSelectorArgs,
    /// Workspace the run works in. Defaults to ALERA_WORKSPACE_ID.
    #[arg(long = "workspace", value_name = "workspace_id")]
    pub workspace: Option<String>,
    /// isolated: a worktree per task, integrated in order. shared: workers
    /// share the run's workspace.
    #[arg(long = "isolation", value_parser = ["isolated", "shared"], default_value = "isolated")]
    pub isolation: String,
    /// Recipe of an isolated run: `builtIn:<id>`, `personal:<id>`,
    /// `project:<path>`, or the source JSON from `recipe list`.
    #[arg(long = "template", value_name = "source")]
    pub template: Option<String>,
    /// Hold the run behind a plan gate until a person approves its plan.
    #[arg(long = "approval")]
    pub approval: bool,
    /// Profile for workers whose role has no profile of its own.
    #[arg(long = "worker-profile", value_name = "id|name")]
    pub worker_profile: Option<String>,
    /// Profile for one recipe role, as role=profile. Repeatable.
    #[arg(long = "role-profile", value_name = "role=profile")]
    pub role_profiles: Vec<String>,
    /// Maximum workers at once (1 to 16).
    #[arg(long = "max-concurrent", value_name = "n")]
    pub max_concurrent: Option<u32>,
    /// What happens when a worker stalls.
    #[arg(long = "stall-policy", value_parser = ["ask", "auto-failover", "wait"])]
    pub stall_policy: Option<String>,
    /// Retry key: repeating the command with it returns the first run.
    #[arg(long = "request-id", value_name = "key")]
    pub request_id: Option<String>,
}

#[derive(Debug, Args)]
pub struct RunListArgs {
    #[arg(long = "project-id", value_name = "project_id")]
    pub project_id: Option<String>,
    #[arg(long = "workspace", value_name = "workspace_id")]
    pub workspace: Option<String>,
    /// Text to search for in run objectives.
    #[arg(long = "search", value_name = "text")]
    pub search: Option<String>,
    #[arg(long = "bucket", value_parser = ["attention", "active", "history"])]
    pub bucket: Option<String>,
    /// The `nextCursor` JSON object of a previous page.
    #[arg(long = "cursor", value_name = "json")]
    pub cursor: Option<String>,
    #[arg(long = "limit", value_name = "n")]
    pub limit: Option<u32>,
}

#[derive(Debug, Args)]
pub struct RunShowArgs {
    #[arg(long = "run", value_name = "run_id")]
    pub run: String,
    /// Continue after this task id from a previous page.
    #[arg(long = "after-task", value_name = "task_id")]
    pub after_task: Option<String>,
    /// Revision of the previous page, so pages stay consistent.
    #[arg(long = "revision", value_name = "n")]
    pub revision: Option<i64>,
    #[arg(long = "limit", value_name = "n")]
    pub limit: Option<u32>,
}

#[derive(Debug, Args)]
pub struct RunTimelineArgs {
    #[arg(long = "run", value_name = "run_id")]
    pub run: String,
    /// Only entries about this task.
    #[arg(long = "task", value_name = "task_id")]
    pub task: Option<String>,
    /// Comma-separated event kinds to keep; `message` keeps messages.
    #[arg(long = "kinds", value_name = "kind,...", value_delimiter = ',')]
    pub kinds: Vec<String>,
    /// The `nextCursor` of a previous page.
    #[arg(long = "cursor", value_name = "cursor")]
    pub cursor: Option<String>,
    #[arg(long = "limit", value_name = "n")]
    pub limit: Option<u32>,
}

#[derive(Debug, Args)]
pub struct RunControlArgs {
    #[arg(long = "run", value_name = "run_id")]
    pub run: String,
    /// Why, recorded on the run's timeline.
    #[arg(long = "reason", value_name = "text")]
    pub reason: Option<String>,
    /// The run's controlSequence from `run show`. Read from the run when omitted.
    #[arg(long = "expected-sequence", value_name = "n")]
    pub expected_sequence: Option<i64>,
}

#[derive(Debug, Args)]
pub struct RunReplanArgs {
    #[arg(long = "run", value_name = "run_id")]
    pub run: String,
    /// What the coordinator should change.
    #[arg(long = "reason", value_name = "text")]
    pub reason: String,
    /// Comma-separated task ids the change is about.
    #[arg(long = "tasks", value_name = "task_id,...", value_delimiter = ',')]
    pub tasks: Vec<String>,
    /// The run's controlSequence from `run show`. Read from the run when omitted.
    #[arg(long = "expected-sequence", value_name = "n")]
    pub expected_sequence: Option<i64>,
}

#[derive(Debug, Args)]
#[command(group(clap::ArgGroup::new("target").required(true).args(["task", "integration", "cancellation"])))]
pub struct RunRetryArgs {
    #[arg(long = "run", value_name = "run_id")]
    pub run: String,
    /// Start a new attempt of this task (isolated runs, paused).
    #[arg(long = "task", value_name = "task_id")]
    pub task: Option<String>,
    /// Integrate this task's result again (isolated runs, paused).
    #[arg(long = "integration", value_name = "task_id")]
    pub integration: Option<String>,
    /// Retry a cancellation that needs attention.
    #[arg(long = "cancellation")]
    pub cancellation: bool,
    /// For --cancellation: the run's controlSequence. Read from the run when omitted.
    #[arg(long = "expected-sequence", value_name = "n")]
    pub expected_sequence: Option<i64>,
}

#[derive(Debug, Args)]
pub struct RunPageArgs {
    #[arg(long = "run", value_name = "run_id")]
    pub run: String,
    /// Continue before this row from a previous page.
    #[arg(long = "before-row", value_name = "n")]
    pub before_row: Option<i64>,
}

#[derive(Debug, Args)]
pub struct RunIntegrationsArgs {
    #[arg(long = "run", value_name = "run_id")]
    pub run: String,
    /// Continue after this row from a previous page.
    #[arg(long = "after-row", value_name = "n")]
    pub after_row: Option<i64>,
}

#[derive(Debug, Subcommand)]
pub enum RunCleanupAction {
    /// Preview removing retained resources. Removes nothing.
    Preview(RunCleanupPreviewArgs),
    /// Apply a reviewed preview.
    Apply(RunCleanupConfirmArgs),
    /// Show one cleanup.
    Status(RunCleanupIdArgs),
    /// List a run's cleanups.
    List(RunPageArgs),
    /// Retry a cleanup that needs attention.
    Retry(RunCleanupConfirmArgs),
    /// Give up on a cleanup and release its resources.
    Abandon(RunCleanupConfirmArgs),
}

#[derive(Debug, Args)]
pub struct RunCleanupPreviewArgs {
    #[arg(long = "run", value_name = "run_id")]
    pub run: String,
    /// Workspace id of a resource from `run resources`. Repeatable, at most 25.
    #[arg(long = "resource", value_name = "workspace_id", required = true)]
    pub resources: Vec<String>,
    /// Also delete the branch of this selected resource. Repeatable.
    #[arg(long = "delete-branch", value_name = "workspace_id")]
    pub delete_branches: Vec<String>,
    /// Cleanup id (a UUID). Generated when omitted.
    #[arg(long = "id", value_name = "uuid")]
    pub id: Option<String>,
}

#[derive(Debug, Args)]
pub struct RunCleanupConfirmArgs {
    /// Cleanup id from the preview.
    #[arg(long = "id", value_name = "uuid")]
    pub id: String,
    /// Digest from the preview or status.
    #[arg(long = "digest", value_name = "digest")]
    pub digest: String,
}

#[derive(Debug, Args)]
pub struct RunCleanupIdArgs {
    #[arg(long = "id", value_name = "uuid")]
    pub id: String,
}

#[derive(Debug, Subcommand)]
pub enum PlanAction {
    /// Read what a run's coordinator plans against: objective, source,
    /// recipe, profiles, the current plan and any change request.
    Context(PlanRunArgs),
    /// Propose a run's plan as JSON. A run that requires approval waits
    /// behind a plan gate until a person resolves it.
    Propose(PlanProposeArgs),
    /// Show a run's current plan, or one revision.
    Show(PlanShowArgs),
}

#[derive(Debug, Args)]
pub struct PlanRunArgs {
    #[arg(long = "run", value_name = "run_id")]
    pub run: String,
}

#[derive(Debug, Args)]
pub struct PlanProposeArgs {
    /// Run the plan applies to.
    #[arg(long = "run", value_name = "run_id")]
    pub run: String,

    /// Path to the plan JSON (`{stages?, tasks?, stallPolicy?, maxConcurrent?}`).
    /// Use `-` to read it from stdin.
    #[arg(long = "plan-file", value_name = "path", conflicts_with = "stdin")]
    pub plan_file: Option<String>,

    /// Read the plan JSON from stdin.
    #[arg(long = "stdin")]
    pub stdin: bool,
}

#[derive(Debug, Args)]
pub struct PlanShowArgs {
    #[arg(long = "run", value_name = "run_id")]
    pub run: String,
    /// Plan revision. Defaults to the current one.
    #[arg(long = "revision", value_name = "n")]
    pub revision: Option<i64>,
}

#[derive(Debug, Subcommand)]
pub enum GateAction {
    /// List gates of a run, or decision gates of tasks outside runs.
    List(GateListArgs),
    /// Show a gate with the plan or evidence it decides on.
    Show(GateIdArgs),
    /// Resolve a pending gate with one of its options.
    Resolve(GateResolveArgs),
    /// Create a decision gate that blocks a task until a person resolves it.
    Create(GateCreateArgs),
}

#[derive(Debug, Args)]
pub struct GateListArgs {
    /// Run whose gates to list.
    #[arg(long = "run", value_name = "run_id")]
    pub run: Option<String>,
    /// Only gates of this task.
    #[arg(long = "task", value_name = "task_id")]
    pub task: Option<String>,
    /// decision|stall|plan|stage.
    #[arg(long = "kind", value_parser = ["decision", "stall", "plan", "stage"])]
    pub kind: Option<String>,
    /// pending|resolved|timeout|invalidated.
    #[arg(long = "status", value_parser = ["pending", "resolved", "timeout", "invalidated"])]
    pub status: Option<String>,
}

#[derive(Debug, Args)]
pub struct GateIdArgs {
    #[arg(long = "id", value_name = "gate_id")]
    pub id: String,
}

#[derive(Debug, Args)]
pub struct GateResolveArgs {
    #[arg(long = "id", value_name = "gate_id")]
    pub id: String,
    /// An option id: approve|requestChanges|reject for plan and stage gates,
    /// killAndFailover|keepWaiting|abortStage for stall gates, or one of a
    /// decision gate's options (free text when it has none).
    #[arg(long = "decision", value_name = "option")]
    pub decision: String,
    /// Why. Required with requestChanges; recorded in the audit log.
    #[arg(long = "reason", value_name = "text")]
    pub reason: Option<String>,
    /// With requestChanges: comma-separated task ids the change is about.
    #[arg(long = "tasks", value_name = "task_id,...", value_delimiter = ',')]
    pub tasks: Vec<String>,
    /// The gate's evidenceDigest from `gate show`; a gate whose evidence
    /// changed since is refused as stale.
    #[arg(long = "expected-digest", value_name = "digest")]
    pub expected_digest: Option<String>,
}

#[derive(Debug, Args)]
pub struct GateCreateArgs {
    /// Task id the gate blocks.
    #[arg(long = "task", value_name = "task_id")]
    pub task: String,
    /// The question for the person.
    #[arg(long = "question", value_name = "text")]
    pub question: String,
    /// JSON array of options.
    #[arg(long = "options", value_name = "json_array")]
    pub options: Option<String>,
}
