//! `alera ssh-target`: saved hosts, their Alera runtime install and update,
//! and the hub's link to them.

use clap::{Args, Subcommand, ValueEnum};

use super::{IdArgs, OutputArgs, RuntimeDirArgs};

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
    /// List saved hosts.
    List,
    /// Save a new host. Does not install the Alera runtime or create a remote workspace. Fails when the id is already saved.
    Add(SshTargetAddArgs),
    /// Change a saved host. Only the flags given change; the installed Alera runtime and its status are kept.
    Update(SshTargetUpdateArgs),
    /// Remove a saved host.
    Remove(IdArgs),
    /// Probe SSH connectivity and, when installed, the Alera runtime on a host.
    Status(SshTargetStatusArgs),
    /// Preview the steps that install the Alera runtime on a host. Does not create a remote worktree.
    BootstrapPlan(SshTargetBootstrapPlanArgs),
    /// Install the Alera runtime on a host. Does not create a remote Git worktree.
    Bootstrap(SshTargetBootstrapArgs),
    /// Cancel an Alera runtime install in progress.
    BootstrapCancel(IdArgs),
    /// Install the latest stable Alera runtime on a host and restart the host's runtime onto it. Prints the install job; follow it with `ssh-target status`.
    UpdateRuntime(SshTargetRuntimeArgs),
    /// Restart a host's Alera runtime so it runs the version installed there. Terminals open on the host block it unless --force.
    RestartRuntime(SshTargetRuntimeArgs),
    /// Show, open, or close this runtime's persistent link to a host's Alera runtime.
    Link(SshTargetLinkArgs),
}

#[derive(Debug, Args)]
pub struct SshTargetLinkArgs {
    /// Host id. Omit to list every link the runtime knows.
    #[arg(long)]
    pub id: Option<String>,
    /// Open the link (starts the host's Alera runtime when needed).
    #[arg(long, conflicts_with = "disconnect")]
    pub connect: bool,
    /// Close the link.
    #[arg(long, conflicts_with = "connect")]
    pub disconnect: bool,
}

#[derive(Debug, Args)]
pub struct SshTargetAddArgs {
    /// Host id. Defaults to a new UUID.
    #[arg(long)]
    pub id: Option<String>,
    /// Display name, unique among saved hosts.
    #[arg(long)]
    pub alias: String,
    /// Hostname or address ssh connects to.
    #[arg(long)]
    pub host: String,
    #[arg(long, default_value_t = 22)]
    pub port: i64,
    #[arg(long)]
    pub username: String,
    /// `macos`, `linux`, or `windows`. Detected during bootstrap when omitted.
    #[arg(long)]
    pub platform: Option<String>,
    /// `x64` or `arm64`. Detected during bootstrap when omitted.
    #[arg(long)]
    pub arch: Option<String>,
    #[arg(long = "auth", value_enum, default_value_t = SshAuthKindArg::Agent)]
    pub auth_kind: SshAuthKindArg,
    /// Folder on the host where projects are cloned when no path is given
    /// (default: alera-projects under the remote home). `~/` and `%VAR%` are
    /// expanded on the host.
    #[arg(long)]
    pub projects_dir: Option<String>,
    /// Private key ssh uses for this host (`ssh -i`, with IdentitiesOnly).
    #[arg(long)]
    pub identity_file: Option<String>,
}

#[derive(Debug, Args)]
pub struct SshTargetUpdateArgs {
    /// Saved host to change.
    #[arg(long)]
    pub id: String,
    /// New display name, unique among saved hosts.
    #[arg(long)]
    pub alias: Option<String>,
    /// New hostname or address. Bootstrap again when it names another machine.
    #[arg(long)]
    pub host: Option<String>,
    #[arg(long)]
    pub port: Option<i64>,
    #[arg(long)]
    pub username: Option<String>,
    /// `macos`, `linux`, or `windows`; an empty value clears it.
    #[arg(long)]
    pub platform: Option<String>,
    /// `x64` or `arm64`; an empty value clears it.
    #[arg(long)]
    pub arch: Option<String>,
    #[arg(long = "auth", value_enum)]
    pub auth_kind: Option<SshAuthKindArg>,
    /// Folder on the host where projects are cloned; an empty value restores
    /// the default (alera-projects under the remote home).
    #[arg(long)]
    pub projects_dir: Option<String>,
    /// Private key ssh uses for this host; an empty value goes back to the
    /// SSH agent and ~/.ssh/config.
    #[arg(long)]
    pub identity_file: Option<String>,
}

#[derive(Debug, Clone, Copy, ValueEnum)]
pub enum SshAuthKindArg {
    /// Hidden so help does not advertise it; add still parses it and rejects
    /// with the bootstrap product error.
    #[value(hide = true)]
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
pub struct SshTargetRuntimeArgs {
    /// Saved host.
    #[arg(long)]
    pub id: String,
    /// Restart even though terminals are still open on the host; they close.
    #[arg(long)]
    pub force: bool,
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
    /// After the install, restart the host's Alera runtime onto the new version. Runs through the Alera runtime, starting it when needed.
    #[arg(long = "restart-runtime")]
    pub restart_runtime: bool,
    /// With --restart-runtime, restart even though terminals are still open on the host; they close.
    #[arg(long, requires = "restart_runtime")]
    pub force: bool,
}
