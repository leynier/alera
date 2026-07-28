use clap::{Args, Subcommand, ValueEnum};

use super::{OutputArgs, RuntimeDirArgs};

#[derive(Debug, Args)]
pub struct BrowserCommand {
    #[command(flatten)]
    pub runtime: RuntimeDirArgs,
    #[command(flatten)]
    pub output: OutputArgs,
    #[command(subcommand)]
    pub action: BrowserAction,
}

#[derive(Debug, Subcommand)]
pub enum BrowserAction {
    /// Report browser routing capabilities and live pages.
    Capabilities,
    /// List persisted browser tabs.
    Tabs(BrowserTabsArgs),
    /// Create a browser tab and target a workbench pane group.
    Open(BrowserOpenArgs),
    /// Close a browser tab and add it to recently closed tabs.
    Close(BrowserPageIdArgs),
    /// Reopen a recently closed browser tab.
    Reopen(BrowserReopenArgs),
    /// Navigate a page to a URL.
    #[command(name = "goto")]
    Navigate(BrowserNavigateArgs),
    /// Navigate backward.
    Back(BrowserTimedPageArgs),
    /// Navigate forward.
    Forward(BrowserTimedPageArgs),
    /// Reload the current page.
    Reload(BrowserTimedPageArgs),
    /// Stop the current navigation.
    Stop(BrowserTimedPageArgs),
    /// Read an automation snapshot and short-lived refs.
    Snapshot(BrowserSnapshotArgs),
    /// Click a ref from a current snapshot.
    Click(BrowserRefArgs),
    /// Replace a field's value.
    Fill(BrowserRefTextArgs),
    /// Type text through the page's input path.
    Type(BrowserRefTextArgs),
    /// Select one option value.
    Select(BrowserRefSelectArgs),
    /// Focus a ref.
    Focus(BrowserRefArgs),
    /// Hover a ref.
    Hover(BrowserRefArgs),
    /// Scroll the page or a ref.
    Scroll(BrowserScrollArgs),
    /// Wait for a page condition.
    Wait(BrowserWaitArgs),
    /// Privileged local evaluation that can read page secrets and web storage.
    Eval(BrowserEvalArgs),
    /// Capture the visible page.
    Screenshot(BrowserCaptureArgs),
    /// Capture the full scrollable page.
    #[command(name = "full-screenshot")]
    FullScreenshot(BrowserCaptureArgs),
    /// Export the page as PDF.
    Pdf(BrowserCaptureArgs),
    /// Manage browser profiles.
    Profiles(BrowserProfilesCommand),
    /// Read or change typed browser settings.
    Settings(BrowserSettingsCommand),
    /// Inspect navigation history.
    History(BrowserHistoryCommand),
    /// Inspect recently closed tabs.
    #[command(name = "closed-tabs")]
    ClosedTabs(BrowserClosedTabsCommand),
    /// Manage per-origin browser permissions.
    Permissions(BrowserPermissionsCommand),
    /// Inspect or delete cookie metadata. Values are never returned.
    Cookies(BrowserCookiesCommand),
}

#[derive(Debug, Args)]
pub struct BrowserTabsArgs {
    #[arg(long = "workspace-id")]
    pub workspace_id: Option<String>,
}

#[derive(Debug, Args)]
pub struct BrowserOpenArgs {
    #[arg(long = "workspace-id")]
    pub workspace_id: String,
    #[arg(long, default_value = "about:blank")]
    pub url: String,
    #[arg(long = "profile-id", default_value = "default")]
    pub profile_id: String,
    #[arg(long)]
    pub title: Option<String>,
    #[arg(long = "page-id", alias = "tab-id")]
    pub page_id: Option<String>,
    #[arg(long = "target-group-id")]
    pub target_group_id: Option<String>,
}

#[derive(Debug, Args)]
pub struct BrowserPageIdArgs {
    #[arg(long = "page", alias = "tab", alias = "page-id", alias = "tab-id")]
    pub page_id: String,
}

#[derive(Debug, Args)]
pub struct BrowserReopenArgs {
    #[arg(long)]
    pub id: String,
    #[arg(long = "target-group-id")]
    pub target_group_id: Option<String>,
}

