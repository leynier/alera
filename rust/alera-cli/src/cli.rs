use clap::{Args, Parser, Subcommand, ValueEnum};

use crate::cli_orchestration::OrchestrationCommand;
use crate::terminal_host::protocol::{
    DEFAULT_DETACHED_SESSION_SHUTDOWN_DELAY_SECONDS, DEFAULT_EMPTY_SHUTDOWN_DELAY_SECONDS,
    DEFAULT_SCROLLBACK_BYTES, TERMINAL_HOST_COMMAND,
};

/// Top-level CLI, mirroring the Dart `AleraCliCommandRunner`.
#[derive(Debug, Parser)]
#[command(
    name = "alera",
    about = "Alera command line tools.",
    disable_help_subcommand = true
)]
pub struct Cli {
    #[command(subcommand)]
    pub command: Command,
}

#[derive(Debug, Subcommand)]
pub enum Command {
    /// Show CLI, host, orchestration, preamble, and skill contract versions.
    Version(VersionCommand),
    /// Run the persistent runtime host sidecar.
    #[command(name = RUNTIME_HOST_COMMAND)]
    RuntimeHost(TerminalHostArgs),

    /// Serve newline-delimited runtime proxy requests over stdin/stdout.
    #[command(name = "runtime-proxy")]
    RuntimeProxy,

    /// Run the persistent terminal host sidecar.
    #[command(name = TERMINAL_HOST_COMMAND)]
    TerminalHost(TerminalHostArgs),

    /// Inspect or operate the local Alera runtime profile.
    Runtime(RuntimeCommand),

    /// Create, list, update, and remove runtime-owned projects.
    Project(ProjectCommand),

    /// Create, list, tag, relate, and remove runtime-owned workspaces.
    Workspace(WorkspaceCommand),

    /// Manage global workspace tags.
    Tag(TagCommand),

    /// Manage runtime-owned workspace tabs.
    Tab(TabCommand),

    /// Inspect and write live terminal sessions.
    Terminal(TerminalCommand),

    /// Manage SSH targets known by the Home Runtime.
    #[command(name = "ssh-target")]
    SshTarget(SshTargetCommand),

    /// Manage mobile companion access and pairing.
    Mobile(MobileCommand),

    /// Inter-agent orchestration: messaging, task DAG, dispatch, gates, coordinator.
    Orchestration(OrchestrationCommand),
}

#[derive(Debug, Args)]
pub struct TerminalCommand {
    #[command(flatten)]
    pub runtime: RuntimeDirArgs,
    #[command(flatten)]
    pub output: OutputArgs,
    #[command(subcommand)]
    pub action: TerminalAction,
}

#[derive(Debug, Subcommand)]
pub enum TerminalAction {
    /// Read retained terminal output, optionally from an incremental cursor.
    Read(TerminalReadArgs),
    /// Write text, a file, or stdin to a terminal.
    Write(TerminalWriteArgs),
}

#[derive(Debug, Args)]
pub struct TerminalReadArgs {
    #[arg(long)]
    pub handle: String,
    #[arg(long)]
    pub cursor: Option<u64>,
    #[arg(long = "max-bytes", default_value_t = 65_536)]
    pub max_bytes: u64,
}

#[derive(Debug, Args)]
pub struct TerminalWriteArgs {
    #[arg(long)]
    pub handle: String,
    #[arg(long, conflicts_with_all = ["file", "stdin"])]
    pub text: Option<String>,
    #[arg(long, conflicts_with_all = ["text", "stdin"])]
    pub file: Option<String>,
    #[arg(long, conflicts_with_all = ["text", "file"])]
    pub stdin: bool,
    #[arg(long)]
    pub enter: bool,
}

#[derive(Debug, Args)]
pub struct VersionCommand {
    #[command(flatten)]
    pub runtime: RuntimeDirArgs,
    #[command(flatten)]
    pub output: OutputArgs,
}

/// Arguments for `alera runtime-host` and `alera terminal-host`. Names and
/// defaults match the Dart launcher so the app can keep using the same sidecar.
#[derive(Debug, Args)]
pub struct TerminalHostArgs {
    /// Directory used for host control and terminal checkpoints.
    #[arg(long = "runtime-dir", value_name = "path")]
    pub runtime_dir: String,

    /// JSON file where the host publishes its socket metadata.
    #[arg(long = "control-file", value_name = "path")]
    pub control_file: String,

    /// Shared authentication token expected by the host.
    #[arg(long = "token", value_name = "token")]
    pub token: String,

