use clap::{Args, Subcommand, ValueEnum};

use super::{AgentProfileSelectorArgs, IdArgs, OutputArgs, PromptSourceArgs, RuntimeDirArgs};

#[derive(Debug, Args)]
pub struct WorkspaceCommand {
    #[command(flatten)]
    pub runtime: RuntimeDirArgs,
    #[command(flatten)]
    pub output: OutputArgs,
    #[command(subcommand)]
    pub action: WorkspaceAction,
}

#[derive(Debug, Subcommand)]
pub enum WorkspaceAction {
    /// List workspaces for one project or all projects.
    List(WorkspaceListArgs),
    /// Create a task on the project folder, or use --worktree for an exclusive Git worktree.
    Add(WorkspaceAddArgs),
    /// Create a task on the project folder and launch an agent profile. Use --worktree for isolation.
    Start(WorkspaceStartArgs),
    /// Remove task state and optionally its owned worktree. Shared project files are preserved.
    Remove(WorkspaceRemoveArgs),
    /// Apply the project's worktree setup to an existing workspace.
    Setup(WorkspaceSetupArgs),
    /// Inspect persisted relocation phases and setup receipts without running commands.
    Recovery(IdArgs),
    /// Register a workspace record without touching Git worktrees. --host-id is metadata only and does not create a remote worktree.
    Register(WorkspaceRegisterArgs),
    /// Remove a workspace record and related runtime records without touching Git worktrees.
    Unregister(IdArgs),
    /// Pin a workspace in the desktop sidebar.
    Pin(IdArgs),
    /// Unpin a workspace from the desktop sidebar.
    Unpin(IdArgs),
    /// Add a parent/child relationship.
    Link(WorkspaceLinkArgs),
    /// Remove a parent/child relationship.
    Unlink(WorkspaceLinkArgs),
    /// Assign a tag to a workspace.
    Tag(WorkspaceTagArgs),
    /// Remove a tag from a workspace.
    Untag(WorkspaceTagArgs),
    /// Preview opt-in cascade targets.
    CascadePreview(CascadePreviewArgs),
    /// Move this task from the project checkout to an exclusive worktree.
    #[command(name = "hand-off")]
    HandOff(WorkspaceHandOffArgs),
    /// Move this task back to its project's checkout on the same host.
    #[command(name = "hand-on")]
    HandOn(WorkspaceHandOnArgs),
    /// Show, link, or unlink the issue a workspace was created for.
    Issue(WorkspaceIssueCommand),
    /// Start, stop, or inspect Watch and Fix for the workspace pull request.
    #[command(name = "pr-watch")]
    PrWatch(WorkspacePrWatchCommand),
    /// List, create, assign, and remove workspace sections.
    Section(WorkspaceSectionCommand),
}

#[derive(Debug, Args)]
pub struct WorkspaceListArgs {
    #[arg(long = "project-id")]
    pub project_id: Option<String>,
    #[arg(long)]
    pub all: bool,
}

#[derive(Debug, Args)]
pub struct WorkspaceAddArgs {
    /// Create a new exclusive worktree instead of sharing the project folder.
    #[arg(long)]
    pub worktree: bool,
    #[arg(long)]
    pub id: Option<String>,
    #[arg(long = "project-id")]
    pub project_id: String,
    #[arg(long, requires = "worktree", required_if_eq("worktree", "true"))]
    pub branch: Option<String>,
    #[arg(long = "source-branch", requires = "worktree")]
    pub source_branch: Option<String>,
    #[arg(long)]
    pub name: Option<String>,
    #[arg(long = "reuse-existing-branch", requires = "worktree")]
    pub reuse_existing_branch: bool,
    #[arg(
        long = "workspace-root",
        conflicts_with = "path",
        requires = "worktree"
    )]
    pub workspace_root: Option<String>,
    #[arg(long, conflicts_with = "workspace_root", requires = "worktree")]
    pub path: Option<String>,
    #[arg(long = "parent-workspace-id")]
    pub parent_workspace_id: Option<String>,
    /// Bootstrapped SSH target that should own the Git worktree. Omit for the local host.
    #[arg(long = "host-id")]
    pub host_id: Option<String>,
    /// Issue URL to link to the new workspace (GitHub, GitLab, Azure DevOps, or any tracker URL).
    #[arg(long = "issue", value_name = "url")]
    pub issue: Option<String>,
    /// Assign the new workspace to this section by unique name (case-insensitive).
    #[arg(long = "section", conflicts_with = "section_id")]
    pub section: Option<String>,
    /// Assign the new workspace to this section by id.
    #[arg(long = "section-id", conflicts_with = "section")]
    pub section_id: Option<String>,
}

