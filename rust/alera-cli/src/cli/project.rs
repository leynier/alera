use super::{OutputArgs, RuntimeDirArgs};
use clap::{Args, Subcommand, ValueEnum};

#[derive(Debug, Args)]
pub struct ProjectCommand {
    #[command(flatten)]
    pub runtime: RuntimeDirArgs,
    #[command(flatten)]
    pub output: OutputArgs,
    #[command(subcommand)]
    pub action: ProjectAction,
}

#[derive(Debug, Subcommand)]
pub enum ProjectAction {
    /// Control a project precheck through its owning runtime without creating a task.
    #[command(hide = true)]
    ControlOwnerPrecheck(crate::remote_owner_precheck::RemoteOwnerPrecheckArgs),
    /// Control an exact relocation setup through its existing owner runtime.
    #[command(hide = true)]
    ControlOwnerSetup(crate::remote_owner_setup::RemoteOwnerSetupArgs),
    /// Inspect persisted recovery and process evidence without starting an owner runtime.
    #[command(hide = true)]
    InspectOwnerRecovery(crate::remote_owner_recovery::RemoteOwnerRecoveryArgs),
    /// Relocate an enrolled task through its live owner runtime and return recovery evidence.
    #[command(hide = true)]
    RelocateOwnerWorkspace(crate::remote_owner_relocation::RemoteOwnerRelocationArgs),
    /// Bridge standard input/output to a terminal owned by the remote runtime.
    #[command(hide = true)]
    OwnerTerminal(crate::remote_owner_terminal::RemoteOwnerTerminalArgs),
    /// Verify an explicit terminal lifecycle action through its existing owner.
    #[command(hide = true)]
    ControlOwnerTerminal(crate::remote_owner_terminal_lifecycle::RemoteOwnerTerminalLifecycleArgs),
    /// Retire a shared task after its running owner verifies process shutdown.
    #[command(hide = true)]
    RetireOwnerWorkspace(crate::remote_owner_retirement::RemoteOwnerRetirementArgs),
    /// Register stable task ownership in the remote runtime profile.
    #[command(hide = true)]
    RegisterOwnerWorkspace(crate::remote_workspace_owner::RemoteWorkspaceOwnerArgs),
    /// Clone into a new directory on the owning host without starting a runtime.
    #[command(hide = true)]
    CloneCheckoutFolder(crate::project_checkout_clone::CloneCheckoutArgs),
    /// Create a linked worktree using only this host's repository.
    #[command(hide = true)]
    CreateCheckoutWorktree(crate::project_checkout_worktree::CreateCheckoutWorktreeArgs),
    /// Register an existing project folder on an SSH host.
    RegisterCheckout(ProjectCheckoutRegisterArgs),
    /// Inspect a checkout on its owning host without starting a runtime.
    #[command(hide = true)]
    InspectCheckout(ProjectCheckoutInspectArgs),
    /// Recover a linked checkout origin from native Git metadata without starting a runtime.
    #[command(hide = true)]
    InspectLinkedCheckout(ProjectLinkedCheckoutInspectArgs),
    /// Inspect branch choices on the owning host without starting a runtime.
    #[command(hide = true)]
    InspectCheckoutBranches(ProjectLinkedCheckoutInspectArgs),
    /// Index files on the owning host without starting a runtime.
    #[command(hide = true)]
    InspectCheckoutFiles(ProjectLinkedCheckoutInspectArgs),
    /// List all projects with the hosts each one is on.
    List,
    /// List, add, and remove the hosts a project is on.
    Hosts(ProjectHostsCommand),
    /// Register a local project path.
    Add(ProjectAddArgs),
    /// Remove a project and runtime-owned child records.
    Remove(ProjectRemoveArgs),
}

#[derive(Debug, Args)]
pub struct ProjectHostsCommand {
    #[command(subcommand)]
    pub action: ProjectHostsAction,
}

#[derive(Debug, Subcommand)]
pub enum ProjectHostsAction {
    /// List the hosts a project is on, with its path on each.
    List(ProjectHostsListArgs),
    /// Add a project to an SSH host. Without --path the host clones the
    /// project's Git remote into its default projects folder.
    Add(ProjectHostsAddArgs),
    /// Forget a project's checkout on a host. Files are never deleted.
    Remove(ProjectHostsRemoveArgs),
}

#[derive(Debug, Args)]
pub struct ProjectHostsListArgs {
    #[arg(long)]
    pub project_id: String,
}

#[derive(Debug, Args)]
pub struct ProjectHostsAddArgs {
    #[arg(long)]
    pub project_id: String,
    #[arg(long)]
    pub host_id: String,
    /// Register this existing checkout instead of cloning.
    #[arg(long)]
    pub path: Option<String>,
    /// Clone this source instead of the project's own Git remote.
    #[arg(long)]
    pub clone_url: Option<String>,
}

#[derive(Debug, Args)]
pub struct ProjectHostsRemoveArgs {
    #[arg(long)]
    pub project_id: String,
    #[arg(long)]
    pub host_id: String,
}

#[derive(Debug, Args)]
pub struct ProjectRemoveArgs {
    #[arg(long)]
    pub id: String,
    /// Pause dependent automations and cancel their active runs before project removal.
    #[arg(long)]
    pub pause_automations_and_cancel_runs: bool,
}

#[derive(Debug, Args)]
pub struct ProjectCheckoutRegisterArgs {
    /// Clone this source into the new path on the SSH host before registration.
    #[arg(long)]
    pub clone_url: Option<String>,
    #[arg(long)]
    pub project_id: String,
    #[arg(long)]
    pub host_id: String,
    #[arg(long)]
    pub path: String,
}

#[derive(Debug, Args)]
pub struct ProjectLinkedCheckoutInspectArgs {
    #[arg(long)]
    pub path: String,
}

#[derive(Debug, Args)]
pub struct ProjectCheckoutInspectArgs {
    #[arg(long)]
    pub path: String,
    #[arg(long, value_enum)]
    pub kind: ProjectKindArg,
}

#[derive(Debug, Args)]
pub struct ProjectAddArgs {
    #[arg(long)]
    pub id: Option<String>,
    #[arg(long)]
    pub name: String,
    #[arg(long = "repo-path")]
    pub repo_path: String,
    #[arg(long, value_enum, default_value_t = ProjectKindArg::GitRepository)]
    pub kind: ProjectKindArg,
}

#[derive(Debug, Clone, Copy, ValueEnum)]
pub enum ProjectKindArg {
    GitRepository,
    Folder,
}
