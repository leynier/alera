use clap::{Args, Subcommand};

use super::{OutputArgs, RuntimeDirArgs};

#[derive(Debug, Args)]
pub struct RuntimeSettingsCommand {
    #[command(subcommand)]
    pub action: RuntimeSettingsAction,
}

#[derive(Debug, Subcommand)]
pub enum RuntimeSettingsAction {
    /// Show the runtime settings the CLI and MCP clients may read and change.
    Show,
    /// Change one or more of those settings.
    Set(RuntimeSettingsSetArgs),
}

#[derive(Debug, Args)]
pub struct RuntimeSettingsSetArgs {
    /// KEY=VALUE. Keys: workspaceDirectory, confirmProjectRemoval,
    /// confirmWorkspaceRemoval, defaultAgentProfileId, aiAssist.enabled,
    /// aiAssist.autoGenerateAgentTitles, aiAssist.agent,
    /// aiAssist.timeoutSeconds, automation.startAtLogin,
    /// automation.runRetentionDays, automation.auditRetentionDays,
    /// automation.trashRetentionDays.
    #[arg(value_name = "key=value", required_unless_present = "unset")]
    pub assignments: Vec<String>,
    /// Clear workspaceDirectory or defaultAgentProfileId. May be repeated.
    #[arg(long = "unset", value_name = "key")]
    pub unset: Vec<String>,
}

#[derive(Debug, Args)]
pub struct AgentQuotaCommand {
    #[command(flatten)]
    pub runtime: RuntimeDirArgs,
    #[command(flatten)]
    pub output: OutputArgs,
    #[command(subcommand)]
    pub action: AgentQuotaAction,
}

#[derive(Debug, Subcommand)]
pub enum AgentQuotaAction {
    /// Show usage limits for the enabled agent providers.
    Show(AgentQuotaShowArgs),
    /// Read one Claude account's usage again through the Claude terminal UI.
    RefreshClaude(AgentQuotaClaudeArgs),
    /// Spend the Codex rate-limit reset credit the latest snapshot offers.
    ConsumeCodexReset(AgentQuotaCodexResetArgs),
}

#[derive(Debug, Args)]
pub struct AgentQuotaShowArgs {
    /// Fetch fresh numbers instead of the cached snapshot.
    #[arg(long)]
    pub refresh: bool,
}

#[derive(Debug, Args)]
pub struct AgentQuotaClaudeArgs {
    /// Claude account from the snapshot, or `default`.
    #[arg(long = "account-id", value_name = "id", default_value = "default")]
    pub account_id: String,
}

#[derive(Debug, Args)]
pub struct AgentQuotaCodexResetArgs {
    /// Offer revision from the Codex snapshot, so a changed offer is refused.
    #[arg(long = "offer-revision", value_name = "revision")]
    pub offer_revision: String,
}
