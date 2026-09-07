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
    /// Create an Alera-managed Git worktree workspace.
    Add(WorkspaceAddArgs),
    /// Create a managed workspace and launch a declared agent profile.
    Start(WorkspaceStartArgs),
    /// Remove an Alera-managed Git worktree workspace.
    Remove(WorkspaceRemoveArgs),
    /// Apply the project's worktree setup to an existing workspace.
    Setup(WorkspaceSetupArgs),
    /// Register a workspace record without touching Git worktrees.
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
    #[arg(long)]
    pub id: Option<String>,
    #[arg(long = "project-id")]
    pub project_id: String,
    #[arg(long)]
    pub branch: String,
    #[arg(long = "source-branch")]
    pub source_branch: Option<String>,
    #[arg(long)]
    pub name: Option<String>,
    #[arg(long = "reuse-existing-branch")]
    pub reuse_existing_branch: bool,
    #[arg(long = "workspace-root", conflicts_with = "path")]
    pub workspace_root: Option<String>,
    #[arg(long, conflicts_with = "workspace_root")]
    pub path: Option<String>,
    #[arg(long = "parent-workspace-id")]
    pub parent_workspace_id: Option<String>,
}

#[derive(Debug, Args)]
pub struct WorkspaceStartArgs {
    #[command(flatten)]
    pub selector: AgentProfileSelectorArgs,
    #[command(flatten)]
    pub prompt: PromptSourceArgs,
    /// Workspace used to infer project, source branch, and parent. Defaults to ALERA_WORKSPACE_ID.
    #[arg(long = "workspace", value_name = "workspace_id")]
    pub workspace: Option<String>,
    #[arg(long)]
    pub id: Option<String>,
    #[arg(long = "project-id")]
    pub project_id: Option<String>,
    #[arg(long)]
    pub branch: Option<String>,
    #[arg(long = "source-branch")]
    pub source_branch: Option<String>,
    #[arg(long)]
    pub name: Option<String>,
    #[arg(long = "workspace-root", conflicts_with = "path")]
    pub workspace_root: Option<String>,
    #[arg(long, conflicts_with = "workspace_root")]
    pub path: Option<String>,
    #[arg(long = "parent-workspace-id", conflicts_with = "no_parent")]
    pub parent_workspace_id: Option<String>,
    /// Do not link the new workspace to the current workspace.
    #[arg(long = "no-parent")]
    pub no_parent: bool,
    /// Stable mutation id used to retry the profile launch.
    #[arg(long = "client-mutation-id", value_name = "id")]
    pub client_mutation_id: Option<String>,
}

#[derive(Debug, Args)]
pub struct WorkspaceRemoveArgs {
    #[arg(long)]
    pub id: String,
    #[arg(long = "delete-branch", conflicts_with = "keep_branch")]
    pub delete_branch: bool,
    #[arg(long = "keep-branch", conflicts_with = "delete_branch")]
    pub keep_branch: bool,
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
}

#[derive(Debug, Args)]
pub struct WorkspaceRegisterArgs {
    #[arg(long)]
    pub id: Option<String>,
    #[arg(long = "instance-id")]
    pub instance_id: Option<String>,
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
