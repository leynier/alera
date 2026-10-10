//! `alera orchestration proposals|execution|cleanup`: workflow lifecycle verbs
//! that need no human decision. Approvals, reviews, and signed decisions stay
//! in the Alera desktop app.

use clap::{Args, Subcommand, ValueEnum};

#[derive(Debug, Args)]
pub struct WorkflowProposalsArgs {
    #[command(subcommand)]
    pub action: WorkflowProposalsAction,
}

#[derive(Debug, Subcommand)]
pub enum WorkflowProposalsAction {
    /// List workflow proposals, newest first.
    List {
        /// Continue after the createdAt of the last entry of a previous page.
        #[arg(long, requires = "before_id")]
        before_created_at: Option<String>,
        /// Continue after the id of the last entry of a previous page.
        #[arg(long, requires = "before_created_at")]
        before_id: Option<String>,
    },
    /// Show the lifecycle state of a proposal, its coordinator, and its run.
    Status {
        #[arg(long)]
        id: String,
    },
    /// Create a proposal from a recipe and the source workspace's current commit.
    Create(WorkflowProposalCreateArgs),
    /// Cancel a proposal, or retry a cancellation that did not finish.
    Cancel {
        #[arg(long)]
        id: String,
        /// Retry an unfinished cancellation at this cancellation sequence.
        #[arg(long)]
        expected_sequence: Option<i64>,
    },
    /// Start the coordinator agent of a proposal. Does not approve any plan.
    StartCoordinator {
        #[arg(long)]
        id: String,
    },
}

#[derive(Debug, Args)]
pub struct WorkflowProposalCreateArgs {
    /// Local Git workspace the workflow starts from.
    #[arg(long)]
    pub workspace_id: String,
    /// Recipe source JSON, such as {"origin":"builtIn","id":"quick-fix"}.
    #[arg(long)]
    pub recipe_source: String,
    /// Recipe digest from `recipes show`; creation fails if the recipe changed.
    #[arg(long)]
    pub recipe_digest: String,
    /// Agent profile id for the coordinator.
    #[arg(long)]
    pub coordinator_profile_id: String,
    /// Agent profile for a recipe role, as role=profileId. Repeat for each role.
    #[arg(long = "role-profile", value_name = "role=profile_id")]
    pub role_profiles: Vec<String>,
    /// Workers that may run at once (1-16, default 4).
    #[arg(long, default_value_t = 4, value_parser = clap::value_parser!(u32).range(1..=16))]
    pub max_concurrent: u32,
    /// Revise this existing run instead of starting a new one.
    #[arg(long, requires = "expected_revision")]
    pub run: Option<String>,
    #[arg(long, requires = "run")]
    pub expected_revision: Option<i64>,
    /// Stable idempotency key. Reuse it after a timeout or disconnect.
    #[arg(long)]
    pub request_id: String,
    /// What the workflow should achieve.
    #[arg(
        long,
        required_unless_present = "objective_stdin",
        conflicts_with = "objective_stdin"
    )]
    pub objective: Option<String>,
    /// Read the objective from standard input.
    #[arg(long)]
    pub objective_stdin: bool,
}

#[derive(Debug, Args)]
pub struct WorkflowExecutionArgs {
    #[command(subcommand)]
    pub action: WorkflowExecutionAction,
}

#[derive(Debug, Clone, Copy, ValueEnum)]
pub enum WorkflowExecutionVerb {
    Start,
    Pause,
    Cancel,
}

#[derive(Debug, Subcommand)]
pub enum WorkflowExecutionAction {
    /// Show the execution state and command sequence of a run revision.
    Show {
        #[arg(long)]
        run: String,
        #[arg(long)]
        revision: Option<i64>,
    },
    /// Start, pause, or cancel scheduling of an approved run revision.
    Control {
        #[arg(long)]
        run: String,
        #[arg(long)]
        revision: i64,
        /// Sequence from `execution show`; a stale value is rejected.
        #[arg(long)]
        expected_sequence: i64,
        #[arg(long, value_enum)]
        action: WorkflowExecutionVerb,
        /// Stable idempotency key. Reuse it after a timeout or disconnect.
        #[arg(long)]
        request_id: String,
    },
    /// Open a correction proposal for a run revision. Does not approve it.
    Correct {
        #[arg(long)]
        run: String,
        #[arg(long)]
        revision: i64,
        /// Plan digest from `plans show`.
        #[arg(long)]
        plan_digest: String,
        /// Stable idempotency key. Reuse it after a timeout or disconnect.
        #[arg(long)]
        request_id: String,
        /// Why the run needs a correction.
        #[arg(
            long,
            required_unless_present = "reason_stdin",
            conflicts_with = "reason_stdin"
        )]
        reason: Option<String>,
        /// Read the reason from standard input.
        #[arg(long)]
        reason_stdin: bool,
    },
}

#[derive(Debug, Args)]
pub struct WorkflowCleanupArgs {
    #[command(subcommand)]
    pub action: WorkflowCleanupAction,
}

#[derive(Debug, Subcommand)]
pub enum WorkflowCleanupAction {
    /// List a run's retained workspaces with their cleanup state.
    Resources {
        #[arg(long)]
        run: String,
        #[arg(long)]
        before_row: Option<i64>,
    },
    /// List a run's cleanup operations.
    List {
        #[arg(long)]
        run: String,
        #[arg(long)]
        before_row: Option<i64>,
    },
    /// Preview removing retained workspaces. Changes nothing.
    Preview {
        #[arg(long)]
        run: String,
        /// Workspace to remove. Repeat for up to 25 workspaces.
        #[arg(long = "workspace", value_name = "workspace_id", required = true)]
        workspaces: Vec<String>,
        /// Also delete the branch of this selected workspace. Repeatable.
        #[arg(long = "remove-branch", value_name = "workspace_id")]
        remove_branches: Vec<String>,
        /// Preview id (a UUID). Defaults to a new one.
        #[arg(long)]
        id: Option<String>,
    },
    /// Show a cleanup operation and its outcome.
    Status {
        #[arg(long)]
        id: String,
    },
    /// Apply a previewed cleanup.
    Apply(WorkflowCleanupConfirmation),
    /// Retry a cleanup that did not finish.
    Retry(WorkflowCleanupConfirmation),
    /// Abandon a cleanup and keep the remaining resources.
    Abandon(WorkflowCleanupConfirmation),
}

#[derive(Debug, Args)]
pub struct WorkflowCleanupConfirmation {
    /// Preview id.
    #[arg(long)]
    pub id: String,
    /// Digest the preview returned.
    #[arg(long)]
    pub digest: String,
}
