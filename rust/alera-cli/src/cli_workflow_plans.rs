use clap::{Args, Subcommand};

#[derive(Debug, Args)]
pub struct WorkflowPlansArgs {
    #[command(subcommand)]
    pub action: WorkflowPlansAction,
}

#[derive(Debug, Subcommand)]
pub enum WorkflowPlansAction {
    /// Read the frozen selection for a coordinator proposal.
    Proposal {
        #[arg(long)]
        id: String,
    },
    /// Submit concrete tasks for a proposal. Does not approve or launch workers.
    SubmitProposal {
        #[arg(long)]
        id: String,
        /// JSON array of WorkflowPlanTask values.
        #[arg(long, required_unless_present = "stdin", conflicts_with = "stdin")]
        document: Option<String>,
        #[arg(long)]
        stdin: bool,
    },
    /// Prepare a durable plan for human review. Does not start any workers.
    Prepare {
        /// JSON PrepareWorkflowPlan document, including a stable requestId.
        #[arg(long, required_unless_present = "stdin", conflicts_with = "stdin")]
        document: Option<String>,
        #[arg(long)]
        stdin: bool,
    },
    /// Read the current or a historical plan revision, including frozen profiles.
    Show {
        #[arg(long)]
        run: String,
        #[arg(long)]
        revision: Option<i64>,
    },
}
