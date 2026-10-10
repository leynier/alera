use clap::{Args, Subcommand, ValueEnum};

use super::{OutputArgs, RuntimeDirArgs};

#[derive(Debug, Args)]
pub struct SkillCommand {
    #[command(flatten)]
    pub runtime: RuntimeDirArgs,
    #[command(flatten)]
    pub output: OutputArgs,
    #[command(subcommand)]
    pub action: SkillAction,
}

#[derive(Debug, Subcommand)]
pub enum SkillAction {
    /// Show whether each Alera agent skill is installed and matches this runtime.
    Status,
    /// Install or update Alera agent skills at this runtime's commit.
    Install(SkillInstallArgs),
}

#[derive(Debug, Args)]
pub struct SkillInstallArgs {
    /// Skill to install. May be repeated; defaults to every Alera skill.
    #[arg(long = "skill", value_enum)]
    pub skills: Vec<SkillName>,
    /// Package runner: auto tries npx, then bunx when npx is missing.
    #[arg(long, value_enum, default_value_t = SkillRunnerName::Auto)]
    pub runner: SkillRunnerName,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, ValueEnum)]
pub enum SkillName {
    Cli,
    Orchestration,
    Automations,
    AgentProfiles,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, ValueEnum)]
pub enum SkillRunnerName {
    Auto,
    Npx,
    Bunx,
}
