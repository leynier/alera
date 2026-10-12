use clap::Args;

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