#[derive(Debug, Args)]
pub struct BrowserTimedPageArgs {
    #[arg(long = "page", alias = "tab", alias = "page-id", alias = "tab-id")]
    pub page_id: String,
    #[arg(long = "timeout-ms", default_value_t = 30_000)]
    pub timeout_ms: u64,
}

#[derive(Debug, Args)]
pub struct BrowserNavigateArgs {
    #[command(flatten)]
    pub page: BrowserTimedPageArgs,
    pub url: String,
}

#[derive(Debug, Args)]
pub struct BrowserSnapshotArgs {
    #[command(flatten)]
    pub page: BrowserTimedPageArgs,
    #[arg(long = "interactive-only")]
    pub interactive_only: bool,
    #[arg(long = "max-nodes", default_value_t = 500)]
    pub max_nodes: usize,
}

#[derive(Debug, Args)]
pub struct BrowserRefArgs {
    #[command(flatten)]
    pub page: BrowserTimedPageArgs,
    #[arg(long = "ref")]
    pub ref_id: String,
    #[arg(long = "snapshot-id")]
    pub snapshot_id: Option<String>,
}

#[derive(Debug, Args)]
pub struct BrowserRefTextArgs {
    #[command(flatten)]
    pub target: BrowserRefArgs,
    #[arg(long, conflicts_with = "text_stdin")]
    pub text: Option<String>,
    #[arg(long = "text-stdin", conflicts_with = "text")]
    pub text_stdin: bool,
}

#[derive(Debug, Args)]
pub struct BrowserRefSelectArgs {
    #[command(flatten)]
    pub target: BrowserRefArgs,
    #[arg(long)]
    pub value: String,
}

#[derive(Debug, Args)]
pub struct BrowserScrollArgs {
    #[command(flatten)]
    pub page: BrowserTimedPageArgs,
    #[arg(long = "ref")]
    pub ref_id: Option<String>,
    #[arg(long, default_value_t = 0.0)]
    pub x: f64,
    #[arg(long, default_value_t = 600.0)]
    pub y: f64,
}

#[derive(Debug, Args)]
pub struct BrowserWaitArgs {
    #[command(flatten)]
    pub page: BrowserTimedPageArgs,
    #[arg(long)]
    pub url: Option<String>,
    #[arg(long)]
    pub text: Option<String>,
    #[arg(long = "ref")]
    pub ref_id: Option<String>,
    #[arg(long = "load-state", value_enum)]
    pub load_state: Option<BrowserLoadStateArg>,
}

#[derive(Debug, Clone, Copy, ValueEnum)]
pub enum BrowserLoadStateArg {
    Started,
    Committed,
    Finished,
}

impl BrowserLoadStateArg {
    pub fn as_wire(self) -> &'static str {
        match self {
            Self::Started => "started",
            Self::Committed => "committed",
            Self::Finished => "finished",
        }
    }
}

#[derive(Debug, Args)]
pub struct BrowserEvalArgs {
    #[command(flatten)]
    pub page: BrowserTimedPageArgs,
    #[arg(long, conflicts_with_all = ["file", "stdin"])]
    pub expression: Option<String>,
    #[arg(long, conflicts_with_all = ["expression", "stdin"])]
    pub file: Option<String>,
    #[arg(long, conflicts_with_all = ["expression", "file"])]
    pub stdin: bool,
}

#[derive(Debug, Args)]
pub struct BrowserCaptureArgs {
    #[command(flatten)]
    pub page: BrowserTimedPageArgs,
    #[arg(long)]
    pub output: Option<String>,
}

#[derive(Debug, Args)]
pub struct BrowserProfilesCommand {
    #[command(subcommand)]
    pub action: BrowserProfilesAction,
}

#[derive(Debug, Subcommand)]
pub enum BrowserProfilesAction {
    List,
}

#[derive(Debug, Args)]
pub struct BrowserSettingsCommand {
    #[command(subcommand)]
    pub action: BrowserSettingsAction,
}

#[derive(Debug, Subcommand)]
pub enum BrowserSettingsAction {
    Get,
    Set(BrowserSettingsSetArgs),
}

