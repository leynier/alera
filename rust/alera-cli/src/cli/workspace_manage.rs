//! Arguments for listing, pinning, sectioning, and removing workspaces.

use clap::{Args, Subcommand, ValueEnum};

use super::IdArgs;

#[derive(Debug, Args)]
pub struct WorkspaceListArgs {
    #[arg(long = "project-id")]
    pub project_id: Option<String>,
    #[arg(long)]
    pub all: bool,
    /// Only workspaces on this host: an SSH target id, or `local`.
    #[arg(long = "host-id")]
    pub host_id: Option<String>,
    /// Only workspaces in this section. `none` lists those in Others.
    #[arg(long = "section-id")]
    pub section_id: Option<String>,
    /// Only workspaces with this tag.
    #[arg(long = "tag-id")]
    pub tag_id: Option<String>,
    /// Only archived workspaces (`true`) or only visible ones (`false`).
    #[arg(long, value_name = "bool")]
    pub archived: Option<bool>,
    /// Only the children of this workspace.
    #[arg(long = "parent-workspace-id")]
    pub parent_workspace_id: Option<String>,
}

#[derive(Debug, Args)]
pub struct WorkspacePinArgs {
    #[arg(long)]
    pub id: String,
    /// Also apply to every descendant of the workspace (Pin Workspace Tree).
    #[arg(long)]
    pub tree: bool,
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
    /// Run the Alera app's Remove flow: save or discard the editors open on
    /// the workspace in connected apps, close its sessions, pause dependent
    /// automations and cancel their runs, refuse when storage cleanup is
    /// blocked, and delete the branch when it can be deleted unless
    /// --keep-branch. Uncommitted changes in the worktree are lost.
    #[arg(long = "editor-buffers", value_enum, value_name = "save|discard")]
    pub editor_buffers: Option<EditorBuffersArg>,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, ValueEnum)]
pub enum EditorBuffersArg {
    Save,
    Discard,
}

impl EditorBuffersArg {
    pub fn as_str(self) -> &'static str {
        match self {
            Self::Save => "save",
            Self::Discard => "discard",
        }
    }
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
    /// Also assign every descendant of the workspace.
    #[arg(long)]
    pub tree: bool,
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
    /// Also assign every descendant of the workspace (Set Section Tree).
    #[arg(long)]
    pub tree: bool,
}

#[derive(Debug, Args)]
pub struct WorkspaceSectionWorkspaceArgs {
    #[arg(long = "workspace-id")]
    pub workspace_id: String,
    /// Also move every descendant of the workspace to Others.
    #[arg(long)]
    pub tree: bool,
}
