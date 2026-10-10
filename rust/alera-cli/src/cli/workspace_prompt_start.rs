use clap::{Args, Subcommand, ValueEnum};

use super::{IdArgs, PromptSourceArgs};

/// New Workspace from Prompt, run by the runtime as one operation.
#[derive(Debug, Args)]
pub struct WorkspacePromptStartCommand {
    #[command(subcommand)]
    pub action: WorkspacePromptStartAction,
}

#[derive(Debug, Subcommand)]
pub enum WorkspacePromptStartAction {
    /// Start an operation: choose the project, name the workspace and its
    /// branch, pick its section, create it, start its setup, and launch the
    /// agent, as the app's New Workspace from Prompt form does.
    Run(Box<WorkspacePromptStartRunArgs>),
    /// Show one operation.
    Show(IdArgs),
    /// List recent operations, newest first.
    List(WorkspacePromptStartListArgs),
    /// Wait until an operation stops running, or until the timeout.
    Wait(WorkspacePromptStartWaitArgs),
    /// Cancel a running operation. A workspace it already created is kept.
    Cancel(IdArgs),
    /// Launch the agent again for an operation whose workspace exists but
    /// whose agent did not start. It never creates another workspace.
    RetryLaunch(IdArgs),
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, ValueEnum)]
pub enum PromptStartModeArg {
    /// A worktree for Git projects, the project folder otherwise.
    Auto,
    Worktree,
    ProjectCheckout,
}

#[derive(Debug, Args)]
pub struct WorkspacePromptStartRunArgs {
    #[command(flatten)]
    pub prompt: PromptSourceArgs,
    /// Project for the workspace. Omit to let AI Assist recognize it from the
    /// prompt; an unclear prompt returns candidates instead of guessing.
    #[arg(long)]
    pub project_id: Option<String>,
    /// Agent profile id or unique name. Defaults to the runtime's default profile.
    #[arg(long)]
    pub profile: Option<String>,
    #[arg(long, value_enum, default_value = "auto")]
    pub mode: PromptStartModeArg,
    /// Branch the new worktree starts from. Defaults to the project's preferred
    /// source branch, then the repository's default branch.
    #[arg(long)]
    pub source_branch: Option<String>,
    /// SSH target that owns the worktree. Omit for this machine.
    #[arg(long)]
    pub host_id: Option<String>,
    #[arg(long)]
    pub parent_workspace_id: Option<String>,
    /// Issue URL to link to the new workspace.
    #[arg(long = "issue", value_name = "url")]
    pub issue_url: Option<String>,
    /// `auto` (default) lets AI Assist pick a section or none ("Others"),
    /// `none` skips sections, any other value names a section.
    #[arg(long, conflicts_with = "section_id")]
    pub section: Option<String>,
    /// Section to join, by id.
    #[arg(long)]
    pub section_id: Option<String>,
    /// Retry key: a second start with the same key returns the first operation.
    #[arg(long)]
    pub request_id: Option<String>,
    /// Seconds to wait for the operation before printing it. 0 returns at once.
    #[arg(long, default_value_t = 0, value_parser = clap::value_parser!(u64).range(0..=600))]
    pub wait: u64,
}

#[derive(Debug, Args)]
pub struct WorkspacePromptStartListArgs {
    #[arg(long, default_value_t = 20, value_parser = clap::value_parser!(i64).range(1..=200))]
    pub limit: i64,
}

#[derive(Debug, Args)]
pub struct WorkspacePromptStartWaitArgs {
    #[arg(long)]
    pub id: String,
    /// Seconds to wait before printing the current state.
    #[arg(long, default_value_t = 30, value_parser = clap::value_parser!(u64).range(1..=600))]
    pub timeout_seconds: u64,
}