#[derive(Debug, Args)]
pub struct BrowserSettingsSetArgs {
    #[arg(long = "search-engine", value_enum)]
    pub search_engine: BrowserSearchEngineArg,
}

#[derive(Debug, Clone, Copy, ValueEnum)]
pub enum BrowserSearchEngineArg {
    Google,
    DuckDuckGo,
    Bing,
    Kagi,
}

impl BrowserSearchEngineArg {
    pub fn as_wire(self) -> &'static str {
        match self {
            Self::Google => "google",
            Self::DuckDuckGo => "duckDuckGo",
            Self::Bing => "bing",
            Self::Kagi => "kagi",
        }
    }
}

#[derive(Debug, Args)]
pub struct BrowserHistoryCommand {
    #[command(subcommand)]
    pub action: BrowserHistoryAction,
}

#[derive(Debug, Subcommand)]
pub enum BrowserHistoryAction {
    List(BrowserListCatalogArgs),
    Clear(BrowserProfileFilterArgs),
}

#[derive(Debug, Args)]
pub struct BrowserClosedTabsCommand {
    #[command(subcommand)]
    pub action: BrowserClosedTabsAction,
}

#[derive(Debug, Subcommand)]
pub enum BrowserClosedTabsAction {
    List(BrowserListCatalogArgs),
    Remove(BrowserIdArgs),
    Reopen(BrowserReopenArgs),
}

#[derive(Debug, Args)]
pub struct BrowserListCatalogArgs {
    #[arg(long = "profile-id")]
    pub profile_id: Option<String>,
    #[arg(long, default_value_t = 100)]
    pub limit: i64,
}

#[derive(Debug, Args)]
pub struct BrowserProfileFilterArgs {
    #[arg(long = "profile-id")]
    pub profile_id: Option<String>,
}

#[derive(Debug, Args)]
pub struct BrowserPermissionsCommand {
    #[command(subcommand)]
    pub action: BrowserPermissionsAction,
}

#[derive(Debug, Subcommand)]
pub enum BrowserPermissionsAction {
    List(BrowserPermissionListArgs),
    Set(BrowserPermissionSetArgs),
    Remove(BrowserPermissionKeyArgs),
}

#[derive(Debug, Args)]
pub struct BrowserPermissionListArgs {
    #[arg(long = "profile-id")]
    pub profile_id: Option<String>,
    #[arg(long)]
    pub origin: Option<String>,
}

#[derive(Debug, Args)]
pub struct BrowserPermissionSetArgs {
    #[command(flatten)]
    pub key: BrowserPermissionKeyArgs,
    #[arg(long, value_enum)]
    pub decision: BrowserPermissionDecisionArg,
}

#[derive(Debug, Args)]
pub struct BrowserPermissionKeyArgs {
    #[arg(long = "profile-id")]
    pub profile_id: String,
    #[arg(long)]
    pub origin: String,
    #[arg(long)]
    pub permission: String,
}

#[derive(Debug, Clone, Copy, ValueEnum)]
pub enum BrowserPermissionDecisionArg {
    Ask,
    Allow,
    Deny,
}

impl BrowserPermissionDecisionArg {
    pub fn as_wire(self) -> &'static str {
        match self {
            Self::Ask => "ask",
            Self::Allow => "allow",
            Self::Deny => "deny",
        }
    }
}

#[derive(Debug, Args)]
pub struct BrowserCookiesCommand {
    #[command(subcommand)]
    pub action: BrowserCookiesAction,
}

#[derive(Debug, Subcommand)]
pub enum BrowserCookiesAction {
    List(BrowserTimedPageArgs),
    Delete(BrowserCookieDeleteArgs),
    Clear(BrowserTimedPageArgs),
}

#[derive(Debug, Args)]
pub struct BrowserCookieDeleteArgs {
    #[command(flatten)]
    pub page: BrowserTimedPageArgs,
    #[arg(long)]
    pub name: String,
    #[arg(long)]
    pub domain: Option<String>,
    #[arg(long)]
    pub path: Option<String>,
}

#[derive(Debug, Args)]
pub struct BrowserIdArgs {
    #[arg(long)]
    pub id: String,
}