    /// Seconds to keep an empty host alive after the app disconnects.
    #[arg(
        long = "empty-shutdown-delay-seconds",
        value_name = "seconds",
        default_value_t = DEFAULT_EMPTY_SHUTDOWN_DELAY_SECONDS,
        value_parser = clap::value_parser!(u64).range(1..),
    )]
    pub empty_shutdown_delay_seconds: u64,

    /// Seconds to keep detached running terminal sessions alive after the app disconnects.
    #[arg(
        long = "detached-session-shutdown-delay-seconds",
        value_name = "seconds",
        default_value_t = DEFAULT_DETACHED_SESSION_SHUTDOWN_DELAY_SECONDS,
        value_parser = clap::value_parser!(u64).range(1..),
    )]
    pub detached_session_shutdown_delay_seconds: u64,

    /// Maximum host-side output bytes retained per terminal session.
    #[arg(
        long = "scrollback-bytes",
        value_name = "bytes",
        default_value_t = DEFAULT_SCROLLBACK_BYTES,
        value_parser = clap::value_parser!(u64).range(1..),
    )]
    pub scrollback_bytes: u64,
}

#[derive(Debug, Args, Clone)]
pub struct RuntimeDirArgs {
    /// Runtime profile directory. Defaults to ALERA_RUNTIME_DIR or ~/.alera/runtime.
    #[arg(long = "runtime-dir", value_name = "path")]
    pub runtime_dir: Option<String>,
}

#[derive(Debug, Args)]
pub struct OutputArgs {
    /// Print machine-readable JSON.
    #[arg(long = "json")]
    pub json: bool,
}

#[derive(Debug, Args)]
pub struct RuntimeCommand {
    #[command(flatten)]
    pub runtime: RuntimeDirArgs,
    #[command(flatten)]
    pub output: OutputArgs,
    #[command(subcommand)]
    pub action: RuntimeAction,
}

