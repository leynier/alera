use clap::{Args, Subcommand};

use super::{OutputArgs, RuntimeDirArgs};

#[derive(Debug, Args)]
pub struct IssueCommand {
    /// Accepted for symmetry with the other groups; issues are read through
    /// the forge CLIs and never touch the runtime.
    #[command(flatten)]
    pub runtime: RuntimeDirArgs,
    #[command(flatten)]
    pub output: OutputArgs,
    #[command(subcommand)]
    pub action: IssueAction,
}

#[derive(Debug, Subcommand)]
pub enum IssueAction {
    /// Fetch an issue from GitHub (gh), GitLab (glab), or Azure DevOps (az boards) without touching any workspace.
    Show(IssueShowArgs),
}

#[derive(Debug, Args)]
pub struct IssueShowArgs {
    /// Issue or work item URL.
    #[arg(value_name = "url")]
    pub url: String,
}
