use crate::cli_orchestration::OrchestrationCommand;
use crate::terminal_host::protocol::{
    DEFAULT_DETACHED_SESSION_SHUTDOWN_DELAY_SECONDS, DEFAULT_EMPTY_SHUTDOWN_DELAY_SECONDS,
    DEFAULT_SCROLLBACK_BYTES, TERMINAL_HOST_COMMAND,
};
mod automation;
mod browser;
mod canvas;
mod computer;
mod emulator;
mod mobile;
mod workspace;

pub use automation::*;
pub use browser::*;
pub use canvas::*;
pub use computer::*;
pub use emulator::*;
pub use mobile::*;
pub use workspace::*;

use clap::{Args, Parser, Subcommand, ValueEnum};
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
    /// Start the automation host from a native user-login entry.
    #[command(name = "automation-host", hide = true)]
    AutomationHost(AutomationHostArgs),
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

    /// Read and drive local desktop application UI.
    Computer(ComputerCommand),

    /// Inspect and automate browser tabs owned by the Alera desktop app.
    Browser(BrowserCommand),

    /// Inspect and automate Android emulators and iOS simulators.
    Emulator(EmulatorCommand),

    /// Publish and inspect Agent Canvas surfaces owned by terminal sessions.
    Canvas(CanvasCommand),

    /// Manage runtime-local automations and their runs.
    Automation(AutomationCommand),

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
    /// List live terminal sessions.
    List(crate::cli_orchestration::OrchestrationTerminalListArgs),
    /// Show one terminal session.
    Show(crate::cli_orchestration::OrchestrationTerminalShowArgs),
    /// Wait for a terminal lifecycle state.
    Wait(crate::cli_orchestration::OrchestrationTerminalWaitArgs),
    /// List or remove stopped terminal sessions.
    Prune(crate::cli_orchestration::OrchestrationTerminalPruneArgs),
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
    #[arg(long, conflicts_with = "submit")]
    pub enter: bool,
    /// Submit to an interactive TUI using bracketed paste and a delayed Enter.
    #[arg(long, conflicts_with = "enter")]
    pub submit: bool,
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

    /// Maximum bytes replayed into a client emulator after attach.
    #[arg(
        long = "restore-snapshot-bytes",
        value_name = "bytes",
        value_parser = clap::value_parser!(u64).range(1..),
        hide = true,
    )]
    pub restore_snapshot_bytes: Option<u64>,

    /// Whether new terminal sessions use the platform login shell.
    #[arg(long = "login-shell", value_name = "bool", hide = true)]
    pub login_shell: Option<bool>,

    /// Keep the runtime alive until an explicit shutdown request.
    #[arg(long)]
    pub persistent: bool,

    /// Log level for the host log file. ALERA_HOST_LOG overrides it.
    #[arg(long = "log-level", value_name = "level", default_value = "info")]
    pub log_level: String,

    /// Send crashes to Sentry. Off unless the user opted in.
    #[arg(long = "crash-reporting")]
    pub crash_reporting: bool,

    /// PID of the exact runtime owner this intentional handoff replaces.
    #[arg(
        long = "handoff-owner-pid",
        value_name = "pid",
        requires = "handoff_owner_start_marker",
        hide = true
    )]
    pub handoff_owner_pid: Option<u32>,

    /// Process start marker of the exact runtime owner this handoff replaces.
    #[arg(
        long = "handoff-owner-start-marker",
        value_name = "marker",
        requires = "handoff_owner_pid",
        hide = true
    )]
    pub handoff_owner_start_marker: Option<u64>,
}

#[derive(Debug, Args)]
pub struct AutomationHostArgs {
    /// Runtime profile directory used by the automation host.
    #[arg(long = "runtime-dir", value_name = "path")]
    pub runtime_dir: String,
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
    /// Start a persistent runtime host in the background.
    Start,
    /// Stop the running runtime host.
    Stop(RuntimeStopArgs),
    /// Delete runtime state so the next start creates a clean profile.
    Clear(RuntimeClearArgs),
    /// Inspect or change runtime-owned agent integrations.
    Agents(RuntimeAgentsCommand),
}

#[derive(Debug, Args)]
pub struct RuntimeStopArgs {
    /// Stop even when terminals or background jobs are active.
    #[arg(long)]
    pub force: bool,
}

#[derive(Debug, Args)]
pub struct RuntimeClearArgs {
    /// Stop a live host and terminate active terminals, agents, and jobs before clearing.
    #[arg(long)]
    pub force: bool,
}

#[derive(Debug, Args)]
pub struct RuntimeAgentsCommand {
    #[command(subcommand)]
    pub action: RuntimeAgentsAction,
}

#[derive(Debug, Subcommand)]
pub enum RuntimeAgentsAction {
    /// Show enabled runtime agent integrations.
    Status,
    /// Enable one or more agent integrations.
    Enable(RuntimeAgentsChangeArgs),
    /// Disable one or more agent integrations.
    Disable(RuntimeAgentsChangeArgs),
}

#[derive(Debug, Args)]
pub struct RuntimeAgentsChangeArgs {
    /// Agent keys: codex, claude, copilot, cursor, agy, opencode, opencode2, pi, amp, grok.
    #[arg(value_name = "agent", required_unless_present = "all")]
    pub agents: Vec<String>,

    /// Apply the change to every supported agent.
    #[arg(long, conflicts_with = "agents")]
    pub all: bool,
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