#[derive(Debug, Args)]
pub struct WorkspaceStartArgs {
    /// Create a new exclusive worktree instead of sharing the project folder.
    #[arg(long)]
    pub worktree: bool,
    #[command(flatten)]
    pub selector: AgentProfileSelectorArgs,
    #[command(flatten)]
    pub prompt: PromptSourceArgs,
    /// Workspace used to infer the project and worktree source branch. Defaults to ALERA_WORKSPACE_ID.
    #[arg(long = "workspace", value_name = "workspace_id")]
    pub workspace: Option<String>,
    #[arg(long)]
    pub id: Option<String>,
    #[arg(long = "project-id")]
    pub project_id: Option<String>,
    #[arg(long, requires = "worktree")]
    pub branch: Option<String>,
    #[arg(long = "source-branch", requires = "worktree")]
    pub source_branch: Option<String>,
    #[arg(long)]
    pub name: Option<String>,
    #[arg(
        long = "workspace-root",
        conflicts_with = "path",
        requires = "worktree"
    )]
    pub workspace_root: Option<String>,
    #[arg(long, conflicts_with = "workspace_root", requires = "worktree")]
    pub path: Option<String>,
    #[arg(long = "parent-workspace-id", conflicts_with = "no_parent")]
    pub parent_workspace_id: Option<String>,
    /// Do not link the new workspace to the current workspace.
    #[arg(long = "no-parent")]
    pub no_parent: bool,
    /// Bootstrapped SSH target that should own the Git worktree. Omit for the local host.
    #[arg(long = "host-id")]
    pub host_id: Option<String>,
    /// Stable mutation id used to retry the profile launch.
    #[arg(long = "client-mutation-id", value_name = "id")]
    pub client_mutation_id: Option<String>,
    /// Issue URL to link to the new workspace (GitHub, GitLab, Azure DevOps, or any tracker URL).
    #[arg(long = "issue", value_name = "url")]
    pub issue: Option<String>,
    /// Assign the new workspace to this section by unique name (case-insensitive).
    #[arg(long = "section", conflicts_with = "section_id")]
    pub section: Option<String>,
    /// Assign the new workspace to this section by id.
    #[arg(long = "section-id", conflicts_with = "section")]
    pub section_id: Option<String>,
}

#[derive(Debug, Args)]
pub struct WorkspaceRemoveArgs {
    #[arg(long)]
    pub id: String,
    #[arg(long = "delete-branch", conflicts_with = "keep_branch")]
    pub delete_branch: bool,
    #[arg(long = "keep-branch", conflicts_with = "delete_branch")]
    pub keep_branch: bool,
    /// Stop only this workspace's processes before removal; otherwise active sessions block removal.
    #[arg(long = "close-sessions")]
    pub close_sessions: bool,
    /// Pause dependent automations and cancel all their active runs before removing the workspace.
    #[arg(long = "pause-automations-and-cancel-runs")]
    pub pause_automations_and_cancel_runs: bool,
}

#[derive(Debug, Args)]
pub struct WorkspaceSetupArgs {
    #[arg(long)]
    pub id: String,
    /// Apply only copy actions (`worktree.copy` plus `.worktreeinclude`) and
    /// skip `worktree.setup`. This is what the generated Setup terminal script
    /// calls, so the copy validation stays in Rust instead of being rewritten
    /// in shell.
    #[arg(long = "copies-only")]
    pub copies_only: bool,
    /// Execute the persisted setup recipe for this relocation once.
    #[arg(long, conflicts_with = "copies_only")]
    pub relocation_id: Option<String>,
    /// Recreate the launcher for pending relocation setup without running its commands.
    #[arg(long, requires = "relocation_id")]
    pub prepare: bool,
    /// Request cancellation of the specified setup attempt.
    #[arg(long, group = "setup_attempt_action", requires_all = ["relocation_id", "attempt_id"], conflicts_with_all = ["prepare", "copies_only"])]
    pub cancel: bool,
    /// Close an interrupted attempt only after verifying process closure, without repeating commands.
    #[arg(long, group = "setup_attempt_action", requires_all = ["relocation_id", "attempt_id"], conflicts_with_all = ["prepare", "copies_only", "cancel"])]
    pub recover: bool,
    /// Attempt identity shown by workspace recovery; scopes cancellation or recovery.
    #[arg(long, requires_all = ["relocation_id", "setup_attempt_action"])]
    pub attempt_id: Option<String>,
}

