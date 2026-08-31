use clap::{Args, Subcommand};

#[derive(Debug, Args)]
pub struct WorkflowWorkspacesArgs {
    #[command(subcommand)]
    pub action: WorkflowWorkspacesAction,
}

#[derive(Debug, Subcommand)]
pub enum WorkflowWorkspacesAction {
    /// Prepare integration or a lazy task attempt. No worker is dispatched.
    Prepare {
        #[arg(long)]
        run: String,
        #[arg(long)]
        revision: i64,
        /// Stable idempotency key. Reuse it after a timeout or disconnect.
        #[arg(long)]
        request_id: String,
        #[arg(long)]
        task: Option<String>,
        /// Latest failed attempt's workspace id; retries always get a new worktree.
        #[arg(long, requires = "task")]
        retry_of: Option<String>,
    },
    /// Inspect retained resources and setup outcomes without changing workspaces.
    List {
        #[arg(long)]
        run: String,
        #[arg(long)]
        before_row: Option<i64>,
        #[arg(long)]
        limit: Option<u32>,
    },
}
