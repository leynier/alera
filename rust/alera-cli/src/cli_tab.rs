use clap::{Args, Subcommand};

use super::{
    OutputArgs, RuntimeDirArgs, TabGenerateTitleArgs, TabRemoveArgs, TabRenameArgs, WorkspaceIdArgs,
};

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
    Remove(TabRemoveArgs),
    /// Rename a tab.
    Rename(TabRenameArgs),
    /// Name an agent tab from its conversation with AI Assist.
    GenerateTitle(TabGenerateTitleArgs),
    /// Bind a running agent to a tab again so its hooks update that tab's
    /// status. Inside Claude Code or Codex every option is detected.
    LinkAgent(TabLinkAgentArgs),
}

#[derive(Debug, Args)]
pub struct TabLinkAgentArgs {
    /// Tab to link the agent to. Defaults to ALERA_TAB_ID.
    #[arg(long, value_name = "tab-id")]
    pub tab: Option<String>,
    /// Agent type, such as claude or codex. Detected inside Claude Code and Codex.
    #[arg(long)]
    pub agent: Option<String>,
    /// The agent's conversation id. Detected inside Claude Code and Codex.
    #[arg(long = "session-id", value_name = "id")]
    pub session_id: Option<String>,
    /// The agent's process id. Detected inside Claude Code.
    #[arg(long)]
    pub pid: Option<u32>,
    /// Terminal session named in the agent's environment, whose hooks are
    /// routed to the tab. Defaults to ALERA_TERMINAL_SESSION_ID.
    #[arg(long = "source-terminal", value_name = "terminal-id")]
    pub source_terminal: Option<String>,
    /// Status shown until the agent's next hook.
    #[arg(long, default_value = "working", value_parser = ["working", "waiting", "blocked", "done"])]
    pub state: String,
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