#[derive(Debug, Args)]
pub struct WorkspaceRegisterArgs {
    #[arg(long)]
    pub id: Option<String>,
    #[arg(long = "instance-id")]
    pub instance_id: Option<String>,
    /// Metadata only. Does not create or attach a remote Git worktree.
    #[arg(long = "host-id")]
    pub host_id: Option<String>,
    #[arg(long = "project-id")]
    pub project_id: String,
    #[arg(long)]
    pub name: String,
    #[arg(long)]
    pub path: String,
    #[arg(long)]
    pub branch: Option<String>,
    #[arg(long = "source-branch")]
    pub source_branch: Option<String>,
    #[arg(long, value_enum, default_value_t = WorkspaceKindArg::Linked)]
    pub kind: WorkspaceKindArg,
    #[arg(long = "reuse-existing-branch")]
    pub reuses_existing_branch: bool,
}

#[derive(Debug, Clone, Copy, ValueEnum)]
pub enum WorkspaceKindArg {
    Main,
    Linked,
}

#[derive(Debug, Args)]
pub struct WorkspaceLinkArgs {
    #[arg(long = "parent-workspace-id")]
    pub parent_workspace_id: String,
    #[arg(long = "child-workspace-id")]
    pub child_workspace_id: String,
}

#[derive(Debug, Args)]
pub struct WorkspaceTagArgs {
    #[arg(long = "workspace-id")]
    pub workspace_id: String,
    #[arg(long = "tag-id")]
    pub tag_id: String,
}

#[derive(Debug, Args)]
pub struct WorkspaceHandOffArgs {
    /// Main workspace to move work out of. Defaults to ALERA_WORKSPACE_ID.
    #[arg(long)]
    pub id: Option<String>,
    /// Reuse this operation identity when retrying after a lost response.
    #[arg(long)]
    pub relocation_id: Option<uuid::Uuid>,
    #[arg(long)]
    pub branch: String,
    #[arg(long)]
    pub name: Option<String>,
    #[arg(long = "reuse-existing-branch")]
    pub reuse_existing_branch: bool,
    #[arg(long = "workspace-root", conflicts_with = "path")]
    pub workspace_root: Option<String>,
    #[arg(long, conflicts_with = "workspace_root")]
    pub path: Option<String>,
    #[arg(long, conflicts_with = "leave_changes")]
    pub move_changes: bool,
    #[arg(long, conflicts_with = "move_changes")]
    pub leave_changes: bool,
    #[arg(long, requires = "reuse_existing_branch")]
    pub replacement_branch: Option<String>,
    #[arg(long)]
    pub confirm_shared_impact: bool,
}

#[derive(Debug, Args)]
pub struct WorkspaceHandOnArgs {
    /// Child workspace to bring back onto main. Defaults to ALERA_WORKSPACE_ID.
    #[arg(long)]
    pub id: Option<String>,
    /// Reuse this operation identity when retrying after a lost response.
    #[arg(long)]
    pub relocation_id: Option<uuid::Uuid>,
    /// Confirm that every task on the project folder will share the resulting branch and files.
    #[arg(long)]
    pub confirm_shared_impact: bool,
}

#[derive(Debug, Args)]
pub struct CascadePreviewArgs {
    #[arg(long = "workspace-id")]
    pub workspace_ids: Vec<String>,
    #[arg(long = "tag-id")]
    pub tag_ids: Vec<String>,
    #[arg(long = "descendants")]
    pub include_descendants: bool,
    #[arg(long = "tags")]
    pub include_tags: bool,
}

#[derive(Debug, Args)]
pub struct WorkspaceIssueCommand {
    #[command(subcommand)]
    pub action: WorkspaceIssueAction,
}

#[derive(Debug, Subcommand)]
pub enum WorkspaceIssueAction {
    /// Print the linked issue, fetched fresh from its forge (title, state, body, labels).
    Show(WorkspaceIssueShowArgs),
    /// Link an issue URL to a workspace, replacing any linked issue.
    Link(WorkspaceIssueLinkArgs),
    /// Remove the workspace's linked issue.
    Unlink(WorkspaceIssueTargetArgs),
}

#[derive(Debug, Args)]
pub struct WorkspaceIssueTargetArgs {
    /// Workspace to act on. Defaults to ALERA_WORKSPACE_ID.
    #[arg(long = "workspace-id", value_name = "id")]
    pub workspace_id: Option<String>,
}