#[derive(Debug, Subcommand)]
pub enum RuntimeAction {
    /// Show runtime database and profile status.
    Status,
}

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
    /// List all projects.
    List,
    /// Register a local project path.
    Add(ProjectAddArgs),
    /// Remove a project and runtime-owned child records.
    Remove(IdArgs),
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
    /// Remove an Alera-managed Git worktree workspace.
    Remove(WorkspaceRemoveArgs),
    /// Register a workspace record without touching Git worktrees.
    Register(WorkspaceRegisterArgs),
    /// Remove a workspace record and related runtime records without touching Git worktrees.
    Unregister(IdArgs),
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
pub struct WorkspaceRemoveArgs {
    #[arg(long)]
    pub id: String,
    #[arg(long = "delete-branch", conflicts_with = "keep_branch")]
    pub delete_branch: bool,
    #[arg(long = "keep-branch", conflicts_with = "delete_branch")]
    pub keep_branch: bool,
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

#[derive(Debug, Args)]
pub struct TagCommand {
    #[command(flatten)]
    pub runtime: RuntimeDirArgs,
    #[command(flatten)]
    pub output: OutputArgs,
    #[command(subcommand)]
    pub action: TagAction,
}

#[derive(Debug, Subcommand)]
pub enum TagAction {
    List,
    Upsert(TagUpsertArgs),
    Remove(IdArgs),
}

#[derive(Debug, Args)]
pub struct TagUpsertArgs {
    #[arg(long)]
    pub id: Option<String>,
    #[arg(long)]
    pub name: String,
    #[arg(long)]
    pub color: Option<String>,
}

#[derive(Debug, Args)]
pub struct TabCommand {
    #[command(flatten)]
    pub runtime: RuntimeDirArgs,
    #[command(flatten)]
    pub output: OutputArgs,
    #[command(subcommand)]
    pub action: TabAction,
}

#[derive(Debug, Subcommand)]
pub enum TabAction {
    List(WorkspaceIdArgs),
    Create(TabCreateArgs),
    Remove(IdArgs),
}

#[derive(Debug, Args)]
pub struct TabCreateArgs {
    #[arg(long = "workspace-id")]
    pub workspace_id: String,
    #[arg(long)]
    pub title: String,
    #[arg(long, default_value = "terminal")]
    pub kind: String,
    /// Initial command executed in the terminal after the shell starts
    /// (terminal tabs only), e.g. an agent CLI like "claude".
    #[arg(long, value_name = "text")]
    pub command: Option<String>,
    /// Start the terminal session as soon as the tab is created, even
    /// before it becomes visible in the app.
    #[arg(long)]
    pub spawn: bool,
}

#[derive(Debug, Args)]
pub struct SshTargetCommand {
    #[command(flatten)]
    pub runtime: RuntimeDirArgs,
    #[command(flatten)]
    pub output: OutputArgs,
    #[command(subcommand)]
    pub action: SshTargetAction,
}

#[derive(Debug, Subcommand)]
pub enum SshTargetAction {
    List,
    Add(SshTargetAddArgs),
    Remove(IdArgs),
    Status(SshTargetStatusArgs),
    BootstrapPlan(SshTargetBootstrapPlanArgs),
    Bootstrap(SshTargetBootstrapArgs),
    BootstrapCancel(IdArgs),
}

#[derive(Debug, Args)]
pub struct SshTargetAddArgs {
    #[arg(long)]
    pub id: Option<String>,
    #[arg(long)]
    pub alias: String,
    #[arg(long)]
    pub host: String,
    #[arg(long, default_value_t = 22)]
    pub port: i64,
    #[arg(long)]
    pub username: String,
    #[arg(long)]
    pub platform: Option<String>,
    #[arg(long)]
    pub arch: Option<String>,
    #[arg(long = "auth", value_enum, default_value_t = SshAuthKindArg::Agent)]
    pub auth_kind: SshAuthKindArg,
}

#[derive(Debug, Clone, Copy, ValueEnum)]
pub enum SshAuthKindArg {
    Password,
    Key,
    Agent,
}

#[derive(Debug, Args)]
pub struct SshTargetStatusArgs {
    #[arg(long)]
    pub id: Option<String>,
}

#[derive(Debug, Args)]
pub struct SshTargetBootstrapPlanArgs {
    #[arg(long)]
    pub id: String,
    #[arg(long)]
    pub channel: Option<String>,
    #[arg(long)]
    pub version: Option<String>,
    #[arg(long = "install-dir")]
    pub install_dir: Option<String>,
    #[arg(long)]
    pub platform: Option<String>,
    #[arg(long)]
    pub arch: Option<String>,
    #[arg(long = "archive-url")]
    pub archive_url: Option<String>,
    #[arg(long = "archive-path")]
    pub archive_path: Option<String>,
    #[arg(long = "artifact-path")]
    pub artifact_path: Option<String>,
    #[arg(long = "manifest-public-key")]
    pub manifest_public_key: Option<String>,
}

#[derive(Debug, Args)]
pub struct SshTargetBootstrapArgs {
    #[arg(long)]
    pub id: String,
    #[arg(long)]
    pub channel: Option<String>,
    #[arg(long)]
    pub version: Option<String>,
    #[arg(long = "install-dir")]
    pub install_dir: Option<String>,
    #[arg(long)]
    pub platform: Option<String>,
    #[arg(long)]
    pub arch: Option<String>,
    #[arg(long = "archive-url")]
    pub archive_url: Option<String>,
    #[arg(long = "archive-path")]
    pub archive_path: Option<String>,
    #[arg(long = "artifact-path")]
    pub artifact_path: Option<String>,
    #[arg(long = "manifest-public-key")]
    pub manifest_public_key: Option<String>,
}

#[derive(Debug, Args)]
pub struct MobileCommand {
    #[command(flatten)]
    pub runtime: RuntimeDirArgs,
    #[command(flatten)]
    pub output: OutputArgs,
    #[command(subcommand)]
    pub action: MobileAction,
}

#[derive(Debug, Subcommand)]
pub enum MobileAction {
    /// Show mobile access settings, devices, and active pairing offers.
    Status,
    /// Enable the mobile gateway settings.
    Enable(MobileEnableArgs),
    /// Disable the mobile gateway settings.
    Disable,
    /// Create a short-lived pairing offer.
    Pairing(MobilePairingCommand),
    /// List or revoke paired devices.
    Devices(MobileDevicesCommand),
}

#[derive(Debug, Args)]
pub struct MobileEnableArgs {
    #[arg(long = "bind-host")]
    pub bind_host: Option<String>,
    #[arg(long)]
    pub port: Option<i64>,
}

#[derive(Debug, Args)]
pub struct MobilePairingCommand {
    #[command(subcommand)]
    pub action: MobilePairingAction,
}

#[derive(Debug, Subcommand)]
pub enum MobilePairingAction {
    /// Create a short-lived pairing offer for QR or manual entry.
    Create(MobilePairingCreateArgs),
    /// Claim a pairing offer and create a revocable device record.
    Claim(MobilePairingClaimArgs),
}

#[derive(Debug, Args)]
pub struct MobilePairingCreateArgs {
    #[arg(long)]
    pub endpoint: Option<String>,
    #[arg(long = "device-name")]
    pub device_name: Option<String>,
    #[arg(long = "expires-minutes")]
    pub expires_minutes: Option<i64>,
}

#[derive(Debug, Args)]
pub struct MobilePairingClaimArgs {
    #[arg(long = "pairing-id")]
    pub pairing_id: String,
    #[arg(long = "pairing-secret")]
    pub pairing_secret: String,
    #[arg(long = "device-name")]
    pub device_name: Option<String>,
    #[arg(long = "public-key-b64")]
    pub public_key_b64: Option<String>,
}

#[derive(Debug, Args)]
pub struct MobileDevicesCommand {
    #[command(subcommand)]
    pub action: MobileDevicesAction,
}

#[derive(Debug, Subcommand)]
pub enum MobileDevicesAction {
    /// List paired mobile devices.
    List(MobileDeviceListArgs),
    /// Revoke a paired mobile device.
    Revoke(IdArgs),
}

#[derive(Debug, Args)]
pub struct MobileDeviceListArgs {
    #[arg(long = "include-revoked")]
    pub include_revoked: bool,
}

#[derive(Debug, Args)]
pub struct IdArgs {
    #[arg(long)]
    pub id: String,
}

#[derive(Debug, Args)]
pub struct WorkspaceIdArgs {
    #[arg(long = "workspace-id")]
    pub workspace_id: String,
}

pub const RUNTIME_HOST_COMMAND: &str = "runtime-host";
