use clap::{Args, Subcommand, ValueEnum};

use super::{OutputArgs, RuntimeDirArgs};

/// Pull requests on GitHub, GitLab, and Azure DevOps through the runtime,
/// which runs `gh`, `glab`, or `az` on the host that owns the checkout.
#[derive(Debug, Args)]
pub struct PullRequestCommand {
    #[command(flatten)]
    pub runtime: RuntimeDirArgs,
    #[command(flatten)]
    pub output: OutputArgs,
    #[command(subcommand)]
    pub action: PullRequestAction,
}

#[derive(Debug, Subcommand)]
pub enum PullRequestAction {
    /// Show the workspace's pull request: state, checks, conversation, and merge methods.
    Show(PrTargetArgs),
    /// List compact pull request summaries for every active workspace.
    Summaries(PrTargetArgs),
    /// Write a title and description for the branch with AI Assist.
    #[command(name = "generate-details")]
    GenerateDetails(PrBaseArgs),
    /// Open a pull request from the current branch and link it to the workspace.
    Create(PrCreateArgs),
    /// Link a pull request by number or URL to the workspace.
    Link(PrLinkArgs),
    /// Unlink the workspace's pull request so branch detection stops showing it.
    Unlink(PrNumberArgs),
    /// Comment on the pull request, or reply to a comment.
    Comment(PrCommentArgs),
    /// Edit one of your comments.
    #[command(name = "comment-edit")]
    CommentEdit(PrCommentEditArgs),
    /// Mark the pull request as a draft, or ready for review with --ready.
    Draft(PrDraftArgs),
    /// Close the pull request without merging.
    Close(PrNumberArgs),
    /// Merge the pull request with a method the forge allows.
    Merge(PrMergeArgs),
    /// Commit, push, and open a pull request in one step, optionally followed by Watch and Fix.
    Ship(PrShipArgs),
    /// Ask an agent to rewrite the branch into logical, easy-to-review commits.
    Restack(PrDispatchArgs),
    /// Ask an agent to fix the pull request's failed checks.
    #[command(name = "fix-checks")]
    FixChecks(PrDispatchArgs),
    /// GitHub pull request stacks: show, create from workspaces, link, merge.
    Stack(PrStackCommand),
}

#[derive(Debug, Args)]
pub struct PrTargetArgs {
    /// Workspace to act on. Defaults to ALERA_WORKSPACE_ID.
    #[arg(long = "workspace-id", value_name = "id")]
    pub workspace_id: Option<String>,
}

#[derive(Debug, Args)]
pub struct PrNumberArgs {
    #[command(flatten)]
    pub target: PrTargetArgs,
    /// Pull request number. Defaults to the workspace's linked or detected pull request.
    #[arg(long, value_name = "n", value_parser = clap::value_parser!(i64).range(1..))]
    pub number: Option<i64>,
}

#[derive(Debug, Args)]
pub struct PrBaseArgs {
    #[command(flatten)]
    pub target: PrTargetArgs,
    /// Base branch the pull request targets.
    #[arg(long = "base", value_name = "branch")]
    pub base: String,
}

#[derive(Debug, Args)]
pub struct PrBodyArgs {
    /// Text of the body.
    #[arg(long, value_name = "text", conflicts_with = "body_stdin")]
    pub body: Option<String>,
    /// Read the body from standard input.
    #[arg(long = "body-stdin")]
    pub body_stdin: bool,
}

#[derive(Debug, Args)]
pub struct PrCreateArgs {
    #[command(flatten)]
    pub base: PrBaseArgs,
    #[arg(long, value_name = "text")]
    pub title: String,
    #[command(flatten)]
    pub body: PrBodyArgs,
    /// Open it as a draft.
    #[arg(long)]
    pub draft: bool,
}

#[derive(Debug, Args)]
pub struct PrLinkArgs {
    #[command(flatten)]
    pub target: PrTargetArgs,
    /// Pull request number, #number, or URL of this repository.
    #[arg(value_name = "reference")]
    pub reference: String,
}

#[derive(Debug, Args)]
pub struct PrCommentArgs {
    #[command(flatten)]
    pub number: PrNumberArgs,
    #[command(flatten)]
    pub body: PrBodyArgs,
    /// Reply to this comment id instead of commenting at the top level.
    #[arg(long = "reply-to", value_name = "id", value_parser = clap::value_parser!(i64).range(1..))]
    pub reply_to: Option<i64>,
    /// Thread or discussion id of the comment (GitLab and Azure DevOps).
    #[arg(long = "thread-id", value_name = "id")]
    pub thread_id: Option<String>,
}

#[derive(Debug, Clone, Copy, ValueEnum)]
pub enum PrCommentSource {
    #[value(name = "conversation")]
    Conversation,
    #[value(name = "reviewSummary")]
    ReviewSummary,
    #[value(name = "reviewThread")]
    ReviewThread,
}

impl PrCommentSource {
    pub fn wire(self) -> &'static str {
        match self {
            Self::Conversation => "conversation",
            Self::ReviewSummary => "reviewSummary",
            Self::ReviewThread => "reviewThread",
        }
    }
}

#[derive(Debug, Args)]
pub struct PrCommentEditArgs {
    #[command(flatten)]
    pub number: PrNumberArgs,
    #[arg(long = "comment-id", value_name = "id", value_parser = clap::value_parser!(i64).range(1..))]
    pub comment_id: i64,
    /// Where the comment lives, as the snapshot's comment `source` says.
    #[arg(long, value_enum)]
    pub source: PrCommentSource,
    /// Thread or discussion id of the comment (GitLab and Azure DevOps).
    #[arg(long = "thread-id", value_name = "id")]
    pub thread_id: Option<String>,
    #[command(flatten)]
    pub body: PrBodyArgs,
}

