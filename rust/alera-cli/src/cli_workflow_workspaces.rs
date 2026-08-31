use clap::{Args, Subcommand};

#[derive(Debug, Args)]
pub struct WorkflowWorkspacesArgs {
    #[command(subcommand)]
    pub action: WorkflowWorkspacesAction,
}

#[derive(Debug, Subcommand)]
pub enum WorkflowWorkspacesAction {
    /// Inspect retained one-shot launches without loading private profile inputs.
    Launches {
        #[arg(long)]
        run: String,
        #[arg(long)]
        after_row: Option<i64>,
    },
    /// Launch one approved task in its ready isolated attempt, at most once.
    Launch {
        #[arg(long)]
        run: String,
        #[arg(long)]
        revision: i64,
        #[arg(long)]
        request_id: String,
        #[arg(long)]
        task: String,
        #[arg(long)]
        workspace_id: String,
    },
    /// Squash a completed task result into its run's local integration workspace.
    Integrate {
        #[arg(long)]
        run: String,
        #[arg(long)]
        revision: i64,
        #[arg(long)]
        request_id: String,
        #[arg(long)]
        task: String,
        #[arg(long)]
        workspace_id: String,
    },
    /// Inspect a page of local integration outcomes, without loading artifacts.
    Integrations {
        #[arg(long)]
        run: String,
        #[arg(long)]
        after_row: Option<i64>,
    },
    /// Inspect one durable integration receipt and any conflict paths.
    Integration {
        #[arg(long)]
        id: String,
    },
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
