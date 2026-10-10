use clap::{Args, Subcommand, ValueEnum};

use super::{OutputArgs, RuntimeDirArgs};

#[derive(Debug, Args)]
pub struct McpCommand {
    #[command(flatten)]
    pub runtime: RuntimeDirArgs,
    #[command(flatten)]
    pub output: OutputArgs,
    #[command(subcommand)]
    pub action: McpAction,
}

#[derive(Debug, Subcommand)]
pub enum McpAction {
    /// Show MCP Control, the runtime name, and the cloud link.
    Status,
    /// Let MCP clients signed in to your Alera account reach this runtime.
    Enable(McpEnableArgs),
    /// Stop MCP clients from reaching this runtime.
    Disable,
    /// List the MCP clients connected to your Alera account.
    Apps,
    /// Revoke a connected MCP client.
    Revoke(McpRevokeArgs),
    /// Print the MCP tool catalog.
    Tools,
    /// Serve the MCP tools over stdio for a local MCP client.
    Serve(McpServeArgs),
}

/// How much of the MCP catalog a client may use.
#[derive(Debug, Clone, Copy, PartialEq, Eq, ValueEnum)]
pub enum McpAccessArg {
    /// Only tools that read runtime state.
    Read,
    /// Reading and running tools, including deletions, merges, and automations.
    Full,
    /// Everything in full, plus agent profile changes, runtime settings, and
    /// internal maintenance.
    Admin,
}

#[derive(Debug, Args)]
pub struct McpEnableArgs {
    /// Tools MCP clients may use. Defaults to full.
    #[arg(long, value_enum, conflicts_with = "read_only")]
    pub access: Option<McpAccessArg>,
    /// Allow only tools that read runtime state. Same as `--access read`.
    #[arg(long)]
    pub read_only: bool,
}

impl McpEnableArgs {
    pub fn level(&self) -> McpAccessArg {
        effective_access(self.access, self.read_only)
    }
}

fn effective_access(access: Option<McpAccessArg>, read_only: bool) -> McpAccessArg {
    if read_only {
        McpAccessArg::Read
    } else {
        access.unwrap_or(McpAccessArg::Full)
    }
}

#[derive(Debug, Args)]
pub struct McpRevokeArgs {
    /// Connected app id from `alera mcp apps`.
    #[arg(value_name = "grant-id")]
    pub grant_id: String,
}

#[derive(Debug, Args)]
pub struct McpServeArgs {
    /// Tools to expose to the local client. Defaults to full; administrative
    /// tools need `--access admin`. MCP Control applies to remote clients only.
    #[arg(long, value_enum, conflicts_with = "read_only")]
    pub access: Option<McpAccessArg>,
    /// Expose only tools that read runtime state. Same as `--access read`.
    #[arg(long)]
    pub read_only: bool,
}

impl McpServeArgs {
    pub fn level(&self) -> McpAccessArg {
        effective_access(self.access, self.read_only)
    }
}

#[derive(Debug, Args)]
pub struct AccountCommand {
    #[command(flatten)]
    pub runtime: RuntimeDirArgs,
    #[command(flatten)]
    pub output: OutputArgs,
    #[command(subcommand)]
    pub action: AccountAction,
}

#[derive(Debug, Subcommand)]
pub enum AccountAction {
    /// Show the Alera account this runtime is signed in to.
    Status,
    /// Sign this runtime in to an Alera account.
    Login(AccountLoginArgs),
    /// Sign this runtime out of its Alera account.
    Logout,
}

#[derive(Debug, Clone, Copy, ValueEnum)]
pub enum AccountProviderArg {
    Github,
    Google,
}

#[derive(Debug, Args)]
pub struct AccountLoginArgs {
    /// Identity provider for the browser sign-in on this machine.
    #[arg(long, value_enum, default_value = "github", conflicts_with = "device")]
    pub provider: AccountProviderArg,
    /// Sign in from another device by entering a code, for machines without a browser.
    #[arg(long)]
    pub device: bool,
}