#[derive(Debug, Args)]
pub struct WorkspaceIssueShowArgs {
    #[command(flatten)]
    pub target: WorkspaceIssueTargetArgs,
    /// Print the cached title and state without contacting the forge.
    #[arg(long)]
    pub cached: bool,
}

#[derive(Debug, Args)]
pub struct WorkspaceIssueLinkArgs {
    #[command(flatten)]
    pub target: WorkspaceIssueTargetArgs,
    /// Issue URL. Unrecognized trackers are stored as a plain link.
    #[arg(value_name = "url")]
    pub url: String,
}

#[derive(Debug, Args)]
pub struct WorkspacePrWatchCommand {
    #[command(subcommand)]
    pub action: WorkspacePrWatchAction,
}

#[derive(Debug, Subcommand)]
pub enum WorkspacePrWatchAction {
    /// Print the active Watch and Fix session for a workspace.
    Show(WorkspacePrWatchTargetArgs),
    /// Watch the linked pull request and send fix prompts to an agent.
    Start(WorkspacePrWatchStartArgs),
    /// Stop Watch and Fix for a workspace.
    Stop(WorkspacePrWatchTargetArgs),
}

#[derive(Debug, Args)]
pub struct WorkspacePrWatchTargetArgs {
    /// Workspace to act on. Defaults to ALERA_WORKSPACE_ID.
    #[arg(long = "workspace-id", value_name = "id")]
    pub workspace_id: Option<String>,
}

#[derive(Debug, Args)]
pub struct WorkspacePrWatchStartArgs {
    #[command(flatten)]
    pub target: WorkspacePrWatchTargetArgs,
    /// Merge once the watched scope is clear (Watch, Fix and Merge).
    #[arg(long)]
    pub merge: bool,
    /// Skip failing CI checks.
    #[arg(long = "no-checks")]
    pub no_checks: bool,
    /// Skip unresolved review comments.
    #[arg(long = "no-comments")]
    pub no_comments: bool,
    /// Skip merge conflicts.
    #[arg(long = "no-conflicts")]
    pub no_conflicts: bool,
    /// Pull request number. Defaults to the workspace's linked review.
    #[arg(long = "review-number", value_name = "n")]
    pub review_number: Option<i64>,
    /// Terminal handle to dispatch to. Defaults to ALERA_TERMINAL_HANDLE.
    #[arg(long)]
    pub handle: Option<String>,
    /// Stable agent profile id used when the bound terminal is gone.
    #[arg(long = "profile-id", value_name = "id")]
    pub profile_id: Option<String>,
    /// Unique agent profile name. Alias for looking up --profile-id.
    #[arg(long = "profile", value_name = "name", conflicts_with = "profile_id")]
    pub profile: Option<String>,
}

#[derive(Debug, Args)]
pub struct WorkspaceSectionCommand {
    #[command(subcommand)]
    pub action: WorkspaceSectionAction,
}

#[derive(Debug, Subcommand)]
pub enum WorkspaceSectionAction {
    /// List workspace sections.
    List,
    /// Create a section and assign its first workspace.
    Create(WorkspaceSectionCreateArgs),
    /// Assign a workspace to an existing section.
    Set(WorkspaceSectionSetArgs),
    /// Move a workspace to Others (no section).
    Clear(WorkspaceSectionWorkspaceArgs),
    /// Delete a section. Workspaces are kept and moved to Others.
    Remove(IdArgs),
}

#[derive(Debug, Args)]
pub struct WorkspaceSectionCreateArgs {
    #[arg(long)]
    pub name: String,
    #[arg(long = "workspace-id")]
    pub workspace_id: String,
}

#[derive(Debug, Args)]
pub struct WorkspaceSectionSetArgs {
    #[arg(long = "workspace-id")]
    pub workspace_id: String,
    /// Unique section name, matched case-insensitively.
    #[arg(
        long = "section",
        required_unless_present = "section_id",
        conflicts_with = "section_id"
    )]
    pub section: Option<String>,
    /// Section id.
    #[arg(
        long = "section-id",
        required_unless_present = "section",
        conflicts_with = "section"
    )]
    pub section_id: Option<String>,
}

#[derive(Debug, Args)]
pub struct WorkspaceSectionWorkspaceArgs {
    #[arg(long = "workspace-id")]
    pub workspace_id: String,
}
