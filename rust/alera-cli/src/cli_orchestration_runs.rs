//! Argument shapes for coordinator runs and their execution policies. Kept
//! beside the orchestration CLI rather than inside it so that file stays
//! navigable.

use clap::Args;

use crate::cli::{AgentProfileSelectorArgs, SpecSourceArgs};
use crate::cli_orchestration_timeouts::parse_agent_spawn_timeout_ms;
use crate::terminal_host::protocol::ORCHESTRATION_ACCEPTANCE_TIMEOUT_MS;

#[derive(Debug, Args)]
pub struct OrchestrationRunPolicyProposeArgs {
    /// Run the plan applies to.
    #[arg(long = "run", value_name = "run_id")]
    pub run: String,

    /// Path to the policy JSON. Use `-` to read it from stdin.
    #[arg(long = "policy-file", value_name = "path")]
    pub policy_file: String,
}

#[derive(Debug, Args)]
pub struct OrchestrationRunPolicyShowArgs {
    #[arg(long = "run", value_name = "run_id")]
    pub run: String,
}

#[derive(Debug, Args)]
pub struct OrchestrationRunPolicyRejectArgs {
    #[arg(long = "run", value_name = "run_id")]
    pub run: String,

    /// Why the plan was rejected. Recorded in the audit log.
    #[arg(long = "reason", value_name = "text")]
    pub reason: String,
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

    /// Agent type used when the coordinator creates worker terminals.
    #[arg(long = "agent", default_value = "codex")]
    pub agent: String,
}

#[derive(Debug, Args)]
pub struct OrchestrationRunListArgs {
    #[arg(long = "workspace", value_name = "workspace_id")]
    pub workspace: Option<String>,
}

#[derive(Debug, Args)]
pub struct OrchestrationRunIdArgs {
    #[arg(long = "id", value_name = "run_id")]
    pub id: String,
}

#[derive(Debug, Args)]
pub struct OrchestrationRunStopArgs {
    #[arg(long = "id", value_name = "run_id")]
    pub id: String,
    #[arg(long = "cancel-active")]
    pub cancel_active: bool,
    #[arg(long = "reason", default_value = "coordinator stopped")]
    pub reason: String,
    /// Bypass coordinator ownership for an audited administrative stop.
    #[arg(long)]
    pub force: bool,
}

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
    /// Create a child worktree, then delegate into it.
    #[arg(long = "new-workspace")]
    pub new_workspace: bool,
    #[arg(long)]
    pub id: Option<String>,
    #[arg(long = "project-id")]
    pub project_id: Option<String>,
    #[arg(long)]
    pub branch: Option<String>,
    #[arg(long = "source-branch")]
    pub source_branch: Option<String>,
    #[arg(long)]
    pub name: Option<String>,
    #[arg(long = "workspace-root", conflicts_with = "path")]
    pub workspace_root: Option<String>,
    #[arg(long, conflicts_with = "workspace_root")]
    pub path: Option<String>,
    /// Workspace used to infer project, source branch, and parent when --new-workspace is set.
    #[arg(long = "from-workspace", value_name = "workspace_id")]
    pub from_workspace: Option<String>,
    #[arg(long = "parent-workspace-id", conflicts_with = "no_parent")]
    pub parent_workspace_id: Option<String>,
    /// Do not link the new workspace to the current workspace.
    #[arg(long = "no-parent")]
    pub no_parent: bool,
    /// Coordinator terminal. Defaults to ALERA_TERMINAL_HANDLE.
    #[arg(long = "from", value_name = "handle")]
    pub from: Option<String>,
    /// Preserve a newly-created worker terminal when startup fails.
    #[arg(long = "keep-on-failure")]
    pub keep_on_failure: bool,
    /// Maximum time to wait for dispatch acceptance.
    #[arg(
        long = "timeout-ms",
        default_value_t = ORCHESTRATION_ACCEPTANCE_TIMEOUT_MS,
        value_parser = parse_agent_spawn_timeout_ms
    )]
    pub timeout_ms: u64,
}
