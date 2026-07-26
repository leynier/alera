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
    /// List applications that have at least one window.
    #[command(name = "list-apps")]
    ListApps,
    /// List one application's windows.
    #[command(name = "list-windows")]
    ListWindows(ComputerAppArgs),
    /// Read one window: its accessibility tree, and a screenshot when available.
    #[command(name = "get-app-state")]
    GetAppState(ComputerAppStateArgs),
    /// Invoke an element's primary action.
    Click(ComputerElementArgs),
    /// Write a value into an element, without needing keyboard focus.
    #[command(name = "set-value")]
    SetValue(ComputerSetValueArgs),
    /// Invoke one of an element's named accessibility actions.
    #[command(name = "perform-secondary-action")]
    PerformSecondaryAction(ComputerPerformActionArgs),
}

#[derive(Debug, Args)]
pub struct ComputerElementArgs {
    #[command(flatten)]
    pub app: ComputerAppArgs,
    /// Element number from the tree you just read. Short-lived and sparse.
    #[arg(long = "element-index", value_name = "n")]
    pub element_index: usize,
    /// Resolve the index against this exact observation instead of the newest.
    #[arg(long = "snapshot-id", value_name = "id")]
    pub snapshot_id: Option<String>,
    /// Skip the screenshot in the returned state.
    #[arg(long = "no-screenshot")]
    pub no_screenshot: bool,
}

#[derive(Debug, Args)]
pub struct ComputerSetValueArgs {
    #[command(flatten)]
    pub element: ComputerElementArgs,
    /// The value to write.
    #[arg(long = "value", value_name = "text", conflicts_with = "value_stdin")]
    pub value: Option<String>,
    /// Read the value from stdin, keeping it out of shell history.
    #[arg(long = "value-stdin")]
    pub value_stdin: bool,
}

#[derive(Debug, Args)]
pub struct ComputerPerformActionArgs {
    #[command(flatten)]
    pub element: ComputerElementArgs,
    /// One of the action names the element lists in the tree.
    #[arg(long = "action", value_name = "name")]
    pub action: String,
}

#[derive(Debug, Args)]
pub struct ComputerAppArgs {
    /// The application: a name, a bundle id, or pid:<number>.
    #[arg(long = "app", value_name = "app")]
    pub app: String,
}

#[derive(Debug, Args)]
pub struct ComputerAppStateArgs {
    #[command(flatten)]
    pub app: ComputerAppArgs,
    /// Window handle, where the platform exposes one. Not available on Linux.
    #[arg(long = "window-id", value_name = "id")]
    pub window_id: Option<i64>,
    /// Window position in `list-windows`. Defaults to the active window.
    #[arg(long = "window-index", value_name = "n", conflicts_with = "window_id")]
    pub window_index: Option<usize>,
    /// Skip the screenshot. Use when only the tree is needed.
    #[arg(long = "no-screenshot")]
    pub no_screenshot: bool,
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
