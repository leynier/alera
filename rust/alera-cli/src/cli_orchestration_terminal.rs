use clap::Args;

use crate::cli_orchestration_timeouts::parse_agent_spawn_timeout_ms;
use crate::terminal_host::protocol::ORCHESTRATION_ACCEPTANCE_TIMEOUT_MS;

#[derive(Debug, Args)]
pub struct OrchestrationTerminalShowArgs {
    #[arg(long = "handle", value_name = "terminal_handle")]
    pub handle: String,
}

#[derive(Debug, Args)]
pub struct OrchestrationTerminalListArgs {
    /// Filter terminals by workspace. Defaults to ALERA_WORKSPACE_ID when set.
    #[arg(long = "workspace", value_name = "workspace_id")]
    pub workspace: Option<String>,
}

#[derive(Debug, Args)]
pub struct OrchestrationTerminalWaitArgs {
    #[arg(long = "terminal")]
    pub terminal: String,
    #[arg(long = "for", value_parser = ["process-started", "agent-detected", "agent-ready", "dispatch-accepted"])]
    pub target: String,
    #[arg(long = "timeout-ms", default_value_t = 30_000)]
    pub timeout_ms: u64,
}

#[derive(Debug, Args)]
pub struct OrchestrationTerminalPruneArgs {
    /// Filter stopped terminals by workspace. Defaults to ALERA_WORKSPACE_ID when set.
    #[arg(long = "workspace", value_name = "workspace_id")]
    pub workspace: Option<String>,
    /// Remove the listed terminal tabs. Without this flag the command is a dry run.
    #[arg(long = "apply")]
    pub apply: bool,
}

#[derive(Debug, Args)]
pub struct OrchestrationAgentSpawnArgs {
    #[arg(long = "workspace", value_name = "workspace_id")]
    pub workspace: Option<String>,
    /// Adapter type. Not needed when --profile resolves it.
    #[arg(
        long = "agent",
        value_name = "agent_type",
        required_unless_present = "profile",
        conflicts_with = "profile"
    )]
    pub agent: Option<String>,

    /// Declared agent profile to launch. Resolves the adapter and the command
    /// host-side, so it cannot be combined with --agent or --command.
    #[arg(long = "profile", value_name = "name", conflicts_with = "command")]
    pub profile: Option<String>,
    #[arg(long = "task", value_name = "task_id")]
    pub task: String,
    #[arg(long = "title", value_name = "text")]
    pub title: Option<String>,
    #[arg(long = "terminal", value_name = "handle")]
    pub terminal: Option<String>,
    #[arg(long = "command", value_name = "command")]
    pub command: Option<String>,
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