#[derive(Debug, Args)]
pub struct PrDraftArgs {
    #[command(flatten)]
    pub number: PrNumberArgs,
    /// Mark it ready for review instead.
    #[arg(long)]
    pub ready: bool,
}

#[derive(Debug, Clone, Copy, ValueEnum)]
pub enum PrMergeMethodArg {
    #[value(name = "mergeCommit")]
    MergeCommit,
    #[value(name = "squash")]
    Squash,
    #[value(name = "rebase")]
    Rebase,
    #[value(name = "providerDefault")]
    ProviderDefault,
}

impl PrMergeMethodArg {
    pub fn wire(self) -> &'static str {
        match self {
            Self::MergeCommit => "mergeCommit",
            Self::Squash => "squash",
            Self::Rebase => "rebase",
            Self::ProviderDefault => "providerDefault",
        }
    }
}

#[derive(Debug, Args)]
pub struct PrMergeArgs {
    #[command(flatten)]
    pub number: PrNumberArgs,
    /// Merge method. Defaults to the forge's preferred allowed method.
    #[arg(long, value_enum)]
    pub method: Option<PrMergeMethodArg>,
    /// Only merge while the head commit is still this SHA.
    #[arg(long = "expected-head", value_name = "sha")]
    pub expected_head: Option<String>,
}

#[derive(Debug, Clone, Copy, ValueEnum)]
pub enum PrShipScope {
    All,
    Staged,
}

#[derive(Debug, Clone, Copy, ValueEnum)]
pub enum PrWatchMode {
    Fix,
    #[value(name = "fixAndMerge")]
    FixAndMerge,
}

#[derive(Debug, Args)]
pub struct PrAgentTargetArgs {
    /// Running terminal handle to send the prompt to.
    #[arg(long, value_name = "handle")]
    pub handle: Option<String>,
    /// Terminal tab to send the prompt to.
    #[arg(long = "tab-id", value_name = "id")]
    pub tab_id: Option<String>,
    /// Agent profile id used to open a new tab when no terminal is given or running.
    #[arg(long = "profile-id", value_name = "id")]
    pub profile_id: Option<String>,
    /// Unique agent profile name. Alias for looking up --profile-id.
    #[arg(long = "profile", value_name = "name", conflicts_with = "profile_id")]
    pub profile: Option<String>,
}

#[derive(Debug, Args)]
pub struct PrShipArgs {
    #[command(flatten)]
    pub base: PrBaseArgs,
    #[arg(long, value_enum, default_value = "all")]
    pub scope: PrShipScope,
    #[arg(long)]
    pub draft: bool,
    /// Start Watch and Fix (fix) or Watch, Fix and Merge (fixAndMerge) on the new pull request.
    #[arg(long = "follow-up-watch", value_enum, value_name = "mode")]
    pub follow_up_watch: Option<PrWatchMode>,
    #[command(flatten)]
    pub agent: PrAgentTargetArgs,
    /// Do not watch failing checks.
    #[arg(long = "no-checks")]
    pub no_checks: bool,
    /// Do not watch unresolved review comments.
    #[arg(long = "no-comments")]
    pub no_comments: bool,
    /// Do not watch merge conflicts.
    #[arg(long = "no-conflicts")]
    pub no_conflicts: bool,
}

#[derive(Debug, Args)]
pub struct PrDispatchArgs {
    #[command(flatten)]
    pub number: PrNumberArgs,
    #[command(flatten)]
    pub agent: PrAgentTargetArgs,
    /// Only print the prompt; do not send it.
    #[arg(long)]
    pub preview: bool,
}

#[derive(Debug, Args)]
pub struct PrStackCommand {
    #[command(subcommand)]
    pub action: PrStackAction,
}

#[derive(Debug, Subcommand)]
pub enum PrStackAction {
    /// Show the stack that holds the workspace's pull request.
    Show(PrNumberArgs),
    /// Open pull requests for workspace branches (bottom to top) and stack them.
    Create(PrStackCreateArgs),
    /// Stack existing pull requests (bottom to top), or append them to the current stack.
    Link(PrStackLinkArgs),
    /// Merge the stack through the workspace's pull request.
    Merge(PrStackMergeArgs),
}

#[derive(Debug, Args)]
pub struct PrStackCreateArgs {
    #[command(flatten)]
    pub target: PrTargetArgs,
    /// Base branch of a new stack.
    #[arg(long = "base", value_name = "branch")]
    pub base: Option<String>,
    /// Workspace of each layer, bottom to top. Repeat or separate with commas.
    #[arg(
        long = "layer",
        value_name = "workspace-id",
        value_delimiter = ',',
        required = true
    )]
    pub layers: Vec<String>,
    /// Title for each layer that needs a new pull request, in layer order.
    #[arg(long = "title", value_name = "text")]
    pub titles: Vec<String>,
    /// Open new pull requests as drafts.
    #[arg(long)]
    pub draft: bool,
}

#[derive(Debug, Args)]
pub struct PrStackLinkArgs {
    #[command(flatten)]
    pub target: PrTargetArgs,
    /// Pull request numbers, bottom to top. Repeat or separate with commas.
    #[arg(
        long = "numbers",
        value_name = "n",
        value_delimiter = ',',
        required = true
    )]
    pub numbers: Vec<i64>,
}

#[derive(Debug, Args)]
pub struct PrStackMergeArgs {
    #[command(flatten)]
    pub number: PrNumberArgs,
    #[arg(long, value_enum)]
    pub method: Option<PrMergeMethodArg>,
}
