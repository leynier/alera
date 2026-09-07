use clap::{ArgGroup, Args, Subcommand, ValueEnum};

use super::{OutputArgs, PromptSourceArgs, RuntimeDirArgs};

#[derive(Debug, Args)]
pub struct AgentProfileCommand {
    #[command(flatten)]
    pub runtime: RuntimeDirArgs,
    #[command(flatten)]
    pub output: OutputArgs,
    #[command(subcommand)]
    pub action: AgentProfileAction,
}

#[derive(Debug, Subcommand)]
pub enum AgentProfileAction {
    /// List the agent profiles declared in this runtime.
    List,
    /// Show one agent profile by stable id or unique name.
    Show(AgentProfileSelectorArgs),
    /// Create a new agent profile.
    Create(AgentProfileCreateArgs),
    /// Patch an existing agent profile.
    Update(AgentProfileUpdateArgs),
    /// Preview references that affect removal.
    #[command(name = "removal-impact")]
    RemovalImpact(AgentProfileRevisionSelectorArgs),
    /// Remove an agent profile after an impact check.
    Remove(AgentProfileRemoveArgs),
    /// Replace the complete profile catalog order.
    Reorder(AgentProfileReorderArgs),
    /// Launch a declared profile in a workspace.
    Launch(AgentProfileLaunchArgs),
}

#[derive(Debug, Args)]
#[command(group(
    ArgGroup::new("profile-selector")
        .required(true)
        .multiple(false)
        .args(["profile_id", "profile_name", "profile"])
))]
pub struct AgentProfileSelectorArgs {
    /// Stable profile id.
    #[arg(long = "profile-id", value_name = "id")]
    pub profile_id: Option<String>,
    /// Unique profile name, matched case-insensitively.
    #[arg(long = "profile-name", value_name = "name")]
    pub profile_name: Option<String>,
    /// Unique profile name. Alias for --profile-name.
    #[arg(long = "profile", value_name = "name")]
    pub profile: Option<String>,
}

impl AgentProfileSelectorArgs {
    pub fn profile_name_or_alias(&self) -> Option<&str> {
        self.profile_name
            .as_deref()
            .or(self.profile.as_deref())
            .map(str::trim)
            .filter(|value| !value.is_empty())
    }
}

#[derive(Debug, Args)]
pub struct AgentProfileRevisionSelectorArgs {
    #[command(flatten)]
    pub selector: AgentProfileSelectorArgs,
    /// Require the profile revision observed by the caller.
    #[arg(long = "expected-revision", value_name = "revision")]
    pub expected_revision: Option<i64>,
}

#[derive(Debug, Args)]
pub struct AgentProfileRemoveArgs {
    #[command(flatten)]
    pub target: AgentProfileRevisionSelectorArgs,
    /// Confirm destructive removal after the runtime checks references.
    #[arg(long, required = true)]
    pub confirm: bool,
}

#[derive(Debug, Clone, Copy, ValueEnum)]
pub enum AgentProfileLaunchModeArg {
    Command,
    Managed,
}

impl AgentProfileLaunchModeArg {
    pub fn as_wire(self) -> &'static str {
        match self {
            Self::Command => "command",
            Self::Managed => "managed",
        }
    }
}

#[derive(Debug, Args)]
#[command(group(
    ArgGroup::new("managed-config-source")
        .required(false)
        .multiple(false)
        .args(["managed_config", "managed_config_file", "managed_config_stdin"])
))]
pub struct ManagedConfigInputArgs {
    /// Managed configuration as a JSON object.
    #[arg(long = "managed-config", value_name = "json")]
    pub managed_config: Option<String>,
    /// Read the managed configuration JSON object from a file.
    #[arg(long = "managed-config-file", value_name = "path")]
    pub managed_config_file: Option<String>,
    /// Read the managed configuration JSON object from standard input.
    #[arg(long = "managed-config-stdin")]
    pub managed_config_stdin: bool,
}

#[derive(Debug, Args)]
pub struct AgentProfileCreateArgs {
    #[arg(long)]
    pub name: String,
    #[arg(long = "agent-type", value_name = "adapter")]
    pub agent_type: String,
    #[arg(long = "launch-mode", value_enum)]
    pub launch_mode: AgentProfileLaunchModeArg,
    /// Interactive command for Command launch mode.
    #[arg(long, value_name = "text")]
    pub command: Option<String>,
    #[command(flatten)]
    pub managed: ManagedConfigInputArgs,
    #[arg(long = "custom-prompt", value_name = "text")]
    pub custom_prompt: Option<String>,
    #[arg(long, value_name = "text")]
    pub description: Option<String>,
    #[arg(long = "quota-group", value_name = "name")]
    pub quota_group: Option<String>,
    /// Confirm newly enabled settings that reduce agent protections.
    #[arg(long = "confirm-reduced-protections")]
    pub confirm_reduced_protections: bool,
}

#[derive(Debug, Args)]
pub struct AgentProfileUpdateArgs {
    #[command(flatten)]
    pub target: AgentProfileRevisionSelectorArgs,
    /// Replace the display name.
    #[arg(long, value_name = "name")]
    pub name: Option<String>,
    /// Replace the adapter type.
    #[arg(long = "agent-type", value_name = "adapter")]
    pub agent_type: Option<String>,
    /// Replace the launch mode.
    #[arg(long = "launch-mode", value_enum)]
    pub launch_mode: Option<AgentProfileLaunchModeArg>,
    /// Replace the interactive command for Command launch mode.
    #[arg(long, value_name = "text")]
    pub command: Option<String>,
    #[command(flatten)]
    pub managed: ManagedConfigInputArgs,
    #[arg(
        long = "custom-prompt",
        value_name = "text",
        conflicts_with = "clear_custom_prompt"
    )]
    pub custom_prompt: Option<String>,
    #[arg(long = "clear-custom-prompt")]
    pub clear_custom_prompt: bool,
    #[arg(long, value_name = "text", conflicts_with = "clear_description")]
    pub description: Option<String>,
    #[arg(long = "clear-description")]
    pub clear_description: bool,
    #[arg(
        long = "quota-group",
        value_name = "name",
        conflicts_with = "clear_quota_group"
    )]
    pub quota_group: Option<String>,
    #[arg(long = "clear-quota-group")]
    pub clear_quota_group: bool,
    /// Confirm newly enabled settings that reduce agent protections.
    #[arg(long = "confirm-reduced-protections")]
    pub confirm_reduced_protections: bool,
}

#[derive(Debug, Args)]
pub struct AgentProfileReorderArgs {
    /// Profile id in the desired order. Repeat once for every profile.
    #[arg(long = "id", value_name = "id", required = true)]
    pub ids: Vec<String>,
    /// Override a fetched revision as ID=REVISION. May be repeated.
    #[arg(long = "expected-revision", value_name = "id=revision")]
    pub expected_revisions: Vec<String>,
}

#[derive(Debug, Args)]
pub struct AgentProfileLaunchArgs {
    #[command(flatten)]
    pub selector: AgentProfileSelectorArgs,
    /// Workspace that receives the new agent tab. Defaults to ALERA_WORKSPACE_ID.
    #[arg(long = "workspace", value_name = "workspace_id")]
    pub workspace: Option<String>,
    #[command(flatten)]
    pub prompt: PromptSourceArgs,
    /// Stable mutation id used to retry an identical launch.
    #[arg(long = "client-mutation-id", value_name = "id")]
    pub client_mutation_id: Option<String>,
}
