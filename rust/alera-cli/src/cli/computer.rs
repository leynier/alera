use clap::{Args, Subcommand, ValueEnum};

use super::{OutputArgs, RuntimeDirArgs};

/// Read and drive local desktop application UI.
#[derive(Debug, Args)]
pub struct ComputerCommand {
    #[command(flatten)]
    pub runtime: RuntimeDirArgs,
    #[command(flatten)]
    pub output: OutputArgs,
    #[command(subcommand)]
    pub action: ComputerAction,
}

#[derive(Debug, Subcommand)]
pub enum ComputerAction {
    /// Report what computer use can do in the current desktop session.
    Capabilities,
    /// Report the operating-system grants computer use depends on.
    ///
    /// Never opens a system prompt on its own.
    Permissions(ComputerPermissionsArgs),
}

#[derive(Debug, Args)]
pub struct ComputerPermissionsArgs {
    /// Report only this grant instead of all of them.
    #[arg(long = "id", value_enum)]
    pub id: Option<PermissionIdArg>,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, ValueEnum)]
pub enum PermissionIdArg {
    Accessibility,
    Screenshots,
}

impl PermissionIdArg {
    pub fn as_wire(self) -> &'static str {
        match self {
            PermissionIdArg::Accessibility => "accessibility",
            PermissionIdArg::Screenshots => "screenshots",
        }
    }
}
