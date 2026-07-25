//! Argument shapes for coordinator runs and their execution policies. Kept
//! beside the orchestration CLI rather than inside it so that file stays
//! navigable.

use clap::Args;

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
