#![cfg_attr(
    all(not(debug_assertions), target_os = "windows"),
    windows_subsystem = "windows"
)]

use std::{
    collections::{BTreeMap, BTreeSet, HashMap, HashSet},
    path::PathBuf,
    time::{Duration, Instant},
};

use alera_desktop_core::{
    BridgeEvent, ForgeAction, ForgeAuthStatus, ForgeCheck, ForgeIdentity, ForgeService,
    ForgeSnapshot, ForgeUnavailableReason, MergeMethod, Project, RuntimeBridge,
    RuntimeHostStartConfig, WorkbenchSnapshot, WorkspaceTag, github_identity,
    replace_workspace_path_prefix, reveal_in_file_manager, unavailable_snapshot,
};
use async_io::Timer;
use chrono::{DateTime, Local, Utc};
use freya::clipboard::Clipboard;
#[cfg(target_os = "macos")]
use freya::winit::dpi::LogicalPosition;
use freya::{icons, prelude::*};
use serde::Deserialize;
use serde_json::{Value, json};
use uuid::Uuid;

mod alera_icons;
mod alera_scroll_view;
mod docking;
mod file_icons;
mod local_settings;
mod mobile_access;
mod preview_surface;
mod quota_provider_card;
mod resource_manager;
mod settings_agents;
mod settings_diagnostics;
mod settings_quotas;
mod settings_switch;
mod settings_terminal;
mod settings_terminal_color;
mod settings_terminal_font;
mod settings_terminal_state;
mod settings_terminal_theme;
mod sidebar;
mod sidebar_action_dialog;

use alera_scroll_view::AleraScrollView as ScrollView;
use settings_quotas::model::QuotaSettings;
use sidebar::{
    AgentRunState, SidebarAgentRun, SidebarGroupBy, SidebarProjection, SidebarRow, SidebarSortBy,
    SidebarViewPrefs, SidebarWorkspaceKind, SidebarWorkspaceRow,
};
use sidebar_action_dialog::{SidebarActionDialog, SidebarActionKind};

const BACKGROUND: (u8, u8, u8) = (16, 16, 16);
const SURFACE: (u8, u8, u8) = (28, 28, 28);
const SURFACE_RAISED: (u8, u8, u8) = (36, 36, 36);
const BORDER: (u8, u8, u8) = (50, 50, 50);
const SIDEBAR_BACKGROUND: (u8, u8, u8) = (32, 32, 32);
const SIDEBAR_HOVER: (u8, u8, u8) = (24, 24, 24);
const SIDEBAR_BORDER: (u8, u8, u8) = (39, 39, 39);
const SIDEBAR_AGENT_ACTIVE: (u8, u8, u8) = (51, 51, 51);
const TEXT: (u8, u8, u8) = (245, 245, 245);
const MUTED: (u8, u8, u8) = (161, 161, 161);
const FAINT: (u8, u8, u8) = (96, 96, 96);
const ACCENT: (u8, u8, u8) = (224, 224, 224);
const SUCCESS: (u8, u8, u8) = (34, 197, 94);

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
enum ActionDialog {
    AddProject,
    NewWorkspace,
}

#[derive(Clone, Copy)]
struct SidebarActionControls {
    dialog: State<Option<SidebarActionDialog>>,
    value: State<String>,
    selected_tags: State<HashSet<String>>,
    selected_parent: State<Option<String>>,
    error: State<Option<String>>,
    new_workspace_project_id: State<Option<String>>,
}

#[derive(Clone, Debug, Eq, PartialEq)]
struct CodexResetOffer {
    available_count: i64,
    next_expires_at: Option<i64>,
    offer_revision: String,
    can_consume: bool,
}

#[derive(Clone, Debug)]
enum SourceGitDialog {
    Amend {
        workspace_path: String,
    },
    DiscardAll {
        workspace_path: String,
    },
    DiscardPath {
        workspace_path: String,
        path: String,
    },
    DiscardPaths {
        workspace_path: String,
        paths: Vec<String>,
        target: String,
    },
    StashPop {
        workspace_path: String,
        stashes: Vec<GitStashView>,
    },
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
enum PullRequestReviewAction {
    Merge,
    Squash,
    Rebase,
    MarkReady,
    ConvertToDraft,
    Close,
    Unlink,
}

#[derive(Clone, Copy, Debug, Default, Eq, PartialEq)]
enum PullRequestComposerMode {
    #[default]
    Create,
    Link,
}

impl PullRequestReviewAction {
    fn label(self) -> &'static str {
        match self {
            Self::Merge => "Merge Pull Request",
            Self::Squash => "Squash And Merge",
            Self::Rebase => "Rebase And Merge",
            Self::MarkReady => "Mark Ready For Review",
            Self::ConvertToDraft => "Convert To Draft",
            Self::Close => "Close Pull Request",
            Self::Unlink => "Unlink Pull Request",
        }
    }

    fn forge_action(self, number: u64) -> Option<ForgeAction> {
        match self {
            Self::Merge => Some(ForgeAction::Merge {
                number,
                method: MergeMethod::Merge,
            }),
            Self::Squash => Some(ForgeAction::Merge {
                number,
                method: MergeMethod::Squash,
            }),
            Self::Rebase => Some(ForgeAction::Merge {
                number,
                method: MergeMethod::Rebase,
            }),
            Self::MarkReady => Some(ForgeAction::SetDraft {
                number,
                draft: false,
            }),
            Self::ConvertToDraft => Some(ForgeAction::SetDraft {
                number,
                draft: true,
            }),
            Self::Close => Some(ForgeAction::Close { number }),
            Self::Unlink => None,
        }
    }
}

#[derive(Clone, Debug)]
struct PullRequestConfirmation {
    action: PullRequestReviewAction,
    number: u64,
    workspace_id: String,
    workspace_path: String,
    identity: ForgeIdentity,
    review_url: String,
}

#[derive(Clone, Debug)]
enum ExplorerDialog {
    Create {
        workspace_path: String,
        parent_relative_path: String,
        directory: bool,
    },
    Rename {
        workspace_path: String,
        relative_path: String,
        current_name: String,
    },
    Delete {
        workspace_path: String,
        relative_path: String,
        name: String,
    },
}

#[derive(Clone, Debug)]
struct ExplorerClipboard {
    relative_path: String,
    cut: bool,
}

#[derive(Clone, Debug, PartialEq, Eq)]
struct ExplorerDragData {
    relative_path: String,
}

#[derive(Clone, Copy)]
struct AiTextGenerationState {
    busy: State<bool>,
    operation_id: State<Option<String>>,
    message: State<Option<String>>,
}

#[derive(Clone, Copy)]
struct RuntimeActionState {
    snapshot: State<Option<Value>>,
    error: State<Option<String>>,
    revision: State<u64>,
    busy: State<bool>,
    force_required: State<Option<String>>,
    message: State<Option<String>>,
    restart_after_stop: State<bool>,
}

#[derive(Clone, Copy, Debug, Deserialize)]
#[serde(default)]
struct FreyaRuntimeHostSettings {
    host_empty_shutdown_delay_seconds: i64,
    host_detached_shutdown_delay_seconds: i64,
    crash_reporting_enabled: bool,
}

impl Default for FreyaRuntimeHostSettings {
    fn default() -> Self {
        Self {
            host_empty_shutdown_delay_seconds: 30,
            host_detached_shutdown_delay_seconds: 3_600,
            crash_reporting_enabled: false,
        }
    }
}

#[derive(Clone, Copy, Debug, Deserialize)]
#[serde(default)]
struct FreyaShellSettings {
    sidebar_width: f32,
    sidebar_collapsed: bool,
}

impl Default for FreyaShellSettings {
    fn default() -> Self {
        Self {
            sidebar_width: 355.,
            sidebar_collapsed: false,
        }
    }
}

#[derive(Clone, Debug, PartialEq, Eq)]
struct ExplorerPathMove {
    generation: u64,
    workspace_path: String,
    old_relative_path: String,
    new_relative_path: String,
}

#[derive(Clone, Debug, PartialEq, Eq)]
struct EditorReloadRequest {
    generation: u64,
    workspace_path: String,
    relative_paths: HashSet<String>,
}

#[derive(Clone, Debug, PartialEq, Eq)]
struct FileOpenRequest {
    relative_path: String,
    force_editor: bool,
    reveal: Option<EditorRevealTarget>,
}

#[derive(Clone, Debug, PartialEq, Eq)]
struct EditorRevealTarget {
    line: u64,
    column: u64,
    match_length: u64,
}

impl FileOpenRequest {
    fn preview(relative_path: impl Into<String>) -> Self {
        Self {
            relative_path: relative_path.into(),
            force_editor: false,
            reveal: None,
        }
    }

    fn editor(relative_path: impl Into<String>) -> Self {
        Self {
            relative_path: relative_path.into(),
            force_editor: true,
            reveal: None,
        }
    }

    fn search(relative_path: impl Into<String>, line: u64, column: u64, match_length: u64) -> Self {
        Self {
            relative_path: relative_path.into(),
            force_editor: true,
            reveal: Some(EditorRevealTarget {
                line,
                column,
                match_length,
            }),
        }
    }
}

#[derive(Clone, Debug, Default, PartialEq)]
struct WorkspaceSearchView {
    files: Vec<WorkspaceSearchFileView>,
    total_matches: u64,
    truncated: bool,
}

#[derive(Clone, Debug, PartialEq)]
struct WorkspaceSearchFileView {
    relative_path: String,
    content_token: String,
    matches: Vec<WorkspaceSearchMatchView>,
}

#[derive(Clone, Debug, PartialEq)]
struct WorkspaceSearchMatchView {
    id: String,
    line: u64,
    column: u64,
    match_length: u64,
    line_content: String,
    display_column: Option<u64>,
    display_match_length: Option<u64>,
    replacement_preview: Option<String>,
}

#[derive(Clone, Debug, PartialEq)]
enum WorkspaceSearchRow {
    Directory {
        name: String,
        path: String,
        depth: usize,
        match_count: usize,
    },
    File {
        file: WorkspaceSearchFileView,
        depth: usize,
        show_directory: bool,
    },
    Match {
        relative_path: String,
        item: WorkspaceSearchMatchView,
        depth: usize,
    },
}

#[derive(Default)]
struct WorkspaceSearchTreeDirectory {
    name: String,
    path: String,
    match_count: usize,
    directories: BTreeMap<String, WorkspaceSearchTreeDirectory>,
    files: Vec<WorkspaceSearchFileView>,
}

#[derive(Clone)]
struct SearchPanelState {
    bridge: RuntimeBridge,
    workspace_path: String,
    results: State<Option<Result<WorkspaceSearchView, String>>>,
    query: State<String>,
    replacement: State<String>,
    include_pattern: State<String>,
    exclude_pattern: State<String>,
    case_sensitive: State<bool>,
    whole_word: State<bool>,
    use_regex: State<bool>,
    preserve_case: State<bool>,
    include_ignored: State<bool>,
    view_as_tree: State<bool>,
    replace_visible: State<bool>,
    details_visible: State<bool>,
    collapsed_nodes: State<HashSet<String>>,
    loading: State<bool>,
    replacing: State<bool>,
    replace_message: State<Option<String>>,
    replace_confirmation: State<Option<(String, String, u64)>>,
    revision: State<u64>,
    open_editor_path: State<Option<FileOpenRequest>>,
    dirty_documents: State<HashMap<String, String>>,
    editor_reload: State<Option<EditorReloadRequest>>,
}

#[derive(Clone, Copy, Debug, Default, Eq, PartialEq)]
struct SourceMenuState {
    open: bool,
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
enum SourceControlAction {
    Commit,
    CommitPush,
    CommitSync,
    Amend,
    StageAll,
    UnstageAll,
    DiscardAll,
    Fetch,
    Pull,
    Push,
    Sync,
    PublishBranch,
    Stash,
    StashPop,
}

impl SourceControlAction {
    fn label(self) -> &'static str {
        match self {
            Self::Commit => "Commit",
            Self::CommitPush => "Commit & Push",
            Self::CommitSync => "Commit & Sync",
            Self::Amend => "Commit Amend",
            Self::StageAll => "Stage All",
            Self::UnstageAll => "Unstage All",
            Self::DiscardAll => "Discard All",
            Self::Fetch => "Fetch",
            Self::Pull => "Pull",
            Self::Push => "Push",
            Self::Sync => "Sync",
            Self::PublishBranch => "Publish Branch",
            Self::Stash => "Stash",
            Self::StashPop => "Stash Pop",
        }
    }

    fn icon(self) -> Bytes {
        match self {
            Self::Commit | Self::Amend => alera_icons::git_commit(),
            Self::CommitPush | Self::Push => alera_icons::git_push(),
            Self::CommitSync | Self::Sync => alera_icons::git_sync(),
            Self::StageAll => alera_icons::git_stage(),
            Self::UnstageAll => alera_icons::git_unstage(),
            Self::DiscardAll => alera_icons::git_discard(),
            Self::Fetch => alera_icons::git_fetch(),
            Self::Pull => alera_icons::git_pull(),
            Self::PublishBranch => alera_icons::git_publish(),
            Self::Stash => alera_icons::git_stash(),
            Self::StashPop => alera_icons::git_stash_pop(),
        }
    }
}

#[derive(Clone, Copy)]
struct SourceControlMenuEntry {
    action: SourceControlAction,
    enabled: bool,
    separator_before: bool,
}

fn is_workbench_snapshot_event(name: &str) -> bool {
    matches!(
        name,
        "projectsChanged"
            | "workspacesChanged"
            | "workspaceTabsChanged"
            | "workbenchLayoutsChanged"
            | "workspaceTagsChanged"
            | "workspaceRelationsChanged"
    )
}

// Keep the provider marks shared with the GPUI implementation while the
// Freya surface is migrated.  The files are embedded so release bundles do
// not depend on the source checkout or a working directory.
const CLAUDE_ICON: &[u8] = include_bytes!("../../alera-gpui/assets/agents/claude.svg");
const CODEX_ICON: &[u8] = include_bytes!("../../alera-gpui/assets/agents/codex.svg");
const GROK_ICON: &[u8] = include_bytes!("../../alera-gpui/assets/agents/grok.svg");
const KIMI_ICON: &[u8] = include_bytes!("../../alera-gpui/assets/agents/kimi.svg");
const MINIMAX_ICON: &[u8] = include_bytes!("../../alera-gpui/assets/agents/minimax.svg");
const ZAI_ICON: &[u8] = include_bytes!("../../alera-gpui/assets/agents/zai.svg");
const ANTIGRAVITY_ICON: &[u8] = include_bytes!("../../alera-gpui/assets/agents/agy.png");
const COPILOT_ICON: &[u8] = include_bytes!("../../../assets/agents/copilot.svg");
const PI_ICON: &[u8] = include_bytes!("../../../assets/agents/pi.svg");
const CURSOR_ICON: &[u8] = include_bytes!("../../../assets/agents/cursor.png");
const OPENCODE_ICON: &[u8] = include_bytes!("../../../assets/agents/opencode.png");
const AMP_ICON: &[u8] = include_bytes!("../../../assets/agents/amp.png");
const ALERA_LOGO: &[u8] = include_bytes!("../../../assets/logo/alera-logo-white.png");

fn main() {
    let bridge = RuntimeBridge::start(runtime_dir());
    let forge_service = ForgeService::start();
    let app_name = app_display_name();
    launch(
        LaunchConfig::new()
            // Keep terminal glyphs (emoji, symbols and accented IME output)
            // readable when JetBrains Mono does not contain the code point.
            // Freya appends these families after the element's primary font.
            .with_fallback_font("Apple Color Emoji")
            .with_fallback_font("SF Symbols")
            .with_fallback_font("Symbols")
            .with_window(
                WindowConfig::new(move || app(bridge.clone(), forge_service.clone()))
                    .with_size(1280., 800.)
                    .with_min_size(860., 560.)
                    .with_title(app_name)
                    .with_app_id("dev.leynier.alera.freya")
                    .with_background(BACKGROUND)
                    .with_window_handle(|window| {
                        #[cfg(target_os = "macos")]
                        {
                            // Visual parity sessions must use the MacBook panel so
                            // screenshots are rendered with Flutter's Retina scale.
                            if let Some(monitor) = window
                                .available_monitors()
                                .max_by_key(|monitor| monitor.position().x)
                            {
                                let scale = monitor.scale_factor();
                                let origin = monitor.position();
                                let size = monitor.size().to_logical::<f64>(scale);
                                let x = origin.x as f64 + (size.width - 1280.).max(0.) / 2.;
                                let y = origin.y as f64 + (size.height - 800.).max(0.) / 2.;
                                window.set_outer_position(LogicalPosition::new(x, y));
                            }
                        }
                    }),
            ),
    );
}

fn app(bridge: RuntimeBridge, forge_service: ForgeService) -> impl IntoElement {
    use_init_theme(docking::alera_theme);
    // Keep one receiver at the application boundary.  The runtime bridge uses
    // a single ordered event lane, so letting each terminal surface read it
    // independently would make output appear in whichever tab happened to
    // wake first.  The keyed buffer below gives every surface a deterministic
    // view of its own session while preserving the existing GPUI bridge API.
    let terminal_outputs = use_state(HashMap::<String, Vec<u8>>::new);
    let shell_settings = local_settings::load_subset::<FreyaShellSettings>();
    let sidebar_width = use_state(|| shell_settings.sidebar_width.clamp(220., 460.));
    let sidebar_collapsed = use_state(|| shell_settings.sidebar_collapsed);
    let sidebar_drag_x = use_state(|| None::<f64>);
    let terminal_settings = use_state(settings_terminal_state::StoredTerminalSettings::default);
    let terminal_settings_revision = use_state(|| 0_u64);
    let terminal_settings_revision_value = *terminal_settings_revision.read();
    let mut terminal_settings_for_load = terminal_settings;
    use_side_effect_with_deps(&terminal_settings_revision_value, move |_| {
        spawn(async move {
            let settings = blocking::unblock(settings_terminal_state::load_settings).await;
            terminal_settings_for_load.set(settings);
        });
    });
    let runtime_host_settings = use_state(local_settings::load_subset::<FreyaRuntimeHostSettings>);
    let event_tick = use_state(|| 0_u64);
    let view_prefs_revision = use_state(|| 0_u64);
    let snapshot_revision = use_state(|| 0_u64);
    let presence_revision = use_state(|| 0_u64);
    let agent_presence = use_state(Vec::<Value>::new);
    let runtime_connection = use_state(|| "Connecting".to_string());
    // Drop the read guard immediately. Keeping it alive for the whole render
    // prevented the event pump from advancing the tick when a PTY delivered
    // output during a tab-tree update.
    let _event_tick = *event_tick.read();
    let events = bridge.events();
    let outputs_for_events = terminal_outputs;
    let tick_for_events = event_tick;
    let prefs_revision_for_events = view_prefs_revision;
    let snapshot_revision_for_events = snapshot_revision;
    let presence_revision_for_events = presence_revision;
    let connection_for_events = runtime_connection;
    use_future(move || {
        let events = events.clone();
        let mut outputs = outputs_for_events;
        let mut tick = tick_for_events;
        let mut prefs_revision = prefs_revision_for_events;
        let mut snapshot_revision = snapshot_revision_for_events;
        let mut presence_revision = presence_revision_for_events;
        let mut connection = connection_for_events;
        async move {
            loop {
                let Ok(event) = events.recv().await else {
                    break;
                };
                match event {
                    BridgeEvent::Connected => {
                        connection.set("Connected".to_string());
                        let next_snapshot = {
                            let current = *snapshot_revision.read();
                            current.saturating_add(1)
                        };
                        snapshot_revision.set(next_snapshot);
                        let next_presence = {
                            let current = *presence_revision.read();
                            current.saturating_add(1)
                        };
                        presence_revision.set(next_presence);
                    }
                    BridgeEvent::Unavailable => connection.set("Unavailable".to_string()),
                    BridgeEvent::Disconnected { .. } => connection.set("Disconnected".to_string()),
                    BridgeEvent::Notification { name, .. } => {
                        if name == "workbenchViewPrefsChanged" {
                            let next = prefs_revision.read().saturating_add(1);
                            prefs_revision.set(next);
                        }
                        if is_workbench_snapshot_event(&name) {
                            let next = {
                                let current = *snapshot_revision.read();
                                current.saturating_add(1)
                            };
                            snapshot_revision.set(next);
                        }
                        if name == "agentPresenceChanged" {
                            let next = {
                                let current = *presence_revision.read();
                                current.saturating_add(1)
                            };
                            presence_revision.set(next);
                        }
                    }
                    BridgeEvent::TerminalOutput { session_id, data } => {
                        outputs.write().entry(session_id).or_default().extend(data);
                        let next_tick = {
                            let current = *tick.read();
                            current.saturating_add(1)
                        };
                        tick.set(next_tick);
                    }
                }
            }
        }
    });

    let presence_deps = (*presence_revision.read(), runtime_connection.read().clone());
    let presence_bridge = bridge.clone();
    let mut agent_presence_for_request = agent_presence;
    use_side_effect_with_deps(&presence_deps, move |_| {
        let bridge = presence_bridge.clone();
        spawn(async move {
            if let Ok(value) = bridge
                .request_with_timeout("agentPresence.list", json!({}), Duration::from_secs(30))
                .await
            {
                agent_presence_for_request.set(value.as_array().cloned().unwrap_or_default());
            }
        });
    });

    let bridge_for_future = bridge.clone();
    let runtime_request = use_future(move || {
        let _connection = runtime_connection.read().clone();
        let bridge = bridge_for_future.clone();
        async move {
            bridge
                .request_with_timeout("project.list", json!({}), Duration::from_secs(30))
                .await
        }
    });
    let _runtime_request_state = runtime_request.state();
    let view_prefs_record = use_state(|| None::<Result<Value, String>>);
    let view_prefs_bridge = bridge.clone();
    let view_prefs_record_for_request = view_prefs_record;
    let view_prefs_deps = (
        *view_prefs_revision.read(),
        runtime_connection.read().clone(),
    );
    use_side_effect_with_deps(&view_prefs_deps, move |_| {
        let bridge = view_prefs_bridge.clone();
        let mut record = view_prefs_record_for_request;
        spawn(async move {
            record.set(Some(
                bridge
                    .request_with_timeout(
                        "workbenchViewPrefs.get",
                        json!({}),
                        Duration::from_secs(30),
                    )
                    .await,
            ));
        });
    });
    let runtime_status = match runtime_connection.read().as_str() {
        "Connected" => "● Connected",
        "Unavailable" => "● Unavailable",
        "Disconnected" => "● Disconnected",
        _ => "● Connecting",
    };
    let runtime_loading = runtime_connection.read().as_str() == "Connecting";
    let quota_refresh_revision = use_state(|| 0_u64);
    let quota_bridge = bridge.clone();
    let quota_request = use_future(move || {
        let _connection = runtime_connection.read().clone();
        let _revision = *quota_refresh_revision.read();
        let bridge = quota_bridge.clone();
        async move {
            bridge
                .request_with_timeout(
                    "agentQuota.snapshot",
                    json!({"forceRefresh": false}),
                    Duration::from_secs(30),
                )
                .await
        }
    });
    let quota_settings = use_state(QuotaSettings::default);
    let codex_reset_confirmation = use_state(|| None::<CodexResetOffer>);
    let codex_reset_busy = use_state(|| false);
    let codex_reset_error = use_state(|| None::<String>);
    let quota_settings_deps = runtime_connection.read().clone();
    let quota_settings_bridge = bridge.clone();
    let mut quota_settings_for_load = quota_settings;
    use_side_effect_with_deps(&quota_settings_deps, move |_| {
        let bridge = quota_settings_bridge.clone();
        spawn(async move {
            if let Ok(settings) = settings_quotas::actions::load_snapshot(bridge).await {
                quota_settings_for_load.set(settings);
            }
        });
    });
    let resource_snapshot = use_state(|| None::<Result<Value, String>>);
    let sidebar_tab_workspace_ids = use_state(HashSet::<String>::new);
    let resource_popover_open = use_state(|| false);
    let resource_sort_column = use_state(|| "memory".to_string());
    let resource_collapsed_projects = use_state(Vec::<String>::new);
    let resource_close_confirmation =
        use_state(|| None::<resource_manager::ResourceCloseConfirmation>);
    let resource_action_busy = use_state(|| false);
    let resource_action_message = use_state(|| None::<String>);
    let resource_poll_bridge = bridge.clone();
    let mut resource_snapshot_for_poll = resource_snapshot;
    let resource_open_for_poll = resource_popover_open;
    use_hook(move || {
        spawn(async move {
            loop {
                resource_snapshot_for_poll.set(Some(
                    resource_manager::fetch_snapshot(&resource_poll_bridge).await,
                ));
                Timer::after(if resource_open_for_poll() {
                    Duration::from_secs(2)
                } else {
                    Duration::from_secs(15)
                })
                .await;
            }
        });
    });
    let resource_open_deps = resource_popover_open();
    let resource_open_bridge = bridge.clone();
    let mut resource_snapshot_for_open = resource_snapshot;
    use_side_effect_with_deps(&resource_open_deps, move |open| {
        if !*open {
            return;
        }
        let bridge = resource_open_bridge.clone();
        spawn(async move {
            resource_snapshot_for_open.set(Some(resource_manager::fetch_snapshot(&bridge).await));
        });
    });
    let runtime_status_snapshot = use_state(|| None::<Value>);
    let runtime_status_error = use_state(|| None::<String>);
    let runtime_status_revision = use_state(|| 0_u64);
    let runtime_action_busy = use_state(|| false);
    let runtime_force_required = use_state(|| None::<String>);
    let runtime_action_message = use_state(|| None::<String>);
    let runtime_restart_after_stop = use_state(|| false);
    let runtime_status_deps = (
        *runtime_status_revision.read(),
        runtime_connection.read().clone(),
    );
    let runtime_status_bridge = bridge.clone();
    let mut runtime_status_for_effect = runtime_status_snapshot;
    let mut runtime_error_for_effect = runtime_status_error;
    use_side_effect_with_deps(&runtime_status_deps, move |_| {
        let bridge = runtime_status_bridge.clone();
        spawn(async move {
            let result = bridge
                .request_with_timeout("status.get", json!({}), Duration::from_secs(30))
                .await;
            let current = runtime_status_for_effect.read().clone();
            let (snapshot, error) = merge_runtime_status(current, result);
            runtime_status_for_effect.set(snapshot);
            runtime_error_for_effect.set(error);
        });
    });
    let runtime_poll_bridge = bridge.clone();
    let runtime_connection_for_poll = runtime_connection;
    let mut runtime_status_for_poll = runtime_status_snapshot;
    let mut runtime_error_for_poll = runtime_status_error;
    use_hook(move || {
        spawn(async move {
            loop {
                Timer::after(Duration::from_secs(15)).await;
                if runtime_connection_for_poll.read().as_str() != "Connected" {
                    continue;
                }
                let result = runtime_poll_bridge
                    .request_with_timeout("status.get", json!({}), Duration::from_secs(10))
                    .await;
                let current = runtime_status_for_poll.read().clone();
                let (snapshot, error) = merge_runtime_status(current, result);
                runtime_status_for_poll.set(snapshot);
                runtime_error_for_poll.set(error);
            }
        });
    });
    let quota_snapshots = quota_snapshots(&quota_request.state());
    let quota_settings_value = quota_settings.read().clone();
    let quota_overview = quota_overview_panel(
        quota_snapshots.clone(),
        quota_settings,
        codex_reset_confirmation,
        codex_reset_error,
        bridge.clone(),
    );
    let runtime_metrics = runtime_metrics(
        runtime_status_snapshot.read().as_ref(),
        runtime_status_error.read().as_deref(),
    );
    let runtime_start_config = runtime_host_config(
        &terminal_settings.read(),
        &runtime_host_settings.read(),
        runtime_status_snapshot.read().as_ref(),
    );
    let runtime_actions = runtime_status_actions(
        bridge.clone(),
        RuntimeActionState {
            snapshot: runtime_status_snapshot,
            error: runtime_status_error,
            revision: runtime_status_revision,
            busy: runtime_action_busy,
            force_required: runtime_force_required,
            message: runtime_action_message,
            restart_after_stop: runtime_restart_after_stop,
        },
        runtime_start_config.clone(),
    );
    let runtime_mode = use_state(|| "Local".to_string());
    let search = use_state(String::new);
    let open_editor_path = use_state(|| None::<FileOpenRequest>);
    let editor_dirty_documents = use_state(HashMap::<String, String>::new);
    let editor_reload = use_state(|| None::<EditorReloadRequest>);
    let explorer_path_move = use_state(|| None::<ExplorerPathMove>);
    let open_git_diff_request = use_state(|| None::<docking::GitDiffOpenRequest>);
    let mut settings_open = use_state(|| false);
    let sidebar_view_options_open = use_state(|| false);
    let sidebar_view_project_query = use_state(String::new);
    let sidebar_view_tag_query = use_state(String::new);
    let mut action_dialog = use_state(|| None::<ActionDialog>);
    let mut action_dialog_error = use_state(|| None::<String>);
    let sidebar_action_dialog = use_state(|| None::<SidebarActionDialog>);
    let sidebar_action_value = use_state(String::new);
    let sidebar_action_selected_tags = use_state(HashSet::<String>::new);
    let sidebar_action_selected_parent = use_state(|| None::<String>);
    let sidebar_action_busy = use_state(|| false);
    let sidebar_action_error = use_state(|| None::<String>);
    let mut workspace_target_project_id = use_state(|| None::<String>);
    let sidebar_action_controls = SidebarActionControls {
        dialog: sidebar_action_dialog,
        value: sidebar_action_value,
        selected_tags: sidebar_action_selected_tags,
        selected_parent: sidebar_action_selected_parent,
        error: sidebar_action_error,
        new_workspace_project_id: workspace_target_project_id,
    };
    let source_git_dialog = use_state(|| None::<SourceGitDialog>);
    let source_git_dialog_message = use_state(String::new);
    let source_git_dialog_error = use_state(|| None::<String>);
    let source_git_dialog_loading = use_state(|| false);
    let source_git_revision = use_state(|| 0_u64);
    let forge_refresh_revision = use_state(|| 0_u64);
    let pull_request_confirmation = use_state(|| None::<PullRequestConfirmation>);
    let pull_request_confirmation_loading = use_state(|| false);
    let pull_request_confirmation_error = use_state(|| None::<String>);
    let explorer_dialog = use_state(|| None::<ExplorerDialog>);
    let explorer_dialog_value = use_state(String::new);
    let explorer_dialog_loading = use_state(|| false);
    let explorer_dialog_error = use_state(|| None::<String>);
    let explorer_revision = use_state(|| 0_u64);
    let source_git_dialog_open = source_git_dialog.read().is_some();
    let mut source_git_dialog_error_for_open = source_git_dialog_error;
    let mut source_git_dialog_loading_for_open = source_git_dialog_loading;
    use_side_effect_with_deps(&source_git_dialog_open, move |open| {
        if *open {
            source_git_dialog_error_for_open.set(None);
            source_git_dialog_loading_for_open.set(false);
        }
    });
    let rename_request = use_state(|| None::<usize>);
    let rename_title = use_state(String::new);
    let selected_tab_request = use_state(|| None::<String>);
    let add_project_path = use_state(String::new);
    let add_project_name = use_state(String::new);
    let add_project_clone_mode = use_state(|| false);
    let add_project_clone_url = use_state(String::new);
    let add_project_clone_parent = use_state(String::new);
    let add_project_clone_directory = use_state(String::new);
    let workspace_name = use_state(String::new);
    let workspace_branch = use_state(|| "feature/new-workspace".to_string());
    let workspace_prompt_mode = use_state(|| true);
    let workspace_prompt = use_state(String::new);
    let workspace_create_another = use_state(|| false);
    let workspace_project = use_state(String::new);
    let workspace_source_branch = use_state(|| "main".to_string());
    let workspace_parent = use_state(|| "No Parent".to_string());
    let workspace_agent_profile = use_state(String::new);
    let workspace_branch_options = use_state(Vec::<String>::new);
    let workspace_local_branch_options = use_state(Vec::<String>::new);
    let workspace_agent_profile_options = use_state(Vec::<String>::new);
    let workspace_reuse_existing_branch = use_state(|| false);
    let workspace_creation_busy = use_state(|| false);
    let workspace_creation_phase = use_state(|| None::<String>);
    let workspace_prompt_created_id = use_state(|| None::<String>);
    let workspace_dialog_initialized = use_state(|| false);
    let workspace_branches_project_id = use_state(|| None::<String>);
    let workspace_open_dropdown = use_state(|| None::<String>);
    let workspace_dropdown_just_opened = use_state(|| false);
    // The sidebar stores the stable workspace id, not its display name. This
    // lets a click reload that workspace's persisted tabs/layout instead of
    // leaving the workbench attached to whichever workspace was loaded first.
    let selected_workspace = use_state(String::new);
    // Freya's `use_future` stores its own state and updates it from the async
    // executor. A workspace click can invalidate that state while the shell
    // is still reading it during the same frame, so snapshot loading uses a
    // plain result signal and a long-lived spawned task instead.
    let snapshot_result = use_state(|| None::<Result<WorkbenchSnapshot, String>>);
    let snapshot_bridge = bridge.clone();
    let selected_workspace_for_load = selected_workspace;
    let snapshot_revision_for_load = snapshot_revision;
    let snapshot_result_for_load = snapshot_result;
    use_side_effect(move || {
        let _connection = runtime_connection.read().clone();
        let selected_workspace_id = selected_workspace_for_load.read().clone();
        let revision = *snapshot_revision_for_load.read();
        let bridge = snapshot_bridge.clone();
        let mut snapshot_result = snapshot_result_for_load;
        let selected_workspace_for_check = selected_workspace_for_load;
        let snapshot_revision_for_check = snapshot_revision_for_load;
        spawn(async move {
            let result = WorkbenchSnapshot::load(
                &bridge,
                (!selected_workspace_id.is_empty()).then_some(selected_workspace_id.as_str()),
            )
            .await;
            let selected_is_current =
                selected_workspace_for_check.peek().as_str() == selected_workspace_id.as_str();
            let revision_is_current = *snapshot_revision_for_check.peek() == revision;
            if selected_is_current && revision_is_current {
                snapshot_result.set(Some(result));
            }
        });
    });
    // `use_side_effect_with_deps` captures its callback on the first render.
    // Keep the fulfilled snapshot in a reactive cache so the docking radio
    // receives the runtime layout after the asynchronous request completes,
    // instead of retaining the three-tab development fallback.
    let snapshot_cache = use_state(|| None::<WorkbenchSnapshot>);
    let sidebar_tabs_by_workspace = use_state(HashMap::<String, Vec<Value>>::new);
    let selected_workspace_for_snapshot_effect = selected_workspace;
    let mut snapshot_cache_for_effect = snapshot_cache;
    let snapshot_result_for_effect = snapshot_result;
    use_side_effect(move || {
        // The workbench remains mounted behind the welcome screen for stable
        // hooks, but the unscoped snapshot has no tabs/layout. Do not apply it
        // there: switching from that empty leaf to the selected split would
        // change the docking component topology mid-render.
        if selected_workspace_for_snapshot_effect.read().is_empty() {
            return;
        }
        let snapshot_result = snapshot_result_for_effect.read().clone();
        if let Some(Ok(snapshot)) = snapshot_result {
            let selected_workspace_id = selected_workspace_for_snapshot_effect.read().clone();
            if snapshot.selected_workspace_id.as_deref() != Some(selected_workspace_id.as_str()) {
                return;
            }
            snapshot_cache_for_effect.set(Some(snapshot.clone()));
        }
    });
    let search_query = search.read().to_lowercase();

    // Keep the last successful snapshot visible while a refresh is in flight
    // or a single runtime request times out.  Replacing it with the fallback
    // root would detach the Explorer from the workspace path even though the
    // terminal session is still correctly attached to that workspace.
    let snapshot_value: Option<Result<WorkbenchSnapshot, String>> =
        match snapshot_result.read().clone() {
            Some(Ok(snapshot)) => Some(Ok(snapshot)),
            Some(Err(_)) | None => snapshot_cache.read().clone().map(Ok),
        };
    let sidebar_tab_scan_deps = (
        *snapshot_revision.read(),
        snapshot_value
            .as_ref()
            .and_then(|result| result.as_ref().ok())
            .into_iter()
            .flat_map(|snapshot| &snapshot.projects)
            .flat_map(|project| &project.workspaces)
            .map(|workspace| workspace.id.clone())
            .collect::<Vec<_>>(),
    );
    let sidebar_tab_scan_bridge = bridge.clone();
    let mut sidebar_tab_workspace_ids_for_scan = sidebar_tab_workspace_ids;
    let mut sidebar_tabs_by_workspace_for_scan = sidebar_tabs_by_workspace;
    use_side_effect_with_deps(&sidebar_tab_scan_deps, move |(_, workspace_ids)| {
        let bridge = sidebar_tab_scan_bridge.clone();
        let workspace_ids = workspace_ids.clone();
        let previous = sidebar_tab_workspace_ids_for_scan.peek().clone();
        spawn(async move {
            let workspace_set = workspace_ids.iter().cloned().collect::<HashSet<_>>();
            let mut next = previous
                .into_iter()
                .filter(|workspace_id| workspace_set.contains(workspace_id))
                .collect::<HashSet<_>>();
            let mut tabs_by_workspace = HashMap::<String, Vec<Value>>::new();
            for workspace_id in workspace_ids {
                match bridge
                    .request_with_timeout(
                        "tab.list",
                        json!({"workspaceId": workspace_id}),
                        Duration::from_secs(30),
                    )
                    .await
                {
                    Ok(value) if value.as_array().is_some_and(|tabs| !tabs.is_empty()) => {
                        let tabs = value.as_array().cloned().unwrap_or_default();
                        next.insert(workspace_id.clone());
                        tabs_by_workspace.insert(workspace_id, tabs);
                    }
                    Ok(_) => {
                        next.remove(&workspace_id);
                    }
                    Err(_) => {}
                }
            }
            let changed = *sidebar_tab_workspace_ids_for_scan.peek() != next;
            if changed {
                sidebar_tab_workspace_ids_for_scan.set(next);
            }
            if *sidebar_tabs_by_workspace_for_scan.peek() != tabs_by_workspace {
                sidebar_tabs_by_workspace_for_scan.set(tabs_by_workspace);
            }
        });
    });
    let sidebar_prefs = SidebarViewPrefs::from_record(
        view_prefs_record
            .read()
            .as_ref()
            .and_then(|result| result.as_ref().ok()),
    );
    let mut active_workspace_ids = sidebar_tab_workspace_ids.read().clone();
    active_workspace_ids.extend(
        resource_snapshot
            .read()
            .as_ref()
            .and_then(|result| result.as_ref().ok())
            .and_then(|value| value.get("sessions"))
            .and_then(Value::as_array)
            .into_iter()
            .flatten()
            .filter_map(|session| session.get("workspaceId").and_then(Value::as_str))
            .map(str::to_string),
    );
    let live_sidebar_agent_presence = filter_live_sidebar_agent_presence(
        &agent_presence.read(),
        &sidebar_tabs_by_workspace.read(),
    );
    let sidebar_rows = snapshot_value
        .as_ref()
        .and_then(|result| result.as_ref().ok())
        .map(|snapshot| {
            SidebarProjection::new(
                snapshot,
                &sidebar_prefs,
                search_query.as_str(),
                &active_workspace_ids,
                &live_sidebar_agent_presence,
            )
            .build()
        })
        .unwrap_or_default();
    let active_sidebar_tab_id = selected_tab_request.read().clone().or_else(|| {
        snapshot_value
            .as_ref()
            .and_then(|result| result.as_ref().ok())
            .and_then(|snapshot| snapshot.layout.as_ref())
            .and_then(|layout| layout.groups.get(&layout.active_group_id))
            .and_then(|group| group.active_tab_id.clone())
    });
    let workspace_count = sidebar_rows
        .iter()
        .filter_map(|row| match row {
            SidebarRow::Workspace(workspace) => Some(workspace.id.as_str()),
            _ => None,
        })
        .collect::<HashSet<_>>()
        .len();
    let collapse_project_ids = sidebar_rows
        .iter()
        .filter_map(|row| match row {
            SidebarRow::ProjectHeader { id, .. } => Some(id.clone()),
            _ => None,
        })
        .collect::<HashSet<_>>();
    let collapse_parent_ids = sidebar_rows
        .iter()
        .filter_map(|row| match row {
            SidebarRow::Workspace(workspace) if workspace.visible_child_count > 0 => {
                Some(workspace.id.clone())
            }
            _ => None,
        })
        .collect::<HashSet<_>>();
    let collapse_agent_ids = sidebar_rows
        .iter()
        .filter_map(|row| match row {
            SidebarRow::Workspace(workspace) if !workspace.agent_runs.is_empty() => {
                Some(workspace.id.clone())
            }
            _ => None,
        })
        .collect::<HashSet<_>>();
    let can_collapse_sidebar = !(collapse_project_ids.is_empty()
        && collapse_parent_ids.is_empty()
        && collapse_agent_ids.is_empty());
    let sidebar_all_collapsed = can_collapse_sidebar
        && collapse_project_ids
            .iter()
            .all(|id| sidebar_prefs.collapsed_project_ids.contains(id))
        && collapse_parent_ids
            .iter()
            .all(|id| sidebar_prefs.collapsed_parent_workspace_ids.contains(id))
        && !collapse_agent_ids
            .iter()
            .any(|id| sidebar_prefs.expanded_workspace_ids.contains(id));
    let selected_project_and_workspace = snapshot_value.as_ref().and_then(|result| {
        result.as_ref().ok().and_then(|snapshot| {
            snapshot.projects.iter().find_map(|project| {
                project
                    .workspaces
                    .iter()
                    .find(|workspace| {
                        !selected_workspace.read().is_empty()
                            && workspace.id == selected_workspace.read().as_str()
                    })
                    .map(|workspace| (project.clone(), workspace.clone()))
            })
        })
    });
    let sidebar_projects = snapshot_value
        .as_ref()
        .and_then(|result| result.as_ref().ok())
        .map(|snapshot| snapshot.projects.clone())
        .unwrap_or_default();
    let runtime_context = selected_project_and_workspace
        .as_ref()
        .map(|(_, workspace)| (workspace.id.clone(), workspace.path.clone()));
    let source_control_scope =
        selected_project_and_workspace
            .as_ref()
            .and_then(|(project, workspace)| {
                source_control_scope_from_prefs(
                    project.kind.as_str(),
                    &workspace.id,
                    &workspace.path,
                    view_prefs_record
                        .read()
                        .as_ref()
                        .and_then(|result| result.as_ref().ok()),
                )
            });
    let can_focus_source_control_folders = selected_project_and_workspace
        .as_ref()
        .is_some_and(|(project, _)| project.kind == "folder");
    let mut sidebar_search = Input::new(search)
        .placeholder("Search workspaces")
        .width(Size::fill())
        .filled()
        .theme_layout(
            InputLayoutThemePartial::new()
                .corner_radius(CornerRadius::new_all(10.))
                .inner_margin(Gaps::new(10., 8., 10., 8.)),
        )
        .leading(
            SvgViewer::new(icons::lucide::search())
                .width(Size::px(14.))
                .height(Size::px(14.))
                .color(FAINT),
        )
        .theme_colors(
            InputColorsThemePartial::new()
                .background((24, 24, 24))
                .focus_background((24, 24, 24))
                .border_fill(SIDEBAR_BORDER)
                .focus_border_fill(BORDER)
                .color(TEXT)
                .placeholder_color(FAINT),
        );
    if !search.read().is_empty() {
        let mut search_for_clear = search;
        sidebar_search = sidebar_search.trailing(
            rect()
                .width(Size::px(24.))
                .height(Size::px(24.))
                .center()
                .corner_radius(4.)
                .a11y_role(AccessibilityRole::Button)
                .a11y_alt("Clear")
                .on_pointer_enter(|_| Cursor::set(CursorIcon::Pointer))
                .on_pointer_leave(|_| Cursor::set(CursorIcon::default()))
                .on_pointer_down(move |event: Event<PointerEventData>| {
                    event.stop_propagation();
                    search_for_clear.set(String::new());
                })
                .child(
                    SvgViewer::new(icons::lucide::x())
                        .width(Size::px(12.))
                        .height(Size::px(12.))
                        .color(FAINT),
                ),
        );
    }
    let current_sidebar_width = *sidebar_width.read();
    let mut sidebar_drag_for_down = sidebar_drag_x;
    let sidebar_drag_for_move = sidebar_drag_x;
    let mut sidebar_drag_for_release = sidebar_drag_x;
    let mut sidebar_width_for_move = sidebar_width;
    let sidebar_width_for_release = sidebar_width;
    let sidebar_resize_handle = rect()
        .position(Position::new_absolute().top(0.).right(0.).bottom(0.))
        .layer(Layer::Overlay)
        .width(Size::px(4.))
        .on_pointer_enter(|_| Cursor::set(CursorIcon::ColResize))
        .on_pointer_leave(move |_| {
            if sidebar_drag_for_move.read().is_none() {
                Cursor::set(CursorIcon::default());
            }
        })
        .on_pointer_down(move |event: Event<PointerEventData>| {
            if !event.data().is_primary() {
                return;
            }
            event.stop_propagation();
            event.prevent_default();
            sidebar_drag_for_down.set(Some(event.global_location().x));
        })
        .on_capture_global_pointer_move(move |event: Event<PointerEventData>| {
            let Some(previous_x) = *sidebar_drag_for_move.read() else {
                return;
            };
            event.prevent_default();
            let current_x = event.global_location().x;
            let delta = (current_x - previous_x) as f32 / 0.75;
            let next_width = (*sidebar_width_for_move.read() + delta).clamp(220., 460.);
            sidebar_width_for_move.set(next_width);
            sidebar_drag_for_down.set(Some(current_x));
        })
        .on_global_pointer_press(move |_| {
            if sidebar_drag_for_release.read().is_none() {
                return;
            }
            sidebar_drag_for_release.set(None);
            Cursor::set(CursorIcon::default());
            let width = *sidebar_width_for_release.peek();
            spawn(async move {
                let _ = blocking::unblock(move || {
                    local_settings::persist_fields([("sidebar_width", json!(width))])
                })
                .await;
            });
        });
    let collapsed_sidebar = collapsed_sidebar(
        sidebar_projects,
        selected_project_and_workspace
            .as_ref()
            .map(|(project, _)| project.id.as_str()),
        sidebar_collapsed,
        selected_workspace,
        action_dialog,
        action_dialog_error,
        settings_open,
    );
    let expanded_sidebar = rect()
        .width(Size::px(current_sidebar_width))
        .height(Size::fill())
        .background(SIDEBAR_BACKGROUND)
        .border(
            Border::new()
                .width(BorderWidth {
                    top: 0.,
                    right: 1.,
                    bottom: 0.,
                    left: 0.,
                })
                .fill(SIDEBAR_BORDER),
        )
        .vertical()
        .content(Content::Flex)
        .main_align(Alignment::Start)
        .cross_align(Alignment::Start)
        .spacing(0.)
        .child(
            rect()
                .width(Size::fill())
                .height(Size::px(44.))
                .padding(Gaps::new(0., 12., 0., 12.))
                .horizontal()
                .content(Content::Flex)
                .cross_align(Alignment::Center)
                .spacing(8.)
                .child(
                    ImageViewer::new(("sidebar-alera-logo", ALERA_LOGO))
                        .width(Size::px(16.))
                        .height(Size::px(16.)),
                )
                .child(
                    label()
                        .font_size(13.)
                        .font_weight(FontWeight::SEMI_BOLD)
                        .color(TEXT)
                        .text("Alera Dev"),
                )
                .child(rect().width(Size::flex(1.)).child(""))
                .child(
                    TooltipContainer::new(Tooltip::new_text("Toggle Sidebar"))
                        .position(AttachedPosition::Bottom)
                        .delay(Duration::from_millis(350))
                        .child(
                            rect()
                                .width(Size::px(32.))
                                .height(Size::px(32.))
                                .center()
                                .corner_radius(6.)
                                .a11y_role(AccessibilityRole::Button)
                                .a11y_alt("Toggle Sidebar")
                                .on_pointer_enter(|_| Cursor::set(CursorIcon::Pointer))
                                .on_pointer_leave(|_| Cursor::set(CursorIcon::default()))
                                .on_pointer_down(move |event: Event<PointerEventData>| {
                                    event.stop_propagation();
                                    let mut collapsed = sidebar_collapsed;
                                    collapsed.set(true);
                                    spawn(async move {
                                        let _ = blocking::unblock(move || {
                                            local_settings::persist_fields([(
                                                "sidebar_collapsed",
                                                json!(true),
                                            )])
                                        })
                                        .await;
                                    });
                                })
                                .child(
                                    SvgViewer::new(icons::lucide::panel_left())
                                        .width(Size::px(15.))
                                        .height(Size::px(15.))
                                        .color(MUTED),
                                ),
                        ),
                ),
        )
        .child(
            rect()
                .width(Size::fill())
                .height(Size::px(1.))
                .background(SIDEBAR_BORDER),
        )
        .child(
            rect()
                .width(Size::fill())
                .padding(Gaps::new(4., 12., 8., 12.))
                .child(sidebar_search),
        )
        .child(
            rect()
                .width(Size::fill())
                .height(Size::px(36.))
                .horizontal()
                .content(Content::Flex)
                .cross_align(Alignment::Center)
                .spacing(6.)
                .padding(Gaps::new(4., 12., 4., 12.))
                .child(
                    label()
                        .font_size(13.)
                        .font_weight(FontWeight::SEMI_BOLD)
                        .color(TEXT)
                        .text(if sidebar_prefs.group_by == SidebarGroupBy::Project {
                            "Projects"
                        } else {
                            "Workspaces"
                        }),
                )
                .child(
                    label()
                        .font_size(10.)
                        .font_weight(FontWeight::MEDIUM)
                        .color(FAINT)
                        .text(workspace_count.to_string()),
                )
                .child(rect().width(Size::flex(1.)).child(""))
                .child(
                    TooltipContainer::new(Tooltip::new_text("View Options"))
                        .position(AttachedPosition::Bottom)
                        .delay(Duration::from_millis(350))
                        .child(sidebar_toolbar_button(
                            "sidebar-view-options",
                            icons::lucide::sliders_horizontal(),
                            move |event: Event<PointerEventData>| {
                                event.stop_propagation();
                                let mut open = sidebar_view_options_open;
                                let mut project_query = sidebar_view_project_query;
                                let mut tag_query = sidebar_view_tag_query;
                                project_query.set(String::new());
                                tag_query.set(String::new());
                                open.set(true);
                            },
                        )),
                )
                .child(
                    TooltipContainer::new(Tooltip::new_text(if sidebar_all_collapsed {
                        "Expand All"
                    } else {
                        "Collapse All"
                    }))
                    .position(AttachedPosition::Bottom)
                    .delay(Duration::from_millis(350))
                    .child(sidebar_toolbar_button(
                        "sidebar-collapse-all",
                        if sidebar_all_collapsed {
                            icons::lucide::chevrons_up_down()
                        } else {
                            icons::lucide::chevrons_down_up()
                        },
                        {
                            let bridge = bridge.clone();
                            let mut projects = sidebar_prefs.collapsed_project_ids.clone();
                            let mut parents = sidebar_prefs.collapsed_parent_workspace_ids.clone();
                            let mut agents = sidebar_prefs.expanded_workspace_ids.clone();
                            if sidebar_all_collapsed {
                                projects.retain(|id| !collapse_project_ids.contains(id));
                                parents.retain(|id| !collapse_parent_ids.contains(id));
                                agents.extend(collapse_agent_ids.iter().cloned());
                            } else {
                                projects.extend(collapse_project_ids.iter().cloned());
                                parents.extend(collapse_parent_ids.iter().cloned());
                                agents.retain(|id| !collapse_agent_ids.contains(id));
                            }
                            move |event: Event<PointerEventData>| {
                                event.stop_propagation();
                                if can_collapse_sidebar {
                                    update_sidebar_prefs(
                                        bridge.clone(),
                                        vec![
                                            ("collapsedProjectIds", string_set_json(&projects)),
                                            (
                                                "collapsedParentWorkspaceIds",
                                                string_set_json(&parents),
                                            ),
                                            ("expandedWorkspaceIds", string_set_json(&agents)),
                                        ],
                                    );
                                }
                            }
                        },
                    )),
                )
                .child(
                    TooltipContainer::new(Tooltip::new_text("New Workspace"))
                        .position(AttachedPosition::Bottom)
                        .delay(Duration::from_millis(350))
                        .child(
                            Button::new()
                                .compact()
                                .flat()
                                .on_press(move |_| {
                                    let selected_project_id = selected_project_and_workspace
                                        .as_ref()
                                        .map(|(project, _)| project.id.clone());
                                    workspace_target_project_id.set(selected_project_id);
                                    action_dialog.set(Some(ActionDialog::NewWorkspace));
                                    action_dialog_error.set(None);
                                })
                                .child("+"),
                        ),
                ),
        )
        .child(
            rect()
                .width(Size::fill())
                .height(Size::px(1.))
                .background(SIDEBAR_BORDER),
        )
        .child(
            rect().width(Size::fill()).height(Size::flex(1.)).child(
                ScrollView::new()
                    .width(Size::fill())
                    .height(Size::fill())
                    .child(sidebar_rows_view(
                        sidebar_rows,
                        selected_workspace,
                        selected_tab_request,
                        active_sidebar_tab_id,
                        sidebar_action_controls,
                        action_dialog,
                        bridge.clone(),
                        sidebar_prefs.clone(),
                    )),
            ),
        )
        .child(
            rect()
                .height(Size::px(44.))
                .background((24, 24, 24))
                .padding(Gaps::new(4., 8., 4., 8.))
                .width(Size::fill())
                .horizontal()
                .content(Content::Flex)
                .cross_align(Alignment::Center)
                .spacing(6.)
                .child(
                    Button::new()
                        .width(Size::px(140.))
                        .height(Size::px(34.))
                        .outline()
                        .theme_colors(
                            ButtonColorsThemePartial::new()
                                .background(SURFACE)
                                .hover_background(SURFACE_RAISED)
                                .border_fill(BORDER)
                                .focus_border_fill(ACCENT)
                                .color(TEXT),
                        )
                        .on_press(move |_| {
                            action_dialog.set(Some(ActionDialog::AddProject));
                            action_dialog_error.set(None);
                        })
                        .child(
                            rect()
                                .horizontal()
                                .cross_align(Alignment::Center)
                                .spacing(6.)
                                .child(
                                    SvgViewer::new(icons::lucide::folder_plus())
                                        .width(Size::px(15.))
                                        .height(Size::px(15.))
                                        .color(TEXT),
                                )
                                .child(label().font_size(11.).color(TEXT).text("Add Project")),
                        ),
                )
                .child(
                    TooltipContainer::new(Tooltip::new_text("Open Settings"))
                        .position(AttachedPosition::Top)
                        .delay(Duration::from_millis(350))
                        .child(
                            rect()
                                .key("sidebar-settings")
                                .width(Size::px(30.))
                                .height(Size::px(30.))
                                .center()
                                .corner_radius(5.)
                                .a11y_role(AccessibilityRole::Button)
                                .a11y_alt("Open Settings")
                                .on_pointer_enter(|_| Cursor::set(CursorIcon::Pointer))
                                .on_pointer_leave(|_| Cursor::set(CursorIcon::default()))
                                .on_pointer_down(move |event: Event<PointerEventData>| {
                                    event.stop_propagation();
                                    settings_open.set(true);
                                })
                                .child(
                                    SvgViewer::new(icons::lucide::settings())
                                        .width(Size::px(16.))
                                        .height(Size::px(16.))
                                        .color(MUTED),
                                ),
                        ),
                ),
        )
        .child(sidebar_resize_handle);
    let sidebar = if sidebar_collapsed() {
        collapsed_sidebar
    } else {
        expanded_sidebar.into_element()
    };

    let show_welcome = selected_workspace.read().is_empty() && !settings_open();
    // Freya hooks must be mounted in a stable order.  Keep the workbench and
    // context panel alive while the welcome screen is visible, and only swap
    // their rendered surface below.
    let workbench_view = docking::workbench(
        bridge.clone(),
        runtime_context.clone(),
        snapshot_cache,
        terminal_outputs,
        event_tick,
        open_editor_path,
        editor_dirty_documents,
        editor_reload,
        explorer_path_move,
        open_git_diff_request,
        rename_request,
        rename_title,
        selected_tab_request,
        terminal_settings,
    );
    let settings_view = settings_panel(settings_open, bridge.clone(), terminal_settings_revision);
    let terminal = rect()
        .width(Size::flex(1.))
        .height(Size::fill())
        .background(BACKGROUND)
        .child(if settings_open() {
            rect().expanded().background(BACKGROUND).into_element()
        } else if show_welcome {
            welcome_dashboard(
                settings_open,
                action_dialog,
                action_dialog_error,
                workspace_target_project_id,
            )
        } else {
            workbench_view
        });

    let context_directory = runtime_context
        .as_ref()
        .map(|(_, path)| path.clone())
        .unwrap_or_else(|| ".".to_string());
    let context_mode = use_state(|| "Explorer".to_string());
    let context_panel_view = context_panel(
        bridge.clone(),
        forge_service.clone(),
        context_mode,
        runtime_mode,
        runtime_loading,
        runtime_status,
        context_directory,
        runtime_context.as_ref().map(|(id, _)| id.clone()),
        source_control_scope,
        can_focus_source_control_folders,
        view_prefs_revision,
        open_editor_path,
        editor_dirty_documents,
        editor_reload,
        explorer_path_move,
        open_git_diff_request,
        source_git_dialog,
        source_git_dialog_message,
        source_git_revision,
        forge_refresh_revision,
        pull_request_confirmation,
        explorer_dialog,
        explorer_dialog_value,
        explorer_revision,
    );
    let context_panel = (!show_welcome && !settings_open()).then_some(context_panel_view);
    let workspace_snapshot = snapshot_value
        .as_ref()
        .and_then(|result| result.as_ref().ok());
    let workspace_project_options = workspace_snapshot
        .map(workspace_project_options)
        .unwrap_or_default();
    let requested_project_id = workspace_target_project_id.read().clone();
    let stored_project_id = option_id(workspace_project.read().as_str()).map(str::to_string);
    let workspace_dialog_project_id = requested_project_id
        .clone()
        .filter(|id| option_has_id(&workspace_project_options, id))
        .or_else(|| stored_project_id.filter(|id| option_has_id(&workspace_project_options, id)))
        .or_else(|| first_option_id(&workspace_project_options));
    let workspace_parent_options = workspace_snapshot
        .map(|snapshot| workspace_parent_options(snapshot, workspace_dialog_project_id.as_deref()))
        .unwrap_or_else(|| vec!["No Parent".to_string()]);
    let workspace_used_branches = workspace_snapshot
        .map(|snapshot| workspace_branch_names(snapshot, workspace_dialog_project_id.as_deref()))
        .unwrap_or_default();
    let workspace_dialog_seed_deps = (
        *action_dialog.read() == Some(ActionDialog::NewWorkspace),
        requested_project_id,
        workspace_project_options.clone(),
    );
    let mut workspace_project_for_seed = workspace_project;
    let mut workspace_target_project_for_seed = workspace_target_project_id;
    let mut workspace_prompt_created_for_seed = workspace_prompt_created_id;
    let mut workspace_creation_phase_for_seed = workspace_creation_phase;
    let mut workspace_action_error_for_seed = action_dialog_error;
    let mut workspace_dialog_initialized_for_seed = workspace_dialog_initialized;
    use_side_effect_with_deps(
        &workspace_dialog_seed_deps,
        move |(open, requested_project_id, project_options)| {
            if !*open {
                workspace_dialog_initialized_for_seed.set(false);
                return;
            }
            let requested = requested_project_id.as_deref();
            let current_project = workspace_project_for_seed.peek();
            let current_id = option_id(current_project.as_str());
            let current_is_valid = current_id.is_some_and(|id| option_has_id(project_options, id));
            let should_initialize = !*workspace_dialog_initialized_for_seed.peek()
                || requested.is_some()
                || !current_is_valid;
            if !should_initialize {
                return;
            }
            let selected = requested
                .and_then(|id| option_for_id(project_options, id))
                .or_else(|| current_id.and_then(|id| option_for_id(project_options, id)))
                .or_else(|| project_options.first().cloned())
                .unwrap_or_default();
            workspace_project_for_seed.set(selected);
            workspace_target_project_for_seed.set(None);
            workspace_prompt_created_for_seed.set(None);
            workspace_creation_phase_for_seed.set(None);
            workspace_action_error_for_seed.set(None);
            workspace_dialog_initialized_for_seed.set(true);
        },
    );
    let workspace_dialog_load_deps = (
        *action_dialog.read() == Some(ActionDialog::NewWorkspace),
        workspace_dialog_project_id.clone(),
        workspace_used_branches.clone(),
    );
    let workspace_dialog_bridge = bridge.clone();
    let mut workspace_branch_options_for_load = workspace_branch_options;
    let mut workspace_local_branch_options_for_load = workspace_local_branch_options;
    let mut workspace_source_branch_for_load = workspace_source_branch;
    let mut workspace_branch_for_load = workspace_branch;
    let mut workspace_prompt_created_for_branch_load = workspace_prompt_created_id;
    let mut workspace_branches_project_for_load = workspace_branches_project_id;
    let workspace_project_for_load_check = workspace_project;
    let mut workspace_error_for_branch_load = action_dialog_error;
    use_side_effect_with_deps(
        &workspace_dialog_load_deps,
        move |(open, project_id, used_branches)| {
            if !*open {
                return;
            }
            let bridge = workspace_dialog_bridge.clone();
            let project_id = project_id.clone();
            let used_branches = used_branches.clone();
            spawn(async move {
                if let Some(project_id) = project_id {
                    let project_changed = workspace_branches_project_for_load.peek().as_deref()
                        != Some(project_id.as_str());
                    if project_changed {
                        workspace_branches_project_for_load.set(Some(project_id.clone()));
                        workspace_prompt_created_for_branch_load.set(None);
                        workspace_error_for_branch_load.set(None);
                    }
                    match bridge
                        .request_with_timeout(
                            "project.branches.list",
                            json!({"projectId": project_id}),
                            Duration::from_secs(30),
                        )
                        .await
                    {
                        Ok(value) => {
                            if option_id(workspace_project_for_load_check.peek().as_str())
                                != Some(project_id.as_str())
                            {
                                return;
                            }
                            let branches = string_options(&value, "branches");
                            let local_branches = string_options(&value, "localBranches")
                                .into_iter()
                                .filter(|branch| !used_branches.contains(branch))
                                .collect::<Vec<_>>();
                            let selected_source = workspace_source_branch_for_load.peek().clone();
                            if project_changed || !branches.contains(&selected_source) {
                                workspace_source_branch_for_load
                                    .set(preferred_workspace_branch(&branches).unwrap_or_default());
                            }
                            if *workspace_reuse_existing_branch.peek() {
                                let selected_branch = workspace_branch_for_load.peek().clone();
                                if project_changed || !local_branches.contains(&selected_branch) {
                                    workspace_branch_for_load.set(
                                        preferred_workspace_branch(&local_branches)
                                            .unwrap_or_default(),
                                    );
                                }
                            } else if project_changed {
                                workspace_branch_for_load.set(String::new());
                            }
                            workspace_branch_options_for_load.set(branches);
                            workspace_local_branch_options_for_load.set(local_branches);
                            workspace_error_for_branch_load.set(None);
                        }
                        Err(error) => workspace_error_for_branch_load.set(Some(error)),
                    }
                }
            });
        },
    );
    let workspace_profiles_load_deps = *action_dialog.read() == Some(ActionDialog::NewWorkspace);
    let workspace_profiles_bridge = bridge.clone();
    let mut workspace_agent_profile_options_for_load = workspace_agent_profile_options;
    let mut workspace_agent_profile_for_load = workspace_agent_profile;
    let mut workspace_error_for_profile_load = action_dialog_error;
    use_side_effect_with_deps(&workspace_profiles_load_deps, move |open| {
        if !*open {
            return;
        }
        let bridge = workspace_profiles_bridge.clone();
        spawn(async move {
            match bridge
                .request_with_timeout("agentProfile.list", json!({}), Duration::from_secs(30))
                .await
                .and_then(|value| parse_agent_profile_options(&value))
            {
                Ok(profiles) => {
                    let current_profile = workspace_agent_profile_for_load.peek();
                    let current_id = option_id(current_profile.as_str());
                    let selected = current_id
                        .and_then(|id| option_for_id(&profiles, id))
                        .or_else(|| profiles.first().cloned())
                        .unwrap_or_default();
                    workspace_agent_profile_for_load.set(selected);
                    workspace_agent_profile_options_for_load.set(profiles);
                }
                Err(error) => workspace_error_for_profile_load.set(Some(error)),
            }
        });
    });
    let dialog_view = (*action_dialog.read()).map(|kind| {
        action_dialog_overlay(
            kind,
            action_dialog,
            action_dialog_error,
            add_project_path,
            add_project_name,
            add_project_clone_mode,
            add_project_clone_url,
            add_project_clone_parent,
            add_project_clone_directory,
            workspace_name,
            workspace_branch,
            workspace_prompt_mode,
            workspace_prompt,
            workspace_create_another,
            workspace_project,
            workspace_source_branch,
            workspace_parent,
            workspace_parent_options,
            workspace_agent_profile,
            workspace_project_options,
            workspace_used_branches,
            workspace_branch_options,
            workspace_local_branch_options,
            workspace_agent_profile_options,
            workspace_reuse_existing_branch,
            workspace_creation_busy,
            workspace_creation_phase,
            workspace_prompt_created_id,
            workspace_open_dropdown,
            workspace_dropdown_just_opened,
            bridge.clone(),
            selected_workspace,
            selected_tab_request,
            snapshot_revision,
        )
    });
    let sidebar_action_dialog_view = sidebar_action_dialog.read().clone().map(|dialog| {
        sidebar_action_dialog::overlay(
            dialog,
            sidebar_action_dialog,
            sidebar_action_value,
            sidebar_action_selected_tags,
            sidebar_action_selected_parent,
            sidebar_action_busy,
            sidebar_action_error,
            bridge.clone(),
            snapshot_value
                .as_ref()
                .and_then(|result| result.as_ref().ok())
                .cloned(),
            snapshot_revision,
            selected_workspace,
        )
    });
    let source_git_dialog_view = source_git_dialog.read().clone().map(|dialog| {
        source_git_dialog_overlay(
            dialog,
            source_git_dialog,
            source_git_dialog_message,
            source_git_dialog_error,
            source_git_dialog_loading,
            source_git_revision,
            bridge.clone(),
        )
    });
    let pull_request_confirmation_view = pull_request_confirmation.read().clone().map(|dialog| {
        pull_request_confirmation_overlay(
            dialog,
            pull_request_confirmation,
            pull_request_confirmation_loading,
            pull_request_confirmation_error,
            forge_refresh_revision,
            bridge.clone(),
            forge_service.clone(),
        )
    });
    let explorer_dialog_view = explorer_dialog.read().clone().map(|dialog| {
        explorer_dialog_overlay(
            dialog,
            explorer_dialog,
            explorer_dialog_value,
            explorer_dialog_loading,
            explorer_dialog_error,
            explorer_revision,
            explorer_path_move,
            bridge.clone(),
        )
    });
    let resource_panel = resource_manager::panel(
        bridge.clone(),
        resource_snapshot.read().clone(),
        snapshot_value
            .as_ref()
            .and_then(|snapshot| snapshot.as_ref().ok())
            .cloned(),
        resource_sort_column,
        resource_collapsed_projects,
        resource_close_confirmation,
        resource_action_busy,
        resource_action_message,
        resource_snapshot,
        selected_workspace,
        selected_tab_request,
        resource_popover_open,
    );
    let resource_chip = resource_status_chip(
        resource_snapshot
            .read()
            .as_ref()
            .and_then(|result| result.as_ref().ok()),
        snapshot_value
            .as_ref()
            .and_then(|snapshot| snapshot.as_ref().ok()),
    );
    let runtime_chip = runtime_status_chip(
        runtime_status_snapshot.read().as_ref(),
        runtime_status_error.read().as_deref(),
    );
    let runtime_force_confirmation_view = runtime_force_confirmation_overlay(
        bridge.clone(),
        RuntimeActionState {
            snapshot: runtime_status_snapshot,
            error: runtime_status_error,
            revision: runtime_status_revision,
            busy: runtime_action_busy,
            force_required: runtime_force_required,
            message: runtime_action_message,
            restart_after_stop: runtime_restart_after_stop,
        },
        runtime_start_config,
    );
    let resource_close_confirmation_view = resource_manager::close_confirmation_dialog(
        bridge.clone(),
        resource_close_confirmation,
        resource_action_busy,
        resource_action_message,
        resource_snapshot,
        snapshot_revision,
    );
    let codex_reset_confirmation_view = codex_reset_confirmation_overlay(
        bridge.clone(),
        codex_reset_confirmation,
        codex_reset_busy,
        codex_reset_error,
        quota_refresh_revision,
    );
    let quota_popover_open = use_state(|| false);
    let runtime_popover_open = use_state(|| false);
    let active_status_popover = use_state(|| None::<String>);
    let sidebar_view_options = sidebar_view_options_open().then(|| {
        sidebar_view_options_overlay(
            sidebar_view_options_open,
            bridge.clone(),
            sidebar_prefs.clone(),
            snapshot_value
                .as_ref()
                .and_then(|result| result.as_ref().ok())
                .cloned(),
            sidebar_view_project_query,
            sidebar_view_tag_query,
        )
    });

    rect()
        .expanded()
        .background(BACKGROUND)
        .color(TEXT)
        .vertical()
        .content(Content::Flex)
        .child(ContextMenuViewer::new())
        .child(
            rect()
                .width(Size::fill())
                .height(Size::flex(1.))
                .horizontal()
                .content(Content::Flex)
                .child(sidebar)
                .child(terminal)
                .maybe_child(context_panel),
        )
        .maybe_child(dialog_view)
        .maybe_child(sidebar_action_dialog_view)
        .maybe_child(source_git_dialog_view)
        .maybe_child(pull_request_confirmation_view)
        .maybe_child(explorer_dialog_view)
        .maybe_child(resource_close_confirmation_view)
        .maybe_child(codex_reset_confirmation_view)
        .maybe_child(runtime_force_confirmation_view)
        .maybe_child(sidebar_view_options)
        .child(
            rect()
                .width(Size::fill())
                .height(Size::px(30.))
                .background(SURFACE)
                .border(Border::new().width(1.).fill(BORDER))
                .horizontal()
                .content(Content::Flex)
                .cross_align(Alignment::Center)
                .padding(Gaps::new(2., 8., 2., 8.))
                .child(label().font_size(12.).color(MUTED).text("Local"))
                .child(status_popover(
                    "Quotas",
                    icons::lucide::gauge(),
                    "Agent Quotas",
                    Vec::new(),
                    Some(quota_overview),
                    quota_popover_open,
                    quota_status_chip(),
                    Some(("quotas".to_string(), active_status_popover)),
                ))
                .child(agent_status_bar(
                    &quota_request.state(),
                    &quota_settings_value,
                    bridge.clone(),
                    quota_refresh_revision,
                    codex_reset_confirmation,
                    codex_reset_error,
                    active_status_popover,
                ))
                .child(rect().width(Size::flex(1.)).child(""))
                .child(status_popover(
                    "Resources",
                    icons::lucide::activity(),
                    "Resource Manager",
                    Vec::new(),
                    Some(resource_panel),
                    resource_popover_open,
                    resource_chip,
                    Some(("resources".to_string(), active_status_popover)),
                ))
                .child(
                    TooltipContainer::new(Tooltip::new_text("Notifications"))
                        .position(AttachedPosition::Top)
                        .delay(Duration::from_millis(350))
                        .child(
                            Button::new().compact().flat().child(
                                SvgViewer::new(icons::lucide::bell())
                                    .width(Size::px(14.))
                                    .height(Size::px(14.))
                                    .color(MUTED),
                            ),
                        ),
                )
                .child(status_popover(
                    "Runtime",
                    icons::lucide::server(),
                    "Runtime",
                    runtime_metrics,
                    Some(runtime_actions),
                    runtime_popover_open,
                    runtime_chip,
                    Some(("runtime".to_string(), active_status_popover)),
                )),
        )
        .maybe_child(settings_open().then_some(settings_view))
}

#[allow(clippy::too_many_arguments)]
fn context_panel(
    bridge: RuntimeBridge,
    forge_service: ForgeService,
    context_mode: State<String>,
    runtime_mode: State<String>,
    runtime_loading: bool,
    runtime_status: &'static str,
    working_directory: String,
    workspace_id: Option<String>,
    source_control_scope: Option<SourceControlScopeView>,
    can_focus_source_control_folders: bool,
    view_prefs_revision: State<u64>,
    open_editor_path: State<Option<FileOpenRequest>>,
    editor_dirty_documents: State<HashMap<String, String>>,
    editor_reload: State<Option<EditorReloadRequest>>,
    explorer_path_move: State<Option<ExplorerPathMove>>,
    open_git_diff_request: State<Option<docking::GitDiffOpenRequest>>,
    source_git_dialog: State<Option<SourceGitDialog>>,
    source_git_dialog_message: State<String>,
    git_refresh_revision: State<u64>,
    forge_refresh_revision: State<u64>,
    pull_request_confirmation: State<Option<PullRequestConfirmation>>,
    explorer_dialog: State<Option<ExplorerDialog>>,
    explorer_dialog_value: State<String>,
    explorer_revision: State<u64>,
) -> Element {
    let source_control_directory = source_control_scope
        .as_ref()
        .map(|scope| scope.path.clone())
        .unwrap_or_default();
    let file_search = use_state(String::new);
    let source_menu = use_state(SourceMenuState::default);
    let source_action_hover = use_state(|| None::<&'static str>);
    let source_toolbar_hover = use_state(|| None::<&'static str>);
    let source_file_action_hover = use_state(|| None::<String>);
    let source_menu_hover = use_state(|| None::<SourceControlAction>);
    let source_filter_visible = use_state(|| false);
    let source_tree_mode = use_state(|| true);
    let source_all_collapsed = use_state(|| false);
    let source_collapsed_areas = use_state(HashSet::<String>::new);
    let source_collapsed_tree_nodes = use_state(HashSet::<String>::new);
    let source_history_expanded = use_state(|| false);
    let source_history_expanded_commits = use_state(HashSet::<String>::new);
    let source_history_hover = use_state(|| None::<String>);
    let source_history_action_menu = use_state(|| None::<String>);
    let source_history_files =
        use_state(HashMap::<String, Result<Vec<GitCommitChangeView>, String>>::new);
    let source_history_loading = use_state(HashSet::<String>::new);
    let source_history_height = use_state(|| 342_f32);
    let source_history_drag_y = use_state(|| None::<f64>);
    let commit_message = use_state(String::new);
    let source_commit_ai = AiTextGenerationState {
        busy: use_state(|| false),
        operation_id: use_state(|| None::<String>),
        message: use_state(|| None::<String>),
    };
    let forge_snapshot = use_state(|| None::<Result<ForgeSnapshot, String>>);
    let forge_loading = use_state(|| false);
    let forge_composer_mode = use_state(PullRequestComposerMode::default);
    let forge_title = use_state(String::new);
    let forge_body = use_state(String::new);
    let forge_base = use_state(String::new);
    let forge_link = use_state(String::new);
    let forge_comment = use_state(String::new);
    let forge_create_draft = use_state(|| false);
    let forge_action_loading = use_state(|| false);
    let forge_action_error = use_state(|| None::<String>);
    let forge_editing = use_state(|| false);
    let forge_collapsed_check_groups = use_state(HashSet::<String>::new);
    let forge_expanded_checks = use_state(HashSet::<String>::new);
    let pull_request_ai = AiTextGenerationState {
        busy: use_state(|| false),
        operation_id: use_state(|| None::<String>),
        message: use_state(|| None::<String>),
    };
    let forge_form_seed = forge_snapshot
        .read()
        .as_ref()
        .and_then(|result| result.as_ref().ok())
        .map(|snapshot| {
            let review = snapshot.review.as_ref();
            (
                snapshot.repo_slug.clone(),
                snapshot.branch.clone(),
                snapshot.suggested_base_branch.clone(),
                review.map(|review| review.number),
                review
                    .map(|review| review.title.clone())
                    .unwrap_or_default(),
                review.map(|review| review.body.clone()).unwrap_or_default(),
                review
                    .map(|review| review.base_branch.clone())
                    .unwrap_or_default(),
            )
        });
    let mut forge_title_for_seed = forge_title;
    let mut forge_body_for_seed = forge_body;
    let mut forge_base_for_seed = forge_base;
    let mut forge_editing_for_seed = forge_editing;
    use_side_effect_with_deps(&forge_form_seed, move |seed| {
        let Some((_, branch, suggested_base, review_number, title, body, review_base)) = seed
        else {
            return;
        };
        forge_title_for_seed.set(if review_number.is_some() {
            title.clone()
        } else {
            branch.clone()
        });
        forge_body_for_seed.set(body.clone());
        forge_base_for_seed.set(if review_base.is_empty() {
            if suggested_base.is_empty() {
                "main".to_string()
            } else {
                suggested_base.clone()
            }
        } else {
            review_base.clone()
        });
        forge_editing_for_seed.set(false);
    });
    let explorer_clipboard = use_state(|| None::<ExplorerClipboard>);
    let explorer_drag = use_drag::<ExplorerDragData>();
    let explorer_drag_hover = use_state(|| None::<String>);
    let explorer_poll_generation = use_state(|| 0_u64);
    let source_root_message = use_state(|| None::<String>);
    let source_root_move_scope = source_control_scope.as_ref().map(|scope| {
        (
            scope.workspace_id.clone(),
            scope.workspace_path.clone(),
            scope.relative_root.clone(),
        )
    });
    let source_root_move_deps = (explorer_path_move.read().clone(), source_root_move_scope);
    let source_root_move_bridge = bridge.clone();
    let source_root_move_revision = view_prefs_revision;
    let source_root_move_message = source_root_message;
    use_side_effect_with_deps(&source_root_move_deps, move |(path_move, scope)| {
        let (Some(path_move), Some((workspace_id, workspace_path, Some(current_root)))) =
            (path_move.as_ref(), scope.as_ref())
        else {
            return;
        };
        if path_move.workspace_path != *workspace_path {
            return;
        }
        let Some(next_root) = replace_workspace_path_prefix(
            current_root,
            &path_move.old_relative_path,
            &path_move.new_relative_path,
        ) else {
            return;
        };
        let bridge = source_root_move_bridge.clone();
        let workspace_id = workspace_id.clone();
        let workspace_path = workspace_path.clone();
        let mut revision = source_root_move_revision;
        let mut message = source_root_move_message;
        spawn(async move {
            match update_source_control_root(
                &bridge,
                Some(&workspace_id),
                &workspace_path,
                Some(next_root),
            )
            .await
            {
                Ok(()) => {
                    message.set(None);
                    let next = revision.read().saturating_add(1);
                    revision.set(next);
                }
                Err(error) => message.set(Some(error)),
            }
        });
    });
    let selected_mode = context_mode.read().clone();
    let source_control_available = source_control_scope.is_some();
    let show_context_title = selected_mode != "Source Control";
    let runtime_selector = runtime_mode_selector(runtime_mode);
    let mut source_menu_for_mode = source_menu;
    let mut source_action_hover_for_mode = source_action_hover;
    let mut source_toolbar_hover_for_mode = source_toolbar_hover;
    let mut source_menu_hover_for_mode = source_menu_hover;
    let mut source_history_action_menu_for_mode = source_history_action_menu;
    use_side_effect_with_deps(&selected_mode, move |_| {
        source_menu_for_mode.set(SourceMenuState::default());
        source_action_hover_for_mode.set(None);
        source_toolbar_hover_for_mode.set(None);
        source_menu_hover_for_mode.set(None);
        source_history_action_menu_for_mode.set(None);
    });
    let mut context_mode_for_availability = context_mode;
    use_side_effect_with_deps(
        &(selected_mode.clone(), source_control_available),
        move |(mode, available)| {
            if !available && matches!(mode.as_str(), "Source Control" | "Pull Request") {
                context_mode_for_availability.set("Explorer".to_string());
            }
        },
    );
    let mut source_history_expanded_for_workspace = source_history_expanded_commits;
    let mut source_history_files_for_workspace = source_history_files;
    let mut source_history_loading_for_workspace = source_history_loading;
    use_side_effect_with_deps(&source_control_directory, move |_| {
        source_history_expanded_for_workspace.set(HashSet::new());
        source_history_files_for_workspace.set(HashMap::new());
        source_history_loading_for_workspace.set(HashSet::new());
    });
    let explorer_poll_deps = (selected_mode.clone(), working_directory.clone());
    let mut explorer_poll_generation_for_effect = explorer_poll_generation;
    let explorer_poll_generation_for_task = explorer_poll_generation;
    let mut explorer_revision_for_poll = explorer_revision;
    use_side_effect_with_deps(&explorer_poll_deps, move |deps| {
        let (mode, directory) = deps.clone();
        let generation = explorer_poll_generation_for_effect.peek().saturating_add(1);
        explorer_poll_generation_for_effect.set(generation);
        if mode != "Explorer" || directory.is_empty() {
            return;
        }
        let generation_state = explorer_poll_generation_for_task;
        spawn(async move {
            loop {
                Timer::after(Duration::from_secs(2)).await;
                if *generation_state.peek() != generation {
                    break;
                }
                let next = explorer_revision_for_poll.peek().saturating_add(1);
                explorer_revision_for_poll.set(next);
            }
        });
    });

    // These states and effects intentionally live at the stable context-panel
    // hook boundary.  Explorer, Search and Source Control are alternate
    // bodies, but Freya still requires their hooks to be called in the same
    // order on every render when the user switches modes.
    let explorer_entries = use_state(|| None::<Result<Vec<ExplorerEntry>, String>>);
    let explorer_entries_for_request = explorer_entries;
    let explorer_bridge = bridge.clone();
    let explorer_request_deps = (working_directory.clone(), *explorer_revision.read());
    use_side_effect_with_deps(&explorer_request_deps, move |deps| {
        let (directory, _) = deps.clone();
        let bridge = explorer_bridge.clone();
        let mut result = explorer_entries_for_request;
        spawn(async move {
            let response = bridge
                .request(
                    "workspaceFiles.list",
                    json!({
                        "workspacePath": directory,
                        "relativePath": "",
                        "hideIgnored": false,
                    }),
                )
                .await
                .map(|value| parse_explorer_entries(&value));
            result.set(Some(response));
        });
    });

    let expanded_dirs = use_state(HashSet::<String>::new);
    let directory_children = use_state(HashMap::<String, Result<Vec<ExplorerEntry>, String>>::new);
    let mut expanded_dirs_for_reset = expanded_dirs;
    let mut directory_children_for_reset = directory_children;
    let explorer_cache_deps = (working_directory.clone(), *explorer_revision.read());
    use_side_effect_with_deps(&explorer_cache_deps, move |_| {
        expanded_dirs_for_reset.set(HashSet::new());
        directory_children_for_reset.set(HashMap::new());
    });

    let directory_request_deps = (working_directory.clone(), expanded_dirs.read().clone());
    let directory_bridge = bridge.clone();
    let directory_children_for_request = directory_children;
    use_side_effect_with_deps(&directory_request_deps, move |deps| {
        let (directory, expanded) = deps.clone();
        let cached = directory_children_for_request
            .read()
            .keys()
            .cloned()
            .collect::<HashSet<_>>();
        for relative_path in expanded.into_iter().filter(|path| !cached.contains(path)) {
            let bridge = directory_bridge.clone();
            let mut children = directory_children_for_request;
            let request_path = relative_path.clone();
            let workspace_path = directory.clone();
            spawn(async move {
                let result = bridge
                    .request(
                        "workspaceFiles.list",
                        json!({
                            "workspacePath": workspace_path.clone(),
                            "relativePath": request_path,
                            "hideIgnored": false,
                        }),
                    )
                    .await
                    .map(|value| parse_explorer_entries(&value));
                children.write().insert(relative_path, result);
            });
        }
    });

    let search_results = use_state(|| None::<Result<WorkspaceSearchView, String>>);
    let search_replacement = use_state(String::new);
    let search_include_pattern = use_state(String::new);
    let search_exclude_pattern = use_state(String::new);
    let search_case_sensitive = use_state(|| false);
    let search_whole_word = use_state(|| false);
    let search_use_regex = use_state(|| false);
    let search_preserve_case = use_state(|| false);
    let search_include_ignored = use_state(|| false);
    let search_view_as_tree = use_state(|| false);
    let search_replace_visible = use_state(|| false);
    let search_details_visible = use_state(|| false);
    let search_collapsed_nodes = use_state(HashSet::<String>::new);
    let search_loading = use_state(|| false);
    let search_replacing = use_state(|| false);
    let search_replace_message = use_state(|| None::<String>);
    let search_replace_confirmation = use_state(|| None::<(String, String, u64)>);
    let search_revision = use_state(|| 0_u64);
    let search_generation = use_state(|| 0_u64);
    let search_request_deps = (
        working_directory.clone(),
        file_search.read().clone(),
        search_replacement.read().clone(),
        search_include_pattern.read().clone(),
        search_exclude_pattern.read().clone(),
        *search_case_sensitive.read(),
        *search_whole_word.read(),
        *search_use_regex.read(),
        *search_preserve_case.read(),
        *search_include_ignored.read(),
        *search_revision.read(),
    );
    let search_bridge = bridge.clone();
    let mut search_results_for_request = search_results;
    let mut search_loading_for_request = search_loading;
    let mut search_generation_for_effect = search_generation;
    let search_generation_for_task = search_generation;
    let mut search_collapsed_for_request = search_collapsed_nodes;
    let mut search_confirmation_for_request = search_replace_confirmation;
    use_side_effect_with_deps(&search_request_deps, move |deps| {
        let (
            directory,
            query,
            replacement,
            include_pattern,
            exclude_pattern,
            case_sensitive,
            whole_word,
            use_regex,
            preserve_case,
            include_ignored,
            _,
        ) = deps.clone();
        let generation = search_generation_for_effect.peek().saturating_add(1);
        search_generation_for_effect.set(generation);
        search_collapsed_for_request.set(HashSet::new());
        search_confirmation_for_request.set(None);
        if query.trim().is_empty() {
            search_loading_for_request.set(false);
            search_results_for_request.set(None);
            return;
        }
        search_loading_for_request.set(true);
        search_results_for_request.set(None);
        let bridge = search_bridge.clone();
        let mut result = search_results_for_request;
        let mut loading = search_loading_for_request;
        let generation_state = search_generation_for_task;
        spawn(async move {
            Timer::after(Duration::from_millis(250)).await;
            if *generation_state.peek() != generation {
                return;
            }
            let method = if replacement.is_empty() {
                "workspaceSearch.search"
            } else {
                "workspaceSearch.previewReplace"
            };
            let response = bridge
                .request(
                    method,
                    json!({
                        "workspacePath": directory,
                        "query": query,
                        "caseSensitive": case_sensitive,
                        "wholeWord": whole_word,
                        "useRegex": use_regex,
                        "includePattern": (!include_pattern.trim().is_empty()).then_some(include_pattern),
                        "excludePattern": (!exclude_pattern.trim().is_empty()).then_some(exclude_pattern),
                        "includeIgnored": include_ignored,
                        "replacement": replacement,
                        "preserveCase": preserve_case,
                    }),
                )
                .await
                .and_then(|value| parse_workspace_search_view(&value));
            if *generation_state.peek() == generation {
                result.set(Some(response));
                loading.set(false);
            }
        });
    });

    let git_snapshot = use_state(|| None::<Result<GitSnapshotView, String>>);
    let git_loading = use_state(|| false);
    let mut git_snapshot_for_request = git_snapshot;
    let mut git_loading_for_request = git_loading;
    let git_bridge = bridge.clone();
    let git_request_deps = (
        source_control_directory.clone(),
        *git_refresh_revision.read(),
    );
    use_side_effect_with_deps(&git_request_deps, move |deps| {
        let (directory, _) = deps.clone();
        if directory.is_empty() {
            git_snapshot_for_request.set(None);
            git_loading_for_request.set(false);
            return;
        }
        let bridge = git_bridge.clone();
        let mut snapshot = git_snapshot_for_request;
        git_loading_for_request.set(true);
        let mut loading = git_loading_for_request;
        spawn(async move {
            let response = bridge
                .request_with_timeout(
                    "workspaceGit.snapshot",
                    json!({"workspacePath": directory}),
                    Duration::from_secs(30),
                )
                .await
                .map(|value| parse_git_snapshot(&value));
            snapshot.set(Some(response));
            loading.set(false);
        });
    });

    let forge_git_seed = git_snapshot
        .read()
        .as_ref()
        .and_then(|result| result.as_ref().ok())
        .map(|snapshot| (snapshot.branch.clone(), snapshot.branches.clone()));
    let forge_request_deps = (
        selected_mode == "Pull Request",
        workspace_id.clone(),
        source_control_directory.clone(),
        forge_git_seed,
        *forge_refresh_revision.read(),
    );
    let forge_bridge = bridge.clone();
    let forge_service_for_request = forge_service.clone();
    let mut forge_snapshot_for_request = forge_snapshot;
    let mut forge_loading_for_request = forge_loading;
    use_side_effect_with_deps(&forge_request_deps, move |deps| {
        let (visible, workspace_id, directory, git_seed, _) = deps.clone();
        if !visible {
            return;
        }
        let Some(workspace_id) = workspace_id else {
            forge_snapshot_for_request.set(None);
            forge_loading_for_request.set(false);
            return;
        };
        let Some((branch, branches)) = git_seed else {
            return;
        };
        forge_loading_for_request.set(true);
        let bridge = forge_bridge.clone();
        let service = forge_service_for_request.clone();
        let mut snapshot = forge_snapshot_for_request;
        let mut loading = forge_loading_for_request;
        spawn(async move {
            let remote = bridge
                .request(
                    "workspace.repositoryWebUrl",
                    json!({
                        "workspaceId": workspace_id,
                        "workspacePath": directory.clone(),
                    }),
                )
                .await
                .ok()
                .and_then(|value| {
                    value
                        .get("remoteUrl")
                        .and_then(Value::as_str)
                        .filter(|remote| !remote.trim().is_empty())
                        .map(str::to_string)
                });
            let result = match remote {
                None => Ok(unavailable_snapshot(ForgeUnavailableReason::NoRemote)),
                Some(remote) => match github_identity(&remote, branch, branches) {
                    Ok(identity) => {
                        let linked = bridge
                            .request("linkedReview.find", json!({"workspaceId": workspace_id}))
                            .await
                            .unwrap_or_else(|_| json!({}));
                        let dismissed = linked
                            .get("dismissed")
                            .and_then(Value::as_bool)
                            .unwrap_or(false);
                        let number = (!dismissed)
                            .then(|| linked.get("number").and_then(Value::as_u64))
                            .flatten();
                        service
                            .snapshot(directory, identity, number, dismissed)
                            .await
                    }
                    Err(reason) => Ok(unavailable_snapshot(reason)),
                },
            };
            snapshot.set(Some(result));
            loading.set(false);
        });
    });

    let nav = rect()
        .horizontal()
        .content(Content::Flex)
        .cross_align(Alignment::Center)
        .spacing(4.)
        .child(context_nav_button(
            context_mode,
            "Explorer",
            icons::lucide::folder_open(),
            true,
        ))
        .child(context_nav_button(
            context_mode,
            "Search",
            icons::lucide::search(),
            true,
        ))
        .child(context_nav_button(
            context_mode,
            "Source Control",
            icons::lucide::git_branch(),
            source_control_available,
        ))
        .child(context_nav_button(
            context_mode,
            "Pull Request",
            icons::lucide::git_fork(),
            source_control_available,
        ));

    let source_control_scope_for_panel =
        source_control_scope
            .clone()
            .unwrap_or_else(|| SourceControlScopeView {
                workspace_id: workspace_id.clone().unwrap_or_default(),
                workspace_path: working_directory.clone(),
                path: working_directory.clone(),
                relative_root: None,
            });

    let body = match selected_mode.as_str() {
        "Search" => context_search_panel(SearchPanelState {
            bridge: bridge.clone(),
            workspace_path: working_directory.clone(),
            results: search_results,
            query: file_search,
            replacement: search_replacement,
            include_pattern: search_include_pattern,
            exclude_pattern: search_exclude_pattern,
            case_sensitive: search_case_sensitive,
            whole_word: search_whole_word,
            use_regex: search_use_regex,
            preserve_case: search_preserve_case,
            include_ignored: search_include_ignored,
            view_as_tree: search_view_as_tree,
            replace_visible: search_replace_visible,
            details_visible: search_details_visible,
            collapsed_nodes: search_collapsed_nodes,
            loading: search_loading,
            replacing: search_replacing,
            replace_message: search_replace_message,
            replace_confirmation: search_replace_confirmation,
            revision: search_revision,
            open_editor_path,
            dirty_documents: editor_dirty_documents,
            editor_reload,
        }),
        "Source Control" => context_source_control_panel(
            bridge.clone(),
            source_control_scope_for_panel,
            git_snapshot,
            git_refresh_revision,
            git_loading,
            source_menu,
            source_action_hover,
            source_toolbar_hover,
            source_file_action_hover,
            source_menu_hover,
            source_filter_visible,
            source_tree_mode,
            source_all_collapsed,
            source_collapsed_areas,
            source_collapsed_tree_nodes,
            source_history_expanded,
            source_history_expanded_commits,
            source_history_hover,
            source_history_action_menu,
            source_history_files,
            source_history_loading,
            source_history_height,
            source_history_drag_y,
            source_git_dialog,
            source_git_dialog_message,
            open_git_diff_request,
            commit_message,
            source_commit_ai,
            file_search,
            view_prefs_revision,
            context_mode,
            source_root_message,
        ),
        "Pull Request" => context_pull_request_panel(
            bridge.clone(),
            forge_service.clone(),
            workspace_id.clone(),
            source_control_directory.clone(),
            forge_snapshot,
            forge_loading,
            forge_refresh_revision,
            forge_composer_mode,
            forge_title,
            forge_body,
            forge_base,
            forge_link,
            forge_comment,
            forge_create_draft,
            forge_action_loading,
            forge_action_error,
            forge_editing,
            pull_request_confirmation,
            pull_request_ai,
            forge_collapsed_check_groups,
            forge_expanded_checks,
        ),
        _ => context_explorer_panel(
            ExplorerPanelState {
                explorer_entries,
                expanded_dirs,
                directory_children,
                open_editor_path,
                drag: explorer_drag,
                drag_hover: explorer_drag_hover,
            },
            runtime_selector,
            runtime_loading,
            runtime_status,
            working_directory,
            ExplorerSourceControlSettings {
                bridge: bridge.clone(),
                workspace_id,
                workspace_path: source_control_scope
                    .as_ref()
                    .map(|scope| scope.workspace_path.clone())
                    .unwrap_or_else(|| source_control_directory.clone()),
                focused_root: source_control_scope
                    .as_ref()
                    .and_then(|scope| scope.relative_root.clone()),
                enabled: can_focus_source_control_folders,
                view_prefs_revision,
                context_mode,
                message: source_root_message,
                dialog: explorer_dialog,
                dialog_value: explorer_dialog_value,
                revision: explorer_revision,
                clipboard: explorer_clipboard,
                path_move: explorer_path_move,
            },
        ),
    };
    let body = if selected_mode == "Source Control" {
        body
    } else {
        ScrollView::new()
            .width(Size::fill())
            .height(Size::fill())
            .show_scrollbar(true)
            .child(body)
            .into_element()
    };

    rect()
        // Match Flutter's 288px trailing context rail at the same 0.75x
        // capture scale used by the Freya window.
        .width(Size::px(384.))
        .height(Size::fill())
        .background(SURFACE)
        .border(Border::new().width(1.).fill(BORDER))
        .padding(Gaps::new_all(12.))
        .spacing(10.)
        .vertical()
        .content(Content::Flex)
        .child(nav)
        .maybe_child(show_context_title.then(|| {
            label()
                .width(Size::fill())
                .font_size(14.)
                .color(TEXT)
                .text(selected_mode)
        }))
        .child(
            rect()
                .width(Size::fill())
                .height(Size::flex(1.))
                .child(body),
        )
        .into_element()
}

fn welcome_dashboard(
    settings_open: State<bool>,
    action_dialog: State<Option<ActionDialog>>,
    action_dialog_error: State<Option<String>>,
    workspace_target_project_id: State<Option<String>>,
) -> Element {
    rect()
        .expanded()
        .center()
        .padding(Gaps::new(39., 32., 25., 32.))
        .child(
            rect()
                .width(Size::px(950.))
                .max_width(Size::percent(100.))
                .vertical()
                .spacing(32.)
                .child(
                    rect()
                        .vertical()
                        .spacing(24.)
                        .child(
                            rect()
                                .horizontal()
                                .cross_align(Alignment::Center)
                                .spacing(16.)
                                .child(
                                    rect()
                                        .width(Size::px(52.))
                                        .height(Size::px(52.))
                                        .center()
                                        .background(SURFACE_RAISED)
                                        .border(Border::new().width(1.).fill(BORDER))
                                        .corner_radius(10.)
                                        .child(
                                            ImageViewer::new(("alera-logo", ALERA_LOGO))
                                                .width(Size::px(32.))
                                                .height(Size::px(32.)),
                                        ),
                                )
                                .child(
                                    rect()
                                        .vertical()
                                        .spacing(4.)
                                        .child(
                                            label()
                                                .font_size(22.)
                                                .color(TEXT)
                                                .text("Welcome to Alera"),
                                        )
                                        .child(label().font_size(14.).color(MUTED).text(
                                            "A terminal-first agentic developer environment",
                                        )),
                                ),
                        )
                        .child(
                            rect()
                                .height(Size::px(1.))
                                .width(Size::fill())
                                .background((39, 39, 39)),
                        ),
                )
                .child(
                    rect()
                        .horizontal()
                        .content(Content::Flex)
                        .cross_align(Alignment::Start)
                        .spacing(32.)
                        .child(
                            rect()
                                .width(Size::flex(1.))
                                .vertical()
                                .spacing(16.)
                                .child(label().font_size(13.).color(MUTED).text("Quick Start"))
                                .child(
                                    rect()
                                        .width(Size::fill())
                                        .vertical()
                                        .background(SURFACE)
                                        .border(Border::new().width(1.).fill((39, 39, 39)))
                                        .corner_radius(10.)
                                        .child(welcome_action(
                                            icons::lucide::folder_plus(),
                                            "Add Project",
                                            "Open a local folder or clone a repository",
                                            settings_open,
                                            action_dialog,
                                            action_dialog_error,
                                            workspace_target_project_id,
                                        ))
                                        .child(welcome_divider())
                                        .child(welcome_action(
                                            icons::lucide::git_fork(),
                                            "New Workspace",
                                            "Create a linked workspace for active Git project",
                                            settings_open,
                                            action_dialog,
                                            action_dialog_error,
                                            workspace_target_project_id,
                                        ))
                                        .child(welcome_divider())
                                        .child(welcome_action(
                                            icons::lucide::settings(),
                                            "Open Settings",
                                            "Configure keyboard shortcuts and preferences",
                                            settings_open,
                                            action_dialog,
                                            action_dialog_error,
                                            workspace_target_project_id,
                                        )),
                                ),
                        )
                        .child(
                            rect()
                                .width(Size::flex(1.))
                                .vertical()
                                .spacing(16.)
                                .child(
                                    label()
                                        .font_size(13.)
                                        .color(MUTED)
                                        .text("Keyboard Shortcuts"),
                                )
                                .child(
                                    rect()
                                        .width(Size::fill())
                                        .vertical()
                                        .background(SURFACE)
                                        .border(Border::new().width(1.).fill((39, 39, 39)))
                                        .corner_radius(10.)
                                        .padding(Gaps::new_all(18.))
                                        .spacing(8.)
                                        .children(
                                            [
                                                ("Add Project", "⌘⇧O"),
                                                ("New Workspace", "⌘⇧N"),
                                                ("Toggle Sidebar", "⌘B"),
                                                ("New Terminal Tab", "⌘T"),
                                                ("Open Settings", "⌘,"),
                                                ("Split Right", "⌘D"),
                                            ]
                                            .into_iter()
                                            .enumerate()
                                            .flat_map(
                                                |(index, (name, shortcut))| {
                                                    (index > 0)
                                                        .then(welcome_divider)
                                                        .into_iter()
                                                        .chain(std::iter::once(welcome_shortcut(
                                                            name, shortcut,
                                                        )))
                                                },
                                            ),
                                        ),
                                ),
                        ),
                ),
        )
        .into_element()
}

fn settings_panel(
    settings_open: State<bool>,
    bridge: RuntimeBridge,
    terminal_settings_revision: State<u64>,
) -> Element {
    let selected_section = use_state(|| "Application".to_string());
    let search = use_state(String::new);
    let reset_revision = use_state(|| 0usize);
    let runtime_settings = use_state(|| None::<Result<Value, String>>);
    let bridge_for_settings = bridge.clone();
    let mut runtime_settings_for_load = runtime_settings;
    use_side_effect(move || {
        let bridge = bridge_for_settings.clone();
        spawn(async move {
            runtime_settings_for_load
                .set(Some(bridge.request("runtimeSettings.get", json!({})).await));
        });
    });
    let selected = selected_section.read().clone();
    let close_settings = settings_open;
    let query = search.read().to_lowercase();
    let groups: [(&str, &[&str]); 2] = [
        (
            "PREFERENCES",
            &[
                "Account",
                "Application",
                "Agents",
                "Quotas",
                "AI Text",
                "Editor",
                "Terminal",
                "Browser",
                "Keyboard",
            ],
        ),
        (
            "RESOURCES",
            &[
                "Projects",
                "Mobile Devices",
                "Remote Hosts",
                "Agent Profiles",
            ],
        ),
    ];
    let navigation = rect()
        .width(Size::px(260.))
        .height(Size::fill())
        .background(SURFACE)
        .border(Border::new().width(1.).fill(BORDER))
        .vertical()
        .child(
            rect()
                .height(Size::px(48.))
                .padding(Gaps::new(12., 0., 12., 0.))
                .horizontal()
                .content(Content::Flex)
                .cross_align(Alignment::Center)
                .child(label().font_size(14.).color(TEXT).text("Settings")),
        )
        .child(rect().height(Size::px(1.)).background(BORDER))
        .child(
            rect().padding(Gaps::new_all(12.)).child(
                Input::new(search)
                    .placeholder("Search settings")
                    .width(Size::fill())
                    .expanded()
                    .filled()
                    .theme_layout(
                        InputLayoutThemePartial::new()
                            .corner_radius(CornerRadius::new_all(6.))
                            .inner_margin(Gaps::new(12., 12., 12., 12.)),
                    )
                    .leading(
                        SvgViewer::new(icons::lucide::search())
                            .width(Size::px(16.))
                            .height(Size::px(16.))
                            .color(FAINT),
                    )
                    .theme_colors(
                        InputColorsThemePartial::new()
                            .background(SURFACE_RAISED)
                            .focus_background(SURFACE_RAISED)
                            .border_fill(BORDER)
                            .focus_border_fill(BORDER)
                            .color(TEXT)
                            .placeholder_color(MUTED),
                    ),
            ),
        )
        .child(rect().height(Size::px(1.)).background(BORDER));
    let mut navigation_items = rect()
        .width(Size::fill())
        .padding(Gaps::new_all(8.))
        .vertical()
        .spacing(2.);
    let mut visible_navigation_entries = 0usize;
    for (group, entries) in groups {
        let matching_entries = entries
            .iter()
            .copied()
            .filter(|section| query.is_empty() || section.to_lowercase().contains(&query))
            .collect::<Vec<_>>();
        if matching_entries.is_empty() {
            continue;
        }
        if visible_navigation_entries > 0 {
            navigation_items = navigation_items.child(rect().height(Size::px(8.)));
        }
        navigation_items = navigation_items.child(
            rect()
                .padding(Gaps::new(8., 4., 8., 4.))
                .child(label().font_size(9.).color(FAINT).text(group)),
        );
        for section in matching_entries {
            visible_navigation_entries += 1;
            let active = selected == section;
            let mut selected_section = selected_section;
            navigation_items = navigation_items.child(
                rect()
                    .key(section)
                    .width(Size::fill())
                    .height(Size::px(30.))
                    .background(if active { SURFACE_RAISED } else { SURFACE })
                    .corner_radius(5.)
                    .padding(Gaps::new(8., 6., 8., 6.))
                    .a11y_role(AccessibilityRole::Button)
                    .a11y_alt(section)
                    .on_pointer_enter(|_| Cursor::set(CursorIcon::Pointer))
                    .on_pointer_leave(|_| Cursor::set(CursorIcon::default()))
                    .on_pointer_down(move |event: Event<PointerEventData>| {
                        event.stop_propagation();
                        selected_section.set(section.to_string());
                    })
                    .child(
                        rect()
                            .width(Size::fill())
                            .horizontal()
                            .content(Content::Flex)
                            .cross_align(Alignment::Center)
                            .spacing(8.)
                            .child(
                                rect()
                                    .width(Size::px(2.))
                                    .height(Size::px(16.))
                                    .corner_radius(2.)
                                    .background(if active { ACCENT } else { SURFACE }),
                            )
                            .child(
                                SvgViewer::new(settings_section_icon(section))
                                    .width(Size::px(15.))
                                    .height(Size::px(15.))
                                    .color(if active { TEXT } else { MUTED }),
                            )
                            .child(
                                label()
                                    .font_size(11.)
                                    .color(if active { TEXT } else { MUTED })
                                    .text(section),
                            ),
                    ),
            );
        }
    }
    if visible_navigation_entries == 0 {
        navigation_items = navigation_items.child(
            rect().height(Size::px(120.)).center().child(
                label()
                    .font_size(11.)
                    .color(MUTED)
                    .text("No matching settings."),
            ),
        );
    }
    let navigation = navigation.child(
        ScrollView::new()
            .width(Size::fill())
            .height(Size::flex(1.))
            .show_scrollbar(true)
            .child(navigation_items),
    );
    let header_title = if selected == "Application" {
        "Application"
    } else {
        selected.as_str()
    };
    let can_reset = matches!(
        selected.as_str(),
        "AI Text" | "Editor" | "Terminal" | "Keyboard"
    );
    let mut reset_revision_for_button = reset_revision;
    let mut close_for_button = close_settings;
    let chips = settings_group_chips(&selected);
    let right_header = rect()
        .width(Size::fill())
        .height(Size::px(120.))
        .background(SURFACE)
        .border(Border::new().width(1.).fill(BORDER))
        .padding(Gaps::new(20., 24., 14., 24.))
        .vertical()
        .spacing(4.)
        .child(
            rect()
                .width(Size::fill())
                .horizontal()
                .content(Content::Flex)
                .cross_align(Alignment::Center)
                .child(
                    rect()
                        .horizontal()
                        .content(Content::Flex)
                        .cross_align(Alignment::Center)
                        .spacing(10.)
                        .child(
                            SvgViewer::new(settings_section_icon(header_title))
                                .width(Size::px(18.))
                                .height(Size::px(18.))
                                .color(TEXT),
                        )
                        .child(
                            label()
                                .font_size(18.)
                                .color(TEXT)
                                .text(header_title.to_string()),
                        ),
                )
                .child(rect().width(Size::flex(1.)).child(""))
                .maybe_child(can_reset.then(|| {
                    Button::new()
                        .compact()
                        .flat()
                        .on_press(move |_| reset_revision_for_button.set(reset_revision() + 1))
                        .child(
                            label()
                                .font_size(10.)
                                .color(MUTED)
                                .text(format!("Reset {header_title}")),
                        )
                }))
                .child(
                    Button::new()
                        .flat()
                        .width(Size::px(34.))
                        .height(Size::px(34.))
                        .on_press(move |_| close_for_button.set(false))
                        .child(
                            SvgViewer::new(icons::lucide::x())
                                .width(Size::px(16.))
                                .height(Size::px(16.))
                                .color(MUTED),
                        ),
                ),
        )
        .child(
            label()
                .font_size(12.)
                .color(MUTED)
                .text(settings_subtitle(header_title)),
        )
        .maybe_child((chips.len() >= 3).then(|| {
            rect()
                .horizontal()
                .spacing(5.)
                .children(chips.into_iter().map(|chip| {
                    rect()
                        .background(SURFACE_RAISED)
                        .corner_radius(4.)
                        .padding(Gaps::new(6., 4., 6., 4.))
                        .child(label().font_size(9.).color(MUTED).text(chip))
                }))
        }));
    rect()
        .expanded()
        .position(Position::new_absolute())
        .layer(Layer::Overlay)
        .width(Size::percent(100.))
        .height(Size::percent(100.))
        .background(Color::from_af32rgb(0.62, 0, 0, 0))
        .padding(Gaps::new(40., 68., 40., 68.))
        .child(
            rect()
                .width(Size::fill())
                .height(Size::fill())
                .background(SURFACE)
                .border(Border::new().width(1.).fill(BORDER))
                .corner_radius(10.)
                .horizontal()
                .child(navigation)
                .child(
                    rect()
                        .width(Size::flex(1.))
                        .height(Size::fill())
                        .vertical()
                        .child(right_header)
                        .child(
                            ScrollView::new()
                                .width(Size::fill())
                                .height(Size::flex(1.))
                                .show_scrollbar(true)
                                .child(
                                    rect()
                                        .key(selected.clone())
                                        .width(Size::fill())
                                        .padding(Gaps::new(24., 24., 22., 24.))
                                        .vertical()
                                        .spacing(10.)
                                        .child(settings_section_content(
                                            &selected,
                                            bridge.clone(),
                                            runtime_settings,
                                            terminal_settings_revision,
                                        )),
                                ),
                        ),
                ),
        )
        .into_element()
}

fn settings_subtitle(section: &str) -> &'static str {
    match section {
        "Account" => "Identity, mobile push and runtime ownership.",
        "Application" => "Storage, safety, runtime, diagnostics and updates.",
        "Agents" => "Agent profiles, hooks and provider behavior.",
        "Quotas" => "Provider usage and refresh settings.",
        "AI Text" => "AI-generated source control text.",
        "Editor" => "Code editor defaults.",
        "Terminal" => "Appearance defaults for new terminal sessions.",
        "Browser" => "System engine, profiles and browsing data.",
        "Keyboard" => "Shortcuts and key bindings.",
        "Projects" => "Per-project workspace setup.",
        "Mobile Devices" => "Pair and manage the mobile companion app.",
        "Remote Hosts" => "SSH runtime targets.",
        "Agent Profiles" => "Launch configurations orchestration can dispatch to.",
        _ => "Configure Alera preferences and runtime behavior.",
    }
}

fn settings_section_icon(section: &str) -> Bytes {
    match section {
        "Account" => icons::lucide::user(),
        "Application" => icons::lucide::sliders_horizontal(),
        "Agents" | "Agent Profiles" => icons::lucide::bot(),
        "Quotas" => icons::lucide::gauge(),
        "AI Text" => icons::lucide::sparkles(),
        "Editor" => icons::lucide::code(),
        "Terminal" => icons::lucide::terminal(),
        "Browser" => icons::lucide::globe(),
        "Keyboard" => icons::lucide::keyboard(),
        "Projects" => icons::lucide::folder(),
        "Mobile Devices" => icons::lucide::smartphone(),
        "Remote Hosts" => icons::lucide::server(),
        _ => icons::lucide::settings(),
    }
}

fn settings_group_chips(section: &str) -> Vec<&'static str> {
    match section {
        "Account" => vec!["Identity", "Mobile Push", "Ownership"],
        "Application" => vec![
            "Storage",
            "Safety",
            "Runtime",
            "Diagnostics",
            "Updates",
            "Support",
        ],
        "Agents" => vec!["CLI And Skills", "Status Hooks", "Behavior"],
        "Quotas" => vec!["Providers", "Claude", "Credentials"],
        "AI Text" => vec!["Generation", "Prompt Overrides", "Instructions"],
        "Terminal" => vec![
            "Typography",
            "Cursor",
            "Appearance",
            "Interaction",
            "Advanced",
        ],
        "Browser" => vec![
            "General",
            "Profiles",
            "Trusted Certificates",
            "Browsing Data",
        ],
        "Mobile Devices" => vec![
            "Mobile Gateway",
            "Link A Device",
            "Active Pairing Offers",
            "Paired Devices",
        ],
        _ => Vec::new(),
    }
}

fn settings_section_content(
    section: &str,
    bridge: RuntimeBridge,
    runtime_settings: State<Option<Result<Value, String>>>,
    terminal_settings_revision: State<u64>,
) -> Element {
    let workspace_directory = use_state(|| "~/.alera/workspaces".to_string());
    let confirm_project_removal = use_state(|| true);
    let confirm_workspace_removal = use_state(|| true);
    let keep_runtime_open = use_state(|| true);
    let empty_host_shutdown = use_state(|| "30".to_string());
    let detached_session_shutdown = use_state(|| "3600".to_string());
    let ai_text_enabled = use_state(|| true);
    let ai_text_command = use_state(|| "alera ai-text".to_string());
    let editor_font_size = use_state(|| "13".to_string());
    let editor_minimap = use_state(|| true);
    let terminal_first_shortcuts = use_state(|| true);
    let browser_profile = use_state(|| "Default".to_string());
    let projects_auto_setup = use_state(|| true);
    let remote_host_target = use_state(|| "No remote hosts configured".to_string());
    let agent_profile = use_state(|| "Default local profile".to_string());
    let settings_seed = runtime_settings.read().clone();
    let mobile_content =
        mobile_access::settings_content(section == "Mobile Devices", bridge.clone());
    let diagnostics_content =
        settings_diagnostics::content(section == "Application", bridge.clone());
    let agents_content = settings_agents::content(section == "Agents", bridge.clone());
    let quotas_content = settings_quotas::content(section == "Quotas", bridge.clone());
    let terminal_content = settings_terminal::content(
        section == "Terminal",
        bridge.clone(),
        terminal_settings_revision,
    );
    let mut workspace_directory_for_seed = workspace_directory;
    let mut confirm_project_for_seed = confirm_project_removal;
    let mut confirm_workspace_for_seed = confirm_workspace_removal;
    let mut ai_enabled_for_seed = ai_text_enabled;
    let mut ai_command_for_seed = ai_text_command;
    use_side_effect_with_deps(&settings_seed, move |record| {
        let Some(Ok(settings)) = record else {
            return;
        };
        workspace_directory_for_seed.set(
            settings
                .get("workspaceDirectory")
                .and_then(Value::as_str)
                .filter(|value| !value.trim().is_empty())
                .unwrap_or("~/.alera/workspaces")
                .to_string(),
        );
        confirm_project_for_seed.set(
            settings
                .get("confirmProjectRemoval")
                .and_then(Value::as_bool)
                .unwrap_or(true),
        );
        confirm_workspace_for_seed.set(
            settings
                .get("confirmWorkspaceRemoval")
                .and_then(Value::as_bool)
                .unwrap_or(true),
        );
        let ai = settings.get("aiTextGeneration").and_then(Value::as_object);
        ai_enabled_for_seed.set(
            ai.and_then(|settings| settings.get("enabled"))
                .and_then(Value::as_bool)
                .unwrap_or(true),
        );
        ai_command_for_seed.set(
            ai.and_then(|settings| settings.get("customCommand"))
                .and_then(Value::as_str)
                .unwrap_or("alera ai-text")
                .to_string(),
        );
    });
    match runtime_settings.read().as_ref() {
        None => {
            return settings_section_layout(
                section,
                vec![
                    rect()
                        .horizontal()
                        .cross_align(Alignment::Center)
                        .spacing(8.)
                        .padding(Gaps::new_all(12.))
                        .child(CircularLoader::new().size(14.))
                        .child(label().font_size(11.).color(MUTED).text("Loading Settings"))
                        .into_element(),
                ],
            );
        }
        Some(Err(error)) => {
            return settings_section_layout(section, vec![explorer_state_message(error.clone())]);
        }
        Some(Ok(_)) => {}
    }
    if section == "Application" {
        return settings_application_content(
            ApplicationSettingsSignals {
                workspace_directory,
                confirm_project_removal,
                confirm_workspace_removal,
                keep_runtime_open,
                empty_host_shutdown,
                detached_session_shutdown,
            },
            bridge,
            diagnostics_content,
        );
    }
    if section == "Mobile Devices" {
        return mobile_content;
    }
    if section == "Agents" {
        return agents_content;
    }
    if section == "Quotas" {
        return quotas_content;
    }
    if section == "Terminal" {
        return terminal_content;
    }
    let rows = match section {
        "Account" => vec![
            settings_value_row(
                "Account Status",
                "Local mode",
                "Sign in to sync identity and push.",
            ),
            settings_value_row(
                "Mobile Push",
                "Not configured",
                "Link the companion app to receive agent notifications.",
            ),
            settings_value_row(
                "Runtime Ownership",
                "This device",
                "Sessions created here remain local to this runtime host.",
            ),
            settings_action_row("Manage Account", "Open account and identity settings."),
        ],
        "AI Text" => vec![
            settings_ai_text_row_persisted(
                "Enable AI Text",
                "Show generation actions in Source Control and pull requests.",
                ai_text_enabled,
                bridge.clone(),
                runtime_settings,
            ),
            settings_text_row_persisted(
                "AI Text Command",
                "The local command used for generated commit messages and PR text.",
                ai_text_command,
                bridge,
                runtime_settings,
            ),
            settings_value_row(
                "Default Agent",
                "Codex",
                "Choose a provider or a custom command per operation.",
            ),
            settings_value_row(
                "Prompt Overrides",
                "Inherited",
                "Commit messages, pull request details and workspace identity can override the default.",
            ),
        ],
        "Editor" => vec![
            settings_text_row(
                "Font Size",
                "Code editor text size in logical pixels.",
                editor_font_size,
            ),
            settings_toggle_row(
                "Minimap",
                "Show a compact overview of the active source file.",
                editor_minimap,
            ),
            settings_value_row(
                "Syntax Theme",
                "Alera Dark",
                "Syntax colors follow the active dark theme.",
            ),
            settings_value_row(
                "Indentation",
                "Detect from file",
                "Use the file's indentation when it is available.",
            ),
        ],
        "Browser" => vec![
            settings_value_row(
                "Engine",
                "System WebView",
                "Use the platform browser engine for preview tabs.",
            ),
            settings_text_row(
                "Active Profile",
                "Browser profile used for new preview tabs.",
                browser_profile,
            ),
            settings_value_row(
                "Trusted Certificates",
                "System Store",
                "Certificates are evaluated by the platform engine.",
            ),
            settings_action_row(
                "Browsing Data",
                "Clear cached browser data and stored previews.",
            ),
        ],
        "Keyboard" => vec![
            settings_toggle_row(
                "Terminal First Shortcuts",
                "Give focused terminals priority over global commands.",
                terminal_first_shortcuts,
            ),
            settings_value_row("Add Project", "⌘⇧O", "Open the project picker."),
            settings_value_row(
                "New Workspace",
                "⌘⇧N",
                "Create a workspace in the selected project.",
            ),
            settings_value_row(
                "Toggle Sidebar",
                "⌘B",
                "Show or hide the workspace sidebar.",
            ),
            settings_value_row(
                "New Terminal Tab",
                "⌘T",
                "Open a terminal in the active workspace.",
            ),
            settings_value_row("Split Right", "⌘D", "Create a right-hand terminal split."),
        ],
        "Projects" => vec![
            settings_path_row(workspace_directory),
            settings_toggle_row(
                "Automatic Workspace Setup",
                "Run the configured setup command when a managed workspace is created.",
                projects_auto_setup,
            ),
            settings_value_row(
                "Copy Rules",
                "Project configuration",
                "Workspace files are copied through the runtime service.",
            ),
        ],
        "Remote Hosts" => vec![
            settings_text_row(
                "SSH Runtime Target",
                "Host alias used when creating a remote runtime session.",
                remote_host_target,
            ),
            settings_value_row(
                "Connection",
                "Not connected",
                "Remote sessions are created only after an explicit connect action.",
            ),
            settings_action_row("Add Remote Host", "Create an SSH runtime target."),
        ],
        "Agent Profiles" => vec![
            settings_text_row(
                "Active Profile",
                "Launch configuration selected by orchestration.",
                agent_profile,
            ),
            settings_value_row(
                "Default local profile",
                "Local runtime",
                "Uses the local runtime host and current workspace.",
            ),
            settings_value_row(
                "Orchestration",
                "Ready",
                "Profiles can be dispatched by the orchestration service.",
            ),
            settings_action_row("Manage Profiles", "Open the profile editor."),
        ],
        _ => vec![
            settings_value_row(
                "Start On Login",
                "Off",
                "Launch Alera when the user signs in.",
            ),
            settings_value_row(
                "Confirm Workspace Removal",
                "On",
                "Ask before removing a linked workspace.",
            ),
            settings_value_row(
                "Open Last Workspace",
                "On",
                "Restore the last selected workspace on launch.",
            ),
            settings_value_row(
                "Default Runtime",
                "Local",
                "Choose where new terminal sessions are hosted.",
            ),
            settings_value_row(
                "Telemetry",
                "Disabled",
                "Alera does not collect usage telemetry.",
            ),
        ],
    };
    settings_section_layout(section, rows)
}

fn settings_section_layout(section: &str, rows: Vec<Element>) -> Element {
    let _ = section;
    rect()
        .width(Size::fill())
        .vertical()
        .spacing(10.)
        .children(rows)
        .into_element()
}

fn settings_value_row(
    title: &'static str,
    value: &'static str,
    description: &'static str,
) -> Element {
    settings_row_shell(title, description)
        .child(label().font_size(11.).color(TEXT).text(value))
        .into_element()
}

fn settings_text_row(
    title: &'static str,
    description: &'static str,
    value: State<String>,
) -> Element {
    settings_row_shell(title, description)
        .child(
            Input::new(value)
                .width(Size::px(220.))
                .compact()
                .filled()
                .theme_colors(
                    InputColorsThemePartial::new()
                        .background(SURFACE)
                        .focus_background(SURFACE)
                        .border_fill(BORDER)
                        .focus_border_fill(ACCENT)
                        .color(TEXT)
                        .placeholder_color(MUTED),
                ),
        )
        .into_element()
}

#[derive(Clone, Copy)]
struct ApplicationSettingsSignals {
    workspace_directory: State<String>,
    confirm_project_removal: State<bool>,
    confirm_workspace_removal: State<bool>,
    keep_runtime_open: State<bool>,
    empty_host_shutdown: State<String>,
    detached_session_shutdown: State<String>,
}

fn settings_application_content(
    signals: ApplicationSettingsSignals,
    bridge: RuntimeBridge,
    diagnostics_content: Element,
) -> Element {
    rect()
        .width(Size::fill())
        .vertical()
        .spacing(12.)
        .child(settings_path_row_persisted(
            signals.workspace_directory,
            bridge.clone(),
        ))
        .child(settings_group_described(
            "Safety",
            "Confirmation prompts for destructive workspace actions.",
            vec![
                settings_toggle_row_persisted(
                    "Confirm Project Removal",
                    "Ask before unregistering a project and deleting its workspace metadata.",
                    signals.confirm_project_removal,
                    bridge.clone(),
                    "confirmProjectRemoval",
                ),
                settings_toggle_row_persisted(
                    "Confirm Workspace Removal",
                    "Ask before removing a linked workspace and deleting its branch.",
                    signals.confirm_workspace_removal,
                    bridge.clone(),
                    "confirmWorkspaceRemoval",
                ),
            ],
        ))
        .child(settings_group_described(
            "Runtime",
            "Lifecycle of the local runtime host that owns terminal sessions.",
            vec![
                settings_toggle_row(
                    "Keep Runtime Open When App Quits",
                    "Leave the app-launched sidecar running after a clean quit. Persistent CLI runtimes are never stopped by quitting, and unexpected exits always leave the host up.",
                    signals.keep_runtime_open,
                ),
                settings_number_row(
                    "Empty Host Shutdown",
                    "Seconds to keep the host alive after the app closes with no running sessions.",
                    signals.empty_host_shutdown,
                ),
                settings_number_row(
                    "Detached Session Shutdown",
                    "Seconds to keep detached running sessions alive after the app closes.",
                    signals.detached_session_shutdown,
                ),
            ],
        ))
        .child(rect().height(Size::px(16.)).child(""))
        .child(diagnostics_content)
        .into_element()
}

fn settings_group_described(
    title: &'static str,
    description: &'static str,
    rows: Vec<Element>,
) -> Element {
    settings_group_body(title, Some(description), rows)
}

fn settings_group_body(
    title: &'static str,
    description: Option<&'static str>,
    rows: Vec<Element>,
) -> Element {
    rect()
        .width(Size::fill())
        .vertical()
        .spacing(8.)
        .child(
            rect()
                .vertical()
                .spacing(4.)
                .padding(Gaps::new(0., 0., 0., 4.))
                .child(label().font_size(16.).color(TEXT).text(title))
                .maybe_child(
                    description.map(|value| label().font_size(12.).color(MUTED).text(value)),
                ),
        )
        .child(
            rect()
                .width(Size::fill())
                .vertical()
                .spacing(1.)
                .background(SURFACE_RAISED)
                .border(Border::new().width(1.).fill(BORDER))
                .corner_radius(7.)
                .children(rows),
        )
        .into_element()
}

fn settings_row_shell(title: &'static str, description: &'static str) -> Rect {
    rect()
        .width(Size::fill())
        .min_height(Size::px(76.))
        .horizontal()
        .content(Content::Flex)
        .cross_align(Alignment::Center)
        .padding(Gaps::new_all(17.))
        .child(
            rect()
                .vertical()
                .spacing(3.)
                .child(label().font_size(14.).color(TEXT).text(title))
                .child(label().font_size(12.).color(MUTED).text(description)),
        )
        .child(rect().width(Size::flex(1.)).child(""))
}

fn settings_path_row(path: State<String>) -> Element {
    settings_row_shell(
        "Workspace Directory",
        "Where new linked workspaces are created on disk. Existing workspaces are not moved.",
    )
    .child(
        Input::new(path)
            .width(Size::px(270.))
            .compact()
            .filled()
            .theme_colors(
                InputColorsThemePartial::new()
                    .background(SURFACE)
                    .focus_background(SURFACE)
                    .border_fill(BORDER)
                    .focus_border_fill(BORDER)
                    .color(TEXT)
                    .placeholder_color(MUTED),
            ),
    )
    .into_element()
}

fn settings_path_row_persisted(path: State<String>, bridge: RuntimeBridge) -> Element {
    let submit_bridge = bridge.clone();
    let browse_bridge = bridge;
    let browse_path = path;
    rect()
        .width(Size::fill())
        .vertical()
        .spacing(12.)
        .background(SURFACE_RAISED)
        .border(Border::new().width(1.).fill(BORDER))
        .corner_radius(7.)
        .padding(Gaps::new_all(21.))
        .child(
            rect()
                .vertical()
                .spacing(4.)
                .child(label().font_size(14.).color(TEXT).text("Workspace Directory"))
                .child(label().font_size(12.).color(MUTED).text(
                    "Where new linked workspaces are created on disk. Existing workspaces are not moved. Leave empty to use the default (~/.alera/workspaces).",
                )),
        )
        .child(
            rect()
                .width(Size::fill())
                .height(Size::px(40.))
                .horizontal()
                .content(Content::Flex)
                .cross_align(Alignment::Center)
                .spacing(8.)
                .child(
                    Input::new(path)
                        .width(Size::flex(1.))
                        .expanded()
                        .filled()
                        .theme_layout(
                            InputLayoutThemePartial::new()
                                .corner_radius(CornerRadius::new_all(6.))
                                .inner_margin(Gaps::new(10., 12., 10., 12.)),
                        )
                        .on_submit(move |value: String| {
                            let workspace_directory =
                                (!value.trim().is_empty()).then_some(value);
                            let _ = submit_bridge.send_ordered(
                                "runtimeSettings.update",
                                json!({"workspaceDirectory": workspace_directory}),
                            );
                        })
                        .theme_colors(
                            InputColorsThemePartial::new()
                                .background(SURFACE)
                                .focus_background(SURFACE)
                                .border_fill(BORDER)
                                .focus_border_fill(ACCENT)
                                .color(TEXT)
                                .placeholder_color(MUTED),
                        ),
                )
                .child(
                    rect()
                        .width(Size::px(112.))
                        .height(Size::px(40.))
                        .child(
                            Button::new()
                                .width(Size::fill())
                                .height(Size::fill())
                                .outline()
                                .on_press(move |_| {
                                    let bridge = browse_bridge.clone();
                                    let mut selected_path = browse_path;
                                    spawn(async move {
                                        let selected = blocking::unblock(|| {
                                            rfd::FileDialog::new().pick_folder()
                                        })
                                        .await;
                                        let Some(selected) = selected else {
                                            return;
                                        };
                                        let selected = selected.to_string_lossy().to_string();
                                        selected_path.set(selected.clone());
                                        let _ = bridge.send_ordered(
                                            "runtimeSettings.update",
                                            json!({"workspaceDirectory": selected}),
                                        );
                                    });
                                })
                                .child(
                                    rect()
                                        .horizontal()
                                        .spacing(6.)
                                        .child(
                                            SvgViewer::new(icons::lucide::folder_open())
                                                .width(Size::px(16.))
                                                .height(Size::px(16.))
                                                .color(TEXT),
                                        )
                                        .child("Browse"),
                                ),
                        ),
                ),
        )
        .into_element()
}

fn settings_toggle_row(
    title: &'static str,
    description: &'static str,
    value: State<bool>,
) -> Element {
    let mut value_for_click = value;
    settings_row_shell(title, description)
        .child(settings_switch::control(value(), true, move |event| {
            event.stop_propagation();
            value_for_click.toggle();
        }))
        .into_element()
}

fn settings_toggle_row_persisted(
    title: &'static str,
    description: &'static str,
    value: State<bool>,
    bridge: RuntimeBridge,
    key: &'static str,
) -> Element {
    let mut value_for_click = value;
    settings_row_shell(title, description)
        .child(settings_switch::control(value(), true, move |event| {
            event.stop_propagation();
            value_for_click.toggle();
            let _ = bridge.send_ordered("runtimeSettings.update", json!({key: value_for_click()}));
        }))
        .into_element()
}

fn settings_ai_text_row_persisted(
    title: &'static str,
    description: &'static str,
    value: State<bool>,
    bridge: RuntimeBridge,
    runtime_settings: State<Option<Result<Value, String>>>,
) -> Element {
    let mut value_for_click = value;
    settings_row_shell(title, description)
        .child(settings_switch::control(value(), true, move |event| {
            event.stop_propagation();
            value_for_click.toggle();
            let ai_text = update_runtime_ai_text_setting(
                runtime_settings,
                "enabled",
                Value::Bool(value_for_click()),
            );
            let _ = bridge.send_ordered(
                "runtimeSettings.update",
                json!({"aiTextGeneration": ai_text}),
            );
        }))
        .into_element()
}

fn settings_text_row_persisted(
    title: &'static str,
    description: &'static str,
    value: State<String>,
    bridge: RuntimeBridge,
    runtime_settings: State<Option<Result<Value, String>>>,
) -> Element {
    settings_row_shell(title, description)
        .child(
            Input::new(value)
                .width(Size::px(220.))
                .compact()
                .filled()
                .on_submit(move |text: String| {
                    let ai_text = update_runtime_ai_text_setting(
                        runtime_settings,
                        "customCommand",
                        Value::String(text),
                    );
                    let _ = bridge.send_ordered(
                        "runtimeSettings.update",
                        json!({"aiTextGeneration": ai_text}),
                    );
                })
                .theme_colors(
                    InputColorsThemePartial::new()
                        .background(SURFACE)
                        .focus_background(SURFACE)
                        .border_fill(BORDER)
                        .focus_border_fill(ACCENT)
                        .color(TEXT)
                        .placeholder_color(MUTED),
                ),
        )
        .into_element()
}

fn update_runtime_ai_text_setting(
    mut runtime_settings: State<Option<Result<Value, String>>>,
    key: &str,
    value: Value,
) -> Value {
    let current_settings = runtime_settings
        .read()
        .as_ref()
        .and_then(|record| record.as_ref().ok())
        .cloned()
        .unwrap_or_else(|| json!({}));
    let ai_value = merged_runtime_ai_text_setting(&current_settings, key, value);
    if let Some(Ok(settings)) = runtime_settings.write().as_mut()
        && let Some(settings) = settings.as_object_mut()
    {
        settings.insert("aiTextGeneration".to_string(), ai_value.clone());
    }
    ai_value
}

fn merged_runtime_ai_text_setting(settings: &Value, key: &str, value: Value) -> Value {
    let mut ai_text = settings
        .get("aiTextGeneration")
        .and_then(Value::as_object)
        .cloned()
        .unwrap_or_default();
    ai_text.insert(key.to_string(), value);
    Value::Object(ai_text)
}

fn settings_number_row(
    title: &'static str,
    description: &'static str,
    value: State<String>,
) -> Element {
    settings_row_shell(title, description)
        .child(
            rect()
                .width(Size::px(142.))
                .height(Size::px(32.))
                .horizontal()
                .content(Content::Flex)
                .cross_align(Alignment::Center)
                .background(SURFACE)
                .border(Border::new().width(1.).fill(BORDER))
                .corner_radius(5.)
                .child(Input::new(value).width(Size::flex(1.)).compact().flat())
                .child(label().font_size(11.).color(MUTED).text("s")),
        )
        .into_element()
}

fn settings_action_row(title: &'static str, description: &'static str) -> Element {
    settings_row_shell(title, description)
        .child(Button::new().compact().outline().child("Open"))
        .into_element()
}

fn welcome_action(
    icon: Bytes,
    title: &'static str,
    description: &'static str,
    settings_open: State<bool>,
    action_dialog: State<Option<ActionDialog>>,
    action_dialog_error: State<Option<String>>,
    mut workspace_target_project_id: State<Option<String>>,
) -> Element {
    let mut settings_open_for_action = settings_open;
    let mut action_dialog_for_action = action_dialog;
    let mut action_dialog_error_for_action = action_dialog_error;
    rect()
        .key(title)
        .width(Size::fill())
        .height(Size::px(70.))
        .background(SURFACE)
        .a11y_role(AccessibilityRole::Button)
        .a11y_alt(title)
        .on_pointer_down(move |event: Event<PointerEventData>| {
            event.stop_propagation();
            match title {
                "Open Settings" => settings_open_for_action.set(true),
                "Add Project" => {
                    action_dialog_for_action.set(Some(ActionDialog::AddProject));
                    action_dialog_error_for_action.set(None);
                }
                "New Workspace" => {
                    workspace_target_project_id.set(None);
                    action_dialog_for_action.set(Some(ActionDialog::NewWorkspace));
                    action_dialog_error_for_action.set(None);
                }
                _ => {}
            }
        })
        .on_pointer_enter(|_| Cursor::set(CursorIcon::Pointer))
        .on_pointer_leave(|_| Cursor::set(CursorIcon::default()))
        .child(
            rect()
                .width(Size::fill())
                .height(Size::fill())
                .padding(Gaps::new_all(16.))
                .horizontal()
                .content(Content::Flex)
                .cross_align(Alignment::Center)
                .spacing(14.)
                .child(
                    SvgViewer::new(icon)
                        .width(Size::px(22.))
                        .height(Size::px(22.))
                        .color(TEXT),
                )
                .child(
                    rect()
                        .vertical()
                        .spacing(3.)
                        .child(label().font_size(14.).color(TEXT).text(title))
                        .child(label().font_size(12.).color(MUTED).text(description)),
                )
                .child(rect().width(Size::flex(1.)).child(""))
                .child(
                    SvgViewer::new(icons::lucide::chevron_right())
                        .width(Size::px(16.))
                        .height(Size::px(16.))
                        .color(MUTED),
                ),
        )
        .into_element()
}

fn welcome_shortcut(name: &'static str, shortcut: &'static str) -> Element {
    rect()
        .width(Size::fill())
        .height(Size::px(28.))
        .horizontal()
        .content(Content::Flex)
        .cross_align(Alignment::Center)
        .child(label().font_size(12.).color(MUTED).text(name))
        .child(rect().width(Size::flex(1.)).child(""))
        .child(
            rect()
                .background(SURFACE_RAISED)
                .padding(Gaps::new(6., 4., 6., 4.))
                .corner_radius(4.)
                .child(label().font_size(11.).color(TEXT).text(shortcut)),
        )
        .into_element()
}

fn welcome_divider() -> Element {
    rect()
        .width(Size::fill())
        .height(Size::px(1.))
        .background((39, 39, 39))
        .into_element()
}

fn dialog_input(value: State<String>, placeholder: &'static str) -> Input {
    Input::new(value)
        .width(Size::fill())
        .placeholder(placeholder)
        .filled()
        .theme_colors(
            InputColorsThemePartial::new()
                .background(SURFACE)
                .focus_background(SURFACE)
                .border_fill(BORDER)
                .focus_border_fill(BORDER)
                .color(TEXT)
                .placeholder_color(MUTED),
        )
}

fn dialog_select<I, S>(
    key: &'static str,
    value: State<String>,
    mut open_menu: State<Option<String>>,
    mut just_opened: State<bool>,
    options: I,
) -> Element
where
    I: IntoIterator<Item = S>,
    S: AsRef<str>,
{
    let selected = value.read().clone();
    let selected_label = selected
        .split_once("::")
        .map_or_else(|| selected.clone(), |(label, _)| label.to_string());
    let is_open = open_menu.read().as_deref() == Some(key);
    let mut open_for_button = open_menu;
    let key_for_button = key.to_string();
    let button = rect()
        .width(Size::fill())
        .height(Size::px(32.))
        .background(SURFACE)
        .border(Border::new().width(1.).fill(BORDER))
        .corner_radius(5.)
        .padding(Gaps::new_all(6.))
        .a11y_role(AccessibilityRole::Button)
        .a11y_alt(format!("Select {key}"))
        .on_pointer_down(move |event: Event<PointerEventData>| {
            event.stop_propagation();
            if open_for_button.read().as_deref() == Some(key_for_button.as_str()) {
                open_for_button.set(None);
                just_opened.set(false);
            } else {
                open_for_button.set(Some(key_for_button.clone()));
                just_opened.set(true);
            }
        })
        .child(
            rect()
                .interactive(false)
                .width(Size::fill())
                .horizontal()
                .content(Content::Flex)
                .cross_align(Alignment::Center)
                .child(label().font_size(11.).color(TEXT).text(selected_label))
                .child(rect().width(Size::flex(1.)).child(""))
                .child(
                    SvgViewer::new(if is_open {
                        icons::lucide::chevron_up()
                    } else {
                        icons::lucide::chevron_down()
                    })
                    .width(Size::px(14.))
                    .height(Size::px(14.))
                    .color(MUTED),
                ),
        );

    let mut menu = rect()
        .width(Size::fill())
        .background((30, 30, 30))
        .border(Border::new().width(1.).fill(BORDER))
        .corner_radius(5.)
        .padding(Gaps::new_all(4.))
        .spacing(2.)
        .vertical()
        .on_press(|event: Event<PressEventData>| event.stop_propagation())
        .on_global_pointer_press(move |_| {
            if just_opened() {
                just_opened.set(false);
            } else {
                open_menu.set(None);
            }
        });
    for option in options
        .into_iter()
        .map(|option| option.as_ref().to_string())
    {
        let mut value = value;
        let mut open_menu = open_menu;
        let mut just_opened = just_opened;
        let option_value = option.clone();
        let option_label = option
            .split_once("::")
            .map_or_else(|| option.clone(), |(label, _)| label.to_string());
        menu = menu.child(
            rect()
                .width(Size::fill())
                .height(Size::px(28.))
                .corner_radius(4.)
                .padding(Gaps::new_all(6.))
                .a11y_role(AccessibilityRole::Button)
                .a11y_alt(option_label.clone())
                .on_pointer_down(move |event: Event<PointerEventData>| {
                    event.stop_propagation();
                    value.set(option_value.clone());
                    open_menu.set(None);
                    just_opened.set(false);
                })
                .child(
                    rect()
                        .interactive(false)
                        .child(label().font_size(11.).color(TEXT).text(option_label)),
                ),
        );
    }

    rect()
        .width(Size::fill())
        .vertical()
        .spacing(2.)
        .child(button)
        .maybe_child(is_open.then_some(menu))
        .into_element()
}

fn option_id(value: &str) -> Option<&str> {
    value
        .split_once("::")
        .map(|(_, id)| id.trim())
        .filter(|id| !id.is_empty())
}

fn option_for_id(options: &[String], id: &str) -> Option<String> {
    options
        .iter()
        .find(|option| option_id(option) == Some(id))
        .cloned()
}

fn option_has_id(options: &[String], id: &str) -> bool {
    option_for_id(options, id).is_some()
}

fn first_option_id(options: &[String]) -> Option<String> {
    options
        .iter()
        .find_map(|option| option_id(option).map(str::to_string))
}

fn workspace_project_options(snapshot: &WorkbenchSnapshot) -> Vec<String> {
    let mut projects = snapshot
        .projects
        .iter()
        .filter(|project| project.kind == "gitRepository")
        .map(|project| (project.name.clone(), project.id.clone()))
        .collect::<Vec<_>>();
    projects.sort_by(|(left_name, left_id), (right_name, right_id)| {
        left_name
            .to_lowercase()
            .cmp(&right_name.to_lowercase())
            .then_with(|| left_name.cmp(right_name))
            .then_with(|| left_id.cmp(right_id))
    });
    projects
        .into_iter()
        .map(|(name, id)| format!("{name}::{id}"))
        .collect()
}

fn workspace_parent_options(
    snapshot: &WorkbenchSnapshot,
    preferred_project_id: Option<&str>,
) -> Vec<String> {
    let mut workspaces = snapshot
        .projects
        .iter()
        .flat_map(|project| {
            project
                .workspaces
                .iter()
                .filter(|workspace| workspace.status == "active")
                .map(move |workspace| (project, workspace))
        })
        .collect::<Vec<_>>();
    workspaces.sort_by(|(left_project, left), (right_project, right)| {
        let left_preferred = Some(left_project.id.as_str()) == preferred_project_id;
        let right_preferred = Some(right_project.id.as_str()) == preferred_project_id;
        right_preferred
            .cmp(&left_preferred)
            .then_with(|| {
                left_project
                    .name
                    .to_lowercase()
                    .cmp(&right_project.name.to_lowercase())
            })
            .then_with(|| left_project.name.cmp(&right_project.name))
            .then_with(|| left_project.id.cmp(&right_project.id))
            .then_with(|| (right.kind == "main").cmp(&(left.kind == "main")))
            .then_with(|| left.name.to_lowercase().cmp(&right.name.to_lowercase()))
            .then_with(|| left.name.cmp(&right.name))
            .then_with(|| left.id.cmp(&right.id))
    });
    std::iter::once("No Parent".to_string())
        .chain(workspaces.into_iter().map(|(project, workspace)| {
            let branch = workspace
                .branch
                .as_deref()
                .filter(|branch| !branch.is_empty())
                .map(|branch| format!(" - {branch}"))
                .unwrap_or_default();
            format!(
                "{} / {}{}::{}",
                project.name, workspace.name, branch, workspace.id
            )
        }))
        .collect()
}

fn workspace_branch_names(
    snapshot: &WorkbenchSnapshot,
    project_id: Option<&str>,
) -> BTreeSet<String> {
    snapshot
        .projects
        .iter()
        .filter(|project| Some(project.id.as_str()) == project_id)
        .flat_map(|project| &project.workspaces)
        .filter_map(|workspace| workspace.branch.as_deref())
        .filter(|branch| !branch.is_empty() && *branch != "HEAD")
        .map(str::to_string)
        .collect()
}

fn string_options(value: &Value, key: &str) -> Vec<String> {
    let mut options = value
        .get(key)
        .and_then(Value::as_array)
        .into_iter()
        .flatten()
        .filter_map(Value::as_str)
        .map(str::to_string)
        .collect::<Vec<_>>();
    options.sort_by_key(|option| option.to_lowercase());
    options.dedup();
    options
}

fn preferred_workspace_branch(branches: &[String]) -> Option<String> {
    ["main", "origin/main", "master", "origin/master"]
        .into_iter()
        .find(|preferred| branches.iter().any(|branch| branch == preferred))
        .map(str::to_string)
        .or_else(|| branches.first().cloned())
}

fn parse_agent_profile_options(value: &Value) -> Result<Vec<String>, String> {
    value
        .get("items")
        .and_then(Value::as_array)
        .ok_or_else(|| "Agent Profile List Omitted Items".to_string())?
        .iter()
        .map(|profile| {
            let id = profile
                .get("id")
                .and_then(Value::as_str)
                .filter(|id| !id.trim().is_empty())
                .ok_or_else(|| "Agent Profile Omitted Id".to_string())?;
            let name = profile
                .get("name")
                .and_then(Value::as_str)
                .filter(|name| !name.trim().is_empty())
                .ok_or_else(|| "Agent Profile Omitted Name".to_string())?;
            Ok(format!("{name}::{id}"))
        })
        .collect()
}

fn manual_workspace_request(
    project_id: &str,
    source_branch: &str,
    target_branch: &str,
    name: &str,
    parent_option: &str,
    reuse_existing_branch: bool,
) -> Result<Value, String> {
    let project_id = project_id.trim();
    if project_id.is_empty() {
        return Err("Select A Project".to_string());
    }
    let target_branch = target_branch.trim();
    if target_branch.is_empty() {
        return Err(if reuse_existing_branch {
            "Existing Branch Is Required".to_string()
        } else {
            "New Branch Name Is Required".to_string()
        });
    }
    let source_branch = source_branch.trim();
    if !reuse_existing_branch && source_branch.is_empty() {
        return Err("Source Branch Is Required".to_string());
    }
    let mut payload = json!({
        "projectId": project_id,
        "branch": target_branch,
        "reuseExistingBranch": reuse_existing_branch,
        "deferSetup": true,
    });
    if !reuse_existing_branch {
        payload["sourceBranch"] = Value::String(source_branch.to_string());
    }
    let name = name.trim();
    if !name.is_empty() {
        payload["name"] = Value::String(name.to_string());
    }
    if let Some(parent_id) = option_id(parent_option) {
        payload["parentWorkspaceId"] = Value::String(parent_id.to_string());
    }
    Ok(payload)
}

fn workspace_id_from_payload(payload: &Value) -> Result<String, String> {
    payload
        .pointer("/workspace/id")
        .and_then(Value::as_str)
        .filter(|id| !id.trim().is_empty())
        .map(str::to_string)
        .ok_or_else(|| "Workspace Creation Omitted Workspace Id".to_string())
}

fn workspace_identity_from_payload(payload: &Value) -> Result<(String, String), String> {
    let name = payload
        .get("workspaceName")
        .and_then(Value::as_str)
        .filter(|name| !name.trim().is_empty())
        .ok_or_else(|| "Generated Identity Omitted Workspace Name".to_string())?;
    let branch = payload
        .get("branchName")
        .and_then(Value::as_str)
        .filter(|branch| !branch.trim().is_empty())
        .ok_or_else(|| "Generated Identity Omitted Branch Name".to_string())?;
    Ok((name.to_string(), branch.to_string()))
}

fn looks_like_workspace_collision(error: &str) -> bool {
    let error = error.to_lowercase();
    error.contains("already exists") || error.contains("workspace for branch")
}

#[allow(clippy::too_many_arguments)]
async fn create_prompt_workspace_from_identity(
    bridge: &RuntimeBridge,
    project_id: &str,
    source_branch: &str,
    prompt: &str,
    parent_option: &str,
    existing_workspace_branches: &BTreeSet<String>,
    mut phase: State<Option<String>>,
) -> Result<String, String> {
    let mut collision_error = None;
    for attempt in 0..2 {
        phase.set(Some("Generating Workspace Identity".to_string()));
        let identity_prompt = if attempt == 0 {
            prompt.to_string()
        } else {
            format!(
                "{prompt}\n\nThe previous generated workspace identity was unavailable. Generate a different workspace name and branch."
            )
        };
        let identity = bridge
            .request_with_timeout(
                "aiText.workspaceIdentity.generate",
                json!({
                    "operationId": format!(
                        "freya-workspace-{}-{}-{attempt}",
                        std::process::id(),
                        Uuid::new_v4()
                    ),
                    "projectId": project_id,
                    "prompt": identity_prompt,
                }),
                Duration::from_secs(11 * 60),
            )
            .await?;
        let (workspace_name, branch) = workspace_identity_from_payload(&identity)?;

        phase.set(Some("Checking Generated Branch".to_string()));
        let branch_state = bridge
            .request_with_timeout(
                "project.branches.list",
                json!({"projectId": project_id}),
                Duration::from_secs(30),
            )
            .await?;
        let branch_exists = existing_workspace_branches.contains(&branch)
            || string_options(&branch_state, "branches").contains(&branch)
            || string_options(&branch_state, "localBranches").contains(&branch);
        if branch_exists {
            collision_error = Some(format!("The Generated Branch \"{branch}\" Already Exists."));
            continue;
        }

        phase.set(Some("Creating Workspace".to_string()));
        let request = manual_workspace_request(
            project_id,
            source_branch,
            &branch,
            &workspace_name,
            parent_option,
            false,
        )?;
        match bridge
            .request_with_timeout(
                "workspace.createManaged",
                request,
                Duration::from_secs(30 * 60),
            )
            .await
        {
            Ok(payload) => return workspace_id_from_payload(&payload),
            Err(error) if attempt == 0 && looks_like_workspace_collision(&error) => {
                collision_error = Some(error);
            }
            Err(error) => return Err(error),
        }
    }
    Err(collision_error.unwrap_or_else(|| {
        "AI Text Could Not Generate An Available Workspace Identity.".to_string()
    }))
}

#[allow(clippy::too_many_arguments)]
fn action_dialog_overlay(
    kind: ActionDialog,
    mut action_dialog: State<Option<ActionDialog>>,
    mut action_dialog_error: State<Option<String>>,
    add_project_path: State<String>,
    add_project_name: State<String>,
    add_project_clone_mode: State<bool>,
    add_project_clone_url: State<String>,
    add_project_clone_parent: State<String>,
    add_project_clone_directory: State<String>,
    workspace_name: State<String>,
    workspace_branch: State<String>,
    workspace_prompt_mode: State<bool>,
    workspace_prompt: State<String>,
    mut workspace_create_another: State<bool>,
    workspace_project: State<String>,
    workspace_source_branch: State<String>,
    workspace_parent: State<String>,
    workspace_parent_options: Vec<String>,
    workspace_agent_profile: State<String>,
    workspace_project_options: Vec<String>,
    workspace_existing_branches: BTreeSet<String>,
    workspace_branch_options: State<Vec<String>>,
    workspace_local_branch_options: State<Vec<String>>,
    workspace_agent_profile_options: State<Vec<String>>,
    workspace_reuse_existing_branch: State<bool>,
    workspace_creation_busy: State<bool>,
    workspace_creation_phase: State<Option<String>>,
    workspace_prompt_created_id: State<Option<String>>,
    workspace_open_dropdown: State<Option<String>>,
    workspace_dropdown_just_opened: State<bool>,
    bridge: RuntimeBridge,
    selected_workspace: State<String>,
    selected_tab_request: State<Option<String>>,
    snapshot_revision: State<u64>,
) -> Element {
    let is_project = kind == ActionDialog::AddProject;
    let title = if is_project {
        "Add Project"
    } else {
        "New Workspace"
    };
    let description = if is_project {
        "Register an existing local Git folder with Alera."
    } else {
        "Create a linked workspace for the active Git project."
    };
    let mut close = action_dialog;
    let mut error = action_dialog_error;
    let mut submit_dialog = action_dialog;
    let mut submit_error = action_dialog_error;
    let submit_bridge = bridge;
    let submit_project_path = add_project_path;
    let submit_project_name = add_project_name;
    let submit_clone_mode = add_project_clone_mode;
    let submit_clone_url = add_project_clone_url;
    let submit_clone_parent = add_project_clone_parent;
    let submit_clone_directory = add_project_clone_directory;
    let mut submit_workspace_name = workspace_name;
    let mut submit_workspace_branch = workspace_branch;
    let submit_workspace_project = workspace_project;
    let submit_workspace_source_branch = workspace_source_branch;
    let mut submit_workspace_parent = workspace_parent;
    let submit_workspace_profile = workspace_agent_profile;
    let mut submit_workspace_reuse = workspace_reuse_existing_branch;
    let submit_prompt_mode = workspace_prompt_mode;
    let mut submit_prompt = workspace_prompt;
    let submit_create_another = workspace_create_another;
    let mut submit_busy = workspace_creation_busy;
    let mut submit_phase = workspace_creation_phase;
    let mut submit_created_id = workspace_prompt_created_id;
    let mut submit_selected_workspace = selected_workspace;
    let mut submit_selected_tab = selected_tab_request;
    let mut submit_revision = snapshot_revision;
    let prompt_created = workspace_prompt_created_id.read().is_some();
    let workspace_project_id = option_id(workspace_project.read().as_str()).map(str::to_string);
    let submit_enabled = if is_project {
        if add_project_clone_mode() {
            !add_project_clone_url.read().trim().is_empty()
                && !add_project_clone_parent.read().trim().is_empty()
                && !add_project_clone_directory.read().trim().is_empty()
        } else {
            !add_project_path.read().trim().is_empty()
        }
    } else if *workspace_creation_busy.read() {
        false
    } else if workspace_prompt_mode() {
        workspace_project_id.is_some()
            && !workspace_prompt.read().trim().is_empty()
            && !workspace_source_branch.read().trim().is_empty()
            && option_id(workspace_agent_profile.read().as_str()).is_some()
    } else {
        workspace_project_id.is_some()
            && !workspace_branch.read().trim().is_empty()
            && (workspace_reuse_existing_branch()
                || !workspace_source_branch.read().trim().is_empty())
    };
    let submit = move |_| {
        if is_project {
            let name = submit_project_name.read().trim().to_string();
            let result = if submit_clone_mode() {
                let url = submit_clone_url.read().trim().to_string();
                let parent_path = submit_clone_parent.read().trim().to_string();
                let directory_name = submit_clone_directory.read().trim().to_string();
                if url.is_empty() || parent_path.is_empty() || directory_name.is_empty() {
                    submit_error.set(Some(
                        "Clone URL, parent folder and directory name are required.".to_string(),
                    ));
                    return;
                }
                let mut payload = json!({
                    "url": url,
                    "parentPath": parent_path,
                    "directoryName": directory_name,
                });
                if !name.is_empty() {
                    payload["name"] = Value::String(name);
                }
                submit_bridge.send_ordered("project.clone.start", payload)
            } else {
                let path = submit_project_path.read().trim().to_string();
                if path.is_empty() {
                    submit_error.set(Some("A local folder path is required.".to_string()));
                    return;
                }
                let mut payload = json!({"path": path});
                if !name.is_empty() {
                    payload["name"] = Value::String(name);
                }
                submit_bridge.send_ordered("project.register", payload)
            };
            if let Err(error) = result {
                submit_error.set(Some(error));
                return;
            }
            submit_selected_workspace.set(String::new());
            let next_revision = submit_revision.read().saturating_add(1);
            submit_revision.set(next_revision);
            submit_error.set(None);
            submit_dialog.set(None);
            return;
        }

        if *submit_busy.peek() {
            return;
        }
        let Some(project_id) =
            option_id(submit_workspace_project.read().as_str()).map(str::to_string)
        else {
            submit_error.set(Some("Select A Project".to_string()));
            return;
        };
        let source_branch = submit_workspace_source_branch.read().trim().to_string();
        let parent_option = submit_workspace_parent.read().clone();
        let create_another = submit_create_another();
        let prompt_mode = submit_prompt_mode();
        let prompt = submit_prompt.read().trim().to_string();
        let profile_id = option_id(submit_workspace_profile.read().as_str()).map(str::to_string);
        let existing_workspace_branches = workspace_existing_branches.clone();
        let bridge = submit_bridge.clone();
        if prompt_mode {
            if prompt.is_empty() {
                submit_error.set(Some("Initial Prompt Is Required".to_string()));
                return;
            }
            let Some(profile_id) = profile_id else {
                submit_error.set(Some("Select An Agent Profile".to_string()));
                return;
            };
            if source_branch.is_empty() {
                submit_error.set(Some("Source Branch Is Required".to_string()));
                return;
            }
            let retry_workspace_id = submit_created_id.read().clone();
            submit_busy.set(true);
            submit_error.set(None);
            let mut phase = submit_phase;
            spawn(async move {
                let workspace_id = match retry_workspace_id {
                    Some(workspace_id) => workspace_id,
                    None => match create_prompt_workspace_from_identity(
                        &bridge,
                        &project_id,
                        &source_branch,
                        &prompt,
                        &parent_option,
                        &existing_workspace_branches,
                        phase,
                    )
                    .await
                    {
                        Ok(workspace_id) => {
                            submit_created_id.set(Some(workspace_id.clone()));
                            workspace_id
                        }
                        Err(error) => {
                            submit_busy.set(false);
                            phase.set(None);
                            submit_error.set(Some(error));
                            return;
                        }
                    },
                };
                phase.set(Some("Starting Agent".to_string()));
                match bridge
                    .request_with_timeout(
                        "agentProfile.launch",
                        json!({
                            "workspaceId": workspace_id,
                            "profileId": profile_id,
                            "prompt": prompt,
                        }),
                        Duration::from_secs(2 * 60),
                    )
                    .await
                {
                    Ok(launch) => {
                        submit_busy.set(false);
                        phase.set(None);
                        submit_created_id.set(None);
                        submit_selected_workspace.set(workspace_id);
                        submit_selected_tab.set(
                            launch
                                .pointer("/tab/id")
                                .and_then(Value::as_str)
                                .map(str::to_string),
                        );
                        submit_revision.set(submit_revision.peek().saturating_add(1));
                        submit_error.set(None);
                        if create_another {
                            submit_prompt.set(String::new());
                            submit_workspace_parent.set("No Parent".to_string());
                            submit_dialog.set(Some(ActionDialog::NewWorkspace));
                        } else {
                            submit_dialog.set(None);
                        }
                    }
                    Err(error) => {
                        submit_busy.set(false);
                        phase.set(None);
                        submit_error.set(Some(error));
                    }
                }
            });
        } else {
            let request = match manual_workspace_request(
                &project_id,
                &source_branch,
                submit_workspace_branch.read().as_str(),
                submit_workspace_name.read().as_str(),
                &parent_option,
                submit_workspace_reuse(),
            ) {
                Ok(request) => request,
                Err(error) => {
                    submit_error.set(Some(error));
                    return;
                }
            };
            submit_busy.set(true);
            submit_phase.set(Some("Creating Workspace".to_string()));
            submit_error.set(None);
            spawn(async move {
                match bridge
                    .request_with_timeout(
                        "workspace.createManaged",
                        request,
                        Duration::from_secs(30 * 60),
                    )
                    .await
                    .and_then(|payload| workspace_id_from_payload(&payload))
                {
                    Ok(workspace_id) => {
                        submit_busy.set(false);
                        submit_phase.set(None);
                        submit_selected_workspace.set(workspace_id);
                        submit_selected_tab.set(None);
                        submit_revision.set(submit_revision.peek().saturating_add(1));
                        submit_error.set(None);
                        if create_another {
                            submit_workspace_name.set(String::new());
                            submit_workspace_branch.set(String::new());
                            submit_workspace_parent.set("No Parent".to_string());
                            submit_workspace_reuse.set(false);
                            submit_dialog.set(Some(ActionDialog::NewWorkspace));
                        } else {
                            submit_dialog.set(None);
                        }
                    }
                    Err(error) => {
                        submit_busy.set(false);
                        submit_phase.set(None);
                        submit_error.set(Some(error));
                    }
                }
            });
        }
    };
    let cancel = move |_| {
        if *workspace_creation_busy.peek() {
            return;
        }
        error.set(None);
        close.set(None);
    };
    let body = if is_project {
        let mut local_mode = add_project_clone_mode;
        let mut clone_mode = add_project_clone_mode;
        let local_selected = !add_project_clone_mode();
        let clone_selected = add_project_clone_mode();
        let fields = if local_selected {
            rect()
                .width(Size::fill())
                .vertical()
                .spacing(8.)
                .child(label().font_size(11.).color(MUTED).text("Project Path"))
                .child(dialog_input(add_project_path, "/path/to/project"))
                .child(dialog_input(add_project_name, "Display Name (Optional)"))
                .into_element()
        } else {
            rect()
                .width(Size::fill())
                .vertical()
                .spacing(8.)
                .child(label().font_size(11.).color(MUTED).text("Clone URL"))
                .child(dialog_input(
                    add_project_clone_url,
                    "https://github.com/org/repository.git",
                ))
                .child(label().font_size(11.).color(MUTED).text("Parent Folder"))
                .child(dialog_input(add_project_clone_parent, "/path/to/projects"))
                .child(label().font_size(11.).color(MUTED).text("Directory Name"))
                .child(dialog_input(add_project_clone_directory, "repository"))
                .child(dialog_input(add_project_name, "Display Name (Optional)"))
                .into_element()
        };
        rect()
            .width(Size::fill())
            .vertical()
            .spacing(10.)
            .child(
                rect()
                    .width(Size::px(314.))
                    .height(Size::px(34.))
                    .horizontal()
                    .content(Content::Flex)
                    .border(Border::new().width(1.).fill(BORDER))
                    .corner_radius(5.)
                    .child(
                        Button::new()
                            .width(Size::flex(1.))
                            .height(Size::fill())
                            .compact()
                            .style_variant(if local_selected {
                                ButtonStyleVariant::Filled
                            } else {
                                ButtonStyleVariant::Flat
                            })
                            .theme_colors(
                                ButtonColorsThemePartial::new()
                                    .background(if local_selected {
                                        (62, 62, 62)
                                    } else {
                                        SURFACE
                                    })
                                    .hover_background((72, 72, 72))
                                    .border_fill(BORDER)
                                    .focus_border_fill(BORDER)
                                    .color(TEXT),
                            )
                            .on_press(move |_| local_mode.set(false))
                            .child(label().font_size(11.).color(TEXT).text("Local Folder")),
                    )
                    .child(
                        Button::new()
                            .width(Size::flex(1.))
                            .height(Size::fill())
                            .compact()
                            .style_variant(if clone_selected {
                                ButtonStyleVariant::Filled
                            } else {
                                ButtonStyleVariant::Flat
                            })
                            .theme_colors(
                                ButtonColorsThemePartial::new()
                                    .background(if clone_selected {
                                        (62, 62, 62)
                                    } else {
                                        SURFACE
                                    })
                                    .hover_background((72, 72, 72))
                                    .border_fill(BORDER)
                                    .focus_border_fill(BORDER)
                                    .color(TEXT),
                            )
                            .on_press(move |_| clone_mode.set(true))
                            .child(label().font_size(11.).color(TEXT).text("Clone From URL")),
                    ),
            )
            .child(label().font_size(11.).color(MUTED).text(if local_selected {
                "Alera will detect whether the folder is a Git repository. Non-Git folders only get a primary workspace."
            } else {
                "Clone the repository into a new local project folder."
            }))
            .child(fields)
            .into_element()
    } else {
        let mut prompt_mode = workspace_prompt_mode;
        let mut prompt_mode_for_manual = workspace_prompt_mode;
        let prompt_active = workspace_prompt_mode();
        let prompt_form = if prompt_active {
            rect()
                .width(Size::fill())
                .vertical()
                .spacing(8.)
                .child(label().font_size(10.).color(MUTED).text("Initial Prompt"))
                .child(
                    rect()
                        .width(Size::fill())
                        .height(Size::px(70.))
                        .border(Border::new().width(1.).fill(BORDER))
                        .corner_radius(5.)
                        .padding(Gaps::new_all(6.))
                        .child(dialog_input(
                            workspace_prompt,
                            "Describe What The Agent Should Build",
                        )),
                )
                .child(label().font_size(10.).color(MUTED).text("Project"))
                .child(dialog_select(
                    "project",
                    workspace_project,
                    workspace_open_dropdown,
                    workspace_dropdown_just_opened,
                    workspace_project_options.clone(),
                ))
                .child(label().font_size(10.).color(MUTED).text("Source Branch"))
                .child(dialog_select(
                    "source-branch",
                    workspace_source_branch,
                    workspace_open_dropdown,
                    workspace_dropdown_just_opened,
                    workspace_branch_options.read().clone(),
                ))
                .child(label().font_size(10.).color(MUTED).text("Parent Workspace"))
                .child(dialog_select(
                    "parent-workspace",
                    workspace_parent,
                    workspace_open_dropdown,
                    workspace_dropdown_just_opened,
                    workspace_parent_options.clone(),
                ))
                .child(label().font_size(10.).color(MUTED).text("Agent Profile"))
                .child(dialog_select(
                    "agent-profile",
                    workspace_agent_profile,
                    workspace_open_dropdown,
                    workspace_dropdown_just_opened,
                    workspace_agent_profile_options.read().clone(),
                ))
                .into_element()
        } else {
            let reuse_existing = workspace_reuse_existing_branch();
            let mut reuse_existing_state = workspace_reuse_existing_branch;
            let mut branch_for_reuse = workspace_branch;
            let available_local_branches = workspace_local_branch_options.read().clone();
            let local_branches_for_toggle = available_local_branches.clone();
            rect()
                .width(Size::fill())
                .vertical()
                .spacing(8.)
                .child(label().font_size(10.).color(MUTED).text("Project"))
                .child(dialog_select(
                    "manual-project",
                    workspace_project,
                    workspace_open_dropdown,
                    workspace_dropdown_just_opened,
                    workspace_project_options.clone(),
                ))
                .child(
                    rect()
                        .horizontal()
                        .cross_align(Alignment::Center)
                        .spacing(6.)
                        .a11y_role(AccessibilityRole::CheckBox)
                        .a11y_alt("Reuse Existing Branch")
                        .on_pointer_down(move |event: Event<PointerEventData>| {
                            event.stop_propagation();
                            if *workspace_creation_busy.peek() {
                                return;
                            }
                            let next = !reuse_existing_state();
                            reuse_existing_state.set(next);
                            branch_for_reuse.set(if next {
                                preferred_workspace_branch(&local_branches_for_toggle)
                                    .unwrap_or_default()
                            } else {
                                String::new()
                            });
                        })
                        .child(Checkbox::new().selected(reuse_existing))
                        .child(
                            label()
                                .font_size(11.)
                                .color(TEXT)
                                .text("Reuse Existing Branch"),
                        ),
                )
                .child(label().font_size(10.).color(MUTED).text(if reuse_existing {
                    "Existing Branch"
                } else {
                    "Source Branch"
                }))
                .child(if reuse_existing {
                    dialog_select(
                        "existing-branch",
                        workspace_branch,
                        workspace_open_dropdown,
                        workspace_dropdown_just_opened,
                        available_local_branches,
                    )
                } else {
                    dialog_select(
                        "manual-source-branch",
                        workspace_source_branch,
                        workspace_open_dropdown,
                        workspace_dropdown_just_opened,
                        workspace_branch_options.read().clone(),
                    )
                })
                .maybe_child((!reuse_existing).then(|| {
                    rect()
                        .width(Size::fill())
                        .vertical()
                        .spacing(8.)
                        .child(label().font_size(10.).color(MUTED).text("New Branch"))
                        .child(dialog_input(workspace_branch, "feature/new-workspace"))
                }))
                .child(label().font_size(12.).color(MUTED).text("Workspace Name"))
                .child(dialog_input(workspace_name, "Optional display name"))
                .child(label().font_size(10.).color(MUTED).text("Parent Workspace"))
                .child(dialog_select(
                    "manual-parent-workspace",
                    workspace_parent,
                    workspace_open_dropdown,
                    workspace_dropdown_just_opened,
                    workspace_parent_options.clone(),
                ))
                .into_element()
        };
        rect()
            .width(Size::fill())
            .vertical()
            .spacing(10.)
            .child(
                rect()
                    .width(Size::px(220.))
                    .height(Size::px(34.))
                    .horizontal()
                    .content(Content::Flex)
                    .border(Border::new().width(1.).fill(BORDER))
                    .corner_radius(5.)
                    .child(
                        Button::new()
                            .width(Size::flex(1.))
                            .height(Size::fill())
                            .compact()
                            .style_variant(if prompt_active {
                                ButtonStyleVariant::Filled
                            } else {
                                ButtonStyleVariant::Flat
                            })
                            .theme_colors(
                                ButtonColorsThemePartial::new()
                                    .background(if prompt_active { (62, 62, 62) } else { SURFACE })
                                    .hover_background((72, 72, 72))
                                    .border_fill(BORDER)
                                    .focus_border_fill(BORDER)
                                    .color(TEXT),
                            )
                            .on_press(move |_| prompt_mode.set(true))
                            .child(label().font_size(11.).color(TEXT).text("From Prompt")),
                    )
                    .child(
                        Button::new()
                            .width(Size::flex(1.))
                            .height(Size::fill())
                            .compact()
                            .style_variant(if !prompt_active {
                                ButtonStyleVariant::Filled
                            } else {
                                ButtonStyleVariant::Flat
                            })
                            .theme_colors(
                                ButtonColorsThemePartial::new()
                                    .background(if !prompt_active {
                                        (62, 62, 62)
                                    } else {
                                        SURFACE
                                    })
                                    .hover_background((72, 72, 72))
                                    .border_fill(BORDER)
                                    .focus_border_fill(BORDER)
                                    .color(TEXT),
                            )
                            .on_press(move |_| prompt_mode_for_manual.set(false))
                            .child(label().font_size(11.).color(TEXT).text("Manual")),
                    ),
            )
            .child(prompt_form)
            .child(
                rect()
                    .horizontal()
                    .cross_align(Alignment::Center)
                    .spacing(6.)
                    .on_pointer_down(move |_| workspace_create_another.toggle())
                    .child(Checkbox::new().selected(workspace_create_another()))
                    .child(label().font_size(11.).color(TEXT).text("Create Another")),
            )
            .into_element()
    };
    let error_text = action_dialog_error
        .read()
        .clone()
        .map(|message| label().font_size(12.).color((248, 113, 113)).text(message));
    let busy = !is_project && *workspace_creation_busy.read();
    let phase_text = busy.then(|| {
        rect()
            .horizontal()
            .cross_align(Alignment::Center)
            .spacing(8.)
            .child(CircularLoader::new().size(14.))
            .child(
                label().font_size(11.).color(MUTED).text(
                    workspace_creation_phase
                        .read()
                        .clone()
                        .unwrap_or_else(|| "Working".to_string()),
                ),
            )
    });
    let submit_label = if is_project {
        "Add Project"
    } else if workspace_prompt_mode() && prompt_created {
        "Retry Agent"
    } else if workspace_prompt_mode() {
        "Create And Start Agent"
    } else {
        "Create Workspace"
    };
    let busy_for_outside = workspace_creation_busy;
    rect()
        .position(Position::new_absolute())
        .layer(Layer::Overlay)
        .width(Size::percent(100.))
        .height(Size::percent(100.))
        .background(Color::from_af32rgb(0.55, 0, 0, 0))
        .on_press(move |_| {
            if !*busy_for_outside.peek() {
                action_dialog.set(None);
                action_dialog_error.set(None);
            }
        })
        .child(
            rect()
                .position(Position::new_absolute())
                .width(Size::percent(100.))
                .height(Size::percent(100.))
                .center()
                .child(
                    rect()
                        .width(Size::px(610.))
                        .background(SURFACE_RAISED)
                        .border(Border::new().width(1.).fill(BORDER))
                        .corner_radius(10.)
                        .padding(Gaps::new_all(20.))
                        .vertical()
                        .spacing(14.)
                        .on_press(|event: Event<PressEventData>| event.stop_propagation())
                        .child(
                            rect()
                                .horizontal()
                                .cross_align(Alignment::Center)
                                .spacing(8.)
                                .child(
                                    SvgViewer::new(if is_project {
                                        icons::lucide::folder_plus()
                                    } else {
                                        icons::lucide::git_fork()
                                    })
                                    .width(Size::px(20.))
                                    .height(Size::px(20.))
                                    .color(TEXT),
                                )
                                .child(label().font_size(18.).color(TEXT).text(title)),
                        )
                        .child(label().font_size(12.).color(MUTED).text(description))
                        .child(body)
                        .maybe_child(phase_text)
                        .maybe_child(error_text)
                        .child(
                            rect()
                                .horizontal()
                                .content(Content::Flex)
                                .cross_align(Alignment::Center)
                                .child(rect().width(Size::flex(1.)).child(""))
                                .child(
                                    rect()
                                        .height(Size::px(28.))
                                        .padding(Gaps::new(10., 6., 10., 6.))
                                        .a11y_role(AccessibilityRole::Button)
                                        .a11y_alt("Cancel")
                                        .on_pointer_down(cancel)
                                        .child(label().font_size(12.).color(MUTED).text("Cancel")),
                                )
                                .child(
                                    rect()
                                        .height(Size::px(28.))
                                        .padding(Gaps::new(10., 6., 10., 6.))
                                        .background(if submit_enabled {
                                            (228, 228, 228)
                                        } else {
                                            (68, 68, 68)
                                        })
                                        .border(Border::new().width(1.).fill(if submit_enabled {
                                            (228, 228, 228)
                                        } else {
                                            (68, 68, 68)
                                        }))
                                        .corner_radius(5.)
                                        .a11y_role(AccessibilityRole::Button)
                                        .a11y_alt(submit_label)
                                        .maybe(submit_enabled, |button| {
                                            button.on_pointer_down(submit)
                                        })
                                        .child(if busy {
                                            CircularLoader::new().size(13.).into_element()
                                        } else {
                                            label()
                                                .font_size(12.)
                                                .color(if submit_enabled {
                                                    BACKGROUND
                                                } else {
                                                    MUTED
                                                })
                                                .text(submit_label)
                                                .into_element()
                                        }),
                                ),
                        ),
                ),
        )
        .into_element()
}

#[allow(clippy::too_many_arguments)]
fn explorer_dialog_overlay(
    dialog: ExplorerDialog,
    explorer_dialog: State<Option<ExplorerDialog>>,
    explorer_dialog_value: State<String>,
    explorer_dialog_loading: State<bool>,
    explorer_dialog_error: State<Option<String>>,
    explorer_revision: State<u64>,
    explorer_path_move: State<Option<ExplorerPathMove>>,
    bridge: RuntimeBridge,
) -> Element {
    let loading = *explorer_dialog_loading.read();
    let (title, description, confirm_label, destructive, requires_value) = match &dialog {
        ExplorerDialog::Create {
            parent_relative_path,
            directory,
            ..
        } => (
            if *directory { "New Folder" } else { "New File" },
            if parent_relative_path.is_empty() {
                "Create This Item In The Workspace Root".to_string()
            } else {
                format!("Create This Item In {parent_relative_path}")
            },
            "Create",
            false,
            true,
        ),
        ExplorerDialog::Rename { current_name, .. } => (
            "Rename",
            format!("Choose A New Name For {current_name}"),
            "Rename",
            false,
            true,
        ),
        ExplorerDialog::Delete { name, .. } => (
            "Delete Item?",
            format!("Move {name} To The Trash?"),
            "Delete",
            true,
            false,
        ),
    };
    let submit_enabled =
        !loading && (!requires_value || !explorer_dialog_value.read().trim().is_empty());
    let mut close_from_overlay = explorer_dialog;
    let mut error_from_overlay = explorer_dialog_error;
    let mut close_from_cancel = explorer_dialog;
    let mut error_from_cancel = explorer_dialog_error;
    let dialog_for_submit = dialog.clone();
    let value_for_submit = explorer_dialog_value;
    let mut loading_for_submit = explorer_dialog_loading;
    let mut error_for_submit = explorer_dialog_error;
    let mut close_for_submit = explorer_dialog;
    let mut revision_for_submit = explorer_revision;
    let mut path_move_for_submit = explorer_path_move;
    let submit = move |event: Event<PointerEventData>| {
        event.stop_propagation();
        if !submit_enabled {
            return;
        }
        let value = value_for_submit.read().trim().to_string();
        let (method, payload, moved_from) = match dialog_for_submit.clone() {
            ExplorerDialog::Create {
                workspace_path,
                parent_relative_path,
                directory,
            } => (
                if directory {
                    "workspaceFiles.createDirectory"
                } else {
                    "workspaceFiles.createFile"
                },
                json!({
                    "workspacePath": workspace_path,
                    "parentRelativePath": parent_relative_path,
                    "name": value,
                }),
                None,
            ),
            ExplorerDialog::Rename {
                workspace_path,
                relative_path,
                ..
            } => (
                "workspaceFiles.rename",
                json!({
                    "workspacePath": workspace_path.clone(),
                    "relativePath": relative_path.clone(),
                    "newName": value,
                }),
                Some((workspace_path, relative_path)),
            ),
            ExplorerDialog::Delete {
                workspace_path,
                relative_path,
                ..
            } => (
                "workspaceFiles.delete",
                json!({
                    "workspacePath": workspace_path,
                    "relativePath": relative_path,
                    "useTrash": true,
                }),
                None,
            ),
        };
        loading_for_submit.set(true);
        error_for_submit.set(None);
        let bridge = bridge.clone();
        spawn(async move {
            match bridge.request(method, payload).await {
                Ok(response) => {
                    if let Some((workspace_path, old_relative_path)) = moved_from
                        && let Some(new_relative_path) = response
                            .get("relativePath")
                            .and_then(Value::as_str)
                            .map(str::to_string)
                    {
                        record_explorer_path_move(
                            &mut path_move_for_submit,
                            workspace_path,
                            old_relative_path,
                            new_relative_path,
                        );
                    }
                    close_for_submit.set(None);
                    let next = revision_for_submit.read().saturating_add(1);
                    revision_for_submit.set(next);
                }
                Err(error) => error_for_submit.set(Some(error)),
            }
            loading_for_submit.set(false);
        });
    };
    let error_view = explorer_dialog_error.read().clone().map(|error| {
        label()
            .font_size(11.)
            .color((248, 113, 113))
            .max_lines(4)
            .text(error)
    });
    rect()
        .position(Position::new_absolute())
        .layer(Layer::Overlay)
        .width(Size::percent(100.))
        .height(Size::percent(100.))
        .background(Color::from_af32rgb(0.55, 0, 0, 0))
        .on_press(move |_| {
            if !loading {
                close_from_overlay.set(None);
                error_from_overlay.set(None);
            }
        })
        .child(
            rect()
                .position(Position::new_absolute())
                .width(Size::percent(100.))
                .height(Size::percent(100.))
                .center()
                .child(
                    rect()
                        .width(Size::px(430.))
                        .background(SURFACE_RAISED)
                        .border(Border::new().width(1.).fill(BORDER))
                        .corner_radius(10.)
                        .padding(Gaps::new_all(20.))
                        .vertical()
                        .spacing(13.)
                        .on_press(|event: Event<PressEventData>| event.stop_propagation())
                        .child(label().font_size(17.).color(TEXT).text(title))
                        .child(label().font_size(12.).color(MUTED).text(description))
                        .maybe_child(requires_value.then(|| {
                            pull_request_text_field(
                                explorer_dialog_value,
                                if matches!(dialog, ExplorerDialog::Rename { .. }) {
                                    "Name"
                                } else {
                                    "Item Name"
                                },
                                34.,
                            )
                        }))
                        .maybe_child(error_view)
                        .child(
                            rect()
                                .width(Size::fill())
                                .height(Size::px(30.))
                                .horizontal()
                                .content(Content::Flex)
                                .spacing(8.)
                                .child(rect().width(Size::flex(1.)).child(""))
                                .child(
                                    rect()
                                        .height(Size::fill())
                                        .padding(Gaps::new(10., 0., 10., 0.))
                                        .center()
                                        .corner_radius(7.)
                                        .a11y_role(AccessibilityRole::Button)
                                        .a11y_alt("Cancel")
                                        .on_pointer_enter(|_| Cursor::set(CursorIcon::Pointer))
                                        .on_pointer_leave(|_| Cursor::set(CursorIcon::default()))
                                        .on_pointer_down(move |event: Event<PointerEventData>| {
                                            event.stop_propagation();
                                            if !loading {
                                                close_from_cancel.set(None);
                                                error_from_cancel.set(None);
                                            }
                                        })
                                        .child(label().font_size(11.).color(MUTED).text("Cancel")),
                                )
                                .child(
                                    rect()
                                        .height(Size::fill())
                                        .padding(Gaps::new(12., 0., 12., 0.))
                                        .center()
                                        .background(if submit_enabled {
                                            if destructive { (220, 38, 38) } else { ACCENT }
                                        } else {
                                            (68, 68, 68)
                                        })
                                        .corner_radius(7.)
                                        .a11y_role(AccessibilityRole::Button)
                                        .a11y_alt(confirm_label)
                                        .on_pointer_enter(move |_| {
                                            Cursor::set(if submit_enabled {
                                                CursorIcon::Pointer
                                            } else {
                                                CursorIcon::default()
                                            })
                                        })
                                        .on_pointer_leave(|_| Cursor::set(CursorIcon::default()))
                                        .on_pointer_down(submit)
                                        .child(if loading {
                                            CircularLoader::new().size(14.).into_element()
                                        } else {
                                            label()
                                                .font_size(11.)
                                                .color(if submit_enabled {
                                                    BACKGROUND
                                                } else {
                                                    MUTED
                                                })
                                                .text(confirm_label)
                                                .into_element()
                                        }),
                                ),
                        ),
                ),
        )
        .into_element()
}

#[allow(clippy::too_many_arguments)]
fn source_git_dialog_overlay(
    dialog: SourceGitDialog,
    source_git_dialog: State<Option<SourceGitDialog>>,
    source_git_dialog_message: State<String>,
    source_git_dialog_error: State<Option<String>>,
    source_git_dialog_loading: State<bool>,
    source_git_revision: State<u64>,
    bridge: RuntimeBridge,
) -> Element {
    let loading = source_git_dialog_loading();
    let (title, description, confirm_label, action, workspace_path, action_paths, destructive) =
        match &dialog {
            SourceGitDialog::Amend { workspace_path } => (
                "Amend Commit".to_string(),
                "Update the latest commit message and replace the existing commit.".to_string(),
                "Amend",
                "amend",
                workspace_path.clone(),
                Vec::new(),
                false,
            ),
            SourceGitDialog::DiscardAll { workspace_path } => (
                "Discard All Changes?".to_string(),
                "This permanently discards unstaged and untracked changes in this workspace."
                    .to_string(),
                "Discard",
                "discardAll",
                workspace_path.clone(),
                Vec::new(),
                true,
            ),
            SourceGitDialog::DiscardPath {
                workspace_path,
                path,
            } => (
                "Discard Changes?".to_string(),
                format!("This permanently discards unstaged and untracked changes in \"{path}\"."),
                "Discard",
                "discardPath",
                workspace_path.clone(),
                vec![path.clone()],
                true,
            ),
            SourceGitDialog::DiscardPaths {
                workspace_path,
                paths,
                target,
            } => (
                "Discard Changes?".to_string(),
                format!("This permanently discards changes in \"{target}\"."),
                "Discard",
                "discardPath",
                workspace_path.clone(),
                paths.clone(),
                true,
            ),
            SourceGitDialog::StashPop { workspace_path, .. } => (
                "Stash Pop".to_string(),
                "Choose the stash to apply and remove.".to_string(),
                "",
                "stashPop",
                workspace_path.clone(),
                Vec::new(),
                false,
            ),
        };
    let mut close_from_overlay = source_git_dialog;
    let mut error_from_overlay = source_git_dialog_error;
    let mut close_from_cancel = source_git_dialog;
    let mut error_from_cancel = source_git_dialog_error;
    let body = match &dialog {
        SourceGitDialog::Amend { .. } => rect()
            .width(Size::fill())
            .height(Size::px(132.))
            .background(SURFACE)
            .border(Border::new().width(1.).fill(BORDER))
            .corner_radius(8.)
            .overflow(Overflow::Clip)
            .child(
                Input::new(source_git_dialog_message)
                    .placeholder("Message")
                    .width(Size::fill())
                    .flat(),
            )
            .into_element(),
        SourceGitDialog::DiscardAll { .. }
        | SourceGitDialog::DiscardPath { .. }
        | SourceGitDialog::DiscardPaths { .. } => rect().into_element(),
        SourceGitDialog::StashPop { stashes, .. } => {
            let mut rows = rect().width(Size::fill()).vertical();
            for stash in stashes {
                let bridge = bridge.clone();
                let workspace_path = workspace_path.clone();
                let index = stash.index;
                let mut dialog_state = source_git_dialog;
                let mut error_state = source_git_dialog_error;
                let mut loading_state = source_git_dialog_loading;
                let mut revision = source_git_revision;
                rows = rows.child(
                    rect()
                        .width(Size::fill())
                        .padding(Gaps::new(10., 7., 10., 7.))
                        .vertical()
                        .spacing(3.)
                        .corner_radius(6.)
                        .a11y_role(AccessibilityRole::Button)
                        .a11y_alt(format!("{} {}", stash.reference, stash.message))
                        .on_pointer_enter(|_| Cursor::set(CursorIcon::Pointer))
                        .on_pointer_leave(|_| Cursor::set(CursorIcon::default()))
                        .on_pointer_down(move |event: Event<PointerEventData>| {
                            event.stop_propagation();
                            if *loading_state.read() {
                                return;
                            }
                            loading_state.set(true);
                            let bridge = bridge.clone();
                            let workspace_path = workspace_path.clone();
                            spawn(async move {
                                let result = bridge
                                    .request(
                                        "workspaceGit.action",
                                        json!({
                                            "workspacePath": workspace_path,
                                            "action": "stashPop",
                                            "path": null,
                                            "message": null,
                                            "index": index,
                                        }),
                                    )
                                    .await;
                                loading_state.set(false);
                                match result {
                                    Ok(_) => {
                                        dialog_state.set(None);
                                        let next = revision.read().saturating_add(1);
                                        revision.set(next);
                                    }
                                    Err(error) => error_state.set(Some(error)),
                                }
                            });
                        })
                        .child(
                            label()
                                .font_size(13.)
                                .color(TEXT)
                                .text(stash.reference.clone()),
                        )
                        .child(
                            label()
                                .font_size(11.)
                                .color(MUTED)
                                .max_lines(2)
                                .text_overflow(TextOverflow::Ellipsis)
                                .text(stash.message.clone()),
                        ),
                );
            }
            ScrollView::new()
                .width(Size::fill())
                .height(Size::px(260.))
                .show_scrollbar(true)
                .child(rows)
                .into_element()
        }
    };
    let message = source_git_dialog_message.read().trim().to_string();
    let submit_enabled = !loading && (action != "amend" || !message.is_empty());
    let bridge_for_submit = bridge;
    let workspace_for_submit = workspace_path;
    let action_paths_for_submit = action_paths;
    let mut dialog_for_submit = source_git_dialog;
    let mut error_for_submit = source_git_dialog_error;
    let mut loading_for_submit = source_git_dialog_loading;
    let mut revision_for_submit = source_git_revision;
    let submit = EventHandler::new(move |event: Event<PointerEventData>| {
        event.stop_propagation();
        if !submit_enabled {
            if action == "amend" && message.is_empty() {
                error_for_submit.set(Some("Message Is Required".to_string()));
            }
            return;
        }
        loading_for_submit.set(true);
        let bridge = bridge_for_submit.clone();
        let workspace_path = workspace_for_submit.clone();
        let action_paths = action_paths_for_submit.clone();
        let message = (action == "amend").then(|| message.clone());
        spawn(async move {
            let paths = if action_paths.is_empty() {
                vec![None]
            } else {
                action_paths.into_iter().map(Some).collect()
            };
            let mut result = Ok(json!({}));
            for path in paths {
                result = bridge
                    .request(
                        "workspaceGit.action",
                        json!({
                            "workspacePath": workspace_path.clone(),
                            "action": action,
                            "path": path,
                            "message": message.clone(),
                            "index": null,
                        }),
                    )
                    .await;
                if result.is_err() {
                    break;
                }
            }
            loading_for_submit.set(false);
            match result {
                Ok(_) => {
                    dialog_for_submit.set(None);
                    let next = revision_for_submit.read().saturating_add(1);
                    revision_for_submit.set(next);
                }
                Err(error) => error_for_submit.set(Some(error)),
            }
        });
    });
    let error_text = source_git_dialog_error
        .read()
        .clone()
        .map(|message| label().font_size(12.).color((248, 113, 113)).text(message));
    let is_stash_picker = matches!(dialog, SourceGitDialog::StashPop { .. });
    rect()
        .position(Position::new_absolute())
        .layer(Layer::Overlay)
        .width(Size::percent(100.))
        .height(Size::percent(100.))
        .background(Color::from_af32rgb(0.55, 0, 0, 0))
        .on_press(move |_| {
            if !loading {
                close_from_overlay.set(None);
                error_from_overlay.set(None);
            }
        })
        .child(
            rect()
                .position(Position::new_absolute())
                .width(Size::percent(100.))
                .height(Size::percent(100.))
                .center()
                .child(
                    rect()
                        .width(Size::px(614.))
                        .background(SURFACE_RAISED)
                        .border(Border::new().width(1.).fill(BORDER))
                        .corner_radius(10.)
                        .padding(Gaps::new_all(20.))
                        .vertical()
                        .spacing(16.)
                        .on_press(|event: Event<PressEventData>| event.stop_propagation())
                        .child(label().font_size(18.).color(TEXT).text(title))
                        .child(label().font_size(12.).color(MUTED).text(description))
                        .child(body)
                        .maybe_child(error_text)
                        .child(
                            rect()
                                .width(Size::fill())
                                .horizontal()
                                .content(Content::Flex)
                                .cross_align(Alignment::Center)
                                .child(rect().width(Size::flex(1.)).child(""))
                                .child(
                                    rect()
                                        .height(Size::px(32.))
                                        .padding(Gaps::new(12., 6., 12., 6.))
                                        .a11y_role(AccessibilityRole::Button)
                                        .a11y_alt("Cancel")
                                        .on_pointer_down(move |event: Event<PointerEventData>| {
                                            event.stop_propagation();
                                            if !loading {
                                                close_from_cancel.set(None);
                                                error_from_cancel.set(None);
                                            }
                                        })
                                        .child(label().font_size(12.).color(MUTED).text("Cancel")),
                                )
                                .maybe_child((!is_stash_picker).then(|| {
                                    rect()
                                        .height(Size::px(32.))
                                        .padding(Gaps::new(12., 6., 12., 6.))
                                        .background(if submit_enabled {
                                            if destructive {
                                                (220, 38, 38)
                                            } else {
                                                (228, 228, 228)
                                            }
                                        } else {
                                            (68, 68, 68)
                                        })
                                        .corner_radius(6.)
                                        .a11y_role(AccessibilityRole::Button)
                                        .a11y_alt(confirm_label)
                                        .on_pointer_down(submit)
                                        .child(if loading {
                                            CircularLoader::new().size(14.).into_element()
                                        } else {
                                            label()
                                                .font_size(12.)
                                                .color(if submit_enabled {
                                                    BACKGROUND
                                                } else {
                                                    MUTED
                                                })
                                                .text(confirm_label)
                                                .into_element()
                                        })
                                })),
                        ),
                ),
        )
        .into_element()
}

fn context_nav_button(
    context_mode: State<String>,
    mode: &'static str,
    icon: Bytes,
    enabled: bool,
) -> Element {
    let active = context_mode.read().as_str() == mode;
    let mut context_mode = context_mode;
    TooltipContainer::new(Tooltip::new_text(mode))
        .position(AttachedPosition::Bottom)
        .delay(Duration::from_millis(350))
        .child(
            rect()
                .width(Size::px(28.))
                .height(Size::px(28.))
                .background(if active { SURFACE_RAISED } else { SURFACE })
                .corner_radius(5.)
                .center()
                .a11y_role(AccessibilityRole::Button)
                .a11y_alt(mode)
                .on_pointer_enter(move |_| {
                    Cursor::set(if enabled {
                        CursorIcon::Pointer
                    } else {
                        CursorIcon::default()
                    });
                })
                .on_pointer_leave(|_| Cursor::set(CursorIcon::default()))
                .on_pointer_down(move |event: Event<PointerEventData>| {
                    event.stop_propagation();
                    if enabled {
                        context_mode.set(mode.to_string());
                    }
                })
                .child(
                    rect().interactive(false).child(
                        SvgViewer::new(icon)
                            .width(Size::px(16.))
                            .height(Size::px(16.))
                            .color(if !enabled {
                                FAINT
                            } else if active {
                                TEXT
                            } else {
                                MUTED
                            }),
                    ),
                ),
        )
        .into_element()
}

#[derive(Clone, Debug)]
struct ExplorerEntry {
    relative_path: String,
    name: String,
    kind: String,
    is_symlink: bool,
    git_status: Option<String>,
}

#[derive(Clone, Copy)]
struct ExplorerPanelState {
    explorer_entries: State<Option<Result<Vec<ExplorerEntry>, String>>>,
    expanded_dirs: State<HashSet<String>>,
    directory_children: State<HashMap<String, Result<Vec<ExplorerEntry>, String>>>,
    open_editor_path: State<Option<FileOpenRequest>>,
    drag: State<Option<ExplorerDragData>>,
    drag_hover: State<Option<String>>,
}

#[derive(Clone)]
struct ExplorerSourceControlSettings {
    bridge: RuntimeBridge,
    workspace_id: Option<String>,
    workspace_path: String,
    focused_root: Option<String>,
    enabled: bool,
    view_prefs_revision: State<u64>,
    context_mode: State<String>,
    message: State<Option<String>>,
    dialog: State<Option<ExplorerDialog>>,
    dialog_value: State<String>,
    revision: State<u64>,
    clipboard: State<Option<ExplorerClipboard>>,
    path_move: State<Option<ExplorerPathMove>>,
}

fn parse_explorer_entries(value: &Value) -> Vec<ExplorerEntry> {
    value
        .as_array()
        .into_iter()
        .flatten()
        .filter_map(|entry| {
            Some(ExplorerEntry {
                relative_path: entry
                    .get("relativePath")
                    .and_then(Value::as_str)
                    .or_else(|| entry.get("name").and_then(Value::as_str))
                    .unwrap_or("file")
                    .to_string(),
                name: entry.get("name")?.as_str()?.to_string(),
                kind: entry
                    .get("kind")
                    .and_then(Value::as_str)
                    .unwrap_or("file")
                    .to_string(),
                is_symlink: entry
                    .get("isSymlink")
                    .and_then(Value::as_bool)
                    .unwrap_or(false),
                git_status: entry
                    .get("gitStatus")
                    .and_then(Value::as_str)
                    .map(str::to_string),
            })
        })
        .collect()
}

fn parse_workspace_search_view(value: &Value) -> Result<WorkspaceSearchView, String> {
    let files = value
        .get("files")
        .and_then(Value::as_array)
        .ok_or_else(|| "Search response omitted files".to_string())?
        .iter()
        .map(|file| {
            let relative_path = file
                .get("relativePath")
                .and_then(Value::as_str)
                .ok_or_else(|| "Search result omitted relativePath".to_string())?
                .to_string();
            let content_token = file
                .get("contentToken")
                .and_then(Value::as_str)
                .ok_or_else(|| format!("Search result for {relative_path} omitted contentToken"))?
                .to_string();
            let matches = file
                .get("matches")
                .and_then(Value::as_array)
                .ok_or_else(|| format!("Search result for {relative_path} omitted matches"))?
                .iter()
                .map(|item| {
                    Ok(WorkspaceSearchMatchView {
                        id: item
                            .get("id")
                            .and_then(Value::as_str)
                            .ok_or_else(|| "Search match omitted id".to_string())?
                            .to_string(),
                        line: item.get("line").and_then(Value::as_u64).unwrap_or(1),
                        column: item.get("column").and_then(Value::as_u64).unwrap_or(1),
                        match_length: item
                            .get("matchLength")
                            .and_then(Value::as_u64)
                            .unwrap_or_default(),
                        line_content: item
                            .get("lineContent")
                            .and_then(Value::as_str)
                            .unwrap_or_default()
                            .to_string(),
                        display_column: item.get("displayColumn").and_then(Value::as_u64),
                        display_match_length: item
                            .get("displayMatchLength")
                            .and_then(Value::as_u64),
                        replacement_preview: item
                            .get("replacementPreview")
                            .and_then(Value::as_str)
                            .map(str::to_string),
                    })
                })
                .collect::<Result<Vec<_>, String>>()?;
            Ok(WorkspaceSearchFileView {
                relative_path,
                content_token,
                matches,
            })
        })
        .collect::<Result<Vec<_>, String>>()?;
    Ok(WorkspaceSearchView {
        total_matches: value
            .get("totalMatches")
            .and_then(Value::as_u64)
            .unwrap_or_else(|| files.iter().map(|file| file.matches.len() as u64).sum()),
        truncated: value
            .get("truncated")
            .and_then(Value::as_bool)
            .unwrap_or(false),
        files,
    })
}

fn workspace_search_directory_paths(relative_path: &str) -> Vec<String> {
    let normalized = relative_path.replace('\\', "/");
    let segments = normalized
        .split('/')
        .filter(|segment| !segment.is_empty())
        .collect::<Vec<_>>();
    if segments.len() <= 1 {
        return Vec::new();
    }
    (1..segments.len())
        .map(|length| segments[..length].join("/"))
        .collect()
}

fn workspace_search_collapsible_keys(
    result: Option<&WorkspaceSearchView>,
    view_as_tree: bool,
) -> HashSet<String> {
    let Some(result) = result else {
        return HashSet::new();
    };
    let mut keys = HashSet::new();
    for file in &result.files {
        if view_as_tree {
            keys.extend(
                workspace_search_directory_paths(&file.relative_path)
                    .into_iter()
                    .map(|path| format!("dir:{path}")),
            );
        }
        keys.insert(format!("file:{}", file.relative_path));
    }
    keys
}

fn workspace_search_rows(
    result: &WorkspaceSearchView,
    collapsed_nodes: &HashSet<String>,
    view_as_tree: bool,
) -> Vec<WorkspaceSearchRow> {
    if !view_as_tree {
        let mut files = result.files.clone();
        files.sort_by(|left, right| left.relative_path.cmp(&right.relative_path));
        let mut rows = Vec::new();
        for file in files {
            rows.push(WorkspaceSearchRow::File {
                file: file.clone(),
                depth: 0,
                show_directory: true,
            });
            if collapsed_nodes.contains(&format!("file:{}", file.relative_path)) {
                continue;
            }
            rows.extend(
                file.matches
                    .into_iter()
                    .map(|item| WorkspaceSearchRow::Match {
                        relative_path: file.relative_path.clone(),
                        item,
                        depth: 0,
                    }),
            );
        }
        return rows;
    }

    let mut root = WorkspaceSearchTreeDirectory::default();
    for file in &result.files {
        let normalized = file.relative_path.replace('\\', "/");
        let segments = normalized
            .split('/')
            .filter(|segment| !segment.is_empty())
            .collect::<Vec<_>>();
        if segments.len() <= 1 {
            root.files.push(file.clone());
            continue;
        }
        let mut directory = &mut root;
        let mut path_segments = Vec::new();
        for name in segments.iter().take(segments.len() - 1) {
            path_segments.push(*name);
            let path = path_segments.join("/");
            directory = directory
                .directories
                .entry((*name).to_string())
                .or_insert_with(|| WorkspaceSearchTreeDirectory {
                    name: (*name).to_string(),
                    path,
                    ..WorkspaceSearchTreeDirectory::default()
                });
            directory.match_count += file.matches.len();
        }
        directory.files.push(file.clone());
    }

    let mut rows = Vec::new();
    append_workspace_search_tree_rows(&root, &mut rows, collapsed_nodes, -1);
    rows
}

fn append_workspace_search_tree_rows(
    directory: &WorkspaceSearchTreeDirectory,
    rows: &mut Vec<WorkspaceSearchRow>,
    collapsed_nodes: &HashSet<String>,
    depth: isize,
) {
    for child in directory.directories.values() {
        let child_depth = (depth + 1) as usize;
        rows.push(WorkspaceSearchRow::Directory {
            name: child.name.clone(),
            path: child.path.clone(),
            depth: child_depth,
            match_count: child.match_count,
        });
        if !collapsed_nodes.contains(&format!("dir:{}", child.path)) {
            append_workspace_search_tree_rows(child, rows, collapsed_nodes, depth + 1);
        }
    }
    let mut files = directory.files.iter().collect::<Vec<_>>();
    files.sort_by(|left, right| left.relative_path.cmp(&right.relative_path));
    for file in files {
        let file_depth = (depth + 1) as usize;
        rows.push(WorkspaceSearchRow::File {
            file: file.clone(),
            depth: file_depth,
            show_directory: false,
        });
        if collapsed_nodes.contains(&format!("file:{}", file.relative_path)) {
            continue;
        }
        rows.extend(
            file.matches
                .iter()
                .cloned()
                .map(|item| WorkspaceSearchRow::Match {
                    relative_path: file.relative_path.clone(),
                    item,
                    depth: file_depth + 1,
                }),
        );
    }
}

fn context_explorer_panel(
    panel_state: ExplorerPanelState,
    runtime_selector: Element,
    runtime_loading: bool,
    runtime_status: &'static str,
    working_directory: String,
    source_control: ExplorerSourceControlSettings,
) -> Element {
    let tree = match panel_state.explorer_entries.read().as_ref() {
        Some(Ok(entries)) if !entries.is_empty() => rect()
            .vertical()
            .spacing(3.)
            .children(explorer_entry_elements(
                entries.clone(),
                0,
                panel_state,
                source_control.clone(),
            ))
            .into_element(),
        Some(Ok(_)) => explorer_state_message("This Workspace Has No Files"),
        Some(Err(error)) => explorer_state_message(error),
        None => rect()
            .horizontal()
            .cross_align(Alignment::Center)
            .spacing(8.)
            .padding(Gaps::new_all(10.))
            .child(CircularLoader::new().size(14.))
            .child(label().font_size(11.).color(MUTED).text("Loading Files"))
            .into_element(),
    };
    let settings_for_new_file = source_control.clone();
    let settings_for_new_folder = source_control.clone();
    let settings_for_refresh = source_control.clone();
    let settings_for_background = source_control.clone();
    let toolbar = rect()
        .width(Size::fill())
        .height(Size::px(30.))
        .horizontal()
        .content(Content::Flex)
        .cross_align(Alignment::Center)
        .child(
            label()
                .width(Size::flex(1.))
                .font_size(11.)
                .color(MUTED)
                .text("Explorer"),
        )
        .child(explorer_toolbar_button(
            "New File",
            icons::lucide::file_plus(),
            move || {
                begin_explorer_dialog(
                    settings_for_new_file.clone(),
                    ExplorerDialog::Create {
                        workspace_path: settings_for_new_file.workspace_path.clone(),
                        parent_relative_path: String::new(),
                        directory: false,
                    },
                    String::new(),
                );
            },
        ))
        .child(explorer_toolbar_button(
            "New Folder",
            icons::lucide::folder_plus(),
            move || {
                begin_explorer_dialog(
                    settings_for_new_folder.clone(),
                    ExplorerDialog::Create {
                        workspace_path: settings_for_new_folder.workspace_path.clone(),
                        parent_relative_path: String::new(),
                        directory: true,
                    },
                    String::new(),
                );
            },
        ))
        .child(explorer_toolbar_button(
            "Refresh",
            icons::lucide::refresh_cw(),
            move || refresh_explorer(settings_for_refresh.clone()),
        ));
    rect()
        .vertical()
        .spacing(8.)
        .child(label().font_size(11.).color(FAINT).text(working_directory))
        .maybe_child(source_control.message.read().clone().map(|message| {
            label()
                .width(Size::fill())
                .font_size(10.)
                .color((248, 113, 113))
                .text(message)
        }))
        .child(toolbar)
        .child(
            rect()
                .width(Size::fill())
                .on_secondary_down(move |event: Event<PressEventData>| {
                    event.stop_propagation();
                    open_explorer_background_menu(settings_for_background.clone());
                })
                .child(tree),
        )
        .child(
            rect()
                .background(SURFACE_RAISED)
                .border(Border::new().width(1.).fill(BORDER))
                .corner_radius(6.)
                .padding(Gaps::new_all(10.))
                .spacing(7.)
                .vertical()
                .child(label().font_size(13.).color(MUTED).text("Runtime"))
                .child(if runtime_loading {
                    CircularLoader::new().into_element()
                } else {
                    label()
                        .font_size(12.)
                        .color(SUCCESS)
                        .text(runtime_status)
                        .into_element()
                })
                .child(runtime_selector)
                .child(label().font_size(12.).color(MUTED).text("Local workspace")),
        )
        .into_element()
}

fn explorer_toolbar_button(
    tooltip: &'static str,
    icon: Bytes,
    action: impl Fn() + 'static,
) -> Element {
    TooltipContainer::new(Tooltip::new_text(tooltip))
        .position(AttachedPosition::Top)
        .delay(Duration::from_millis(350))
        .child(
            rect()
                .width(Size::px(27.))
                .height(Size::px(27.))
                .corner_radius(5.)
                .center()
                .a11y_role(AccessibilityRole::Button)
                .a11y_alt(tooltip)
                .on_pointer_enter(|_| Cursor::set(CursorIcon::Pointer))
                .on_pointer_leave(|_| Cursor::set(CursorIcon::default()))
                .on_pointer_down(move |event: Event<PointerEventData>| {
                    event.stop_propagation();
                    action();
                })
                .child(
                    SvgViewer::new(icon)
                        .width(Size::px(14.))
                        .height(Size::px(14.))
                        .color(MUTED),
                ),
        )
        .into_element()
}

fn open_explorer_background_menu(settings: ExplorerSourceControlSettings) {
    let settings_for_file = settings.clone();
    let settings_for_folder = settings.clone();
    let settings_for_paste = settings.clone();
    let settings_for_refresh = settings.clone();
    let mut menu = Menu::new()
        .child(
            MenuButton::new()
                .on_press(move |_| {
                    ContextMenu::close();
                    begin_explorer_dialog(
                        settings_for_file.clone(),
                        ExplorerDialog::Create {
                            workspace_path: settings_for_file.workspace_path.clone(),
                            parent_relative_path: String::new(),
                            directory: false,
                        },
                        String::new(),
                    );
                })
                .child("New File"),
        )
        .child(
            MenuButton::new()
                .on_press(move |_| {
                    ContextMenu::close();
                    begin_explorer_dialog(
                        settings_for_folder.clone(),
                        ExplorerDialog::Create {
                            workspace_path: settings_for_folder.workspace_path.clone(),
                            parent_relative_path: String::new(),
                            directory: true,
                        },
                        String::new(),
                    );
                })
                .child("New Folder"),
        );
    if let Some(clipboard) = settings.clipboard.read().clone() {
        menu = menu.child(
            MenuButton::new()
                .on_press(move |_| {
                    ContextMenu::close();
                    let method = if clipboard.cut {
                        "workspaceFiles.move"
                    } else {
                        "workspaceFiles.copy"
                    };
                    let mut clipboard_state = settings_for_paste.clipboard;
                    let settings_after = settings_for_paste.clone();
                    let moved_from = clipboard.relative_path.clone();
                    let payload = json!({
                        "workspacePath": settings_for_paste.workspace_path,
                        "relativePath": moved_from.clone(),
                        "targetParentRelativePath": "",
                    });
                    spawn(async move {
                        match settings_after.bridge.request(method, payload).await {
                            Ok(response) => {
                                if clipboard.cut {
                                    if let Some(new_relative_path) = response
                                        .get("relativePath")
                                        .and_then(Value::as_str)
                                        .map(str::to_string)
                                    {
                                        let mut path_move = settings_after.path_move;
                                        record_explorer_path_move(
                                            &mut path_move,
                                            settings_after.workspace_path.clone(),
                                            moved_from.clone(),
                                            new_relative_path,
                                        );
                                    }
                                    clipboard_state.set(None);
                                }
                                refresh_explorer(settings_after);
                            }
                            Err(error) => {
                                let mut message = settings_after.message;
                                message.set(Some(error));
                            }
                        }
                    });
                })
                .child("Paste"),
        );
    }
    menu = menu.child(
        MenuButton::new()
            .on_press(move |_| {
                ContextMenu::close();
                refresh_explorer(settings_for_refresh.clone());
            })
            .child("Refresh"),
    );
    ContextMenu::open_from_down(menu);
}

fn explorer_state_message(message: impl Into<String>) -> Element {
    rect()
        .width(Size::fill())
        .padding(Gaps::new_all(10.))
        .child(
            label()
                .font_size(11.)
                .color(MUTED)
                .max_lines(4)
                .text(message.into()),
        )
        .into_element()
}

fn explorer_entry_elements(
    entries: Vec<ExplorerEntry>,
    depth: usize,
    panel_state: ExplorerPanelState,
    source_control: ExplorerSourceControlSettings,
) -> Vec<Element> {
    let expanded_dirs = panel_state.expanded_dirs;
    let directory_children = panel_state.directory_children;
    let open_editor_path = panel_state.open_editor_path;
    let drag = panel_state.drag;
    let drag_hover = panel_state.drag_hover;
    entries
        .into_iter()
        .flat_map(|entry| {
            let is_directory = entry.kind == "directory";
            let relative_path = entry.relative_path.clone();
            let expanded = is_directory && expanded_dirs.read().contains(&relative_path);
            let color = if is_directory {
                (96, 170, 220)
            } else if entry.name == "package.json" {
                (237, 190, 86)
            } else {
                TEXT
            };
            let status = entry.git_status.as_deref().map(|status| match status {
                "untracked" => " U",
                "added" => " A",
                "modified" => " M",
                _ => "",
            });
            let mut expanded_dirs_for_row = expanded_dirs;
            let mut open_editor_path_for_row = open_editor_path;
            let row_relative_path = relative_path.clone();
            let context_path = relative_path.clone();
            let context_name = entry.name.clone();
            let context_open_editor_path = open_editor_path;
            let source_control_for_menu = source_control.clone();
            let is_drop_hovered =
                is_directory && drag_hover.read().as_deref() == Some(relative_path.as_str());
            let row = rect()
                .width(Size::fill())
                .horizontal()
                .cross_align(Alignment::Center)
                .spacing(4.)
                .padding(Gaps::new(8. + depth as f32 * 16., 3., 4., 3.))
                .background(if is_drop_hovered {
                    SURFACE_RAISED
                } else {
                    SURFACE
                })
                .corner_radius(4.)
                .on_pointer_enter(|_| Cursor::set(CursorIcon::Pointer))
                .on_pointer_leave(|_| Cursor::set(CursorIcon::default()))
                .on_press(move |event: Event<PressEventData>| {
                    event.stop_propagation();
                    if is_directory {
                        let path = row_relative_path.clone();
                        let mut expanded_dirs = expanded_dirs_for_row.write();
                        if !expanded_dirs.insert(path.clone()) {
                            expanded_dirs.remove(&path);
                        }
                    } else {
                        open_editor_path_for_row
                            .set(Some(FileOpenRequest::preview(row_relative_path.clone())));
                    }
                })
                .on_secondary_down(move |event: Event<PressEventData>| {
                    event.stop_propagation();
                    open_explorer_context_menu(
                        source_control_for_menu.clone(),
                        context_path.clone(),
                        context_name.clone(),
                        is_directory,
                        context_open_editor_path,
                    );
                })
                .child(if is_directory {
                    SvgViewer::new(if expanded {
                        icons::lucide::chevron_down()
                    } else {
                        icons::lucide::chevron_right()
                    })
                    .width(Size::px(14.))
                    .height(Size::px(14.))
                    .color(MUTED)
                    .into_element()
                } else {
                    rect()
                        .width(Size::px(14.))
                        .height(Size::px(14.))
                        .into_element()
                })
                .child(file_icons::file_icon(
                    &entry.name,
                    is_directory,
                    expanded,
                    entry.is_symlink,
                    14.,
                ))
                .child(label().font_size(12.).color(color).text(entry.name))
                .maybe_child(status.map(|status| label().font_size(10.).color(MUTED).text(status)))
                .into_element();

            let drag_feedback = rect()
                .width(Size::px(360.))
                .background(SURFACE_RAISED)
                .border(Border::new().width(1.).fill(BORDER))
                .corner_radius(4.)
                .shadow(Shadow::new().x(0.).y(2.).blur(4.).color((0, 0, 0, 0.55)))
                .child(row.clone());
            let dragger = DragZone::<ExplorerDragData>::new(
                ExplorerDragData {
                    relative_path: relative_path.clone(),
                },
                row,
            )
            .drag_element(drag_feedback)
            .show_while_dragging(true)
            .key(("explorer-drag", relative_path.clone()))
            .into_element();
            let row = if is_directory {
                let target_path = relative_path.clone();
                let target_path_for_hover = target_path.clone();
                let drag_for_hover = drag;
                let mut drag_hover_for_hover = drag_hover;
                let settings_for_drop = source_control.clone();
                DropZone::<ExplorerDragData>::new(dragger, move |payload: ExplorerDragData| {
                    if explorer_can_drop(&payload.relative_path, &target_path) {
                        move_explorer_entry(
                            settings_for_drop.clone(),
                            payload.relative_path,
                            target_path.clone(),
                        );
                    }
                })
                .on_drag_over(move |hovering| {
                    let accepts = hovering
                        && drag_for_hover.peek().as_ref().is_some_and(|payload| {
                            explorer_can_drop(&payload.relative_path, &target_path_for_hover)
                        });
                    if accepts {
                        drag_hover_for_hover.set(Some(target_path_for_hover.clone()));
                    } else if drag_hover_for_hover.peek().as_deref()
                        == Some(target_path_for_hover.as_str())
                    {
                        drag_hover_for_hover.set(None);
                    }
                })
                .key(("explorer-drop", relative_path.clone()))
                .into_element()
            } else {
                dragger
            };

            let mut rendered = vec![row];
            if expanded {
                match directory_children.read().get(&relative_path) {
                    Some(Ok(children)) => rendered.extend(explorer_entry_elements(
                        children.clone(),
                        depth + 1,
                        panel_state,
                        source_control.clone(),
                    )),
                    Some(Err(error)) => rendered.push(
                        rect()
                            .padding(Gaps::new(24. + depth as f32 * 16., 2., 4., 2.))
                            .child(label().font_size(11.).color(MUTED).text(error.clone()))
                            .into_element(),
                    ),
                    None => rendered.push(
                        rect()
                            .padding(Gaps::new(24. + depth as f32 * 16., 2., 4., 2.))
                            .child(label().font_size(11.).color(FAINT).text("Loading..."))
                            .into_element(),
                    ),
                }
            }
            rendered
        })
        .collect()
}

fn explorer_parent_path(relative_path: &str) -> String {
    relative_path
        .rsplit_once('/')
        .map(|(parent, _)| parent.to_string())
        .unwrap_or_default()
}

fn explorer_can_drop(source_relative_path: &str, target_directory: &str) -> bool {
    let source = source_relative_path.trim_matches('/');
    let target = target_directory.trim_matches('/');
    !source.is_empty() && source != target && !target.starts_with(&format!("{source}/"))
}

fn move_explorer_entry(
    settings: ExplorerSourceControlSettings,
    source_relative_path: String,
    target_parent_relative_path: String,
) {
    let payload = json!({
        "workspacePath": settings.workspace_path.clone(),
        "relativePath": source_relative_path.clone(),
        "targetParentRelativePath": target_parent_relative_path,
    });
    spawn(async move {
        let mut settings = settings;
        match settings
            .bridge
            .request("workspaceFiles.move", payload)
            .await
        {
            Ok(response) => {
                if let Some(new_relative_path) = response
                    .get("relativePath")
                    .and_then(Value::as_str)
                    .map(str::to_string)
                {
                    record_explorer_path_move(
                        &mut settings.path_move,
                        settings.workspace_path.clone(),
                        source_relative_path,
                        new_relative_path,
                    );
                }
                refresh_explorer(settings);
            }
            Err(error) => settings.message.set(Some(error)),
        }
    });
}

fn begin_explorer_dialog(
    mut settings: ExplorerSourceControlSettings,
    dialog: ExplorerDialog,
    value: String,
) {
    settings.message.set(None);
    settings.dialog_value.set(value);
    settings.dialog.set(Some(dialog));
}

fn refresh_explorer(mut settings: ExplorerSourceControlSettings) {
    settings.message.set(None);
    let next = settings.revision.read().saturating_add(1);
    settings.revision.set(next);
}

fn record_explorer_path_move(
    path_move: &mut State<Option<ExplorerPathMove>>,
    workspace_path: String,
    old_relative_path: String,
    new_relative_path: String,
) {
    let generation = path_move
        .read()
        .as_ref()
        .map_or(1, |path_move| path_move.generation.saturating_add(1));
    path_move.set(Some(ExplorerPathMove {
        generation,
        workspace_path,
        old_relative_path,
        new_relative_path,
    }));
}

fn run_explorer_mutation(
    settings: ExplorerSourceControlSettings,
    method: &'static str,
    payload: Value,
) {
    let mut settings = settings;
    spawn(async move {
        match settings.bridge.request(method, payload).await {
            Ok(_) => refresh_explorer(settings),
            Err(error) => settings.message.set(Some(error)),
        }
    });
}

fn open_explorer_context_menu(
    settings: ExplorerSourceControlSettings,
    relative_path: String,
    name: String,
    is_directory: bool,
    open_editor_path: State<Option<FileOpenRequest>>,
) {
    let target_directory = if is_directory {
        relative_path.clone()
    } else {
        explorer_parent_path(&relative_path)
    };
    let path_for_open = relative_path.clone();
    let mut open_editor = open_editor_path;
    let settings_for_file = settings.clone();
    let directory_for_file = target_directory.clone();
    let settings_for_folder = settings.clone();
    let directory_for_folder = target_directory.clone();
    let settings_for_copy = settings.clone();
    let copy_path = relative_path.clone();
    let settings_for_cut = settings.clone();
    let cut_path = relative_path.clone();
    let settings_for_relative_path = settings.clone();
    let relative_path_for_copy = relative_path.clone();
    let settings_for_absolute_path = settings.clone();
    let absolute_path_for_copy = relative_path.clone();
    let settings_for_duplicate = settings.clone();
    let duplicate_path = relative_path.clone();
    let duplicate_parent = explorer_parent_path(&relative_path);
    let settings_for_reveal = settings.clone();
    let reveal_path = relative_path.clone();
    let settings_for_rename = settings.clone();
    let rename_path = relative_path.clone();
    let rename_name = name.clone();
    let settings_for_refresh = settings.clone();
    let settings_for_delete = settings.clone();
    let delete_path = relative_path.clone();
    let delete_name = name.clone();

    let mut menu = Menu::new()
        .child(
            MenuButton::new()
                .on_press(move |_| {
                    ContextMenu::close();
                    if !is_directory {
                        open_editor.set(Some(FileOpenRequest::preview(path_for_open.clone())));
                    }
                })
                .child(if is_directory { "Open Folder" } else { "Open" }),
        )
        .child(
            MenuButton::new()
                .on_press(move |_| {
                    ContextMenu::close();
                    begin_explorer_dialog(
                        settings_for_file.clone(),
                        ExplorerDialog::Create {
                            workspace_path: settings_for_file.workspace_path.clone(),
                            parent_relative_path: directory_for_file.clone(),
                            directory: false,
                        },
                        String::new(),
                    );
                })
                .child("New File"),
        )
        .child(
            MenuButton::new()
                .on_press(move |_| {
                    ContextMenu::close();
                    begin_explorer_dialog(
                        settings_for_folder.clone(),
                        ExplorerDialog::Create {
                            workspace_path: settings_for_folder.workspace_path.clone(),
                            parent_relative_path: directory_for_folder.clone(),
                            directory: true,
                        },
                        String::new(),
                    );
                })
                .child("New Folder"),
        )
        .child(
            MenuButton::new()
                .on_press(move |_| {
                    ContextMenu::close();
                    let mut clipboard = settings_for_copy.clipboard;
                    clipboard.set(Some(ExplorerClipboard {
                        relative_path: copy_path.clone(),
                        cut: false,
                    }));
                })
                .child("Copy"),
        )
        .child(
            MenuButton::new()
                .on_press(move |_| {
                    ContextMenu::close();
                    let mut clipboard = settings_for_cut.clipboard;
                    clipboard.set(Some(ExplorerClipboard {
                        relative_path: cut_path.clone(),
                        cut: true,
                    }));
                })
                .child("Cut"),
        );
    if let Some(clipboard) = settings.clipboard.read().clone() {
        let settings_for_paste = settings.clone();
        let paste_target = target_directory.clone();
        menu = menu.child(
            MenuButton::new()
                .on_press(move |_| {
                    ContextMenu::close();
                    let method = if clipboard.cut {
                        "workspaceFiles.move"
                    } else {
                        "workspaceFiles.copy"
                    };
                    let mut clipboard_state = settings_for_paste.clipboard;
                    let settings_after = settings_for_paste.clone();
                    let moved_from = clipboard.relative_path.clone();
                    let payload = json!({
                        "workspacePath": settings_for_paste.workspace_path,
                        "relativePath": moved_from.clone(),
                        "targetParentRelativePath": paste_target,
                    });
                    spawn(async move {
                        match settings_after.bridge.request(method, payload).await {
                            Ok(response) => {
                                if clipboard.cut {
                                    if let Some(new_relative_path) = response
                                        .get("relativePath")
                                        .and_then(Value::as_str)
                                        .map(str::to_string)
                                    {
                                        let mut path_move = settings_after.path_move;
                                        record_explorer_path_move(
                                            &mut path_move,
                                            settings_after.workspace_path.clone(),
                                            moved_from.clone(),
                                            new_relative_path,
                                        );
                                    }
                                    clipboard_state.set(None);
                                }
                                refresh_explorer(settings_after);
                            }
                            Err(error) => {
                                let mut message = settings_after.message;
                                message.set(Some(error));
                            }
                        }
                    });
                })
                .child("Paste"),
        );
    }
    menu = menu
        .child(
            MenuButton::new()
                .on_press(move |_| {
                    ContextMenu::close();
                    let absolute = PathBuf::from(&settings_for_absolute_path.workspace_path)
                        .join(&absolute_path_for_copy)
                        .to_string_lossy()
                        .into_owned();
                    let _ = Clipboard::set(absolute);
                })
                .child("Copy Path"),
        )
        .child(
            MenuButton::new()
                .on_press(move |_| {
                    ContextMenu::close();
                    let _ = Clipboard::set(relative_path_for_copy.clone());
                    let mut message = settings_for_relative_path.message;
                    message.set(None);
                })
                .child("Copy Relative Path"),
        )
        .child(
            MenuButton::new()
                .on_press(move |_| {
                    ContextMenu::close();
                    run_explorer_mutation(
                        settings_for_duplicate.clone(),
                        "workspaceFiles.copy",
                        json!({
                            "workspacePath": settings_for_duplicate.workspace_path,
                            "relativePath": duplicate_path,
                            "targetParentRelativePath": duplicate_parent,
                        }),
                    );
                })
                .child("Duplicate"),
        )
        .child(
            MenuButton::new()
                .on_press(move |_| {
                    ContextMenu::close();
                    let absolute =
                        PathBuf::from(&settings_for_reveal.workspace_path).join(&reveal_path);
                    let mut message = settings_for_reveal.message;
                    match reveal_in_file_manager(&absolute) {
                        Ok(()) => message.set(None),
                        Err(error) => message.set(Some(error)),
                    }
                })
                .child("Reveal In File Manager"),
        )
        .child(
            MenuButton::new()
                .on_press(move |_| {
                    ContextMenu::close();
                    begin_explorer_dialog(
                        settings_for_rename.clone(),
                        ExplorerDialog::Rename {
                            workspace_path: settings_for_rename.workspace_path.clone(),
                            relative_path: rename_path.clone(),
                            current_name: rename_name.clone(),
                        },
                        rename_name.clone(),
                    );
                })
                .child("Rename"),
        );
    if is_directory && settings.enabled {
        let clear = settings.focused_root.as_deref() == Some(relative_path.as_str());
        let settings_for_root = settings.clone();
        let root = (!clear).then(|| relative_path.clone());
        menu = menu.child(
            MenuButton::new()
                .on_press(move |_| {
                    ContextMenu::close();
                    let mut settings = settings_for_root.clone();
                    let root = root.clone();
                    spawn(async move {
                        let result = update_source_control_root(
                            &settings.bridge,
                            settings.workspace_id.as_deref(),
                            &settings.workspace_path,
                            root,
                        )
                        .await;
                        match result {
                            Ok(()) => {
                                settings.message.set(None);
                                let next = settings.view_prefs_revision.read().saturating_add(1);
                                settings.view_prefs_revision.set(next);
                                settings.context_mode.set(if clear {
                                    "Explorer".to_string()
                                } else {
                                    "Source Control".to_string()
                                });
                            }
                            Err(error) => settings.message.set(Some(error)),
                        }
                    });
                })
                .child(if clear {
                    "Clear Source Control Root"
                } else {
                    "Use As Source Control Root"
                }),
        );
    }
    menu = menu
        .child(
            MenuButton::new()
                .on_press(move |_| {
                    ContextMenu::close();
                    refresh_explorer(settings_for_refresh.clone());
                })
                .child("Refresh"),
        )
        .child(
            MenuButton::new()
                .on_press(move |_| {
                    ContextMenu::close();
                    begin_explorer_dialog(
                        settings_for_delete.clone(),
                        ExplorerDialog::Delete {
                            workspace_path: settings_for_delete.workspace_path.clone(),
                            relative_path: delete_path.clone(),
                            name: delete_name.clone(),
                        },
                        String::new(),
                    );
                })
                .child("Delete"),
        );
    ContextMenu::open_from_down(menu);
}

fn context_search_panel(state: SearchPanelState) -> Element {
    let query = state.query.read().clone();
    let results = state.results.read().clone();
    let loading = *state.loading.read();
    let replacing = *state.replacing.read();
    let replace_visible = *state.replace_visible.read();
    let details_visible = *state.details_visible.read();
    let view_as_tree = *state.view_as_tree.read();
    let result = results.as_ref().and_then(|result| result.as_ref().ok());
    let has_results = result.is_some_and(|result| !result.files.is_empty());
    let can_replace = !query.is_empty()
        && !loading
        && !replacing
        && result.is_some_and(|result| result.total_matches > 0);
    let can_replace_all = can_replace && result.is_some_and(|result| !result.truncated);
    let can_clear = !query.is_empty()
        || !state.replacement.read().is_empty()
        || !state.include_pattern.read().is_empty()
        || !state.exclude_pattern.read().is_empty()
        || results.is_some()
        || loading;
    let summary = if query.trim().is_empty() {
        String::new()
    } else if loading {
        "Searching...".to_string()
    } else if let Some(result) = result {
        let match_word = if result.total_matches == 1 {
            "match"
        } else {
            "matches"
        };
        let file_word = if result.files.len() == 1 {
            "file"
        } else {
            "files"
        };
        format!(
            "{} {} in {} {}{}",
            result.total_matches,
            match_word,
            result.files.len(),
            file_word,
            if result.truncated { " shown" } else { "" }
        )
    } else {
        "No Results".to_string()
    };
    let mut clear_state = state.clone();
    let mut ignored = state.include_ignored;
    let mut tree = state.view_as_tree;
    let mut collapsed = state.collapsed_nodes;
    let all_collapsible_keys = workspace_search_collapsible_keys(result, view_as_tree);
    let all_collapsed = !all_collapsible_keys.is_empty()
        && all_collapsible_keys
            .iter()
            .all(|key| collapsed.read().contains(key));
    let mut revision = state.revision;
    let refresh_button = if loading {
        search_loading_icon_button("Searching")
    } else {
        search_icon_button_enabled(
            "Refresh",
            icons::lucide::refresh_cw(),
            !query.is_empty(),
            move || {
                let next = revision.read().saturating_add(1);
                revision.set(next);
            },
        )
    };
    let toolbar = rect()
        .width(Size::fill())
        .height(Size::px(44.))
        .horizontal()
        .content(Content::Flex)
        .cross_align(Alignment::Center)
        .spacing(3.)
        .child(
            label()
                .width(Size::flex(1.))
                .font_size(12.)
                .color(TEXT)
                .text("Search"),
        )
        .child(search_icon_button_enabled(
            "Clear Search Results",
            icons::lucide::x(),
            can_clear,
            move || {
                clear_state.query.set(String::new());
                clear_state.replacement.set(String::new());
                clear_state.include_pattern.set(String::new());
                clear_state.exclude_pattern.set(String::new());
                clear_state.results.set(None);
                clear_state.replace_message.set(None);
                clear_state.replace_confirmation.set(None);
                clear_state.collapsed_nodes.set(HashSet::new());
            },
        ))
        .child(search_icon_button(
            if *state.include_ignored.read() {
                "Ignore Ignored Files"
            } else {
                "Search Ignored Files"
            },
            if *state.include_ignored.read() {
                icons::lucide::eye()
            } else {
                icons::lucide::eye_off()
            },
            move || ignored.toggle(),
        ))
        .child(search_icon_button(
            if *state.view_as_tree.read() {
                "View As List"
            } else {
                "View As Tree"
            },
            if *state.view_as_tree.read() {
                icons::lucide::list()
            } else {
                icons::lucide::git_graph()
            },
            move || tree.toggle(),
        ))
        .child(search_icon_button_enabled(
            if all_collapsed {
                "Expand All"
            } else {
                "Collapse All"
            },
            if all_collapsed {
                icons::lucide::chevrons_up_down()
            } else {
                icons::lucide::chevrons_down_up()
            },
            has_results,
            move || {
                collapsed.set(if all_collapsed {
                    HashSet::new()
                } else {
                    all_collapsible_keys.clone()
                });
            },
        ))
        .child(refresh_button);

    let mut toggle_replace = state.replace_visible;
    let mut toggle_details = state.details_visible;
    let search_input = rect()
        .width(Size::fill())
        .horizontal()
        .cross_align(Alignment::Center)
        .spacing(4.)
        .child(search_icon_button_sized(
            if replace_visible {
                "Hide Replace"
            } else {
                "Show Replace"
            },
            if replace_visible {
                icons::lucide::chevron_down()
            } else {
                icons::lucide::chevron_right()
            },
            true,
            16.,
            16.,
            move || toggle_replace.toggle(),
        ))
        .child(
            Input::new(state.query)
                .placeholder("Search")
                .width(Size::flex(1.))
                .compact()
                .filled(),
        )
        .child(search_text_toggle("Match Case", "Aa", state.case_sensitive))
        .child(search_text_toggle(
            "Match Whole Word",
            "ab",
            state.whole_word,
        ))
        .child(search_text_toggle(
            "Use Regular Expression",
            ".*",
            state.use_regex,
        ));
    let replace_input = replace_visible.then(|| {
        let replace_state = state.clone();
        rect()
            .width(Size::fill())
            .horizontal()
            .cross_align(Alignment::Center)
            .spacing(4.)
            .child(rect().width(Size::px(28.)).child(""))
            .child(
                Input::new(state.replacement)
                    .placeholder("Replace")
                    .width(Size::flex(1.))
                    .compact()
                    .filled(),
            )
            .child(search_text_toggle(
                "Preserve Case",
                "AB",
                state.preserve_case,
            ))
            .child(search_inline_icon_button_enabled(
                "Replace All",
                icons::lucide::check_check(),
                can_replace_all,
                move || {
                    run_workspace_search_replace(replace_state.clone(), None);
                },
            ))
    });
    let details = details_visible.then(|| {
        rect()
            .width(Size::fill())
            .vertical()
            .spacing(5.)
            .child(
                Input::new(state.include_pattern)
                    .placeholder("Files To Include")
                    .width(Size::fill())
                    .compact()
                    .filled(),
            )
            .child(
                Input::new(state.exclude_pattern)
                    .placeholder("Files To Exclude")
                    .width(Size::fill())
                    .compact()
                    .filled(),
            )
    });

    let result_body = if query.trim().is_empty() {
        explorer_state_message("Enter A Search Query")
    } else if loading {
        rect()
            .horizontal()
            .cross_align(Alignment::Center)
            .spacing(8.)
            .padding(Gaps::new_all(10.))
            .child(CircularLoader::new().size(14.))
            .child(label().font_size(11.).color(MUTED).text("Searching"))
            .into_element()
    } else {
        match results {
            Some(Ok(result)) if result.files.is_empty() => explorer_state_message("No Results"),
            Some(Ok(result)) => rect()
                .width(Size::fill())
                .vertical()
                .children(workspace_search_result_elements(result, state.clone()))
                .into_element(),
            Some(Err(error)) => explorer_state_message(error),
            None => explorer_state_message("No Results"),
        }
    };
    rect()
        .vertical()
        .spacing(6.)
        .child(toolbar)
        .child(search_input)
        .maybe_child(replace_input)
        .child(
            rect()
                .width(Size::fill())
                .horizontal()
                .content(Content::Flex)
                .child(rect().width(Size::flex(1.)).child(""))
                .child(search_inline_icon_button(
                    if details_visible {
                        "Hide Details"
                    } else {
                        "Show Details"
                    },
                    icons::lucide::ellipsis(),
                    move || toggle_details.toggle(),
                )),
        )
        .maybe_child(details)
        .child(
            rect()
                .width(Size::fill())
                .horizontal()
                .cross_align(Alignment::Center)
                .spacing(7.)
                .padding(Gaps::new_all(6.))
                .child(label().font_size(11.).color(MUTED).text(summary))
                .maybe_child(replacing.then(|| CircularLoader::new().size(13.))),
        )
        .maybe_child(state.replace_message.read().clone().map(|message| {
            label()
                .font_size(10.)
                .color(
                    if message.starts_with("Replaced") && !message.contains("Skipped") {
                        SUCCESS
                    } else {
                        (248, 113, 113)
                    },
                )
                .text(message)
        }))
        .child(rect().height(Size::px(1.)).background(BORDER))
        .child(
            ScrollView::new()
                .width(Size::fill())
                .height(Size::flex(1.))
                .show_scrollbar(true)
                .child(result_body),
        )
        .into_element()
}

fn search_icon_button(
    tooltip: &'static str,
    icon: Bytes,
    action: impl FnMut() + 'static,
) -> Element {
    search_icon_button_enabled(tooltip, icon, true, action)
}

fn search_icon_button_enabled(
    tooltip: &'static str,
    icon: Bytes,
    enabled: bool,
    action: impl FnMut() + 'static,
) -> Element {
    search_icon_button_sized(tooltip, icon, enabled, 30., 16., action)
}

fn search_inline_icon_button(
    tooltip: &'static str,
    icon: Bytes,
    action: impl FnMut() + 'static,
) -> Element {
    search_inline_icon_button_enabled(tooltip, icon, true, action)
}

fn search_inline_icon_button_enabled(
    tooltip: &'static str,
    icon: Bytes,
    enabled: bool,
    action: impl FnMut() + 'static,
) -> Element {
    search_icon_button_sized(tooltip, icon, enabled, 24., 14., action)
}

fn search_icon_button_sized(
    tooltip: &'static str,
    icon: Bytes,
    enabled: bool,
    size: f32,
    icon_size: f32,
    mut action: impl FnMut() + 'static,
) -> Element {
    TooltipContainer::new(Tooltip::new_text(tooltip))
        .position(AttachedPosition::Top)
        .delay(Duration::from_millis(350))
        .child(
            rect()
                .width(Size::px(size))
                .height(Size::px(size))
                .center()
                .corner_radius(6.)
                .a11y_role(AccessibilityRole::Button)
                .a11y_alt(tooltip)
                .on_pointer_enter(move |_| {
                    Cursor::set(if enabled {
                        CursorIcon::Pointer
                    } else {
                        CursorIcon::default()
                    })
                })
                .on_pointer_leave(|_| Cursor::set(CursorIcon::default()))
                .on_pointer_down(move |event: Event<PointerEventData>| {
                    event.stop_propagation();
                    if enabled {
                        action();
                    }
                })
                .child(
                    SvgViewer::new(icon)
                        .width(Size::px(icon_size))
                        .height(Size::px(icon_size))
                        .color(if enabled { MUTED } else { FAINT }),
                ),
        )
        .into_element()
}

fn search_loading_icon_button(tooltip: &'static str) -> Element {
    TooltipContainer::new(Tooltip::new_text(tooltip))
        .position(AttachedPosition::Top)
        .delay(Duration::from_millis(350))
        .child(
            rect()
                .width(Size::px(30.))
                .height(Size::px(30.))
                .center()
                .corner_radius(6.)
                .a11y_role(AccessibilityRole::Button)
                .a11y_alt(tooltip)
                .child(CircularLoader::new().size(16.)),
        )
        .into_element()
}

fn search_text_toggle(tooltip: &'static str, text: &'static str, state: State<bool>) -> Element {
    let active = *state.read();
    let mut state = state;
    TooltipContainer::new(Tooltip::new_text(tooltip))
        .position(AttachedPosition::Top)
        .delay(Duration::from_millis(350))
        .child(
            rect()
                .height(Size::px(24.))
                .padding(Gaps::new(5., 3., 5., 3.))
                .center()
                .background(if active { SURFACE_RAISED } else { SURFACE })
                .border(
                    Border::new()
                        .width(1.)
                        .fill(if active { MUTED } else { BORDER }),
                )
                .corner_radius(4.)
                .a11y_role(AccessibilityRole::Button)
                .a11y_alt(tooltip)
                .on_pointer_enter(|_| Cursor::set(CursorIcon::Pointer))
                .on_pointer_leave(|_| Cursor::set(CursorIcon::default()))
                .on_pointer_down(move |event: Event<PointerEventData>| {
                    event.stop_propagation();
                    state.toggle();
                })
                .child(label().font_size(10.).color(TEXT).text(text)),
        )
        .into_element()
}

fn workspace_search_result_elements(
    result: WorkspaceSearchView,
    state: SearchPanelState,
) -> Vec<Element> {
    let collapsed_nodes = state.collapsed_nodes.read().clone();
    let view_as_tree = *state.view_as_tree.read();
    workspace_search_rows(&result, &collapsed_nodes, view_as_tree)
        .into_iter()
        .map(|row| match row {
            WorkspaceSearchRow::Directory {
                name,
                path,
                depth,
                match_count,
            } => {
                let is_collapsed = collapsed_nodes.contains(&format!("dir:{path}"));
                workspace_search_directory_element(
                    name,
                    path,
                    depth,
                    match_count,
                    state.collapsed_nodes,
                    is_collapsed,
                )
            }
            WorkspaceSearchRow::File {
                file,
                depth,
                show_directory,
            } => workspace_search_file_element(
                file,
                depth,
                show_directory,
                state.clone(),
                &collapsed_nodes,
            ),
            WorkspaceSearchRow::Match {
                relative_path,
                item,
                depth,
            } => workspace_search_match_element(relative_path, item, depth, state.clone()),
        })
        .collect()
}

fn workspace_search_directory_element(
    name: String,
    path: String,
    depth: usize,
    match_count: usize,
    mut collapsed_nodes: State<HashSet<String>>,
    collapsed: bool,
) -> Element {
    let key = format!("dir:{path}");
    rect()
        .width(Size::fill())
        .height(Size::px(30.))
        .horizontal()
        .cross_align(Alignment::Center)
        .spacing(5.)
        .padding(Gaps::new(6., 8. + depth as f32 * 16., 6., 8.))
        .on_pointer_enter(|_| Cursor::set(CursorIcon::Pointer))
        .on_pointer_leave(|_| Cursor::set(CursorIcon::default()))
        .on_pointer_down(move |event: Event<PointerEventData>| {
            event.stop_propagation();
            let mut nodes = collapsed_nodes.write();
            if !nodes.insert(key.clone()) {
                nodes.remove(&key);
            }
        })
        .child(
            SvgViewer::new(if collapsed {
                icons::lucide::chevron_right()
            } else {
                icons::lucide::chevron_down()
            })
            .width(Size::px(14.))
            .height(Size::px(14.))
            .color(MUTED),
        )
        .child(
            SvgViewer::new(if collapsed {
                icons::lucide::folder()
            } else {
                icons::lucide::folder_open()
            })
            .width(Size::px(14.))
            .height(Size::px(14.))
            .color(FAINT),
        )
        .child(label().font_size(11.).color(TEXT).text(name))
        .child(rect().width(Size::flex(1.)).child(""))
        .child(
            label()
                .font_size(10.)
                .color(TEXT)
                .text(match_count.to_string()),
        )
        .into_element()
}

fn workspace_search_file_element(
    file: WorkspaceSearchFileView,
    depth: usize,
    show_directory: bool,
    state: SearchPanelState,
    collapsed_nodes: &HashSet<String>,
) -> Element {
    let file_key = format!("file:{}", file.relative_path);
    let file_collapsed = collapsed_nodes.contains(&file_key);
    let file_path = file.relative_path.clone();
    let normalized = file_path.replace('\\', "/");
    let file_name = normalized
        .rsplit('/')
        .next()
        .unwrap_or(&normalized)
        .to_string();
    let directory = normalized
        .rsplit_once('/')
        .map(|(directory, _)| directory.to_string())
        .unwrap_or_default();
    let count = file.matches.len();
    let replace_enabled = *state.replace_visible.read()
        && !*state.replacing.read()
        && state
            .results
            .read()
            .as_ref()
            .and_then(|result| result.as_ref().ok())
            .is_some_and(|result| result.total_matches > 0 && !result.truncated);
    let mut collapsed_for_file = state.collapsed_nodes;
    let file_key_for_click = file_key;
    let replace_file_state = state.clone();
    let file_match_ids = file
        .matches
        .iter()
        .map(|item| item.id.clone())
        .collect::<Vec<_>>();
    rect()
        .width(Size::fill())
        .height(Size::px(30.))
        .horizontal()
        .cross_align(Alignment::Center)
        .spacing(5.)
        .padding(Gaps::new(6., 8. + depth as f32 * 16., 6., 8.))
        .on_pointer_enter(|_| Cursor::set(CursorIcon::Pointer))
        .on_pointer_leave(|_| Cursor::set(CursorIcon::default()))
        .on_pointer_down(move |event: Event<PointerEventData>| {
            event.stop_propagation();
            let mut collapsed = collapsed_for_file.write();
            if !collapsed.insert(file_key_for_click.clone()) {
                collapsed.remove(&file_key_for_click);
            }
        })
        .child(
            SvgViewer::new(if file_collapsed {
                icons::lucide::chevron_right()
            } else {
                icons::lucide::chevron_down()
            })
            .width(Size::px(14.))
            .height(Size::px(14.))
            .color(MUTED),
        )
        .child(file_icons::file_icon(
            &file.relative_path,
            false,
            false,
            false,
            14.,
        ))
        .child(label().font_size(11.).color(TEXT).text(file_name))
        .maybe_child(
            (show_directory && !directory.is_empty())
                .then(|| label().font_size(10.).color(FAINT).text(directory)),
        )
        .child(rect().width(Size::flex(1.)).child(""))
        .child(label().font_size(10.).color(TEXT).text(count.to_string()))
        .child(search_inline_icon_button_enabled(
            "Replace In File",
            icons::lucide::replace(),
            replace_enabled,
            move || {
                run_workspace_search_replace(
                    replace_file_state.clone(),
                    Some(file_match_ids.clone()),
                );
            },
        ))
        .into_element()
}

fn workspace_search_match_element(
    relative_path: String,
    item: WorkspaceSearchMatchView,
    depth: usize,
    state: SearchPanelState,
) -> Element {
    let mut open_editor = state.open_editor_path;
    let replace_enabled = *state.replace_visible.read()
        && !*state.replacing.read()
        && state
            .results
            .read()
            .as_ref()
            .and_then(|result| result.as_ref().ok())
            .is_some_and(|result| result.total_matches > 0);
    let replace_match_state = state;
    let match_id = item.id.clone();
    let line_preview = workspace_search_line_preview(&item);
    rect()
        .width(Size::fill())
        .min_height(Size::px(28.))
        .horizontal()
        .cross_align(Alignment::Center)
        .spacing(6.)
        .padding(Gaps::new(4., 8. + depth as f32 * 16., 6., 8.))
        .on_pointer_enter(|_| Cursor::set(CursorIcon::Pointer))
        .on_pointer_leave(|_| Cursor::set(CursorIcon::default()))
        .on_pointer_down(move |event: Event<PointerEventData>| {
            event.stop_propagation();
            open_editor.set(Some(FileOpenRequest::search(
                relative_path.clone(),
                item.line,
                item.column,
                item.match_length,
            )));
        })
        .child(
            label()
                .width(Size::px(32.))
                .font_family("JetBrains Mono")
                .font_size(10.)
                .color(FAINT)
                .text(item.line.to_string()),
        )
        .child(workspace_search_line_preview_element(line_preview))
        .child(search_inline_icon_button_enabled(
            "Replace Match",
            icons::lucide::replace(),
            replace_enabled,
            move || {
                run_workspace_search_replace(
                    replace_match_state.clone(),
                    Some(vec![match_id.clone()]),
                );
            },
        ))
        .into_element()
}

#[derive(Clone, Debug, PartialEq, Eq)]
struct WorkspaceSearchLinePreview {
    before: String,
    matched: String,
    replacement: Option<String>,
    after: String,
}

fn workspace_search_line_preview(item: &WorkspaceSearchMatchView) -> WorkspaceSearchLinePreview {
    let text = item.line_content.trim_end();
    let characters = text.chars().collect::<Vec<_>>();
    let one_based_column = item.display_column.unwrap_or(item.column);
    let match_length = item.display_match_length.unwrap_or(item.match_length) as usize;
    let start = one_based_column.saturating_sub(1) as usize;
    let start = start.min(characters.len());
    let end = start.saturating_add(match_length).min(characters.len());
    WorkspaceSearchLinePreview {
        before: characters[..start].iter().collect(),
        matched: characters[start..end].iter().collect(),
        replacement: item.replacement_preview.clone(),
        after: characters[end..].iter().collect(),
    }
}

fn workspace_search_line_preview_element(preview: WorkspaceSearchLinePreview) -> Element {
    let replacement = preview.replacement.clone();
    rect()
        .width(Size::flex(1.))
        .height(Size::px(18.))
        .horizontal()
        .cross_align(Alignment::Center)
        .overflow(Overflow::Clip)
        .child(search_preview_span(preview.before, MUTED, None, false))
        .child(search_preview_span(
            preview.matched,
            if replacement.is_some() {
                (248, 113, 113)
            } else {
                TEXT
            },
            Some(if replacement.is_some() {
                (69, 10, 10)
            } else {
                SURFACE_RAISED
            }),
            replacement.is_none(),
        ))
        .maybe_child(
            replacement.map(|replacement| search_preview_span(replacement, SUCCESS, None, true)),
        )
        .child(search_preview_span(preview.after, MUTED, None, false))
        .into_element()
}

fn search_preview_span(
    text: String,
    color: (u8, u8, u8),
    background: Option<(u8, u8, u8)>,
    bold: bool,
) -> Element {
    let mut span = rect().height(Size::px(16.));
    if let Some(background) = background {
        span = span.background(background);
    }
    span.maybe(bold, |span| span.font_weight(FontWeight::BOLD))
        .child(
            label()
                .font_family("JetBrains Mono")
                .font_size(10.)
                .color(color)
                .text(text),
        )
        .into_element()
}

fn workspace_search_replace_message(result: &Value) -> String {
    let files_changed = result
        .get("filesChanged")
        .and_then(Value::as_u64)
        .unwrap_or_default();
    let matches_replaced = result
        .get("matchesReplaced")
        .and_then(Value::as_u64)
        .unwrap_or_default();
    let conflicts = result
        .get("conflicts")
        .and_then(Value::as_array)
        .map(Vec::as_slice)
        .unwrap_or_default();
    if let Some(first) = conflicts.first() {
        let skipped = conflicts
            .iter()
            .filter_map(|conflict| conflict.get("relativePath").and_then(Value::as_str))
            .collect::<HashSet<_>>()
            .len();
        let path = first
            .get("relativePath")
            .and_then(Value::as_str)
            .unwrap_or("Unknown File");
        let reason = first
            .get("reason")
            .and_then(Value::as_str)
            .unwrap_or("Replace Conflict");
        let skipped_files = if skipped == 1 {
            "1 File".to_string()
        } else {
            format!("{skipped} Files")
        };
        return if matches_replaced > 0 {
            let matches = if matches_replaced == 1 {
                "1 Match".to_string()
            } else {
                format!("{matches_replaced} Matches")
            };
            format!("Replaced {matches}. {skipped_files} Skipped. {path}: {reason}")
        } else {
            format!("Replace Skipped {skipped_files}. {path}: {reason}")
        };
    }
    format!("Replaced {matches_replaced} Matches In {files_changed} Files")
}

fn workspace_search_requires_replace_confirmation(
    current: Option<&(String, String, u64)>,
    candidate: &(String, String, u64),
) -> bool {
    current != Some(candidate)
}

fn run_workspace_search_replace(state: SearchPanelState, match_ids: Option<Vec<String>>) {
    if *state.replacing.read() {
        return;
    }
    let Some(Ok(result)) = state.results.read().clone() else {
        let mut message = state.replace_message;
        message.set(Some("Run Search Before Replacing".to_string()));
        return;
    };
    if match_ids.is_none() && result.truncated {
        let mut message = state.replace_message;
        message.set(Some(
            "Replace All Is Unavailable While Results Are Truncated".to_string(),
        ));
        return;
    }
    if match_ids.is_none() {
        let confirmation = (
            state.query.read().clone(),
            state.replacement.read().clone(),
            result.total_matches,
        );
        if workspace_search_requires_replace_confirmation(
            state.replace_confirmation.read().as_ref(),
            &confirmation,
        ) {
            let mut replace_confirmation = state.replace_confirmation;
            let mut message = state.replace_message;
            replace_confirmation.set(Some(confirmation));
            message.set(Some(format!(
                "Confirm Replacing {} Matches By Clicking Replace All Again",
                result.total_matches
            )));
            return;
        }
    }
    let selected_ids = match_ids
        .as_ref()
        .map(|ids| ids.iter().cloned().collect::<HashSet<_>>());
    let affected_files = result
        .files
        .iter()
        .filter(|file| {
            selected_ids
                .as_ref()
                .is_none_or(|ids| file.matches.iter().any(|item| ids.contains(&item.id)))
        })
        .cloned()
        .collect::<Vec<_>>();
    let dirty_paths = state
        .dirty_documents
        .read()
        .values()
        .filter(|path| {
            affected_files
                .iter()
                .any(|file| file.relative_path == path.as_str())
        })
        .cloned()
        .collect::<BTreeSet<_>>();
    if !dirty_paths.is_empty() {
        let mut message = state.replace_message;
        message.set(Some(format!(
            "Save Or Close Dirty Editors Before Replacing: {}",
            dirty_paths.into_iter().collect::<Vec<_>>().join(", ")
        )));
        return;
    }
    let payload = json!({
        "workspacePath": state.workspace_path.clone(),
        "query": state.query.read().clone(),
        "caseSensitive": *state.case_sensitive.read(),
        "wholeWord": *state.whole_word.read(),
        "useRegex": *state.use_regex.read(),
        "includePattern": (!state.include_pattern.read().trim().is_empty()).then(|| state.include_pattern.read().clone()),
        "excludePattern": (!state.exclude_pattern.read().trim().is_empty()).then(|| state.exclude_pattern.read().clone()),
        "includeIgnored": *state.include_ignored.read(),
        "replacement": state.replacement.read().clone(),
        "preserveCase": *state.preserve_case.read(),
        "matchIds": match_ids.unwrap_or_default(),
        "expectedFiles": affected_files.iter().map(|file| json!({
            "relativePath": file.relative_path.clone(),
            "contentToken": file.content_token.clone(),
        })).collect::<Vec<_>>(),
    });
    let bridge = state.bridge.clone();
    let workspace_path = state.workspace_path.clone();
    let affected_paths = affected_files
        .iter()
        .map(|file| file.relative_path.clone())
        .collect::<HashSet<_>>();
    let mut replacing = state.replacing;
    let mut message = state.replace_message;
    let mut replace_confirmation = state.replace_confirmation;
    let mut revision = state.revision;
    let mut editor_reload = state.editor_reload;
    replacing.set(true);
    message.set(None);
    spawn(async move {
        match bridge
            .request("workspaceSearch.replaceMatches", payload)
            .await
        {
            Ok(result) => {
                message.set(Some(workspace_search_replace_message(&result)));
                let generation = editor_reload
                    .read()
                    .as_ref()
                    .map_or(1, |request| request.generation.saturating_add(1));
                editor_reload.set(Some(EditorReloadRequest {
                    generation,
                    workspace_path,
                    relative_paths: affected_paths,
                }));
                let next = revision.read().saturating_add(1);
                revision.set(next);
            }
            Err(error) => message.set(Some(error)),
        }
        replace_confirmation.set(None);
        replacing.set(false);
    });
}

#[derive(Clone, Debug)]
struct GitChangeView {
    path: String,
    old_path: Option<String>,
    area: String,
    status: String,
    added: Option<u64>,
    removed: Option<u64>,
}

#[derive(Clone, Debug)]
enum SourceTreeRowView {
    Directory {
        path: String,
        name: String,
        depth: usize,
        file_count: usize,
    },
    File {
        change: GitChangeView,
        depth: usize,
    },
}

fn source_tree_rows(entries: Vec<GitChangeView>, tree_mode: bool) -> Vec<SourceTreeRowView> {
    if !tree_mode {
        return entries
            .into_iter()
            .map(|change| SourceTreeRowView::File { change, depth: 0 })
            .collect();
    }
    let mut directories = BTreeSet::new();
    for entry in &entries {
        let components = entry.path.split('/').collect::<Vec<_>>();
        for depth in 0..components.len().saturating_sub(1) {
            directories.insert(components[..=depth].join("/"));
        }
    }
    let mut paths = entries
        .iter()
        .map(|entry| entry.path.clone())
        .chain(directories.iter().cloned())
        .collect::<Vec<_>>();
    paths.sort();
    paths
        .into_iter()
        .filter_map(|path| {
            if directories.contains(&path) {
                Some(SourceTreeRowView::Directory {
                    name: path.rsplit('/').next().unwrap_or(&path).to_string(),
                    depth: path.matches('/').count(),
                    file_count: entries
                        .iter()
                        .filter(|entry| entry.path.starts_with(&format!("{path}/")))
                        .count(),
                    path,
                })
            } else {
                entries
                    .iter()
                    .find(|entry| entry.path == path)
                    .cloned()
                    .map(|change| SourceTreeRowView::File {
                        depth: change.path.matches('/').count(),
                        change,
                    })
            }
        })
        .collect()
}

fn source_tree_ancestor_keys(area: &str, path: &str) -> Vec<String> {
    let components = path.split('/').collect::<Vec<_>>();
    (0..components.len().saturating_sub(1))
        .map(|depth| format!("{area}:{}", components[..=depth].join("/")))
        .collect()
}

#[derive(Clone, Debug)]
struct GitSnapshotView {
    branch: String,
    upstream: Option<String>,
    ahead: u64,
    behind: u64,
    has_conflicts: bool,
    head_message: Option<String>,
    history_count: usize,
    history: Vec<GitHistoryView>,
    history_has_more: bool,
    history_current_ref_id: Option<String>,
    history_current_revision: Option<String>,
    history_remote_ref_id: Option<String>,
    history_base_ref_id: Option<String>,
    stash_count: usize,
    stashes: Vec<GitStashView>,
    changes: Vec<GitChangeView>,
    branches: Vec<String>,
}

#[derive(Clone, Debug)]
struct GitHistoryView {
    full_id: String,
    parent_ids: Vec<String>,
    subject: String,
    message: String,
    author: String,
    timestamp_millis: Option<i64>,
    references: Vec<GitHistoryRefView>,
}

#[derive(Clone, Debug)]
struct GitCommitChangeView {
    path: String,
    old_path: Option<String>,
    status: String,
    added: Option<u64>,
    removed: Option<u64>,
}

#[derive(Clone, Debug)]
struct GitStashView {
    index: u32,
    reference: String,
    message: String,
}

#[derive(Clone, Debug)]
struct GitHistoryRefView {
    id: String,
    name: String,
}

fn parse_git_snapshot(value: &Value) -> GitSnapshotView {
    let changes = value
        .get("changes")
        .and_then(Value::as_array)
        .into_iter()
        .flatten()
        .filter_map(|change| {
            Some(GitChangeView {
                path: change.get("path")?.as_str()?.to_string(),
                old_path: change
                    .get("oldPath")
                    .and_then(Value::as_str)
                    .map(str::to_string),
                area: change
                    .get("area")
                    .and_then(Value::as_str)
                    .unwrap_or("unstaged")
                    .to_string(),
                status: change
                    .get("status")
                    .and_then(Value::as_str)
                    .unwrap_or("Modified")
                    .to_string(),
                added: change.get("added").and_then(Value::as_u64),
                removed: change.get("removed").and_then(Value::as_u64),
            })
        })
        .collect();
    let history = value
        .get("history")
        .and_then(Value::as_array)
        .into_iter()
        .flatten()
        .map(|item| {
            let id = item
                .get("id")
                .and_then(Value::as_str)
                .unwrap_or_default()
                .to_string();
            GitHistoryView {
                full_id: item
                    .get("fullId")
                    .and_then(Value::as_str)
                    .unwrap_or(&id)
                    .to_string(),
                parent_ids: item
                    .get("parentIds")
                    .and_then(Value::as_array)
                    .into_iter()
                    .flatten()
                    .filter_map(Value::as_str)
                    .map(str::to_string)
                    .collect(),
                subject: item
                    .get("subject")
                    .and_then(Value::as_str)
                    .unwrap_or("Commit")
                    .to_string(),
                message: item
                    .get("message")
                    .and_then(Value::as_str)
                    .unwrap_or_default()
                    .to_string(),
                author: item
                    .get("author")
                    .and_then(Value::as_str)
                    .unwrap_or_default()
                    .to_string(),
                timestamp_millis: item.get("timestampMillis").and_then(Value::as_i64),
                references: item
                    .get("references")
                    .and_then(Value::as_array)
                    .into_iter()
                    .flatten()
                    .filter_map(|reference| {
                        Some(GitHistoryRefView {
                            id: reference.get("id")?.as_str()?.to_string(),
                            name: reference
                                .get("name")
                                .and_then(Value::as_str)
                                .unwrap_or_default()
                                .to_string(),
                        })
                    })
                    .collect(),
            }
        })
        .collect::<Vec<_>>();
    let history_metadata = value.get("historyMetadata");
    let history_ref = |name: &str| {
        history_metadata
            .and_then(|metadata| metadata.get(name))
            .filter(|reference| !reference.is_null())
    };
    let mut branches = value
        .get("history")
        .and_then(Value::as_array)
        .into_iter()
        .flatten()
        .flat_map(|item| item.get("references").and_then(Value::as_array))
        .flatten()
        .filter(|reference| {
            reference
                .get("category")
                .and_then(Value::as_str)
                .is_some_and(|category| category.eq_ignore_ascii_case("branches"))
        })
        .filter_map(|reference| {
            reference
                .get("name")
                .and_then(Value::as_str)
                .map(str::to_string)
        })
        .collect::<Vec<_>>();
    if let Some(branch) = value.get("branch").and_then(Value::as_str)
        && !branches.iter().any(|candidate| candidate == branch)
    {
        branches.insert(0, branch.to_string());
    }
    branches.sort();
    branches.dedup();
    let stashes = value
        .get("stashes")
        .and_then(Value::as_array)
        .into_iter()
        .flatten()
        .map(|stash| GitStashView {
            index: stash
                .get("index")
                .and_then(Value::as_u64)
                .unwrap_or_default() as u32,
            reference: stash
                .get("reference")
                .and_then(Value::as_str)
                .unwrap_or("stash")
                .to_string(),
            message: stash
                .get("message")
                .and_then(Value::as_str)
                .unwrap_or_default()
                .to_string(),
        })
        .collect::<Vec<_>>();
    GitSnapshotView {
        branch: value
            .get("branch")
            .and_then(Value::as_str)
            .unwrap_or("main")
            .to_string(),
        upstream: value
            .get("upstream")
            .and_then(Value::as_str)
            .map(str::to_string),
        ahead: value.get("ahead").and_then(Value::as_u64).unwrap_or(0),
        behind: value.get("behind").and_then(Value::as_u64).unwrap_or(0),
        has_conflicts: value
            .get("hasConflicts")
            .and_then(Value::as_bool)
            .unwrap_or(false),
        head_message: value
            .get("headMessage")
            .and_then(Value::as_str)
            .map(str::to_string),
        history_count: history.len(),
        history,
        history_has_more: history_metadata
            .and_then(|metadata| metadata.get("hasMore"))
            .and_then(Value::as_bool)
            .unwrap_or(false),
        history_current_ref_id: history_ref("currentRef")
            .and_then(|reference| reference.get("id"))
            .and_then(Value::as_str)
            .map(str::to_string),
        history_current_revision: history_ref("currentRef")
            .and_then(|reference| reference.get("revision"))
            .and_then(Value::as_str)
            .map(str::to_string),
        history_remote_ref_id: history_ref("remoteRef")
            .and_then(|reference| reference.get("id"))
            .and_then(Value::as_str)
            .map(str::to_string),
        history_base_ref_id: history_ref("baseRef")
            .and_then(|reference| reference.get("id"))
            .and_then(Value::as_str)
            .map(str::to_string),
        stash_count: stashes.len(),
        stashes,
        changes,
        branches,
    }
}

fn parse_git_commit_changes(value: &Value) -> Result<Vec<GitCommitChangeView>, String> {
    value
        .get("files")
        .and_then(Value::as_array)
        .ok_or_else(|| "Workspace Git Commit Compare Omitted Files.".to_string())?
        .iter()
        .map(|entry| {
            Ok(GitCommitChangeView {
                path: entry
                    .get("path")
                    .and_then(Value::as_str)
                    .ok_or_else(|| "Commit File Omitted Path.".to_string())?
                    .to_string(),
                old_path: entry
                    .get("oldPath")
                    .and_then(Value::as_str)
                    .map(str::to_string),
                status: entry
                    .get("status")
                    .and_then(Value::as_str)
                    .unwrap_or("Modified")
                    .to_string(),
                added: entry.get("added").and_then(Value::as_u64),
                removed: entry.get("removed").and_then(Value::as_u64),
            })
        })
        .collect()
}

fn format_git_history_time(timestamp_millis: i64) -> String {
    DateTime::from_timestamp_millis(timestamp_millis)
        .map(|time| {
            time.with_timezone(&Local)
                .format("%Y-%m-%d %H:%M")
                .to_string()
        })
        .unwrap_or_default()
}

fn source_control_primary_action(
    git: &GitSnapshotView,
    commit_message: &str,
) -> SourceControlAction {
    let has_staged = git
        .changes
        .iter()
        .any(|change| change.area.eq_ignore_ascii_case("staged"));
    let has_stageable = git.changes.iter().any(|change| {
        change.area.eq_ignore_ascii_case("unstaged")
            || change.area.eq_ignore_ascii_case("untracked")
    });
    if has_staged && !commit_message.trim().is_empty() {
        SourceControlAction::Commit
    } else if git.has_conflicts {
        SourceControlAction::Fetch
    } else if git.upstream.is_none() && git.branch != "HEAD" {
        SourceControlAction::PublishBranch
    } else if git.ahead > 0 && git.behind > 0 {
        SourceControlAction::Sync
    } else if git.behind > 0 {
        SourceControlAction::Pull
    } else if git.ahead > 0 {
        SourceControlAction::Push
    } else if has_stageable {
        SourceControlAction::StageAll
    } else {
        SourceControlAction::Fetch
    }
}

fn source_control_menu_entries(git: &GitSnapshotView) -> Vec<SourceControlMenuEntry> {
    let has_staged = git
        .changes
        .iter()
        .any(|change| change.area.eq_ignore_ascii_case("staged"));
    let has_stageable = git.changes.iter().any(|change| {
        change.area.eq_ignore_ascii_case("unstaged")
            || change.area.eq_ignore_ascii_case("untracked")
    });
    let has_discardable = git
        .changes
        .iter()
        .any(|change| !change.area.eq_ignore_ascii_case("staged"));
    let has_upstream = git.upstream.is_some();
    let can_publish = !has_upstream && git.branch != "HEAD";
    [
        (
            SourceControlAction::Commit,
            has_staged && !git.has_conflicts,
            false,
        ),
        (
            SourceControlAction::CommitPush,
            has_staged && !git.has_conflicts,
            false,
        ),
        (
            SourceControlAction::CommitSync,
            has_staged && !git.has_conflicts && has_upstream,
            false,
        ),
        (
            SourceControlAction::Amend,
            has_staged && !git.has_conflicts && git.history_count > 0,
            false,
        ),
        (SourceControlAction::StageAll, has_stageable, true),
        (SourceControlAction::UnstageAll, has_staged, false),
        (SourceControlAction::DiscardAll, has_discardable, false),
        (SourceControlAction::Fetch, true, true),
        (SourceControlAction::Pull, true, false),
        (SourceControlAction::Push, !git.has_conflicts, false),
        (
            SourceControlAction::Sync,
            !git.has_conflicts && has_upstream,
            false,
        ),
        (SourceControlAction::PublishBranch, can_publish, false),
        (SourceControlAction::Stash, has_discardable, true),
        (SourceControlAction::StashPop, git.stash_count > 0, false),
    ]
    .into_iter()
    .map(
        |(action, enabled, separator_before)| SourceControlMenuEntry {
            action,
            enabled,
            separator_before,
        },
    )
    .collect()
}

fn dispatch_source_control_action(
    bridge: &RuntimeBridge,
    workspace_path: &str,
    action: SourceControlAction,
    commit_message: &str,
    head_message: Option<&str>,
) -> bool {
    let send = |name: &'static str, message: Option<String>, index: Option<u32>| {
        bridge
            .send_ordered(
                "workspaceGit.action",
                json!({
                    "workspacePath": workspace_path,
                    "action": name,
                    "message": message,
                    "index": index,
                }),
            )
            .is_ok()
    };
    let message = commit_message.trim();
    match action {
        SourceControlAction::Commit => {
            !message.is_empty() && send("commit", Some(message.to_string()), None)
        }
        SourceControlAction::CommitPush => {
            !message.is_empty()
                && send("commit", Some(message.to_string()), None)
                && send("push", None, None)
        }
        SourceControlAction::CommitSync => {
            !message.is_empty()
                && send("commit", Some(message.to_string()), None)
                && send("sync", None, None)
        }
        SourceControlAction::Amend => {
            let amend_message = (!message.is_empty())
                .then(|| message.to_string())
                .or_else(|| head_message.map(str::to_string));
            amend_message.is_some() && send("amend", amend_message, None)
        }
        SourceControlAction::StageAll => send("stageAll", None, None),
        SourceControlAction::UnstageAll => send("unstageAll", None, None),
        SourceControlAction::DiscardAll => send("discardAll", None, None),
        SourceControlAction::Fetch => send("fetch", None, None),
        SourceControlAction::Pull => send("pull", None, None),
        SourceControlAction::Push | SourceControlAction::PublishBranch => send("push", None, None),
        SourceControlAction::Sync => send("sync", None, None),
        SourceControlAction::Stash => send("stash", None, None),
        SourceControlAction::StashPop => send("stashPop", None, Some(0)),
    }
}

fn dispatch_source_path_action(
    bridge: RuntimeBridge,
    workspace_path: String,
    paths: Vec<String>,
    action: &'static str,
    refresh_revision: State<u64>,
) {
    let mut refresh = refresh_revision;
    spawn(async move {
        let mut succeeded = true;
        for path in paths {
            if bridge
                .request(
                    "workspaceGit.action",
                    json!({
                        "workspacePath": workspace_path,
                        "action": action,
                        "path": path,
                        "message": null,
                        "index": null,
                    }),
                )
                .await
                .is_err()
            {
                succeeded = false;
                break;
            }
        }
        if succeeded {
            let next = refresh.read().saturating_add(1);
            refresh.set(next);
        }
    });
}

fn source_control_state_message(message: String, loading: bool) -> Element {
    rect()
        .width(Size::fill())
        .height(Size::fill())
        .center()
        .padding(Gaps::new_all(20.))
        .child(
            rect()
                .vertical()
                .cross_align(Alignment::Center)
                .spacing(9.)
                .maybe_child(loading.then(|| CircularLoader::new().size(16.)))
                .child(
                    label()
                        .font_size(11.)
                        .color(MUTED)
                        .max_lines(5)
                        .text_align(TextAlign::Center)
                        .text(message),
                ),
        )
        .into_element()
}

fn toggle_commit_message_generation(
    bridge: RuntimeBridge,
    workspace_path: String,
    commit_message: State<String>,
    state: AiTextGenerationState,
    can_generate: bool,
) {
    if *state.busy.read() {
        let Some(operation_id) = state.operation_id.read().clone() else {
            return;
        };
        let mut message = state.message;
        spawn(async move {
            if bridge
                .request("aiText.cancel", json!({"operationId": operation_id}))
                .await
                .is_ok()
            {
                message.set(Some("AI Commit Message Generation Canceled".to_string()));
            }
        });
        return;
    }
    if !can_generate {
        let mut message = state.message;
        message.set(Some(
            "Stage Changes Before Generating A Commit Message".to_string(),
        ));
        return;
    }

    let operation_id = format!("freya-commit-{}", Uuid::new_v4());
    let initial_text = commit_message.read().clone();
    let mut busy = state.busy;
    let mut operation = state.operation_id;
    let mut message = state.message;
    busy.set(true);
    operation.set(Some(operation_id.clone()));
    message.set(None);
    spawn(async move {
        let result = bridge
            .request_with_timeout(
                "aiText.commitMessage.generate",
                json!({
                    "operationId": operation_id.clone(),
                    "workspacePath": workspace_path,
                }),
                Duration::from_secs(600),
            )
            .await;
        if operation.peek().as_deref() != Some(operation_id.as_str()) {
            return;
        }
        busy.set(false);
        operation.set(None);
        match result {
            Ok(value) => {
                let generated = value
                    .get("text")
                    .and_then(Value::as_str)
                    .unwrap_or_default()
                    .to_string();
                let agent = value
                    .get("agentLabel")
                    .and_then(Value::as_str)
                    .unwrap_or("AI");
                if *commit_message.peek() == initial_text {
                    let mut commit_message = commit_message;
                    commit_message.set(generated);
                    message.set(Some(format!("Commit Message Generated With {agent}")));
                } else {
                    message.set(Some(
                        "Generated Message Was Not Applied Because The Field Changed".to_string(),
                    ));
                }
            }
            Err(error) if error.contains("was canceled") => message.set(None),
            Err(error) => message.set(Some(error)),
        }
    });
}

fn clean_generated_text(raw: &str) -> String {
    let mut text = raw.replace("\r\n", "\n").trim().to_owned();
    if let Some((first, rest)) = text.clone().split_once('\n') {
        let first = first.trim().to_ascii_lowercase();
        if first.starts_with("generating")
            || first.starts_with("thinking")
            || first
                .chars()
                .all(|character| matches!(character, '.' | '…'))
        {
            text = rest.trim().to_owned();
        }
    }
    if text.starts_with("```")
        && text.ends_with("```")
        && let Some(first_newline) = text.find('\n')
    {
        text = text[first_newline + 1..text.len() - 3].trim().to_owned();
    }
    let trimmed = text.trim_start();
    for prefix in ["- ", "* "] {
        if let Some(value) = trimmed.strip_prefix(prefix) {
            return value.trim().to_owned();
        }
    }
    text.trim().to_owned()
}

fn parse_pull_request_details(raw: &str) -> (String, String) {
    let normalized = clean_generated_text(raw);
    let mut lines = normalized.lines();
    let subject = lines
        .next()
        .unwrap_or_default()
        .trim()
        .trim_end_matches('.');
    let title = if subject.is_empty() {
        "Update Project".to_owned()
    } else {
        subject
            .chars()
            .take(72)
            .collect::<String>()
            .trim()
            .to_owned()
    };
    let body = lines.collect::<Vec<_>>().join("\n").trim().to_owned();
    (title, body)
}

#[allow(clippy::too_many_arguments)]
fn toggle_pull_request_generation(
    bridge: RuntimeBridge,
    workspace_path: String,
    head_branch: String,
    title: State<String>,
    body: State<String>,
    base: State<String>,
    state: AiTextGenerationState,
    can_generate: bool,
) {
    if *state.busy.read() {
        let Some(operation_id) = state.operation_id.read().clone() else {
            return;
        };
        let mut message = state.message;
        spawn(async move {
            if bridge
                .request("aiText.cancel", json!({"operationId": operation_id}))
                .await
                .is_ok()
            {
                message.set(Some(
                    "AI Pull Request Details Generation Canceled".to_string(),
                ));
            }
        });
        return;
    }
    if !can_generate {
        let mut message = state.message;
        message.set(Some("Base Branch Is Required".to_string()));
        return;
    }

    let operation_id = format!("freya-pull-request-{}", Uuid::new_v4());
    let initial_title = title.read().clone();
    let initial_body = body.read().clone();
    let base_branch = base.read().trim().to_string();
    let mut busy = state.busy;
    let mut operation = state.operation_id;
    let mut message = state.message;
    busy.set(true);
    operation.set(Some(operation_id.clone()));
    message.set(None);
    spawn(async move {
        let result = bridge
            .request_with_timeout(
                "aiText.pullRequestDetails.generate",
                json!({
                    "operationId": operation_id.clone(),
                    "workspacePath": workspace_path,
                    "baseBranch": base_branch,
                    "headBranch": head_branch,
                }),
                Duration::from_secs(600),
            )
            .await;
        if operation.peek().as_deref() != Some(operation_id.as_str()) {
            return;
        }
        busy.set(false);
        operation.set(None);
        match result {
            Ok(value) => {
                let generated = value
                    .get("text")
                    .and_then(Value::as_str)
                    .unwrap_or_default();
                let (generated_title, generated_body) = parse_pull_request_details(generated);
                let agent = value
                    .get("agentLabel")
                    .and_then(Value::as_str)
                    .unwrap_or("AI");
                if *title.peek() == initial_title && *body.peek() == initial_body {
                    let mut title = title;
                    let mut body = body;
                    title.set(generated_title);
                    body.set(generated_body);
                    message.set(Some(format!("Pull Request Details Generated With {agent}")));
                } else {
                    message.set(Some(
                        "Generated Details Were Not Applied Because The Fields Changed".to_string(),
                    ));
                }
            }
            Err(error) if error.contains("was canceled") => message.set(None),
            Err(error) => message.set(Some(error)),
        }
    });
}

#[allow(clippy::too_many_arguments)]
fn context_source_control_panel(
    bridge: RuntimeBridge,
    source_control_scope: SourceControlScopeView,
    snapshot: State<Option<Result<GitSnapshotView, String>>>,
    refresh_revision: State<u64>,
    git_loading: State<bool>,
    menu_state: State<SourceMenuState>,
    action_hover: State<Option<&'static str>>,
    toolbar_hover: State<Option<&'static str>>,
    file_action_hover: State<Option<String>>,
    menu_hover: State<Option<SourceControlAction>>,
    filter_visible: State<bool>,
    tree_mode: State<bool>,
    all_collapsed: State<bool>,
    collapsed_areas: State<HashSet<String>>,
    collapsed_tree_nodes: State<HashSet<String>>,
    history_expanded: State<bool>,
    history_expanded_commits: State<HashSet<String>>,
    history_hover: State<Option<String>>,
    history_action_menu: State<Option<String>>,
    history_files: State<HashMap<String, Result<Vec<GitCommitChangeView>, String>>>,
    history_loading: State<HashSet<String>>,
    history_height: State<f32>,
    history_drag_y: State<Option<f64>>,
    source_git_dialog: State<Option<SourceGitDialog>>,
    source_git_dialog_message: State<String>,
    open_git_diff_request: State<Option<docking::GitDiffOpenRequest>>,
    commit_message: State<String>,
    commit_ai: AiTextGenerationState,
    file_filter: State<String>,
    view_prefs_revision: State<u64>,
    context_mode: State<String>,
    source_root_message: State<Option<String>>,
) -> Element {
    let working_directory = source_control_scope.path.clone();
    let git = match snapshot.read().as_ref() {
        Some(Ok(snapshot)) => snapshot.clone(),
        Some(Err(error)) => return source_control_state_message(error.clone(), false),
        None => return source_control_state_message("Loading Source Control".to_string(), true),
    };
    let mut summary_parts = source_control_scope
        .relative_root
        .clone()
        .into_iter()
        .chain(std::iter::once(git.branch.clone()))
        .collect::<Vec<_>>();
    if let Some(upstream) = git.upstream.clone() {
        summary_parts.push(upstream);
    }
    if git.ahead > 0 {
        summary_parts.push(format!("Ahead {}", git.ahead));
    }
    if git.behind > 0 {
        summary_parts.push(format!("Behind {}", git.behind));
    }
    if git.has_conflicts {
        summary_parts.push("Conflicts".to_string());
    }
    let branch_summary = summary_parts.join(" · ");
    let message_snapshot = commit_message.read().clone();
    let primary_action = source_control_primary_action(&git, &message_snapshot);
    let filter_query = file_filter.read().trim().to_lowercase();
    let changes_snapshot = git
        .changes
        .iter()
        .filter(|change| {
            filter_query.is_empty() || change.path.to_lowercase().contains(&filter_query)
        })
        .cloned()
        .collect::<Vec<_>>();
    let bridge_for_action = bridge.clone();
    let path_for_action = working_directory.clone();
    let mut refresh_for_primary = refresh_revision;
    let primary_bridge = bridge_for_action.clone();
    let primary_path = path_for_action.clone();
    let primary_message = message_snapshot.clone();
    let primary_head_message = git.head_message.clone();
    let mut run_primary = move || {
        if dispatch_source_control_action(
            &primary_bridge,
            &primary_path,
            primary_action,
            &primary_message,
            primary_head_message.as_deref(),
        ) {
            let next_revision = refresh_for_primary.read().saturating_add(1);
            refresh_for_primary.set(next_revision);
        }
    };
    let mut menu_for_right = menu_state;
    let primary_hovered = action_hover() == Some("primary");
    let menu_hovered = action_hover() == Some("menu");
    let mut hover_for_primary_enter = action_hover;
    let mut hover_for_primary_leave = action_hover;
    let mut hover_for_menu_enter = action_hover;
    let mut hover_for_menu_leave = action_hover;
    let mut filter_for_button = filter_visible;
    let mut tree_mode_for_button = tree_mode;
    let tree_mode_enabled = tree_mode();
    let mut collapsed_for_button = all_collapsed;
    let all_collapsed_now = all_collapsed();
    let git_loading_now = git_loading();
    let commit_ai_busy = *commit_ai.busy.read();
    let can_generate_commit = !git.has_conflicts
        && !git_loading_now
        && git
            .changes
            .iter()
            .any(|change| change.area.eq_ignore_ascii_case("staged"));
    let ai_bridge = bridge.clone();
    let ai_workspace = working_directory.clone();
    let commit_message_for_ai = commit_message;
    let commit_ai_for_action = commit_ai;
    let mut refresh_for_toolbar = refresh_revision;
    let mut open_all_changes = open_git_diff_request;
    let scope_for_open_all = source_control_scope.clone();
    let toolbar_button = |icon: Bytes,
                          tooltip: &'static str,
                          loading: bool,
                          action: EventHandler<Event<PointerEventData>>| {
        let hovered = toolbar_hover() == Some(tooltip);
        let mut hover_for_enter = toolbar_hover;
        let mut hover_for_leave = toolbar_hover;
        TooltipContainer::new(Tooltip::new_text(tooltip))
            .position(AttachedPosition::Bottom)
            .delay(Duration::from_millis(350))
            .child(
                rect()
                    .width(Size::px(24.))
                    .height(Size::px(24.))
                    .center()
                    .background(if hovered { (48, 48, 48) } else { SURFACE })
                    .corner_radius(4.)
                    .a11y_role(AccessibilityRole::Button)
                    .a11y_alt(tooltip)
                    .on_pointer_enter(move |_| {
                        Cursor::set(CursorIcon::Pointer);
                        hover_for_enter.set(Some(tooltip));
                    })
                    .on_pointer_leave(move |_| {
                        Cursor::set(CursorIcon::default());
                        hover_for_leave.set(None);
                    })
                    .on_pointer_down(action)
                    .child(rect().interactive(false).child(if loading {
                        CircularLoader::new().size(14.).into_element()
                    } else {
                        SvgViewer::new(icon)
                            .width(Size::px(14.))
                            .height(Size::px(14.))
                            .color(MUTED)
                            .into_element()
                    })),
            )
            .into_element()
    };
    let clear_root_button = source_control_scope.relative_root.is_some().then(|| {
        let bridge = bridge.clone();
        let workspace_id = source_control_scope.workspace_id.clone();
        let workspace_path = source_control_scope.workspace_path.clone();
        let mut revision = view_prefs_revision;
        let mut mode = context_mode;
        let mut message = source_root_message;
        toolbar_button(
            icons::lucide::x(),
            "Clear Source Control Root",
            false,
            EventHandler::new(move |event: Event<PointerEventData>| {
                event.stop_propagation();
                let bridge = bridge.clone();
                let workspace_id = workspace_id.clone();
                let workspace_path = workspace_path.clone();
                spawn(async move {
                    match update_source_control_root(
                        &bridge,
                        Some(&workspace_id),
                        &workspace_path,
                        None,
                    )
                    .await
                    {
                        Ok(()) => {
                            message.set(None);
                            let next = revision.read().saturating_add(1);
                            revision.set(next);
                            mode.set("Explorer".to_string());
                        }
                        Err(error) => message.set(Some(error)),
                    }
                });
            }),
        )
    });
    let primary_label = primary_action.label();
    let primary_icon = primary_action.icon();
    let action_button = rect()
        .width(Size::fill())
        .height(Size::px(28.))
        .background((232, 232, 232))
        .corner_radius(8.)
        .overflow(Overflow::Clip)
        .horizontal()
        .content(Content::Flex)
        .cross_align(Alignment::Center)
        .child(
            rect()
                .width(Size::flex(1.))
                .height(Size::fill())
                .center()
                .background(if primary_hovered {
                    (220, 220, 220)
                } else {
                    (232, 232, 232)
                })
                .a11y_role(AccessibilityRole::Button)
                .a11y_alt(primary_label)
                .on_pointer_enter(move |_| {
                    Cursor::set(CursorIcon::Pointer);
                    hover_for_primary_enter.set(Some("primary"));
                })
                .on_pointer_leave(move |_| {
                    Cursor::set(CursorIcon::default());
                    hover_for_primary_leave.set(None);
                })
                .on_pointer_down(move |event: Event<PointerEventData>| {
                    event.stop_propagation();
                    run_primary();
                })
                .child(
                    rect()
                        .interactive(false)
                        .horizontal()
                        .cross_align(Alignment::Center)
                        .spacing(8.)
                        .child(
                            SvgViewer::new(primary_icon)
                                .width(Size::px(15.))
                                .height(Size::px(15.))
                                .color((20, 20, 20)),
                        )
                        .child(
                            label()
                                .font_size(13.)
                                .color((20, 20, 20))
                                .text(primary_label),
                        ),
                ),
        )
        .child(
            rect()
                .width(Size::px(0.5))
                .height(Size::px(18.))
                .background((170, 170, 170))
                .interactive(false),
        )
        .child(
            rect()
                .width(Size::px(34.))
                .height(Size::fill())
                .center()
                .background(if menu_hovered {
                    (220, 220, 220)
                } else {
                    (232, 232, 232)
                })
                .a11y_role(AccessibilityRole::Button)
                .a11y_alt("Source Control Actions")
                .on_pointer_enter(move |_| {
                    Cursor::set(CursorIcon::Pointer);
                    hover_for_menu_enter.set(Some("menu"));
                })
                .on_pointer_leave(move |_| {
                    Cursor::set(CursorIcon::default());
                    hover_for_menu_leave.set(None);
                })
                .on_pointer_down(move |event: Event<PointerEventData>| {
                    event.stop_propagation();
                    let current = *menu_for_right.read();
                    menu_for_right.set(if current.open {
                        SourceMenuState::default()
                    } else {
                        SourceMenuState { open: true }
                    });
                })
                .child(
                    rect().interactive(false).child(
                        SvgViewer::new(icons::lucide::chevron_down())
                            .width(Size::px(17.))
                            .height(Size::px(17.))
                            .color((20, 20, 20)),
                    ),
                ),
        );
    let changes_empty = changes_snapshot.is_empty();
    let mut changes = rect().width(Size::fill()).vertical().spacing(2.);
    for (area, title) in [
        ("staged", "Staged"),
        ("unstaged", "Unstaged"),
        ("untracked", "Untracked"),
    ] {
        let group = changes_snapshot
            .iter()
            .filter(|change| change.area.eq_ignore_ascii_case(area))
            .cloned()
            .collect::<Vec<_>>();
        if group.is_empty() {
            continue;
        }
        let area_collapsed = all_collapsed() || collapsed_areas.read().contains(area);
        let mut collapsed_for_area = collapsed_areas;
        let area_for_toggle = area.to_string();
        let staged_group = area == "staged";
        let mut group_paths = Vec::new();
        for change in &group {
            if change.status.eq_ignore_ascii_case("renamed")
                && let Some(old_path) = change
                    .old_path
                    .as_ref()
                    .filter(|old_path| *old_path != &change.path)
            {
                group_paths.push(old_path.clone());
            }
            group_paths.push(change.path.clone());
        }
        let group_stage_label = if staged_group { "Unstage" } else { "Stage" };
        let group_stage_action = if staged_group {
            "unstagePath"
        } else {
            "stagePath"
        };
        let mut group_stage_hover = file_action_hover;
        let mut group_stage_leave = file_action_hover;
        let group_stage_key = format!("Group {group_stage_label}:{area}");
        let group_stage_key_for_enter = group_stage_key.clone();
        let group_stage_hovered =
            file_action_hover.read().as_deref() == Some(group_stage_key.as_str());
        let bridge_for_group_stage = bridge.clone();
        let workspace_for_group_stage = working_directory.clone();
        let paths_for_group_stage = group_paths.clone();
        let refresh_for_group_stage = refresh_revision;
        let group_stage_button = TooltipContainer::new(Tooltip::new_text(group_stage_label))
            .position(AttachedPosition::Top)
            .delay(Duration::from_millis(350))
            .child(
                rect()
                    .width(Size::px(24.))
                    .height(Size::px(24.))
                    .center()
                    .corner_radius(4.)
                    .background(if group_stage_hovered {
                        (48, 48, 48)
                    } else {
                        SURFACE
                    })
                    .a11y_role(AccessibilityRole::Button)
                    .a11y_alt(group_stage_label)
                    .on_pointer_enter(move |_| {
                        Cursor::set(CursorIcon::Pointer);
                        group_stage_hover.set(Some(group_stage_key_for_enter.clone()));
                    })
                    .on_pointer_leave(move |_| {
                        Cursor::set(CursorIcon::default());
                        group_stage_leave.set(None);
                    })
                    .on_pointer_down(move |event: Event<PointerEventData>| {
                        event.stop_propagation();
                        dispatch_source_path_action(
                            bridge_for_group_stage.clone(),
                            workspace_for_group_stage.clone(),
                            paths_for_group_stage.clone(),
                            group_stage_action,
                            refresh_for_group_stage,
                        );
                    })
                    .child(
                        SvgViewer::new(if staged_group {
                            alera_icons::git_unstage()
                        } else {
                            alera_icons::git_stage()
                        })
                        .width(Size::px(14.))
                        .height(Size::px(14.))
                        .color(MUTED),
                    ),
            );
        let mut dialog_for_group_discard = source_git_dialog;
        let workspace_for_group_discard = working_directory.clone();
        let paths_for_group_discard = group_paths.clone();
        let area_for_group_discard = area.to_string();
        let group_discard_button = (!staged_group).then(|| {
            TooltipContainer::new(Tooltip::new_text("Discard"))
                .position(AttachedPosition::Top)
                .delay(Duration::from_millis(350))
                .child(
                    rect()
                        .width(Size::px(24.))
                        .height(Size::px(24.))
                        .center()
                        .corner_radius(4.)
                        .a11y_role(AccessibilityRole::Button)
                        .a11y_alt("Discard")
                        .on_pointer_enter(|_| Cursor::set(CursorIcon::Pointer))
                        .on_pointer_leave(|_| Cursor::set(CursorIcon::default()))
                        .on_pointer_down(move |event: Event<PointerEventData>| {
                            event.stop_propagation();
                            dialog_for_group_discard.set(Some(SourceGitDialog::DiscardPaths {
                                workspace_path: workspace_for_group_discard.clone(),
                                paths: paths_for_group_discard.clone(),
                                target: area_for_group_discard.clone(),
                            }));
                        })
                        .child(
                            SvgViewer::new(alera_icons::git_discard())
                                .width(Size::px(14.))
                                .height(Size::px(14.))
                                .color(MUTED),
                        ),
                )
                .into_element()
        });
        changes = changes.child(
            rect()
                .width(Size::fill())
                .height(Size::px(28.))
                .horizontal()
                .cross_align(Alignment::Center)
                .spacing(4.)
                .a11y_role(AccessibilityRole::Button)
                .a11y_alt(title)
                .on_pointer_enter(|_| Cursor::set(CursorIcon::Pointer))
                .on_pointer_leave(|_| Cursor::set(CursorIcon::default()))
                .on_pointer_down(move |event: Event<PointerEventData>| {
                    event.stop_propagation();
                    let mut next = collapsed_for_area.read().clone();
                    if !next.insert(area_for_toggle.clone()) {
                        next.remove(&area_for_toggle);
                    }
                    collapsed_for_area.set(next);
                })
                .child(
                    SvgViewer::new(if area_collapsed {
                        icons::lucide::chevron_right()
                    } else {
                        icons::lucide::chevron_down()
                    })
                    .width(Size::px(13.))
                    .height(Size::px(13.))
                    .color(MUTED),
                )
                .child(label().font_size(11.).color(MUTED).text(title))
                .child(
                    label()
                        .font_size(10.)
                        .color(FAINT)
                        .text(group.len().to_string()),
                )
                .child(
                    rect()
                        .width(Size::px(58.))
                        .horizontal()
                        .main_align(Alignment::End)
                        .child(group_stage_button)
                        .maybe_child(group_discard_button),
                ),
        );
        if !area_collapsed {
            for tree_row in source_tree_rows(group, tree_mode()) {
                let (change, depth) = match tree_row {
                    SourceTreeRowView::Directory {
                        path,
                        name,
                        depth,
                        file_count,
                    } => {
                        if source_tree_ancestor_keys(area, &path)
                            .iter()
                            .any(|key| collapsed_tree_nodes.read().contains(key))
                        {
                            continue;
                        }
                        let tree_key = format!("{area}:{path}");
                        let collapsed = collapsed_tree_nodes.read().contains(&tree_key);
                        let mut collapsed_for_directory = collapsed_tree_nodes;
                        let tree_key_for_toggle = tree_key.clone();
                        changes = changes.child(
                            rect()
                                .width(Size::fill())
                                .height(Size::px(30.))
                                .padding(Gaps::new(6. + depth as f32 * 12., 3., 6., 3.))
                                .horizontal()
                                .content(Content::Flex)
                                .cross_align(Alignment::Center)
                                .spacing(5.)
                                .a11y_role(AccessibilityRole::Button)
                                .a11y_alt(format!("{name} Folder"))
                                .on_pointer_enter(|_| Cursor::set(CursorIcon::Pointer))
                                .on_pointer_leave(|_| Cursor::set(CursorIcon::default()))
                                .on_pointer_down(move |event: Event<PointerEventData>| {
                                    event.stop_propagation();
                                    let mut next = collapsed_for_directory.read().clone();
                                    if !next.insert(tree_key_for_toggle.clone()) {
                                        next.remove(&tree_key_for_toggle);
                                    }
                                    collapsed_for_directory.set(next);
                                })
                                .child(
                                    SvgViewer::new(if collapsed {
                                        icons::lucide::chevron_right()
                                    } else {
                                        icons::lucide::chevron_down()
                                    })
                                    .width(Size::px(13.))
                                    .height(Size::px(13.))
                                    .color(MUTED),
                                )
                                .child(
                                    SvgViewer::new(icons::lucide::folder())
                                        .width(Size::px(14.))
                                        .height(Size::px(14.))
                                        .color(MUTED),
                                )
                                .child(
                                    label()
                                        .width(Size::flex(1.))
                                        .font_size(12.)
                                        .color(MUTED)
                                        .max_lines(1)
                                        .text_overflow(TextOverflow::Ellipsis)
                                        .text(name),
                                )
                                .child(
                                    label()
                                        .font_size(10.)
                                        .color(FAINT)
                                        .text(file_count.to_string()),
                                ),
                        );
                        continue;
                    }
                    SourceTreeRowView::File { change, depth } => (change, depth),
                };
                if tree_mode()
                    && source_tree_ancestor_keys(area, &change.path)
                        .iter()
                        .any(|key| collapsed_tree_nodes.read().contains(key))
                {
                    continue;
                }
                let status = change.status.to_ascii_lowercase();
                let status_mark = if status.contains("untracked") {
                    "U"
                } else if status.contains("added") {
                    "A"
                } else if status.contains("deleted") {
                    "D"
                } else {
                    "M"
                };
                let display_path = if tree_mode() {
                    change
                        .path
                        .rsplit_once('/')
                        .map(|(_, name)| name.to_string())
                        .unwrap_or_else(|| change.path.clone())
                } else {
                    change.path.clone()
                };
                let mut open_change = open_git_diff_request;
                let scope_for_change = source_control_scope.clone();
                let path_for_change = change.path.clone();
                let area_for_change = change.area.clone();
                let mut action_paths = Vec::new();
                if status.contains("renamed")
                    && let Some(old_path) = change
                        .old_path
                        .as_ref()
                        .filter(|old_path| *old_path != &change.path)
                {
                    action_paths.push(old_path.clone());
                }
                action_paths.push(change.path.clone());
                let staged = change.area.eq_ignore_ascii_case("staged");
                let stage_label = if staged { "Unstage" } else { "Stage" };
                let stage_action = if staged { "unstagePath" } else { "stagePath" };
                let stage_icon = if staged {
                    alera_icons::git_unstage()
                } else {
                    alera_icons::git_stage()
                };
                let stage_hover_key = format!("{stage_label}:{}", change.path);
                let stage_hovered =
                    file_action_hover.read().as_deref() == Some(stage_hover_key.as_str());
                let stage_hover_key_for_enter = stage_hover_key.clone();
                let mut stage_hover_for_enter = file_action_hover;
                let mut stage_hover_for_leave = file_action_hover;
                let bridge_for_stage = bridge.clone();
                let workspace_for_stage = working_directory.clone();
                let paths_for_stage = action_paths.clone();
                let refresh_for_stage = refresh_revision;
                let stage_button = TooltipContainer::new(Tooltip::new_text(stage_label))
                    .position(AttachedPosition::Top)
                    .delay(Duration::from_millis(350))
                    .child(
                        rect()
                            .width(Size::px(24.))
                            .height(Size::px(24.))
                            .center()
                            .corner_radius(4.)
                            .background(if stage_hovered { (48, 48, 48) } else { SURFACE })
                            .a11y_role(AccessibilityRole::Button)
                            .a11y_alt(stage_label)
                            .on_pointer_enter(move |_| {
                                Cursor::set(CursorIcon::Pointer);
                                stage_hover_for_enter.set(Some(stage_hover_key_for_enter.clone()));
                            })
                            .on_pointer_leave(move |_| {
                                Cursor::set(CursorIcon::default());
                                stage_hover_for_leave.set(None);
                            })
                            .on_pointer_down(move |event: Event<PointerEventData>| {
                                event.stop_propagation();
                                dispatch_source_path_action(
                                    bridge_for_stage.clone(),
                                    workspace_for_stage.clone(),
                                    paths_for_stage.clone(),
                                    stage_action,
                                    refresh_for_stage,
                                );
                            })
                            .child(
                                SvgViewer::new(stage_icon)
                                    .width(Size::px(14.))
                                    .height(Size::px(14.))
                                    .color(MUTED),
                            ),
                    );
                let discard_hover_key = format!("Discard:{}", change.path);
                let discard_hovered =
                    file_action_hover.read().as_deref() == Some(discard_hover_key.as_str());
                let discard_hover_key_for_enter = discard_hover_key.clone();
                let mut discard_hover_for_enter = file_action_hover;
                let mut discard_hover_for_leave = file_action_hover;
                let mut dialog_for_discard = source_git_dialog;
                let workspace_for_discard = working_directory.clone();
                let path_for_discard = change.path.clone();
                let discard_button = (!staged).then(|| {
                    TooltipContainer::new(Tooltip::new_text("Discard"))
                        .position(AttachedPosition::Top)
                        .delay(Duration::from_millis(350))
                        .child(
                            rect()
                                .width(Size::px(24.))
                                .height(Size::px(24.))
                                .center()
                                .corner_radius(4.)
                                .background(if discard_hovered {
                                    (48, 48, 48)
                                } else {
                                    SURFACE
                                })
                                .a11y_role(AccessibilityRole::Button)
                                .a11y_alt("Discard")
                                .on_pointer_enter(move |_| {
                                    Cursor::set(CursorIcon::Pointer);
                                    discard_hover_for_enter
                                        .set(Some(discard_hover_key_for_enter.clone()));
                                })
                                .on_pointer_leave(move |_| {
                                    Cursor::set(CursorIcon::default());
                                    discard_hover_for_leave.set(None);
                                })
                                .on_pointer_down(move |event: Event<PointerEventData>| {
                                    event.stop_propagation();
                                    dialog_for_discard.set(Some(SourceGitDialog::DiscardPath {
                                        workspace_path: workspace_for_discard.clone(),
                                        path: path_for_discard.clone(),
                                    }));
                                })
                                .child(
                                    SvgViewer::new(alera_icons::git_discard())
                                        .width(Size::px(14.))
                                        .height(Size::px(14.))
                                        .color(MUTED),
                                ),
                        )
                        .into_element()
                });
                changes = changes.child(
                    rect()
                        .width(Size::fill())
                        .height(Size::px(24.))
                        .horizontal()
                        .content(Content::Flex)
                        .cross_align(Alignment::Center)
                        .padding(Gaps::new(6. + depth as f32 * 12., 3., 6., 3.))
                        .a11y_role(AccessibilityRole::Button)
                        .a11y_alt(format!("Open Diff For {}", change.path))
                        .on_pointer_enter(|_| Cursor::set(CursorIcon::Pointer))
                        .on_pointer_leave(|_| Cursor::set(CursorIcon::default()))
                        .on_pointer_down(move |event: Event<PointerEventData>| {
                            event.stop_propagation();
                            open_change.set(Some(working_tree_diff_request(
                                &scope_for_change,
                                Some(path_for_change.clone()),
                                Some(area_for_change.clone()),
                            )));
                        })
                        .maybe_child(tree_mode().then(|| rect().width(Size::px(18.)).child("")))
                        .child(file_icons::file_icon(
                            &change.path,
                            false,
                            false,
                            false,
                            14.,
                        ))
                        .child(
                            label()
                                .width(Size::flex(1.))
                                .font_size(12.)
                                .color(MUTED)
                                .max_lines(1)
                                .text_overflow(TextOverflow::Ellipsis)
                                .text(display_path),
                        )
                        .child(
                            label()
                                .font_size(12.)
                                .color((226, 166, 78))
                                .text(status_mark),
                        )
                        .maybe_child((change.added.unwrap_or_default() > 0).then(|| {
                            label()
                                .font_size(10.)
                                .color((74, 222, 128))
                                .text(format!("+{}", change.added.unwrap_or_default()))
                        }))
                        .maybe_child((change.removed.unwrap_or_default() > 0).then(|| {
                            label()
                                .font_size(10.)
                                .color((248, 113, 113))
                                .text(format!("-{}", change.removed.unwrap_or_default()))
                        }))
                        .child(stage_button)
                        .maybe_child(discard_button),
                );
            }
        }
    }
    let changes_panel = if changes_empty {
        let empty_message = if filter_query.is_empty() {
            "No Changes"
        } else {
            "No Files Match The Current Filter"
        };
        rect()
            .width(Size::fill())
            .height(Size::flex(1.))
            .position(Position::new_stacked().top(14.))
            .center()
            .child(label().font_size(12.).color(MUTED).text(empty_message))
            .into_element()
    } else {
        ScrollView::new()
            .width(Size::fill())
            .height(Size::flex(1.))
            .show_scrollbar(true)
            .child(changes)
            .into_element()
    };
    let history_panel = source_control_history_panel(
        &git,
        bridge.clone(),
        source_control_scope.clone(),
        history_expanded,
        history_expanded_commits,
        history_hover,
        history_action_menu,
        history_files,
        history_loading,
        history_height,
        history_drag_y,
        git_loading_now,
        refresh_revision,
        open_git_diff_request,
    );
    let refresh_for_menu = refresh_revision;
    let bridge_for_menu = bridge_for_action;
    let path_for_menu = path_for_action;
    let menu_for_option = menu_state;
    let menu_message = message_snapshot;
    let menu_head_message = git.head_message.clone();
    let menu_stashes = git.stashes.clone();
    let dialog_for_option = source_git_dialog;
    let dialog_message_for_option = source_git_dialog_message;
    let menu_visible = menu_state.read().open;
    let mut menu_for_global = menu_state;
    let mut options = rect()
        .position(Position::new_absolute().top(112.).right(0.))
        .layer(Layer::Overlay)
        .width(Size::px(174.))
        .background(SURFACE_RAISED)
        .border(Border::new().width(1.).fill(BORDER))
        .corner_radius(8.)
        .padding(Gaps::new_all(4.))
        .on_press(|event: Event<PressEventData>| event.stop_propagation())
        .on_global_pointer_press(move |_| menu_for_global.set(SourceMenuState::default()))
        .vertical();
    for entry in source_control_menu_entries(&git) {
        let bridge = bridge_for_menu.clone();
        let workspace_path = path_for_menu.clone();
        let mut refresh = refresh_for_menu;
        let mut menu_open = menu_for_option;
        let mut hover_for_enter = menu_hover;
        let mut hover_for_leave = menu_hover;
        let hovered = menu_hover() == Some(entry.action);
        let message = menu_message.clone();
        let head_message = menu_head_message.clone();
        let stashes = menu_stashes.clone();
        let mut git_dialog = dialog_for_option;
        let mut git_dialog_message = dialog_message_for_option;
        let foreground = if entry.enabled { TEXT } else { FAINT };
        let icon_color = if !entry.enabled {
            FAINT
        } else if entry.action == SourceControlAction::DiscardAll {
            (248, 113, 113)
        } else {
            MUTED
        };
        let mut row = rect()
            .width(Size::fill())
            .height(Size::px(28.))
            .horizontal()
            .cross_align(Alignment::Center)
            .spacing(8.)
            .padding(Gaps::new(8., 4., 8., 4.))
            .background(if hovered && entry.enabled {
                (48, 48, 48)
            } else {
                SURFACE_RAISED
            })
            .corner_radius(4.)
            .a11y_role(AccessibilityRole::Button)
            .a11y_alt(entry.action.label())
            .on_pointer_enter(move |_| {
                if entry.enabled {
                    Cursor::set(CursorIcon::Pointer);
                    hover_for_enter.set(Some(entry.action));
                }
            })
            .on_pointer_leave(move |_| {
                Cursor::set(CursorIcon::default());
                hover_for_leave.set(None);
            })
            .child(
                rect().interactive(false).child(
                    SvgViewer::new(entry.action.icon())
                        .width(Size::px(16.))
                        .height(Size::px(16.))
                        .color(icon_color),
                ),
            )
            .child(
                rect().interactive(false).child(
                    label()
                        .font_size(13.)
                        .color(foreground)
                        .text(entry.action.label()),
                ),
            );
        if entry.enabled {
            row = row.on_press(move |event: Event<PressEventData>| {
                event.stop_propagation();
                let opened_dialog = match entry.action {
                    SourceControlAction::Amend => {
                        git_dialog_message.set(head_message.clone().unwrap_or_default());
                        git_dialog.set(Some(SourceGitDialog::Amend {
                            workspace_path: workspace_path.clone(),
                        }));
                        true
                    }
                    SourceControlAction::DiscardAll => {
                        git_dialog.set(Some(SourceGitDialog::DiscardAll {
                            workspace_path: workspace_path.clone(),
                        }));
                        true
                    }
                    SourceControlAction::StashPop => {
                        git_dialog.set(Some(SourceGitDialog::StashPop {
                            workspace_path: workspace_path.clone(),
                            stashes: stashes.clone(),
                        }));
                        true
                    }
                    _ => false,
                };
                if !opened_dialog
                    && dispatch_source_control_action(
                        &bridge,
                        &workspace_path,
                        entry.action,
                        &message,
                        head_message.as_deref(),
                    )
                {
                    let next_revision = refresh.read().saturating_add(1);
                    refresh.set(next_revision);
                }
                menu_open.set(SourceMenuState::default());
            });
        }
        let mut entry_container = rect().width(Size::fill()).vertical();
        if entry.separator_before {
            entry_container = entry_container.child(
                rect()
                    .width(Size::fill())
                    .height(Size::px(5.))
                    .padding(Gaps::new(0., 2., 0., 2.))
                    .child(
                        rect()
                            .width(Size::fill())
                            .height(Size::px(1.))
                            .background(BORDER),
                    ),
            );
        }
        options = options.child(entry_container.child(row));
    }
    let options = options;
    rect()
        .width(Size::fill())
        .height(Size::fill())
        .vertical()
        .content(Content::Flex)
        .spacing(8.)
        .child(
            rect()
                .width(Size::fill())
                .height(Size::px(26.))
                .horizontal()
                .content(Content::Flex)
                .cross_align(Alignment::Center)
                .child(label().font_size(14.).color(TEXT).text("Source Control"))
                .child(rect().width(Size::flex(1.)).child(""))
                .maybe_child(clear_root_button)
                .child(toolbar_button(
                    icons::lucide::sparkles(),
                    if commit_ai_busy {
                        "Cancel Commit Message Generation"
                    } else {
                        "Generate Commit Message"
                    },
                    commit_ai_busy,
                    EventHandler::new(move |event: Event<PointerEventData>| {
                        event.stop_propagation();
                        toggle_commit_message_generation(
                            ai_bridge.clone(),
                            ai_workspace.clone(),
                            commit_message_for_ai,
                            commit_ai_for_action,
                            can_generate_commit,
                        );
                    }),
                ))
                .child(toolbar_button(
                    icons::lucide::git_compare(),
                    "Open All Changes",
                    false,
                    EventHandler::new(move |event: Event<PointerEventData>| {
                        event.stop_propagation();
                        open_all_changes.set(Some(working_tree_diff_request(
                            &scope_for_open_all,
                            None,
                            None,
                        )));
                    }),
                ))
                .child(toolbar_button(
                    if tree_mode_enabled {
                        icons::lucide::list()
                    } else {
                        icons::lucide::git_graph()
                    },
                    "Toggle Tree/List View",
                    false,
                    EventHandler::new(move |_| tree_mode_for_button.toggle()),
                ))
                .child(toolbar_button(
                    icons::lucide::search(),
                    "Filter Changes",
                    false,
                    EventHandler::new(move |_| filter_for_button.toggle()),
                ))
                .child(toolbar_button(
                    if all_collapsed_now {
                        icons::lucide::chevrons_up_down()
                    } else {
                        icons::lucide::chevrons_down_up()
                    },
                    if all_collapsed_now {
                        "Expand All"
                    } else {
                        "Collapse All"
                    },
                    false,
                    EventHandler::new(move |_| collapsed_for_button.toggle()),
                ))
                .child(toolbar_button(
                    alera_icons::git_refresh(),
                    "Refresh",
                    git_loading_now,
                    EventHandler::new(move |_| {
                        let next_revision = refresh_for_toolbar.read().saturating_add(1);
                        refresh_for_toolbar.set(next_revision);
                    }),
                )),
        )
        .child(
            rect()
                .position(Position::new_stacked())
                .width(Size::fill())
                .height(Size::px(64.))
                .background(SURFACE)
                .border(Border::new().width(1.).fill(BORDER))
                .corner_radius(8.)
                .overflow(Overflow::Clip)
                .child(
                    Input::new(commit_message)
                        .placeholder("Message")
                        .width(Size::fill())
                        .enabled(!commit_ai_busy)
                        .flat(),
                )
                .maybe_child(commit_ai_busy.then(|| {
                    rect()
                        .position(Position::new_absolute().top(0.).left(0.))
                        .layer(Layer::Overlay)
                        .width(Size::fill())
                        .height(Size::fill())
                        .background(Color::from_af32rgb(0.58, 0, 0, 0))
                        .center()
                        .child(
                            rect()
                                .horizontal()
                                .cross_align(Alignment::Center)
                                .spacing(8.)
                                .padding(Gaps::new(10., 7., 10., 7.))
                                .background(SURFACE_RAISED)
                                .border(Border::new().width(1.).fill(BORDER))
                                .corner_radius(6.)
                                .child(CircularLoader::new().size(14.))
                                .child(
                                    label()
                                        .font_size(11.)
                                        .color(MUTED)
                                        .text("Generating With AI"),
                                ),
                        )
                })),
        )
        .maybe_child(commit_ai.message.read().clone().map(|message| {
            label()
                .font_size(10.)
                .color(if message.contains("Generated With") {
                    SUCCESS
                } else {
                    MUTED
                })
                .max_lines(3)
                .text(message)
        }))
        .child(action_button)
        .child(label().font_size(10.).color(FAINT).text(branch_summary))
        .maybe_child(filter_visible().then(|| {
            rect()
                .width(Size::fill())
                .height(Size::px(32.))
                .border(Border::new().width(1.).fill(BORDER))
                .corner_radius(6.)
                .overflow(Overflow::Clip)
                .child(
                    Input::new(file_filter)
                        .placeholder("Filter Changes")
                        .width(Size::fill())
                        .compact()
                        .flat(),
                )
        }))
        .child(changes_panel)
        .child(history_panel)
        .maybe_child(menu_visible.then_some(options))
        .into_element()
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
enum GitGraphColor {
    Reference,
    RemoteReference,
    BaseReference,
    Lane(u8),
}

#[derive(Clone, Debug)]
struct GitGraphNode {
    id: String,
    color: GitGraphColor,
}

#[derive(Clone, Debug)]
struct GitGraphRow {
    input: Vec<GitGraphNode>,
    output: Vec<GitGraphNode>,
    item_id: String,
    parent_ids: Vec<String>,
    head: bool,
}

fn git_graph_color(color: GitGraphColor) -> &'static str {
    match color {
        GitGraphColor::Reference => "#22c55e",
        GitGraphColor::RemoteReference => "#60a5fa",
        GitGraphColor::BaseReference => "#c084fc",
        GitGraphColor::Lane(0) => "#22c55e",
        GitGraphColor::Lane(1) => "#60a5fa",
        GitGraphColor::Lane(2) => "#f59e0b",
        GitGraphColor::Lane(3) => "#f472b6",
        GitGraphColor::Lane(_) => "#a78bfa",
    }
}

fn git_graph_ui_color(color: GitGraphColor) -> (u8, u8, u8) {
    match color {
        GitGraphColor::Reference | GitGraphColor::Lane(0) => (34, 197, 94),
        GitGraphColor::RemoteReference | GitGraphColor::Lane(1) => (96, 165, 250),
        GitGraphColor::BaseReference => (192, 132, 252),
        GitGraphColor::Lane(2) => (245, 158, 11),
        GitGraphColor::Lane(3) => (244, 114, 182),
        GitGraphColor::Lane(_) => (167, 139, 250),
    }
}

fn git_history_reference_color(
    item_ref: &GitHistoryRefView,
    git: &GitSnapshotView,
) -> GitGraphColor {
    if git.history_current_ref_id.as_deref() == Some(item_ref.id.as_str()) {
        GitGraphColor::Reference
    } else if git.history_remote_ref_id.as_deref() == Some(item_ref.id.as_str()) {
        GitGraphColor::RemoteReference
    } else if git.history_base_ref_id.as_deref() == Some(item_ref.id.as_str()) {
        GitGraphColor::BaseReference
    } else {
        GitGraphColor::Lane(4)
    }
}

fn git_history_graph_rows(git: &GitSnapshotView) -> Vec<GitGraphRow> {
    let mut color_map = BTreeMap::<String, GitGraphColor>::new();
    if let Some(id) = &git.history_current_ref_id {
        color_map.insert(id.clone(), GitGraphColor::Reference);
    }
    if let Some(id) = &git.history_remote_ref_id {
        color_map.insert(id.clone(), GitGraphColor::RemoteReference);
    }
    if let Some(id) = &git.history_base_ref_id {
        color_map.insert(id.clone(), GitGraphColor::BaseReference);
    }
    let label_color = |item: &GitHistoryView| {
        item.references
            .iter()
            .find_map(|item_ref| color_map.get(&item_ref.id).copied())
    };
    let mut rows = Vec::with_capacity(git.history.len());
    let mut previous_output = Vec::<GitGraphNode>::new();
    let mut next_color = 0_u8;
    for item in &git.history {
        let input = previous_output.clone();
        let mut output = Vec::new();
        let mut first_parent_added = false;
        if !item.parent_ids.is_empty() {
            for node in &input {
                if node.id == item.full_id {
                    if !first_parent_added {
                        output.push(GitGraphNode {
                            id: item.parent_ids[0].clone(),
                            color: label_color(item).unwrap_or(node.color),
                        });
                        first_parent_added = true;
                    }
                } else {
                    output.push(node.clone());
                }
            }
        }
        for parent_index in if first_parent_added { 1 } else { 0 }..item.parent_ids.len() {
            let color = label_color(item).unwrap_or_else(|| {
                let color = GitGraphColor::Lane(next_color % 5);
                next_color = next_color.wrapping_add(1);
                color
            });
            output.push(GitGraphNode {
                id: item.parent_ids[parent_index].clone(),
                color,
            });
        }
        rows.push(GitGraphRow {
            input,
            output: output.clone(),
            item_id: item.full_id.clone(),
            parent_ids: item.parent_ids.clone(),
            head: git.history_current_revision.as_deref() == Some(item.full_id.as_str()),
        });
        previous_output = output;
    }
    rows
}

fn git_history_graph_svg(row: &GitGraphRow) -> (Bytes, f32) {
    const LANE_WIDTH: f32 = 11.;
    const HEIGHT: f32 = 24.;
    const NODE_Y: f32 = 12.;
    let lanes = row.input.len().max(row.output.len()).max(1) + 1;
    let width = LANE_WIDTH * lanes as f32;
    let input_index = row.input.iter().position(|node| node.id == row.item_id);
    let circle_index = input_index.unwrap_or(row.input.len());
    let circle_color = row
        .output
        .get(circle_index)
        .or_else(|| row.input.get(circle_index))
        .map(|node| node.color)
        .unwrap_or(GitGraphColor::Reference);
    let point = |index: usize, y: f32| (LANE_WIDTH * (index as f32 + 1.), y);
    let mut paths = String::new();
    let mut output_index = 0_usize;
    for (index, node) in row.input.iter().enumerate() {
        let (x, _) = point(index, 0.);
        if input_index == Some(index) {
            output_index += 1;
            continue;
        }
        if row
            .output
            .get(output_index)
            .is_some_and(|output| output.id == node.id)
        {
            let (output_x, _) = point(output_index, HEIGHT);
            let data = if index == output_index {
                format!("M{x} 0 L{x} {HEIGHT}")
            } else {
                format!("M{x} 0 L{x} 6 Q{x} {NODE_Y} {output_x} {NODE_Y} L{output_x} {HEIGHT}")
            };
            paths.push_str(&format!(
                "<path d=\"{data}\" stroke=\"{}\"/>",
                git_graph_color(node.color)
            ));
            output_index += 1;
        }
    }
    let (circle_x, _) = point(circle_index, NODE_Y);
    if input_index.is_some() {
        paths.push_str(&format!(
            "<path d=\"M{circle_x} 0 L{circle_x} {NODE_Y}\" stroke=\"{}\"/>",
            git_graph_color(circle_color)
        ));
    }
    if !row.parent_ids.is_empty() {
        paths.push_str(&format!(
            "<path d=\"M{circle_x} {NODE_Y} L{circle_x} {HEIGHT}\" stroke=\"{}\"/>",
            git_graph_color(circle_color)
        ));
    }
    for parent_id in row.parent_ids.iter().skip(1) {
        if let Some(parent_index) = row.output.iter().rposition(|node| &node.id == parent_id) {
            let (parent_x, _) = point(parent_index, NODE_Y);
            paths.push_str(&format!(
                "<path d=\"M{circle_x} {NODE_Y} L{parent_x} {NODE_Y} Q{parent_x} {NODE_Y} {parent_x} {HEIGHT}\" stroke=\"{}\"/>",
                git_graph_color(row.output[parent_index].color)
            ));
        }
    }
    let node = if row.head {
        format!(
            "<circle cx=\"{circle_x}\" cy=\"{NODE_Y}\" r=\"6.5\" fill=\"{}\"/><circle cx=\"{circle_x}\" cy=\"{NODE_Y}\" r=\"3.5\" fill=\"#101010\"/>",
            git_graph_color(circle_color)
        )
    } else if row.parent_ids.len() > 1 {
        format!(
            "<circle cx=\"{circle_x}\" cy=\"{NODE_Y}\" r=\"4.5\" fill=\"{}\"/><circle cx=\"{circle_x}\" cy=\"{NODE_Y}\" r=\"2\" fill=\"#101010\"/>",
            git_graph_color(circle_color)
        )
    } else {
        format!(
            "<circle cx=\"{circle_x}\" cy=\"{NODE_Y}\" r=\"3.5\" fill=\"{}\"/>",
            git_graph_color(circle_color)
        )
    };
    let svg = format!(
        "<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"{width}\" height=\"{HEIGHT}\" viewBox=\"0 0 {width} {HEIGHT}\" fill=\"none\" stroke-width=\"1.5\" stroke-linecap=\"round\" stroke-linejoin=\"round\">{paths}{node}</svg>"
    );
    (Bytes::from(svg.into_bytes()), width)
}

#[allow(clippy::too_many_arguments)]
fn source_control_history_panel(
    git: &GitSnapshotView,
    bridge: RuntimeBridge,
    source_control_scope: SourceControlScopeView,
    history_expanded: State<bool>,
    expanded_commits: State<HashSet<String>>,
    history_hover: State<Option<String>>,
    history_action_menu: State<Option<String>>,
    history_files: State<HashMap<String, Result<Vec<GitCommitChangeView>, String>>>,
    history_loading: State<HashSet<String>>,
    history_height: State<f32>,
    history_drag_y: State<Option<f64>>,
    git_loading: bool,
    refresh_revision: State<u64>,
    open_git_diff_request: State<Option<docking::GitDiffOpenRequest>>,
) -> Element {
    let workspace_path = source_control_scope.path.clone();
    let expanded = history_expanded();
    let mut expanded_for_toggle = history_expanded;
    let mut refresh_for_button = refresh_revision;
    let current_history_height = *history_height.read();
    let mut drag_for_down = history_drag_y;
    let drag_for_move = history_drag_y;
    let mut drag_for_release = history_drag_y;
    let mut height_for_move = history_height;
    let history_count = git.history.len();
    let history_count_label = if git.history_has_more {
        format!("{history_count}+")
    } else {
        history_count.to_string()
    };
    let resize_handle = expanded.then(|| {
        rect()
            .width(Size::fill())
            .height(Size::px(8.))
            .background(SURFACE)
            .center()
            .on_pointer_enter(|_| Cursor::set(CursorIcon::RowResize))
            .on_pointer_leave(move |_| {
                if drag_for_move.read().is_none() {
                    Cursor::set(CursorIcon::default());
                }
            })
            .on_pointer_down(move |event: Event<PointerEventData>| {
                if !event.data().is_primary() {
                    return;
                }
                event.stop_propagation();
                event.prevent_default();
                drag_for_down.set(Some(event.global_location().y));
            })
            .on_capture_global_pointer_move(move |event: Event<PointerEventData>| {
                let Some(previous_y) = *drag_for_move.read() else {
                    return;
                };
                event.prevent_default();
                let current_y = event.global_location().y;
                let delta = (current_y - previous_y) as f32 / 0.75;
                let next_height = (*height_for_move.read() - delta).clamp(128., 693.);
                height_for_move.set(next_height);
                drag_for_down.set(Some(current_y));
            })
            .on_global_pointer_press(move |_| {
                drag_for_release.set(None);
                Cursor::set(CursorIcon::default());
            })
            .child(
                rect()
                    .width(Size::fill())
                    .height(Size::px(1.))
                    .background(BORDER),
            )
    });
    let header = rect()
        .width(Size::fill())
        .height(Size::px(44.))
        .background(SURFACE)
        .border(Border::new().width(1.).fill(BORDER))
        .padding(Gaps::new(8., 4., 4., 4.))
        .horizontal()
        .content(Content::Flex)
        .cross_align(Alignment::Center)
        .spacing(6.)
        .a11y_role(AccessibilityRole::Button)
        .a11y_alt("Commits")
        .on_pointer_enter(|_| Cursor::set(CursorIcon::Pointer))
        .on_pointer_leave(|_| Cursor::set(CursorIcon::default()))
        .on_pointer_down(move |event: Event<PointerEventData>| {
            event.stop_propagation();
            expanded_for_toggle.toggle();
        })
        .child(
            SvgViewer::new(if expanded {
                icons::lucide::chevron_down()
            } else {
                icons::lucide::chevron_right()
            })
            .width(Size::px(14.))
            .height(Size::px(14.))
            .color(MUTED),
        )
        .child(
            label()
                .font_size(11.)
                .font_weight(FontWeight::BOLD)
                .color(MUTED)
                .text("COMMITS"),
        )
        .maybe_child(expanded.then(|| {
            label()
                .font_size(10.)
                .color(FAINT)
                .text(history_count_label)
        }))
        .child(rect().width(Size::flex(1.)).child(""))
        .child(
            TooltipContainer::new(Tooltip::new_text("Refresh Commits"))
                .position(AttachedPosition::Top)
                .delay(Duration::from_millis(350))
                .child(
                    rect()
                        .width(Size::px(38.))
                        .height(Size::px(38.))
                        .center()
                        .background(SURFACE_RAISED)
                        .border(Border::new().width(1.).fill(BORDER))
                        .corner_radius(6.)
                        .a11y_role(AccessibilityRole::Button)
                        .a11y_alt("Refresh Commits")
                        .on_pointer_enter(|_| Cursor::set(CursorIcon::Pointer))
                        .on_pointer_leave(|_| Cursor::set(CursorIcon::default()))
                        .on_pointer_down(move |event: Event<PointerEventData>| {
                            event.stop_propagation();
                            let next_revision = refresh_for_button.read().saturating_add(1);
                            refresh_for_button.set(next_revision);
                        })
                        .child(if git_loading {
                            CircularLoader::new().size(15.).into_element()
                        } else {
                            SvgViewer::new(alera_icons::git_refresh())
                                .width(Size::px(15.))
                                .height(Size::px(15.))
                                .color(MUTED)
                                .into_element()
                        }),
                ),
        );
    let body = expanded.then(|| {
        let graph_rows = git_history_graph_rows(git);
        let expanded_snapshot = expanded_commits.read().clone();
        let history_files_snapshot = history_files.read().clone();
        let history_loading_snapshot = history_loading.read().clone();
        let history_rows = if git.history.is_empty() {
            vec![
                rect()
                    .width(Size::fill())
                    .height(Size::px(72.))
                    .center()
                    .child(label().font_size(12.).color(MUTED).text("No Commits"))
                    .into_element(),
            ]
        } else {
            git.history
                .iter()
                .zip(graph_rows.iter())
                .map(|(item, graph)| {
                    let item_expanded = expanded_snapshot.contains(&item.full_id);
                    let item_loading = history_loading_snapshot.contains(&item.full_id);
                    let item_files = history_files_snapshot.get(&item.full_id).cloned();
                    let hovered = history_hover.read().as_deref() == Some(item.full_id.as_str());
                    let action_menu_open =
                        history_action_menu.read().as_deref() == Some(item.full_id.as_str());
                    let mut hover_for_enter = history_hover;
                    let mut hover_for_leave = history_hover;
                    let mut expanded_for_row = expanded_commits;
                    let files_for_row = history_files;
                    let mut loading_for_row = history_loading;
                    let mut action_menu_for_button = history_action_menu;
                    let mut action_menu_for_global = history_action_menu;
                    let item_id = item.full_id.clone();
                    let item_id_for_enter = item_id.clone();
                    let item_id_for_toggle = item_id.clone();
                    let item_id_for_request = item_id.clone();
                    let item_id_for_menu = item_id.clone();
                    let bridge_for_row = bridge.clone();
                    let workspace_path_for_row = workspace_path.clone();
                    let (graph_svg, graph_width) = git_history_graph_svg(graph);
                    let mut references = item.references.clone();
                    references.sort_by_key(|item_ref| {
                        if git.history_current_ref_id.as_deref() == Some(item_ref.id.as_str()) {
                            0
                        } else if git.history_remote_ref_id.as_deref() == Some(item_ref.id.as_str())
                        {
                            1
                        } else if git.history_base_ref_id.as_deref() == Some(item_ref.id.as_str()) {
                            2
                        } else {
                            3
                        }
                    });
                    let hidden_references = references.len().saturating_sub(2);
                    let reference_badges = references
                        .iter()
                        .take(2)
                        .map(|item_ref| {
                            let color =
                                git_graph_ui_color(git_history_reference_color(item_ref, git));
                            rect()
                                .height(Size::px(22.))
                                .max_width(Size::px(104.))
                                .padding(Gaps::new(6., 2., 6., 2.))
                                .border(Border::new().width(1.).fill(color))
                                .corner_radius(999.)
                                .center()
                                .child(
                                    label()
                                        .font_size(10.)
                                        .color(color)
                                        .max_lines(1)
                                        .text_overflow(TextOverflow::Ellipsis)
                                        .text(item_ref.name.clone()),
                                )
                                .into_element()
                        })
                        .collect::<Vec<_>>();
                    let row = rect()
                        .width(Size::fill())
                        .height(Size::px(36.))
                        .padding(Gaps::new(8., 4., 6., 4.))
                        .horizontal()
                        .content(Content::Flex)
                        .cross_align(Alignment::Center)
                        .spacing(5.)
                        .background(if hovered { (39, 39, 39) } else { SURFACE })
                        .a11y_role(AccessibilityRole::Button)
                        .a11y_alt(item.subject.clone())
                        .on_pointer_enter(move |_| {
                            Cursor::set(CursorIcon::Pointer);
                            hover_for_enter.set(Some(item_id_for_enter.clone()));
                        })
                        .on_pointer_leave(move |_| {
                            Cursor::set(CursorIcon::default());
                            hover_for_leave.set(None);
                        })
                        .on_pointer_down(move |event: Event<PointerEventData>| {
                            event.stop_propagation();
                            let mut next = expanded_for_row.read().clone();
                            let expanding = next.insert(item_id_for_toggle.clone());
                            if !expanding {
                                next.remove(&item_id_for_toggle);
                            }
                            expanded_for_row.set(next);
                            if expanding
                                && !files_for_row.read().contains_key(&item_id_for_request)
                                && !loading_for_row.read().contains(&item_id_for_request)
                            {
                                let mut next_loading = loading_for_row.read().clone();
                                next_loading.insert(item_id_for_request.clone());
                                loading_for_row.set(next_loading);
                                let bridge = bridge_for_row.clone();
                                let workspace_path = workspace_path_for_row.clone();
                                let commit_id = item_id_for_request.clone();
                                let mut files = files_for_row;
                                let mut loading = loading_for_row;
                                spawn(async move {
                                    let result = bridge
                                        .request(
                                            "workspaceGit.commitCompare",
                                            json!({
                                                "workspacePath": workspace_path,
                                                "commitId": commit_id,
                                            }),
                                        )
                                        .await
                                        .and_then(|value| parse_git_commit_changes(&value));
                                    let mut next_files = files.read().clone();
                                    next_files.insert(commit_id.clone(), result);
                                    files.set(next_files);
                                    let mut next_loading = loading.read().clone();
                                    next_loading.remove(&commit_id);
                                    loading.set(next_loading);
                                });
                            }
                        })
                        .child(
                            rect().interactive(false).child(
                                SvgViewer::new(graph_svg)
                                    .width(Size::px(graph_width))
                                    .height(Size::px(24.)),
                            ),
                        )
                        .child(
                            rect().interactive(false).child(
                                SvgViewer::new(if item_expanded {
                                    icons::lucide::chevron_down()
                                } else {
                                    icons::lucide::chevron_right()
                                })
                                .width(Size::px(11.))
                                .height(Size::px(11.))
                                .color(FAINT),
                            ),
                        )
                        .child(
                            label()
                                .width(Size::flex(1.))
                                .font_size(11.)
                                .color(TEXT)
                                .max_lines(1)
                                .text_overflow(TextOverflow::Ellipsis)
                                .text(item.subject.clone()),
                        )
                        .children(reference_badges)
                        .maybe_child((hidden_references > 0).then(|| {
                            label()
                                .font_size(9.)
                                .color(FAINT)
                                .text(format!("+{hidden_references}"))
                        }))
                        .child(
                            TooltipContainer::new(Tooltip::new_text("Commit Actions"))
                                .position(AttachedPosition::Top)
                                .delay(Duration::from_millis(350))
                                .child(
                                    rect()
                                        .width(Size::px(24.))
                                        .height(Size::px(24.))
                                        .corner_radius(5.)
                                        .center()
                                        .a11y_role(AccessibilityRole::Button)
                                        .a11y_alt("Commit Actions")
                                        .on_pointer_enter(|_| Cursor::set(CursorIcon::Pointer))
                                        .on_pointer_leave(|_| Cursor::set(CursorIcon::default()))
                                        .on_pointer_down(move |event: Event<PointerEventData>| {
                                            event.stop_propagation();
                                            let next = if action_menu_for_button.read().as_deref()
                                                == Some(item_id_for_menu.as_str())
                                            {
                                                None
                                            } else {
                                                Some(item_id_for_menu.clone())
                                            };
                                            action_menu_for_button.set(next);
                                        })
                                        .child(
                                            SvgViewer::new(icons::lucide::ellipsis())
                                                .width(Size::px(13.))
                                                .height(Size::px(13.))
                                                .color(FAINT),
                                        ),
                                ),
                        )
                        .into_element();
                    let details = item_expanded.then(|| {
                        let timestamp = item
                            .timestamp_millis
                            .map(format_git_history_time)
                            .unwrap_or_default();
                        let metadata = [item.author.clone(), timestamp]
                            .into_iter()
                            .filter(|part| !part.trim().is_empty())
                            .collect::<Vec<_>>()
                            .join(" · ");
                        let body = if item_loading || item_files.is_none() {
                            rect()
                                .width(Size::fill())
                                .height(Size::px(32.))
                                .padding(Gaps::new(40., 4., 8., 6.))
                                .horizontal()
                                .cross_align(Alignment::Center)
                                .spacing(8.)
                                .child(CircularLoader::new().size(13.))
                                .child(label().font_size(11.).color(MUTED).text("Loading Files..."))
                                .into_element()
                        } else {
                            match item_files.as_ref() {
                                Some(Err(error)) => rect()
                                    .width(Size::fill())
                                    .padding(Gaps::new(40., 4., 8., 6.))
                                    .child(
                                        label()
                                            .font_size(11.)
                                            .color((248, 113, 113))
                                            .text(error.clone()),
                                    )
                                    .into_element(),
                                Some(Ok(files)) if files.is_empty() => rect()
                                    .width(Size::fill())
                                    .padding(Gaps::new(40., 4., 8., 6.))
                                    .child(
                                        label().font_size(11.).color(MUTED).text("No File Changes"),
                                    )
                                    .into_element(),
                                Some(Ok(files)) => {
                                    let commit_id = item.full_id.clone();
                                    let commit_subject = item.subject.clone();
                                    let rows = files
                                        .iter()
                                        .map(|change| {
                                            let display_path =
                                                change.old_path.as_ref().map_or_else(
                                                    || change.path.clone(),
                                                    |old_path| {
                                                        format!("{old_path} -> {}", change.path)
                                                    },
                                                );
                                            let status = change
                                                .status
                                                .chars()
                                                .next()
                                                .unwrap_or('M')
                                                .to_string();
                                            let mut open_commit_file = open_git_diff_request;
                                            let scope_for_commit_file =
                                                source_control_scope.clone();
                                            let path_for_commit_file = change.path.clone();
                                            let old_path_for_commit_file = change.old_path.clone();
                                            let commit_for_file = commit_id.clone();
                                            let subject_for_file = commit_subject.clone();
                                            let added = change.added.filter(|count| *count > 0);
                                            let removed = change.removed.filter(|count| *count > 0);
                                            rect()
                                                .width(Size::fill())
                                                .height(Size::px(30.))
                                                .padding(Gaps::new(40., 4., 8., 4.))
                                                .horizontal()
                                                .content(Content::Flex)
                                                .cross_align(Alignment::Center)
                                                .spacing(7.)
                                                .a11y_role(AccessibilityRole::Button)
                                                .a11y_alt(display_path.clone())
                                                .on_pointer_enter(|_| {
                                                    Cursor::set(CursorIcon::Pointer)
                                                })
                                                .on_pointer_leave(|_| {
                                                    Cursor::set(CursorIcon::default())
                                                })
                                                .on_pointer_down(
                                                    move |event: Event<PointerEventData>| {
                                                        event.stop_propagation();
                                                        open_commit_file.set(Some(
                                                            commit_diff_request(
                                                                &scope_for_commit_file,
                                                                Some(path_for_commit_file.clone()),
                                                                old_path_for_commit_file.clone(),
                                                                commit_for_file.clone(),
                                                                subject_for_file.clone(),
                                                            ),
                                                        ));
                                                    },
                                                )
                                                .child(
                                                    SvgViewer::new(icons::lucide::file())
                                                        .width(Size::px(14.))
                                                        .height(Size::px(14.))
                                                        .color(MUTED),
                                                )
                                                .child(
                                                    label()
                                                        .width(Size::flex(1.))
                                                        .font_family("JetBrains Mono")
                                                        .font_size(11.)
                                                        .color(MUTED)
                                                        .max_lines(1)
                                                        .text_overflow(TextOverflow::Ellipsis)
                                                        .text(display_path),
                                                )
                                                .maybe_child(added.map(|count| {
                                                    label()
                                                        .font_size(10.)
                                                        .color(SUCCESS)
                                                        .text(format!("+{count}"))
                                                }))
                                                .maybe_child(removed.map(|count| {
                                                    label()
                                                        .font_size(10.)
                                                        .color((248, 113, 113))
                                                        .text(format!("-{count}"))
                                                }))
                                                .child(
                                                    label()
                                                        .font_size(11.)
                                                        .color((226, 166, 78))
                                                        .text(status),
                                                )
                                                .into_element()
                                        })
                                        .collect::<Vec<_>>();
                                    let mut open_commit = open_git_diff_request;
                                    let scope_for_commit = source_control_scope.clone();
                                    let commit_for_all = commit_id.clone();
                                    let subject_for_all = commit_subject.clone();
                                    rect()
                                        .width(Size::fill())
                                        .vertical()
                                        .children(rows)
                                        .child(
                                            rect()
                                                .height(Size::px(32.))
                                                .padding(Gaps::new(40., 5., 8., 7.))
                                                .horizontal()
                                                .cross_align(Alignment::Center)
                                                .spacing(7.)
                                                .a11y_role(AccessibilityRole::Button)
                                                .a11y_alt("Open All Changes")
                                                .on_pointer_enter(|_| {
                                                    Cursor::set(CursorIcon::Pointer)
                                                })
                                                .on_pointer_leave(|_| {
                                                    Cursor::set(CursorIcon::default())
                                                })
                                                .on_pointer_down(
                                                    move |event: Event<PointerEventData>| {
                                                        event.stop_propagation();
                                                        open_commit.set(Some(commit_diff_request(
                                                            &scope_for_commit,
                                                            None,
                                                            None,
                                                            commit_for_all.clone(),
                                                            subject_for_all.clone(),
                                                        )));
                                                    },
                                                )
                                                .child(
                                                    SvgViewer::new(icons::lucide::external_link())
                                                        .width(Size::px(13.))
                                                        .height(Size::px(13.))
                                                        .color(MUTED),
                                                )
                                                .child(
                                                    label()
                                                        .font_size(11.)
                                                        .color(MUTED)
                                                        .text("Open All Changes"),
                                                ),
                                        )
                                        .into_element()
                                }
                                None => rect().into_element(),
                            }
                        };
                        rect()
                            .width(Size::fill())
                            .vertical()
                            .background(SURFACE)
                            .maybe_child((!metadata.is_empty()).then(|| {
                                rect()
                                    .padding(Gaps::new(40., 4., 8., 2.))
                                    .child(label().font_size(9.).color(FAINT).text(metadata))
                            }))
                            .child(body)
                    });
                    let action_menu = action_menu_open.then(|| {
                        let mut close_after_hash = history_action_menu;
                        let mut close_after_message = history_action_menu;
                        let hash = item.full_id.clone();
                        let message = if item.message.trim().is_empty() {
                            item.subject.clone()
                        } else {
                            item.message.trim().to_string()
                        };
                        rect()
                            .position(Position::new_absolute().top(32.).right(6.))
                            .layer(Layer::Overlay)
                            .width(Size::px(206.))
                            .vertical()
                            .background(SURFACE_RAISED)
                            .border(Border::new().width(1.).fill(BORDER))
                            .corner_radius(8.)
                            .padding(Gaps::new_all(4.))
                            .on_press(|event: Event<PressEventData>| event.stop_propagation())
                            .on_global_pointer_press(move |_| action_menu_for_global.set(None))
                            .child(
                                rect()
                                    .height(Size::px(34.))
                                    .padding(Gaps::new(8., 4., 8., 4.))
                                    .horizontal()
                                    .cross_align(Alignment::Center)
                                    .spacing(8.)
                                    .corner_radius(5.)
                                    .a11y_role(AccessibilityRole::Button)
                                    .a11y_alt("Copy Commit Hash")
                                    .on_pointer_enter(|_| Cursor::set(CursorIcon::Pointer))
                                    .on_pointer_leave(|_| Cursor::set(CursorIcon::default()))
                                    .on_pointer_down(move |event: Event<PointerEventData>| {
                                        event.stop_propagation();
                                        let _ = Clipboard::set(hash.clone());
                                        close_after_hash.set(None);
                                    })
                                    .child(
                                        SvgViewer::new(icons::lucide::git_branch())
                                            .width(Size::px(16.))
                                            .height(Size::px(16.))
                                            .color(MUTED),
                                    )
                                    .child(
                                        label().font_size(13.).color(TEXT).text("Copy Commit Hash"),
                                    ),
                            )
                            .child(
                                rect()
                                    .height(Size::px(34.))
                                    .padding(Gaps::new(8., 4., 8., 4.))
                                    .horizontal()
                                    .cross_align(Alignment::Center)
                                    .spacing(8.)
                                    .corner_radius(5.)
                                    .a11y_role(AccessibilityRole::Button)
                                    .a11y_alt("Copy Commit Message")
                                    .on_pointer_enter(|_| Cursor::set(CursorIcon::Pointer))
                                    .on_pointer_leave(|_| Cursor::set(CursorIcon::default()))
                                    .on_pointer_down(move |event: Event<PointerEventData>| {
                                        event.stop_propagation();
                                        let _ = Clipboard::set(message.clone());
                                        close_after_message.set(None);
                                    })
                                    .child(
                                        SvgViewer::new(icons::lucide::copy())
                                            .width(Size::px(16.))
                                            .height(Size::px(16.))
                                            .color(MUTED),
                                    )
                                    .child(
                                        label()
                                            .font_size(13.)
                                            .color(TEXT)
                                            .text("Copy Commit Message"),
                                    ),
                            )
                    });
                    rect()
                        .width(Size::fill())
                        .vertical()
                        .child(row)
                        .maybe_child(details)
                        .maybe_child(action_menu)
                        .into_element()
                })
                .collect::<Vec<_>>()
        };
        ScrollView::new()
            .width(Size::fill())
            .height(Size::px(current_history_height))
            .show_scrollbar(true)
            .child(rect().width(Size::fill()).vertical().children(history_rows))
    });
    rect()
        .position(Position::new_stacked().top(12.).left(-12.))
        .width(Size::px(384.))
        .vertical()
        .maybe_child(resize_handle)
        .child(header)
        .maybe_child(body)
        .into_element()
}

#[allow(clippy::too_many_arguments)]
fn context_pull_request_panel(
    bridge: RuntimeBridge,
    forge_service: ForgeService,
    workspace_id: Option<String>,
    workspace_path: String,
    snapshot: State<Option<Result<ForgeSnapshot, String>>>,
    loading: State<bool>,
    mut refresh_revision: State<u64>,
    composer_mode: State<PullRequestComposerMode>,
    forge_title: State<String>,
    forge_body: State<String>,
    forge_base: State<String>,
    forge_link: State<String>,
    forge_comment: State<String>,
    forge_create_draft: State<bool>,
    forge_action_loading: State<bool>,
    forge_action_error: State<Option<String>>,
    forge_editing: State<bool>,
    pull_request_confirmation: State<Option<PullRequestConfirmation>>,
    pull_request_ai: AiTextGenerationState,
    forge_collapsed_check_groups: State<HashSet<String>>,
    forge_expanded_checks: State<HashSet<String>>,
) -> Element {
    let refreshing = *loading.read();
    let header = rect()
        .width(Size::fill())
        .height(Size::px(34.))
        .horizontal()
        .content(Content::Flex)
        .cross_align(Alignment::Center)
        .child(
            label()
                .width(Size::flex(1.))
                .font_size(13.)
                .color(TEXT)
                .text("Pull Request"),
        )
        .child(
            TooltipContainer::new(Tooltip::new_text("Refresh Pull Request"))
                .position(AttachedPosition::Top)
                .delay(Duration::from_millis(350))
                .child(
                    rect()
                        .width(Size::px(28.))
                        .height(Size::px(28.))
                        .corner_radius(5.)
                        .center()
                        .a11y_role(AccessibilityRole::Button)
                        .a11y_alt("Refresh Pull Request")
                        .on_pointer_enter(|_| Cursor::set(CursorIcon::Pointer))
                        .on_pointer_leave(|_| Cursor::set(CursorIcon::default()))
                        .on_pointer_down(move |event: Event<PointerEventData>| {
                            event.stop_propagation();
                            if !refreshing {
                                let next = refresh_revision.read().saturating_add(1);
                                refresh_revision.set(next);
                            }
                        })
                        .child(if refreshing {
                            CircularLoader::new().size(14.).into_element()
                        } else {
                            SvgViewer::new(icons::lucide::refresh_cw())
                                .width(Size::px(14.))
                                .height(Size::px(14.))
                                .color(MUTED)
                                .into_element()
                        }),
                ),
        );

    let body = if refreshing && snapshot.read().is_none() {
        pull_request_message(None, "Loading Pull Request")
    } else {
        match snapshot.read().as_ref() {
            Some(Err(error)) => pull_request_message(Some("Could Not Load Pull Request"), error),
            Some(Ok(snapshot)) => pull_request_snapshot_body(
                snapshot,
                bridge,
                forge_service,
                workspace_id,
                workspace_path,
                composer_mode,
                forge_title,
                forge_body,
                forge_base,
                forge_link,
                forge_comment,
                forge_create_draft,
                forge_action_loading,
                forge_action_error,
                forge_editing,
                refresh_revision,
                pull_request_confirmation,
                pull_request_ai,
                forge_collapsed_check_groups,
                forge_expanded_checks,
            ),
            None => pull_request_message(None, "Loading Pull Request"),
        }
    };

    rect()
        .width(Size::fill())
        .height(Size::fill())
        .vertical()
        .child(header)
        .child(
            rect()
                .width(Size::fill())
                .height(Size::px(1.))
                .background(BORDER),
        )
        .child(body)
        .into_element()
}

fn forge_check_group(check: &ForgeCheck) -> &'static str {
    match check.bucket.to_ascii_lowercase().as_str() {
        "pass" | "success" => "Successful",
        "pending" | "queued" | "in_progress" | "in progress" => "In Progress",
        _ => "Failing",
    }
}

fn pull_request_checks(
    checks: &[ForgeCheck],
    collapsed_groups: State<HashSet<String>>,
    expanded_checks: State<HashSet<String>>,
) -> Element {
    let mut groups = BTreeMap::<&'static str, Vec<ForgeCheck>>::new();
    for check in checks.iter().cloned() {
        groups
            .entry(forge_check_group(&check))
            .or_default()
            .push(check);
    }
    for checks in groups.values_mut() {
        checks.sort_by_key(|check| check.name.to_ascii_lowercase());
    }

    let mut section = rect().width(Size::fill()).vertical().spacing(3.).child(
        label()
            .font_size(11.)
            .color(TEXT)
            .text(format!("Checks ({})", checks.len())),
    );
    if checks.is_empty() {
        return section
            .child(
                label()
                    .font_size(10.)
                    .color(MUTED)
                    .text("No Checks Reported"),
            )
            .into_element();
    }

    for group in ["Failing", "In Progress", "Successful"] {
        let Some(group_checks) = groups.remove(group) else {
            continue;
        };
        let collapsed = collapsed_groups.read().contains(group);
        let mut collapsed_for_row = collapsed_groups;
        let group_key = group.to_string();
        section = section.child(
            rect()
                .width(Size::fill())
                .height(Size::px(28.))
                .horizontal()
                .cross_align(Alignment::Center)
                .spacing(4.)
                .corner_radius(4.)
                .a11y_role(AccessibilityRole::Button)
                .a11y_alt(format!("{group} Checks"))
                .on_pointer_enter(|_| Cursor::set(CursorIcon::Pointer))
                .on_pointer_leave(|_| Cursor::set(CursorIcon::default()))
                .on_press(move |event: Event<PressEventData>| {
                    event.stop_propagation();
                    let mut collapsed = collapsed_for_row.write();
                    if !collapsed.insert(group_key.clone()) {
                        collapsed.remove(&group_key);
                    }
                })
                .child(
                    SvgViewer::new(if collapsed {
                        icons::lucide::chevron_right()
                    } else {
                        icons::lucide::chevron_down()
                    })
                    .width(Size::px(14.))
                    .height(Size::px(14.))
                    .color(MUTED),
                )
                .child(label().font_size(10.).color(MUTED).text(format!(
                    "{} {group} {}",
                    group_checks.len(),
                    if group_checks.len() == 1 {
                        "Check"
                    } else {
                        "Checks"
                    }
                ))),
        );
        if collapsed {
            continue;
        }

        for check in group_checks {
            let check_key = format!("{}|{}", check.name, check.link.as_deref().unwrap_or(""));
            let expanded = expanded_checks.read().contains(&check_key);
            let mut expanded_for_row = expanded_checks;
            let toggle_key = check_key.clone();
            let status = forge_check_group(&check);
            let status_icon = match status {
                "Successful" => SvgViewer::new(icons::lucide::circle_check())
                    .width(Size::px(13.))
                    .height(Size::px(13.))
                    .color(SUCCESS)
                    .into_element(),
                "In Progress" => CircularLoader::new().size(13.).into_element(),
                _ => SvgViewer::new(icons::lucide::circle_x())
                    .width(Size::px(13.))
                    .height(Size::px(13.))
                    .color((248, 113, 113))
                    .into_element(),
            };
            let details = [
                check.workflow.clone().map(|value| ("Workflow", value)),
                check
                    .description
                    .clone()
                    .map(|value| ("Description", value)),
            ]
            .into_iter()
            .flatten()
            .collect::<Vec<_>>();
            section = section.child(
                rect()
                    .width(Size::fill())
                    .vertical()
                    .padding(Gaps::new(8., 0., 0., 0.))
                    .child(
                        rect()
                            .width(Size::fill())
                            .min_height(Size::px(30.))
                            .horizontal()
                            .cross_align(Alignment::Center)
                            .spacing(7.)
                            .corner_radius(4.)
                            .a11y_role(AccessibilityRole::Button)
                            .a11y_alt(format!("{} Check Details", check.name))
                            .on_pointer_enter(|_| Cursor::set(CursorIcon::Pointer))
                            .on_pointer_leave(|_| Cursor::set(CursorIcon::default()))
                            .on_press(move |event: Event<PressEventData>| {
                                event.stop_propagation();
                                let mut expanded = expanded_for_row.write();
                                if !expanded.insert(toggle_key.clone()) {
                                    expanded.remove(&toggle_key);
                                }
                            })
                            .child(status_icon)
                            .child(
                                label()
                                    .width(Size::flex(1.))
                                    .font_size(11.)
                                    .color(TEXT)
                                    .max_lines(1)
                                    .text_overflow(TextOverflow::Ellipsis)
                                    .text(check.name.clone()),
                            )
                            .child(
                                SvgViewer::new(if expanded {
                                    icons::lucide::chevron_up()
                                } else {
                                    icons::lucide::chevron_down()
                                })
                                .width(Size::px(14.))
                                .height(Size::px(14.))
                                .color(MUTED),
                            ),
                    )
                    .maybe_child(expanded.then(|| {
                        let mut body = rect()
                            .width(Size::fill())
                            .vertical()
                            .spacing(5.)
                            .padding(Gaps::new(24., 0., 0., 6.));
                        if details.is_empty() {
                            body = body.child(
                                label()
                                    .font_size(10.)
                                    .color(MUTED)
                                    .text("No Details Available"),
                            );
                        } else {
                            body = body.children(details.into_iter().map(|(title, value)| {
                                rect()
                                    .width(Size::fill())
                                    .horizontal()
                                    .spacing(8.)
                                    .child(
                                        label()
                                            .width(Size::px(72.))
                                            .font_size(10.)
                                            .color(MUTED)
                                            .text(title),
                                    )
                                    .child(
                                        label()
                                            .width(Size::flex(1.))
                                            .font_size(10.)
                                            .color(TEXT)
                                            .max_lines(4)
                                            .text(value),
                                    )
                            }));
                        }
                        body
                    })),
            );
        }
    }
    section.into_element()
}

#[allow(clippy::too_many_arguments)]
fn pull_request_snapshot_body(
    snapshot: &ForgeSnapshot,
    bridge: RuntimeBridge,
    forge_service: ForgeService,
    workspace_id: Option<String>,
    workspace_path: String,
    composer_mode: State<PullRequestComposerMode>,
    forge_title: State<String>,
    forge_body: State<String>,
    forge_base: State<String>,
    forge_link: State<String>,
    forge_comment: State<String>,
    forge_create_draft: State<bool>,
    forge_action_loading: State<bool>,
    forge_action_error: State<Option<String>>,
    forge_editing: State<bool>,
    refresh_revision: State<u64>,
    pull_request_confirmation: State<Option<PullRequestConfirmation>>,
    pull_request_ai: AiTextGenerationState,
    forge_collapsed_check_groups: State<HashSet<String>>,
    forge_expanded_checks: State<HashSet<String>>,
) -> Element {
    if let Some(reason) = snapshot.unavailable_reason {
        let (title, message) = match reason {
            ForgeUnavailableReason::NoRemote => (
                "No Remote",
                "This Repository Has No Remote To Detect A Provider From.",
            ),
            ForgeUnavailableReason::ProviderNotDetected => (
                "Provider Not Detected",
                "Could Not Detect The Git Hosting Provider. Set It In Project Settings.",
            ),
            ForgeUnavailableReason::UnsupportedProvider => (
                "Unsupported Provider",
                "This Hosting Provider Is Not Supported Yet.",
            ),
        };
        return pull_request_message(Some(title), message);
    }
    match snapshot.auth_status {
        ForgeAuthStatus::CliMissing => {
            return pull_request_message(
                Some("CLI Not Found"),
                "Install `gh` And Ensure It Is On Your PATH.",
            );
        }
        ForgeAuthStatus::NotAuthenticated => {
            return pull_request_message(
                Some("Not Authenticated"),
                "Run `gh auth login` To Sign In, Then Refresh.",
            );
        }
        ForgeAuthStatus::Unknown | ForgeAuthStatus::Authenticated => {}
    }
    let Some(review) = snapshot.review.as_ref() else {
        return pull_request_composer(
            snapshot,
            bridge,
            forge_service,
            workspace_id,
            workspace_path,
            composer_mode,
            forge_title,
            forge_body,
            forge_base,
            forge_link,
            forge_create_draft,
            forge_action_loading,
            forge_action_error,
            refresh_revision,
            pull_request_ai,
        );
    };

    let state_label = if review.draft {
        "Draft"
    } else if review.state.eq_ignore_ascii_case("open") {
        "Open"
    } else if review.state.eq_ignore_ascii_case("merged") {
        "Merged"
    } else {
        "Closed"
    };
    let state_color = match state_label {
        "Open" => SUCCESS,
        "Merged" => (168, 85, 247),
        "Closed" => (248, 113, 113),
        _ => MUTED,
    };
    let checks = pull_request_checks(
        &snapshot.checks,
        forge_collapsed_check_groups,
        forge_expanded_checks,
    );
    let editing = *forge_editing.read();
    let busy = *forge_action_loading.read();
    let action_error = forge_action_error.read().clone();
    let review_number = review.number;
    let review_url = review.url.clone();
    let identity = forge_identity_from_snapshot(snapshot);
    let workspace_id_for_action = workspace_id.clone().unwrap_or_default();
    let workspace_path_for_action = workspace_path.clone();
    let identity_for_action = identity.clone();
    let review_url_for_action = review_url.clone();
    let mut confirmation_for_main = pull_request_confirmation;
    let primary_action = if review.draft {
        PullRequestReviewAction::MarkReady
    } else {
        PullRequestReviewAction::Merge
    };
    let main_action = move |event: Event<PointerEventData>| {
        event.stop_propagation();
        if busy {
            return;
        }
        let Some(identity) = identity_for_action.clone() else {
            return;
        };
        confirmation_for_main.set(Some(PullRequestConfirmation {
            action: primary_action,
            number: review_number,
            workspace_id: workspace_id_for_action.clone(),
            workspace_path: workspace_path_for_action.clone(),
            identity,
            review_url: review_url_for_action.clone(),
        }));
    };
    let action_options = pull_request_action_options(review.draft, &review.state);
    let workspace_id_for_menu = workspace_id.clone().unwrap_or_default();
    let workspace_path_for_menu = workspace_path.clone();
    let identity_for_menu = identity.clone();
    let review_url_for_menu = review_url.clone();
    let confirmation_for_menu = pull_request_confirmation;
    let open_actions = move |event: Event<PointerEventData>| {
        event.stop_propagation();
        if busy {
            return;
        }
        let Some(identity) = identity_for_menu.clone() else {
            return;
        };
        let mut menu = Menu::new();
        for option in action_options.clone() {
            let identity = identity.clone();
            let workspace_id = workspace_id_for_menu.clone();
            let workspace_path = workspace_path_for_menu.clone();
            let review_url = review_url_for_menu.clone();
            let mut confirmation = confirmation_for_menu;
            menu = menu.child(
                MenuButton::new()
                    .on_press(move |_| {
                        ContextMenu::close();
                        confirmation.set(Some(PullRequestConfirmation {
                            action: option,
                            number: review_number,
                            workspace_id: workspace_id.clone(),
                            workspace_path: workspace_path.clone(),
                            identity: identity.clone(),
                            review_url: review_url.clone(),
                        }));
                    })
                    .child(option.label()),
            );
        }
        ContextMenu::open_from_down(menu);
    };

    let mut editing_for_button = forge_editing;
    let mut title_for_edit = forge_title;
    let mut body_for_edit = forge_body;
    let mut base_for_edit = forge_base;
    let review_title_for_edit = review.title.clone();
    let review_body_for_edit = review.body.clone();
    let review_base_for_edit = review.base_branch.clone();
    let edit_button = move |event: Event<PointerEventData>| {
        event.stop_propagation();
        if busy {
            return;
        }
        title_for_edit.set(review_title_for_edit.clone());
        body_for_edit.set(review_body_for_edit.clone());
        base_for_edit.set(review_base_for_edit.clone());
        editing_for_button.set(true);
    };
    let review_header = if editing {
        pull_request_edit_form(
            review.number,
            review.body.clone(),
            snapshot.base_branches.clone(),
            forge_service.clone(),
            identity.clone(),
            workspace_path.clone(),
            forge_title,
            forge_body,
            forge_base,
            forge_action_loading,
            forge_action_error,
            forge_editing,
            refresh_revision,
        )
    } else {
        rect()
            .width(Size::fill())
            .vertical()
            .spacing(8.)
            .child(
                rect()
                    .horizontal()
                    .cross_align(Alignment::Center)
                    .spacing(8.)
                    .child(
                        SvgViewer::new(icons::lucide::git_pull_request())
                            .width(Size::px(16.))
                            .height(Size::px(16.))
                            .color(MUTED),
                    )
                    .child(
                        label()
                            .font_size(13.)
                            .color(TEXT)
                            .text(format!("#{}", review.number)),
                    )
                    .child(
                        rect()
                            .background(state_color)
                            .corner_radius(10.)
                            .padding(Gaps::new(7., 3., 7., 3.))
                            .child(label().font_size(9.).color(BACKGROUND).text(state_label)),
                    )
                    .child(rect().width(Size::flex(1.)).child(""))
                    .child(
                        TooltipContainer::new(Tooltip::new_text("Edit Pull Request"))
                            .position(AttachedPosition::Top)
                            .delay(Duration::from_millis(350))
                            .child(
                                rect()
                                    .width(Size::px(28.))
                                    .height(Size::px(28.))
                                    .corner_radius(5.)
                                    .center()
                                    .a11y_role(AccessibilityRole::Button)
                                    .a11y_alt("Edit Pull Request")
                                    .on_pointer_enter(|_| Cursor::set(CursorIcon::Pointer))
                                    .on_pointer_leave(|_| Cursor::set(CursorIcon::default()))
                                    .on_pointer_down(edit_button)
                                    .child(
                                        SvgViewer::new(icons::lucide::pencil())
                                            .width(Size::px(14.))
                                            .height(Size::px(14.))
                                            .color(MUTED),
                                    ),
                            ),
                    ),
            )
            .child(
                label()
                    .font_size(12.)
                    .color(TEXT)
                    .max_lines(2)
                    .text(review.title.clone()),
            )
            .child(label().font_size(10.).color(MUTED).text(format!(
                "{} · {} → {}",
                review.author, review.head_branch, review.base_branch
            )))
            .into_element()
    };
    let comments = snapshot.comments.iter().map(|comment| {
        let detail = match (&comment.path, comment.line) {
            (Some(path), Some(line)) => format!(" · {path}:{line}"),
            _ => String::new(),
        };
        rect()
            .width(Size::fill())
            .vertical()
            .spacing(3.)
            .padding(Gaps::new(0., 6., 0., 6.))
            .child(
                label()
                    .font_size(10.)
                    .color(MUTED)
                    .text(format!("{}{}", comment.author, detail)),
            )
            .child(
                label()
                    .font_size(11.)
                    .color(TEXT)
                    .max_lines(6)
                    .text(comment.body.clone()),
            )
    });
    let comment_body = forge_comment.read().trim().to_string();
    let comment_enabled = !busy && !comment_body.is_empty() && identity.is_some();
    let service_for_comment = forge_service.clone();
    let identity_for_comment = identity.clone();
    let workspace_path_for_comment = workspace_path.clone();
    let mut loading_for_comment = forge_action_loading;
    let mut error_for_comment = forge_action_error;
    let mut comment_for_submit = forge_comment;
    let mut refresh_for_comment = refresh_revision;
    let submit_comment = move |event: Event<PointerEventData>| {
        event.stop_propagation();
        if !comment_enabled {
            return;
        }
        let Some(identity) = identity_for_comment.clone() else {
            return;
        };
        let body = comment_for_submit.read().trim().to_string();
        loading_for_comment.set(true);
        error_for_comment.set(None);
        let service = service_for_comment.clone();
        let workspace_path = workspace_path_for_comment.clone();
        spawn(async move {
            match service
                .action(
                    workspace_path,
                    identity,
                    ForgeAction::Comment {
                        number: review_number,
                        body,
                    },
                )
                .await
            {
                Ok(_) => {
                    comment_for_submit.set(String::new());
                    let next = refresh_for_comment.read().saturating_add(1);
                    refresh_for_comment.set(next);
                }
                Err(error) => error_for_comment.set(Some(error)),
            }
            loading_for_comment.set(false);
        });
    };
    let action_label = primary_action.label();
    let action_background = if primary_action == PullRequestReviewAction::Close {
        (220, 38, 38)
    } else {
        ACCENT
    };
    let action_foreground = BACKGROUND;
    let error_view = action_error.map(|error| {
        label()
            .font_size(11.)
            .color((248, 113, 113))
            .max_lines(4)
            .text(error)
    });
    ScrollView::new()
        .width(Size::fill())
        .height(Size::fill())
        .show_scrollbar(true)
        .child(
            rect()
                .width(Size::fill())
                .vertical()
                .padding(Gaps::new_all(12.))
                .spacing(10.)
                .child(review_header)
                .child(checks)
                .maybe_child((!snapshot.comments.is_empty()).then(|| {
                    rect()
                        .width(Size::fill())
                        .vertical()
                        .spacing(3.)
                        .child(
                            label()
                                .font_size(11.)
                                .color(TEXT)
                                .text(format!("Comments ({})", snapshot.comments.len())),
                        )
                        .children(comments)
                }))
                .child(label().font_size(11.).color(MUTED).text("Add Comment"))
                .child(
                    rect()
                        .width(Size::fill())
                        .height(Size::px(72.))
                        .background(SURFACE)
                        .border(Border::new().width(1.).fill(BORDER))
                        .corner_radius(7.)
                        .padding(Gaps::new_all(5.))
                        .child(
                            Input::new(forge_comment)
                                .placeholder("Write A Comment")
                                .width(Size::fill())
                                .flat(),
                        ),
                )
                .child(
                    rect()
                        .width(Size::fill())
                        .height(Size::px(30.))
                        .horizontal()
                        .content(Content::Flex)
                        .child(
                            rect()
                                .width(Size::flex(1.))
                                .height(Size::fill())
                                .background(if comment_enabled {
                                    ACCENT
                                } else {
                                    (68, 68, 68)
                                })
                                .corner_radius(7.)
                                .center()
                                .a11y_role(AccessibilityRole::Button)
                                .a11y_alt("Add Comment")
                                .on_pointer_enter(move |_| {
                                    Cursor::set(if comment_enabled {
                                        CursorIcon::Pointer
                                    } else {
                                        CursorIcon::default()
                                    })
                                })
                                .on_pointer_leave(|_| Cursor::set(CursorIcon::default()))
                                .on_pointer_down(submit_comment)
                                .child(if busy {
                                    CircularLoader::new().size(14.).into_element()
                                } else {
                                    label()
                                        .font_size(11.)
                                        .color(if comment_enabled { BACKGROUND } else { MUTED })
                                        .text("Comment")
                                        .into_element()
                                }),
                        ),
                )
                .maybe_child(error_view)
                .child(
                    rect()
                        .width(Size::fill())
                        .height(Size::px(34.))
                        .horizontal()
                        .content(Content::Flex)
                        .overflow(Overflow::Clip)
                        .corner_radius(8.)
                        .child(
                            rect()
                                .width(Size::flex(1.))
                                .height(Size::fill())
                                .background(action_background)
                                .center()
                                .a11y_role(AccessibilityRole::Button)
                                .a11y_alt(action_label)
                                .on_pointer_enter(move |_| {
                                    Cursor::set(if busy {
                                        CursorIcon::default()
                                    } else {
                                        CursorIcon::Pointer
                                    })
                                })
                                .on_pointer_leave(|_| Cursor::set(CursorIcon::default()))
                                .on_pointer_down(main_action)
                                .child(if busy {
                                    CircularLoader::new().size(14.).into_element()
                                } else {
                                    label()
                                        .font_size(11.)
                                        .color(action_foreground)
                                        .text(action_label)
                                        .into_element()
                                }),
                        )
                        .child(
                            rect()
                                .width(Size::px(34.))
                                .height(Size::fill())
                                .background(action_background)
                                .border(Border::new().width(1.).fill((188, 188, 188)))
                                .center()
                                .a11y_role(AccessibilityRole::Button)
                                .a11y_alt("Pull Request Actions")
                                .on_pointer_enter(move |_| {
                                    Cursor::set(if busy {
                                        CursorIcon::default()
                                    } else {
                                        CursorIcon::Pointer
                                    })
                                })
                                .on_pointer_leave(|_| Cursor::set(CursorIcon::default()))
                                .on_pointer_down(open_actions)
                                .child(
                                    SvgViewer::new(icons::lucide::chevron_down())
                                        .width(Size::px(16.))
                                        .height(Size::px(16.))
                                        .color(action_foreground),
                                ),
                        ),
                ),
        )
        .into_element()
}

fn forge_identity_from_snapshot(snapshot: &ForgeSnapshot) -> Option<ForgeIdentity> {
    (!snapshot.repo_slug.is_empty() && !snapshot.branch.is_empty()).then(|| ForgeIdentity {
        host: snapshot.host.clone(),
        repo_slug: snapshot.repo_slug.clone(),
        branch: snapshot.branch.clone(),
        base_branches: snapshot.base_branches.clone(),
    })
}

fn pull_request_action_options(draft: bool, state: &str) -> Vec<PullRequestReviewAction> {
    let mut actions = Vec::new();
    if state.eq_ignore_ascii_case("open") {
        if draft {
            actions.push(PullRequestReviewAction::MarkReady);
        } else {
            actions.extend([
                PullRequestReviewAction::Merge,
                PullRequestReviewAction::Squash,
                PullRequestReviewAction::Rebase,
                PullRequestReviewAction::ConvertToDraft,
            ]);
        }
        actions.push(PullRequestReviewAction::Close);
    }
    actions.push(PullRequestReviewAction::Unlink);
    actions
}

#[allow(clippy::too_many_arguments)]
fn pull_request_composer(
    snapshot: &ForgeSnapshot,
    bridge: RuntimeBridge,
    forge_service: ForgeService,
    workspace_id: Option<String>,
    workspace_path: String,
    composer_mode: State<PullRequestComposerMode>,
    forge_title: State<String>,
    forge_body: State<String>,
    forge_base: State<String>,
    forge_link: State<String>,
    forge_create_draft: State<bool>,
    forge_action_loading: State<bool>,
    forge_action_error: State<Option<String>>,
    refresh_revision: State<u64>,
    pull_request_ai: AiTextGenerationState,
) -> Element {
    let mode = *composer_mode.read();
    let action_busy = *forge_action_loading.read();
    let ai_busy = *pull_request_ai.busy.read();
    let busy = action_busy || ai_busy;
    let identity = forge_identity_from_snapshot(snapshot);
    let mut branches = snapshot.base_branches.clone();
    if branches.is_empty() {
        branches.push(if snapshot.suggested_base_branch.is_empty() {
            "main".to_string()
        } else {
            snapshot.suggested_base_branch.clone()
        });
    }
    branches.sort();
    branches.dedup();
    let base_label = forge_base.read().clone();
    let base_for_menu = forge_base;
    let error_for_base = forge_action_error;
    let base_options = branches.clone();
    let open_base_menu = move |event: Event<PointerEventData>| {
        event.stop_propagation();
        if busy {
            return;
        }
        let mut menu = Menu::new();
        for branch in base_options.clone() {
            let selected = branch.clone();
            let mut base = base_for_menu;
            let mut error = error_for_base;
            menu = menu.child(
                MenuButton::new()
                    .on_press(move |_| {
                        ContextMenu::close();
                        base.set(selected.clone());
                        error.set(None);
                    })
                    .child(branch),
            );
        }
        ContextMenu::open_from_down(menu);
    };
    let base_field = rect()
        .width(Size::fill())
        .height(Size::px(34.))
        .horizontal()
        .content(Content::Flex)
        .cross_align(Alignment::Center)
        .background(SURFACE)
        .border(Border::new().width(1.).fill(BORDER))
        .corner_radius(7.)
        .padding(Gaps::new(10., 0., 8., 0.))
        .a11y_role(AccessibilityRole::Button)
        .a11y_alt("Base Branch")
        .on_pointer_enter(move |_| {
            Cursor::set(if busy {
                CursorIcon::default()
            } else {
                CursorIcon::Pointer
            })
        })
        .on_pointer_leave(|_| Cursor::set(CursorIcon::default()))
        .on_pointer_down(open_base_menu)
        .child(
            label()
                .width(Size::flex(1.))
                .font_size(11.)
                .color(TEXT)
                .text(base_label),
        )
        .child(
            SvgViewer::new(icons::lucide::chevron_down())
                .width(Size::px(15.))
                .height(Size::px(15.))
                .color(MUTED),
        );

    let error_view = forge_action_error.read().clone().map(|error| {
        label()
            .font_size(11.)
            .color((248, 113, 113))
            .max_lines(4)
            .text(error)
    });
    let mut mode_for_toggle = composer_mode;
    let mut error_for_toggle = forge_action_error;
    let toggle_mode = move |event: Event<PointerEventData>| {
        event.stop_propagation();
        if busy {
            return;
        }
        mode_for_toggle.set(match mode {
            PullRequestComposerMode::Create => PullRequestComposerMode::Link,
            PullRequestComposerMode::Link => PullRequestComposerMode::Create,
        });
        error_for_toggle.set(None);
    };

    let body = match mode {
        PullRequestComposerMode::Create => {
            let enabled = !busy
                && identity.is_some()
                && !forge_title.read().trim().is_empty()
                && !forge_base.read().trim().is_empty();
            let can_generate = !action_busy
                && !ai_busy
                && !snapshot.branch.is_empty()
                && !forge_base.read().trim().is_empty();
            let bridge_for_ai = bridge.clone();
            let workspace_for_ai = workspace_path.clone();
            let head_for_ai = snapshot.branch.clone();
            let title_for_ai = forge_title;
            let body_for_ai = forge_body;
            let base_for_ai = forge_base;
            let ai_state_for_action = pull_request_ai;
            let ai_button = TooltipContainer::new(Tooltip::new_text(if ai_busy {
                "Cancel Pull Request Details Generation"
            } else {
                "Generate Pull Request Details"
            }))
            .position(AttachedPosition::Top)
            .delay(Duration::from_millis(350))
            .child(
                rect()
                    .width(Size::px(24.))
                    .height(Size::px(24.))
                    .corner_radius(5.)
                    .center()
                    .a11y_role(AccessibilityRole::Button)
                    .a11y_alt(if ai_busy {
                        "Cancel Pull Request Details Generation"
                    } else {
                        "Generate Pull Request Details"
                    })
                    .on_pointer_enter(move |_| {
                        Cursor::set(if can_generate || ai_busy {
                            CursorIcon::Pointer
                        } else {
                            CursorIcon::default()
                        })
                    })
                    .on_pointer_leave(|_| Cursor::set(CursorIcon::default()))
                    .on_pointer_down(move |event: Event<PointerEventData>| {
                        event.stop_propagation();
                        if can_generate || ai_busy {
                            toggle_pull_request_generation(
                                bridge_for_ai.clone(),
                                workspace_for_ai.clone(),
                                head_for_ai.clone(),
                                title_for_ai,
                                body_for_ai,
                                base_for_ai,
                                ai_state_for_action,
                                can_generate,
                            );
                        }
                    })
                    .child(if ai_busy {
                        CircularLoader::new().size(14.).into_element()
                    } else {
                        SvgViewer::new(icons::lucide::sparkles())
                            .width(Size::px(14.))
                            .height(Size::px(14.))
                            .color(if can_generate { MUTED } else { FAINT })
                            .into_element()
                    }),
            );
            let draft = *forge_create_draft.read();
            let create_label = if draft {
                "Draft Pull Request"
            } else {
                "Create Pull Request"
            };
            let draft_for_menu = forge_create_draft;
            let open_create_menu = move |event: Event<PointerEventData>| {
                event.stop_propagation();
                if busy {
                    return;
                }
                let mut publish = draft_for_menu;
                let mut draft_state = draft_for_menu;
                ContextMenu::open_from_down(
                    Menu::new()
                        .child(
                            MenuButton::new()
                                .on_press(move |_| {
                                    ContextMenu::close();
                                    publish.set(false);
                                })
                                .child("Create Pull Request"),
                        )
                        .child(
                            MenuButton::new()
                                .on_press(move |_| {
                                    ContextMenu::close();
                                    draft_state.set(true);
                                })
                                .child("Draft Pull Request"),
                        ),
                );
            };
            let service_for_create = forge_service.clone();
            let bridge_for_create = bridge.clone();
            let workspace_id_for_create = workspace_id.clone();
            let workspace_path_for_create = workspace_path.clone();
            let identity_for_create = identity.clone();
            let mut loading_for_create = forge_action_loading;
            let mut error_for_create = forge_action_error;
            let title_for_create = forge_title;
            let body_for_create = forge_body;
            let base_for_create = forge_base;
            let mut refresh_for_create = refresh_revision;
            let submit_create = move |event: Event<PointerEventData>| {
                event.stop_propagation();
                if busy {
                    return;
                }
                let title = title_for_create.read().trim().to_string();
                let base = base_for_create.read().trim().to_string();
                if title.is_empty() {
                    error_for_create.set(Some("Title Is Required".to_string()));
                    return;
                }
                if base.is_empty() {
                    error_for_create.set(Some("Base Branch Is Required".to_string()));
                    return;
                }
                let Some(identity) = identity_for_create.clone() else {
                    error_for_create.set(Some("Repository Identity Is Not Available".to_string()));
                    return;
                };
                let Some(workspace_id) = workspace_id_for_create.clone() else {
                    error_for_create.set(Some("Workspace Is Not Available".to_string()));
                    return;
                };
                let body = body_for_create.read().trim().to_string();
                loading_for_create.set(true);
                error_for_create.set(None);
                let service = service_for_create.clone();
                let bridge = bridge_for_create.clone();
                let workspace_path = workspace_path_for_create.clone();
                spawn(async move {
                    let result = async {
                        service
                            .action(
                                workspace_path.clone(),
                                identity.clone(),
                                ForgeAction::Create {
                                    title,
                                    body,
                                    base,
                                    draft,
                                },
                            )
                            .await?;
                        let refreshed = service
                            .snapshot(workspace_path, identity, None, false)
                            .await?;
                        let review = refreshed.review.ok_or_else(|| {
                            "Created Pull Request Could Not Be Reloaded".to_string()
                        })?;
                        upsert_linked_review(&bridge, &workspace_id, &review, false).await
                    }
                    .await;
                    match result {
                        Ok(()) => {
                            let next = refresh_for_create.read().saturating_add(1);
                            refresh_for_create.set(next);
                        }
                        Err(error) => error_for_create.set(Some(error)),
                    }
                    loading_for_create.set(false);
                });
            };
            rect()
                .width(Size::fill())
                .vertical()
                .spacing(9.)
                .child(label().font_size(11.).color(MUTED).text("Base Branch"))
                .child(base_field)
                .child(
                    rect()
                        .width(Size::fill())
                        .height(Size::px(24.))
                        .horizontal()
                        .content(Content::Flex)
                        .cross_align(Alignment::Center)
                        .child(
                            label()
                                .width(Size::flex(1.))
                                .font_size(11.)
                                .color(MUTED)
                                .text("Title"),
                        )
                        .child(ai_button),
                )
                .child(pull_request_text_field_enabled(
                    forge_title,
                    "Title",
                    34.,
                    !busy,
                ))
                .child(label().font_size(11.).color(MUTED).text("Description"))
                .child(
                    rect()
                        .position(Position::new_stacked())
                        .width(Size::fill())
                        .height(Size::px(96.))
                        .child(pull_request_text_field_enabled(
                            forge_body,
                            "Description",
                            96.,
                            !busy,
                        ))
                        .maybe_child(ai_busy.then(|| {
                            rect()
                                .position(Position::new_absolute().top(0.).left(0.))
                                .layer(Layer::Overlay)
                                .width(Size::fill())
                                .height(Size::fill())
                                .background(Color::from_af32rgb(0.58, 0, 0, 0))
                                .center()
                                .child(
                                    rect()
                                        .horizontal()
                                        .cross_align(Alignment::Center)
                                        .spacing(8.)
                                        .padding(Gaps::new(10., 7., 10., 7.))
                                        .background(SURFACE_RAISED)
                                        .border(Border::new().width(1.).fill(BORDER))
                                        .corner_radius(6.)
                                        .child(CircularLoader::new().size(14.))
                                        .child(
                                            label()
                                                .font_size(11.)
                                                .color(MUTED)
                                                .text("Generating With AI"),
                                        ),
                                )
                        })),
                )
                .maybe_child(pull_request_ai.message.read().clone().map(|message| {
                    label()
                        .font_size(10.)
                        .color(if message.contains("Generated With") {
                            SUCCESS
                        } else {
                            MUTED
                        })
                        .max_lines(3)
                        .text(message)
                }))
                .maybe_child(error_view)
                .child(
                    rect()
                        .width(Size::fill())
                        .height(Size::px(30.))
                        .horizontal()
                        .content(Content::Flex)
                        .overflow(Overflow::Clip)
                        .corner_radius(8.)
                        .child(
                            rect()
                                .width(Size::flex(1.))
                                .height(Size::fill())
                                .background(if enabled { ACCENT } else { (68, 68, 68) })
                                .center()
                                .a11y_role(AccessibilityRole::Button)
                                .a11y_alt(create_label)
                                .on_pointer_enter(move |_| {
                                    Cursor::set(if enabled {
                                        CursorIcon::Pointer
                                    } else {
                                        CursorIcon::default()
                                    })
                                })
                                .on_pointer_leave(|_| Cursor::set(CursorIcon::default()))
                                .on_pointer_down(submit_create)
                                .child(if busy {
                                    CircularLoader::new().size(14.).into_element()
                                } else {
                                    label()
                                        .font_size(11.)
                                        .color(if enabled { BACKGROUND } else { MUTED })
                                        .text(create_label)
                                        .into_element()
                                }),
                        )
                        .child(
                            rect()
                                .width(Size::px(34.))
                                .height(Size::fill())
                                .background(if busy { (68, 68, 68) } else { ACCENT })
                                .border(Border::new().width(1.).fill((188, 188, 188)))
                                .center()
                                .a11y_role(AccessibilityRole::Button)
                                .a11y_alt("Create Options")
                                .on_pointer_enter(move |_| {
                                    Cursor::set(if busy {
                                        CursorIcon::default()
                                    } else {
                                        CursorIcon::Pointer
                                    })
                                })
                                .on_pointer_leave(|_| Cursor::set(CursorIcon::default()))
                                .on_pointer_down(open_create_menu)
                                .child(
                                    SvgViewer::new(icons::lucide::chevron_down())
                                        .width(Size::px(16.))
                                        .height(Size::px(16.))
                                        .color(if busy { MUTED } else { BACKGROUND }),
                                ),
                        ),
                )
                .into_element()
        }
        PullRequestComposerMode::Link => {
            let link_value = forge_link.read().trim().to_string();
            let enabled = !busy && !link_value.is_empty() && identity.is_some();
            let service_for_link = forge_service.clone();
            let bridge_for_link = bridge.clone();
            let workspace_id_for_link = workspace_id.clone();
            let workspace_path_for_link = workspace_path.clone();
            let identity_for_link = identity.clone();
            let link_for_submit = forge_link;
            let mut loading_for_link = forge_action_loading;
            let mut error_for_link = forge_action_error;
            let mut refresh_for_link = refresh_revision;
            let submit_link = move |event: Event<PointerEventData>| {
                event.stop_propagation();
                if busy {
                    return;
                }
                let value = link_for_submit.read().trim().to_string();
                let Some(number) = parse_pull_request_number(&value) else {
                    error_for_link.set(Some("Enter A PR Number Or URL".to_string()));
                    return;
                };
                let Some(identity) = identity_for_link.clone() else {
                    error_for_link.set(Some("Repository Identity Is Not Available".to_string()));
                    return;
                };
                let Some(workspace_id) = workspace_id_for_link.clone() else {
                    error_for_link.set(Some("Workspace Is Not Available".to_string()));
                    return;
                };
                loading_for_link.set(true);
                error_for_link.set(None);
                let service = service_for_link.clone();
                let bridge = bridge_for_link.clone();
                let workspace_path = workspace_path_for_link.clone();
                spawn(async move {
                    let result = async {
                        let linked = service
                            .snapshot(workspace_path, identity, Some(number), false)
                            .await?;
                        let review = linked
                            .review
                            .ok_or_else(|| format!("Pull Request #{number} Could Not Be Found"))?;
                        upsert_linked_review(&bridge, &workspace_id, &review, false).await
                    }
                    .await;
                    match result {
                        Ok(()) => {
                            let next = refresh_for_link.read().saturating_add(1);
                            refresh_for_link.set(next);
                        }
                        Err(error) => error_for_link.set(Some(error)),
                    }
                    loading_for_link.set(false);
                });
            };
            rect()
                .width(Size::fill())
                .vertical()
                .spacing(9.)
                .child(label().font_size(13.).color(TEXT).text("Link Pull Request"))
                .child(
                    label()
                        .font_size(11.)
                        .color(MUTED)
                        .text("Pull Request Number Or URL"),
                )
                .child(pull_request_text_field(
                    forge_link,
                    "#123 Or GitHub URL",
                    34.,
                ))
                .maybe_child(error_view)
                .child(
                    rect()
                        .width(Size::fill())
                        .height(Size::px(30.))
                        .background(if enabled { ACCENT } else { (68, 68, 68) })
                        .corner_radius(8.)
                        .center()
                        .a11y_role(AccessibilityRole::Button)
                        .a11y_alt("Link")
                        .on_pointer_enter(move |_| {
                            Cursor::set(if enabled {
                                CursorIcon::Pointer
                            } else {
                                CursorIcon::default()
                            })
                        })
                        .on_pointer_leave(|_| Cursor::set(CursorIcon::default()))
                        .on_pointer_down(submit_link)
                        .child(if busy {
                            CircularLoader::new().size(14.).into_element()
                        } else {
                            label()
                                .font_size(11.)
                                .color(if enabled { BACKGROUND } else { MUTED })
                                .text("Link")
                                .into_element()
                        }),
                )
                .into_element()
        }
    };
    let toggle_label = match mode {
        PullRequestComposerMode::Create => "Link Existing Pull Request",
        PullRequestComposerMode::Link => "Create Pull Request",
    };
    ScrollView::new()
        .width(Size::fill())
        .height(Size::fill())
        .show_scrollbar(true)
        .child(
            rect()
                .width(Size::fill())
                .vertical()
                .padding(Gaps::new_all(12.))
                .spacing(12.)
                .child(body)
                .child(
                    rect()
                        .width(Size::fill())
                        .height(Size::px(28.))
                        .center()
                        .corner_radius(7.)
                        .a11y_role(AccessibilityRole::Button)
                        .a11y_alt(toggle_label)
                        .on_pointer_enter(move |_| {
                            Cursor::set(if busy {
                                CursorIcon::default()
                            } else {
                                CursorIcon::Pointer
                            })
                        })
                        .on_pointer_leave(|_| Cursor::set(CursorIcon::default()))
                        .on_pointer_down(toggle_mode)
                        .child(label().font_size(11.).color(MUTED).text(toggle_label)),
                ),
        )
        .into_element()
}

fn pull_request_text_field(
    value: State<String>,
    placeholder: &'static str,
    height: f32,
) -> Element {
    pull_request_text_field_enabled(value, placeholder, height, true)
}

fn pull_request_text_field_enabled(
    value: State<String>,
    placeholder: &'static str,
    height: f32,
    enabled: bool,
) -> Element {
    rect()
        .width(Size::fill())
        .height(Size::px(height))
        .background(SURFACE)
        .border(Border::new().width(1.).fill(BORDER))
        .corner_radius(7.)
        .padding(Gaps::new_all(5.))
        .child(
            Input::new(value)
                .placeholder(placeholder)
                .width(Size::fill())
                .enabled(enabled)
                .flat(),
        )
        .into_element()
}

fn parse_pull_request_number(value: &str) -> Option<u64> {
    value
        .trim()
        .trim_end_matches('/')
        .rsplit(['/', '#'])
        .next()
        .and_then(|value| value.parse::<u64>().ok())
        .filter(|number| *number > 0)
}

async fn upsert_linked_review(
    bridge: &RuntimeBridge,
    workspace_id: &str,
    review: &alera_desktop_core::ForgeReview,
    dismissed: bool,
) -> Result<(), String> {
    bridge
        .request(
            "linkedReview.upsert",
            json!({
                "workspaceId": workspace_id,
                "dismissed": dismissed,
                "provider": "github",
                "number": review.number,
                "url": review.url,
                "linkedAt": chrono::Utc::now().to_rfc3339(),
            }),
        )
        .await
        .map(|_| ())
}

#[allow(clippy::too_many_arguments)]
fn pull_request_edit_form(
    number: u64,
    current_body: String,
    branches: Vec<String>,
    forge_service: ForgeService,
    identity: Option<ForgeIdentity>,
    workspace_path: String,
    forge_title: State<String>,
    forge_body: State<String>,
    forge_base: State<String>,
    forge_action_loading: State<bool>,
    forge_action_error: State<Option<String>>,
    forge_editing: State<bool>,
    refresh_revision: State<u64>,
) -> Element {
    let busy = *forge_action_loading.read();
    let base_label = forge_base.read().clone();
    let base_for_menu = forge_base;
    let options = branches;
    let open_base_menu = move |event: Event<PointerEventData>| {
        event.stop_propagation();
        if busy {
            return;
        }
        let mut menu = Menu::new();
        for branch in options.clone() {
            let selected = branch.clone();
            let mut base = base_for_menu;
            menu = menu.child(
                MenuButton::new()
                    .on_press(move |_| {
                        ContextMenu::close();
                        base.set(selected.clone());
                    })
                    .child(branch),
            );
        }
        ContextMenu::open_from_down(menu);
    };
    let mut editing_for_cancel = forge_editing;
    let cancel = move |event: Event<PointerEventData>| {
        event.stop_propagation();
        if !busy {
            editing_for_cancel.set(false);
        }
    };
    let service_for_save = forge_service;
    let identity_for_save = identity;
    let title_for_save = forge_title;
    let body_for_save = forge_body;
    let base_for_save = forge_base;
    let mut loading_for_save = forge_action_loading;
    let mut error_for_save = forge_action_error;
    let mut editing_for_save = forge_editing;
    let mut refresh_for_save = refresh_revision;
    let submit = move |event: Event<PointerEventData>| {
        event.stop_propagation();
        if busy {
            return;
        }
        let title = title_for_save.read().trim().to_string();
        let base = base_for_save.read().trim().to_string();
        if title.is_empty() {
            error_for_save.set(Some("Title Is Required".to_string()));
            return;
        }
        if base.is_empty() {
            error_for_save.set(Some("Base Branch Is Required".to_string()));
            return;
        }
        let Some(identity) = identity_for_save.clone() else {
            error_for_save.set(Some("Repository Identity Is Not Available".to_string()));
            return;
        };
        loading_for_save.set(true);
        error_for_save.set(None);
        let service = service_for_save.clone();
        let workspace_path = workspace_path.clone();
        let body = body_for_save.read().trim().to_string();
        spawn(async move {
            match service
                .action(
                    workspace_path,
                    identity,
                    ForgeAction::Update {
                        number,
                        title,
                        body,
                        base,
                    },
                )
                .await
            {
                Ok(_) => {
                    editing_for_save.set(false);
                    let next = refresh_for_save.read().saturating_add(1);
                    refresh_for_save.set(next);
                }
                Err(error) => error_for_save.set(Some(error)),
            }
            loading_for_save.set(false);
        });
    };
    rect()
        .width(Size::fill())
        .vertical()
        .spacing(7.)
        .child(label().font_size(11.).color(MUTED).text("Title"))
        .child(pull_request_text_field(forge_title, "Title", 34.))
        .child(label().font_size(11.).color(MUTED).text("Base Branch"))
        .child(
            rect()
                .width(Size::fill())
                .height(Size::px(34.))
                .horizontal()
                .cross_align(Alignment::Center)
                .background(SURFACE)
                .border(Border::new().width(1.).fill(BORDER))
                .corner_radius(7.)
                .padding(Gaps::new(10., 0., 8., 0.))
                .a11y_role(AccessibilityRole::Button)
                .a11y_alt("Base Branch")
                .on_pointer_enter(|_| Cursor::set(CursorIcon::Pointer))
                .on_pointer_leave(|_| Cursor::set(CursorIcon::default()))
                .on_pointer_down(open_base_menu)
                .child(
                    label()
                        .width(Size::flex(1.))
                        .font_size(11.)
                        .color(TEXT)
                        .text(base_label),
                )
                .child(
                    SvgViewer::new(icons::lucide::chevron_down())
                        .width(Size::px(15.))
                        .height(Size::px(15.))
                        .color(MUTED),
                ),
        )
        .child(label().font_size(11.).color(MUTED).text("Description"))
        .child(pull_request_text_field(
            forge_body,
            if current_body.is_empty() {
                "Description"
            } else {
                "Edit Description"
            },
            86.,
        ))
        .child(
            rect()
                .width(Size::fill())
                .height(Size::px(30.))
                .horizontal()
                .content(Content::Flex)
                .spacing(7.)
                .child(rect().width(Size::flex(1.)).child(""))
                .child(
                    rect()
                        .height(Size::fill())
                        .padding(Gaps::new(10., 0., 10., 0.))
                        .center()
                        .corner_radius(7.)
                        .a11y_role(AccessibilityRole::Button)
                        .a11y_alt("Cancel Editing")
                        .on_pointer_enter(|_| Cursor::set(CursorIcon::Pointer))
                        .on_pointer_leave(|_| Cursor::set(CursorIcon::default()))
                        .on_pointer_down(cancel)
                        .child(label().font_size(11.).color(MUTED).text("Cancel")),
                )
                .child(
                    rect()
                        .height(Size::fill())
                        .padding(Gaps::new(12., 0., 12., 0.))
                        .center()
                        .background(if busy { (68, 68, 68) } else { ACCENT })
                        .corner_radius(7.)
                        .a11y_role(AccessibilityRole::Button)
                        .a11y_alt("Save Pull Request")
                        .on_pointer_enter(move |_| {
                            Cursor::set(if busy {
                                CursorIcon::default()
                            } else {
                                CursorIcon::Pointer
                            })
                        })
                        .on_pointer_leave(|_| Cursor::set(CursorIcon::default()))
                        .on_pointer_down(submit)
                        .child(if busy {
                            CircularLoader::new().size(14.).into_element()
                        } else {
                            label()
                                .font_size(11.)
                                .color(BACKGROUND)
                                .text("Save")
                                .into_element()
                        }),
                ),
        )
        .into_element()
}

fn pull_request_confirmation_overlay(
    dialog: PullRequestConfirmation,
    pull_request_confirmation: State<Option<PullRequestConfirmation>>,
    pull_request_confirmation_loading: State<bool>,
    pull_request_confirmation_error: State<Option<String>>,
    forge_refresh_revision: State<u64>,
    bridge: RuntimeBridge,
    forge_service: ForgeService,
) -> Element {
    let busy = *pull_request_confirmation_loading.read();
    let destructive = dialog.action == PullRequestReviewAction::Close;
    let title = dialog.action.label();
    let description = match dialog.action {
        PullRequestReviewAction::Merge => "Merge This Pull Request Using A Merge Commit?",
        PullRequestReviewAction::Squash => "Squash All Commits And Merge This Pull Request?",
        PullRequestReviewAction::Rebase => "Rebase And Merge This Pull Request?",
        PullRequestReviewAction::MarkReady => "Mark This Pull Request Ready For Review?",
        PullRequestReviewAction::ConvertToDraft => "Convert This Pull Request Back To Draft?",
        PullRequestReviewAction::Close => "Close This Pull Request Without Merging It?",
        PullRequestReviewAction::Unlink => "Stop Tracking This Pull Request In Alera?",
    };
    let mut close_from_overlay = pull_request_confirmation;
    let mut error_from_overlay = pull_request_confirmation_error;
    let mut close_from_cancel = pull_request_confirmation;
    let mut error_from_cancel = pull_request_confirmation_error;
    let mut loading_for_confirm = pull_request_confirmation_loading;
    let mut error_for_confirm = pull_request_confirmation_error;
    let mut close_for_confirm = pull_request_confirmation;
    let mut refresh_for_confirm = forge_refresh_revision;
    let dialog_for_confirm = dialog.clone();
    let confirm = move |event: Event<PointerEventData>| {
        event.stop_propagation();
        if busy {
            return;
        }
        loading_for_confirm.set(true);
        error_for_confirm.set(None);
        let service = forge_service.clone();
        let bridge = bridge.clone();
        let dialog = dialog_for_confirm.clone();
        spawn(async move {
            let result = if dialog.action == PullRequestReviewAction::Unlink {
                bridge
                    .request(
                        "linkedReview.upsert",
                        json!({
                            "workspaceId": dialog.workspace_id,
                            "dismissed": true,
                            "provider": "github",
                            "number": dialog.number,
                            "url": dialog.review_url,
                            "linkedAt": chrono::Utc::now().to_rfc3339(),
                        }),
                    )
                    .await
                    .map(|_| ())
            } else {
                let action = dialog
                    .action
                    .forge_action(dialog.number)
                    .ok_or_else(|| "Pull Request Action Is Not Available".to_string());
                match action {
                    Ok(action) => service
                        .action(dialog.workspace_path, dialog.identity, action)
                        .await
                        .map(|_| ()),
                    Err(error) => Err(error),
                }
            };
            match result {
                Ok(()) => {
                    close_for_confirm.set(None);
                    let next = refresh_for_confirm.read().saturating_add(1);
                    refresh_for_confirm.set(next);
                }
                Err(error) => error_for_confirm.set(Some(error)),
            }
            loading_for_confirm.set(false);
        });
    };
    let error_view = pull_request_confirmation_error.read().clone().map(|error| {
        label()
            .font_size(11.)
            .color((248, 113, 113))
            .max_lines(4)
            .text(error)
    });
    rect()
        .position(Position::new_absolute())
        .layer(Layer::Overlay)
        .width(Size::percent(100.))
        .height(Size::percent(100.))
        .background(Color::from_af32rgb(0.55, 0, 0, 0))
        .on_press(move |_| {
            if !busy {
                close_from_overlay.set(None);
                error_from_overlay.set(None);
            }
        })
        .child(
            rect()
                .position(Position::new_absolute())
                .width(Size::percent(100.))
                .height(Size::percent(100.))
                .center()
                .child(
                    rect()
                        .width(Size::px(430.))
                        .background(SURFACE_RAISED)
                        .border(Border::new().width(1.).fill(BORDER))
                        .corner_radius(10.)
                        .padding(Gaps::new_all(20.))
                        .vertical()
                        .spacing(13.)
                        .on_press(|event: Event<PressEventData>| event.stop_propagation())
                        .child(label().font_size(17.).color(TEXT).text(title))
                        .child(label().font_size(12.).color(MUTED).text(description))
                        .maybe_child(error_view)
                        .child(
                            rect()
                                .width(Size::fill())
                                .height(Size::px(30.))
                                .horizontal()
                                .content(Content::Flex)
                                .spacing(8.)
                                .child(rect().width(Size::flex(1.)).child(""))
                                .child(
                                    rect()
                                        .height(Size::fill())
                                        .padding(Gaps::new(10., 0., 10., 0.))
                                        .center()
                                        .corner_radius(7.)
                                        .a11y_role(AccessibilityRole::Button)
                                        .a11y_alt("Cancel")
                                        .on_pointer_enter(|_| Cursor::set(CursorIcon::Pointer))
                                        .on_pointer_leave(|_| Cursor::set(CursorIcon::default()))
                                        .on_pointer_down(move |event: Event<PointerEventData>| {
                                            event.stop_propagation();
                                            if !busy {
                                                close_from_cancel.set(None);
                                                error_from_cancel.set(None);
                                            }
                                        })
                                        .child(label().font_size(11.).color(MUTED).text("Cancel")),
                                )
                                .child(
                                    rect()
                                        .height(Size::fill())
                                        .padding(Gaps::new(12., 0., 12., 0.))
                                        .center()
                                        .background(if destructive {
                                            (220, 38, 38)
                                        } else {
                                            ACCENT
                                        })
                                        .corner_radius(7.)
                                        .a11y_role(AccessibilityRole::Button)
                                        .a11y_alt(title)
                                        .on_pointer_enter(move |_| {
                                            Cursor::set(if busy {
                                                CursorIcon::default()
                                            } else {
                                                CursorIcon::Pointer
                                            })
                                        })
                                        .on_pointer_leave(|_| Cursor::set(CursorIcon::default()))
                                        .on_pointer_down(confirm)
                                        .child(if busy {
                                            CircularLoader::new().size(14.).into_element()
                                        } else {
                                            label()
                                                .font_size(11.)
                                                .color(BACKGROUND)
                                                .text(title)
                                                .into_element()
                                        }),
                                ),
                        ),
                ),
        )
        .into_element()
}

fn pull_request_message(title: Option<&str>, message: &str) -> Element {
    rect()
        .width(Size::fill())
        .height(Size::fill())
        .center()
        .padding(Gaps::new_all(20.))
        .child(
            rect()
                .vertical()
                .cross_align(Alignment::Center)
                .spacing(9.)
                .child(
                    SvgViewer::new(icons::lucide::git_pull_request())
                        .width(Size::px(28.))
                        .height(Size::px(28.))
                        .color(MUTED),
                )
                .maybe_child(
                    title.map(|title| label().font_size(13.).color(TEXT).text(title.to_string())),
                )
                .child(
                    label()
                        .font_size(11.)
                        .color(MUTED)
                        .max_lines(4)
                        .text_align(TextAlign::Center)
                        .text(message.to_string()),
                ),
        )
        .into_element()
}

#[derive(Clone, Debug, PartialEq, Eq)]
struct SourceControlScopeView {
    workspace_id: String,
    workspace_path: String,
    path: String,
    relative_root: Option<String>,
}

fn working_tree_diff_request(
    scope: &SourceControlScopeView,
    source_relative_path: Option<String>,
    area: Option<String>,
) -> docking::GitDiffOpenRequest {
    match scope.relative_root.as_ref() {
        Some(root) => docking::GitDiffOpenRequest::working_tree_in_scope(
            scope.workspace_path.clone(),
            scope.path.clone(),
            root.clone(),
            source_relative_path,
            area,
        ),
        None => docking::GitDiffOpenRequest::working_tree(
            scope.workspace_path.clone(),
            source_relative_path,
            area,
        ),
    }
}

fn commit_diff_request(
    scope: &SourceControlScopeView,
    source_relative_path: Option<String>,
    source_old_path: Option<String>,
    commit_id: String,
    commit_subject: String,
) -> docking::GitDiffOpenRequest {
    match scope.relative_root.as_ref() {
        Some(root) => docking::GitDiffOpenRequest::commit_in_scope(
            scope.workspace_path.clone(),
            scope.path.clone(),
            root.clone(),
            source_relative_path,
            source_old_path,
            commit_id,
            commit_subject,
        ),
        None => docking::GitDiffOpenRequest::commit(
            scope.workspace_path.clone(),
            source_relative_path,
            source_old_path,
            commit_id,
            commit_subject,
        ),
    }
}

fn source_control_scope_from_prefs(
    project_kind: &str,
    workspace_id: &str,
    workspace_path: &str,
    prefs_record: Option<&Value>,
) -> Option<SourceControlScopeView> {
    let relative_root = match project_kind {
        "gitRepository" => None,
        "folder" => prefs_record
            .and_then(|record| record.get("prefs").unwrap_or(record).as_object())
            .and_then(|prefs| prefs.get("sourceControlRootByWorkspaceId"))
            .and_then(Value::as_object)
            .and_then(|roots| roots.get(workspace_id))
            .and_then(Value::as_str)
            .and_then(normalize_source_control_root),
        _ => return None,
    };
    if project_kind == "folder" && relative_root.is_none() {
        return None;
    }
    let path = relative_root.as_deref().map_or_else(
        || workspace_path.to_string(),
        |root| {
            PathBuf::from(workspace_path)
                .join(root)
                .to_string_lossy()
                .into_owned()
        },
    );
    Some(SourceControlScopeView {
        workspace_id: workspace_id.to_string(),
        workspace_path: workspace_path.to_string(),
        path,
        relative_root,
    })
}

fn normalize_source_control_root(value: &str) -> Option<String> {
    let value = value.replace('\\', "/");
    if value.starts_with('/') || value.as_bytes().get(1).copied() == Some(b':') {
        return None;
    }
    let mut parts = Vec::new();
    for part in value.split('/') {
        match part {
            "" | "." => {}
            ".." => {
                parts.pop()?;
            }
            part => parts.push(part),
        }
    }
    (!parts.is_empty()).then(|| parts.join("/"))
}

async fn update_source_control_root(
    bridge: &RuntimeBridge,
    workspace_id: Option<&str>,
    workspace_path: &str,
    relative_root: Option<String>,
) -> Result<(), String> {
    let workspace_id = workspace_id.ok_or_else(|| "Workspace Is Not Available".to_string())?;
    let normalized_root = match relative_root.as_deref() {
        Some(root) => Some(
            normalize_source_control_root(root)
                .ok_or_else(|| "Folder Is Not A Git Repository".to_string())?,
        ),
        None => None,
    };
    if let Some(root) = normalized_root.as_deref() {
        let candidate = PathBuf::from(workspace_path)
            .join(root)
            .to_string_lossy()
            .into_owned();
        bridge
            .request_with_timeout(
                "workspaceGit.snapshot",
                json!({"workspacePath": candidate}),
                Duration::from_secs(30),
            )
            .await
            .map_err(|_| "Folder Is Not A Git Repository".to_string())?;
    }
    let record = bridge.request("workbenchViewPrefs.get", json!({})).await?;
    let revision = record.get("revision").and_then(Value::as_i64);
    let mut prefs = record.get("prefs").cloned().unwrap_or_else(|| json!({}));
    let prefs_object = prefs
        .as_object_mut()
        .ok_or_else(|| "View Options Are Invalid".to_string())?;
    let roots = prefs_object
        .entry("sourceControlRootByWorkspaceId")
        .or_insert_with(|| json!({}));
    if !roots.is_object() {
        *roots = json!({});
    }
    let roots = roots
        .as_object_mut()
        .ok_or_else(|| "Source Control Roots Are Invalid".to_string())?;
    if let Some(root) = normalized_root {
        roots.insert(workspace_id.to_string(), Value::String(root));
    } else {
        roots.remove(workspace_id);
    }
    bridge
        .request(
            "workbenchViewPrefs.update",
            json!({"expectedRevision": revision, "prefs": prefs}),
        )
        .await?;
    Ok(())
}

fn sidebar_toolbar_button(
    key: &'static str,
    icon: Bytes,
    action: impl Into<EventHandler<Event<PointerEventData>>>,
) -> Element {
    rect()
        .key(key)
        .width(Size::px(28.))
        .height(Size::px(28.))
        .center()
        .corner_radius(6.)
        .a11y_role(AccessibilityRole::Button)
        .on_pointer_enter(|_| Cursor::set(CursorIcon::Pointer))
        .on_pointer_leave(|_| Cursor::set(CursorIcon::default()))
        .on_pointer_down(action)
        .child(
            SvgViewer::new(icon)
                .width(Size::px(14.))
                .height(Size::px(14.))
                .color(MUTED),
        )
        .into()
}

#[allow(clippy::too_many_arguments)]
fn sidebar_rows_view(
    rows: Vec<SidebarRow>,
    selected_workspace: State<String>,
    selected_tab_request: State<Option<String>>,
    active_tab_id: Option<String>,
    action_controls: SidebarActionControls,
    new_workspace_dialog: State<Option<ActionDialog>>,
    bridge: RuntimeBridge,
    prefs: SidebarViewPrefs,
) -> Element {
    let hovered = use_state(|| None::<String>);
    let selected_id = selected_workspace.read().clone();
    let mut list = rect()
        .width(Size::fill())
        .vertical()
        .content(Content::Flex)
        .padding(Gaps::new(4., 0., 8., 0.));
    for row in rows {
        let element = match row {
            SidebarRow::PinnedHeader { count, collapsed } => sidebar_section_row(
                "pinned-header",
                "Pinned",
                icons::lucide::pin(),
                count,
                collapsed,
                hovered,
                {
                    let bridge = bridge.clone();
                    move |_| {
                        update_sidebar_pref(
                            bridge.clone(),
                            "pinnedSectionCollapsed",
                            json!(!collapsed),
                        )
                    }
                },
            ),
            SidebarRow::AllHeader { count, collapsed } => sidebar_section_row(
                "all-header",
                "All",
                icons::lucide::list(),
                count,
                collapsed,
                hovered,
                {
                    let bridge = bridge.clone();
                    move |_| {
                        update_sidebar_pref(
                            bridge.clone(),
                            "allSectionCollapsed",
                            json!(!collapsed),
                        )
                    }
                },
            ),
            SidebarRow::ProjectHeader {
                id,
                name,
                count,
                collapsed,
                supports_linked_workspaces,
            } => sidebar_project_row(
                id,
                name,
                count,
                collapsed,
                supports_linked_workspaces,
                hovered,
                bridge.clone(),
                &prefs,
                action_controls,
                new_workspace_dialog,
            ),
            SidebarRow::Workspace(workspace) => sidebar_workspace_row(
                *workspace,
                selected_id.as_str(),
                selected_workspace,
                selected_tab_request,
                active_tab_id.as_deref(),
                hovered,
                bridge.clone(),
                &prefs,
                action_controls,
            ),
        };
        list = list.child(element);
    }
    list.into()
}

#[allow(clippy::too_many_arguments)]
fn collapsed_sidebar(
    projects: Vec<alera_desktop_core::Project>,
    active_project_id: Option<&str>,
    collapsed: State<bool>,
    mut selected_workspace: State<String>,
    mut action_dialog: State<Option<ActionDialog>>,
    mut action_dialog_error: State<Option<String>>,
    mut settings_open: State<bool>,
) -> Element {
    let active_project_id = active_project_id.map(str::to_string);
    let mut rail = rect()
        .width(Size::px(52.))
        .height(Size::fill())
        .background(SIDEBAR_BACKGROUND)
        .border(
            Border::new()
                .width(BorderWidth {
                    top: 0.,
                    right: 1.,
                    bottom: 0.,
                    left: 0.,
                })
                .fill(SIDEBAR_BORDER),
        )
        .vertical()
        .content(Content::Flex)
        .cross_align(Alignment::Center)
        .child(
            rect()
                .width(Size::fill())
                .height(Size::px(44.))
                .center()
                .child(
                    TooltipContainer::new(Tooltip::new_text("Toggle Sidebar"))
                        .position(AttachedPosition::Right)
                        .delay(Duration::from_millis(300))
                        .child(
                            rect()
                                .width(Size::px(32.))
                                .height(Size::px(32.))
                                .center()
                                .corner_radius(6.)
                                .a11y_role(AccessibilityRole::Button)
                                .a11y_alt("Toggle Sidebar")
                                .on_pointer_enter(|_| Cursor::set(CursorIcon::Pointer))
                                .on_pointer_leave(|_| Cursor::set(CursorIcon::default()))
                                .on_pointer_down(move |event: Event<PointerEventData>| {
                                    event.stop_propagation();
                                    let mut collapsed = collapsed;
                                    collapsed.set(false);
                                    spawn(async move {
                                        let _ = blocking::unblock(move || {
                                            local_settings::persist_fields([(
                                                "sidebar_collapsed",
                                                json!(false),
                                            )])
                                        })
                                        .await;
                                    });
                                })
                                .child(
                                    SvgViewer::new(icons::lucide::panel_left())
                                        .width(Size::px(16.))
                                        .height(Size::px(16.))
                                        .color(MUTED),
                                ),
                        ),
                ),
        )
        .child(
            rect()
                .width(Size::fill())
                .height(Size::px(1.))
                .background(SIDEBAR_BORDER),
        );
    let mut project_list = rect()
        .width(Size::fill())
        .height(Size::flex(1.))
        .vertical()
        .content(Content::Flex)
        .cross_align(Alignment::Center)
        .padding(Gaps::new(4., 0., 4., 0.));
    for project in projects {
        let is_active = active_project_id.as_deref() == Some(project.id.as_str());
        let project_name = project.name.clone();
        let workspace_id = project
            .workspaces
            .iter()
            .find(|workspace| workspace.kind == "main")
            .or_else(|| project.workspaces.first())
            .map(|workspace| workspace.id.clone());
        let initial = project
            .name
            .chars()
            .next()
            .map(|character| character.to_uppercase().to_string())
            .unwrap_or_else(|| "?".to_string());
        project_list = project_list.child(
            TooltipContainer::new(Tooltip::new_text(project_name))
                .position(AttachedPosition::Right)
                .delay(Duration::from_millis(300))
                .child(
                    rect()
                        .width(Size::px(32.))
                        .height(Size::px(32.))
                        .margin(Gaps::new(3., 0., 3., 0.))
                        .center()
                        .background(if is_active {
                            SURFACE_RAISED
                        } else {
                            SIDEBAR_BACKGROUND
                        })
                        .border(Border::new().width(1.).fill(if is_active {
                            BORDER
                        } else {
                            SIDEBAR_BORDER
                        }))
                        .corner_radius(6.)
                        .a11y_role(AccessibilityRole::Button)
                        .a11y_alt(format!("Project {}", project.name))
                        .on_pointer_enter(|_| Cursor::set(CursorIcon::Pointer))
                        .on_pointer_leave(|_| Cursor::set(CursorIcon::default()))
                        .on_pointer_down(move |event: Event<PointerEventData>| {
                            event.stop_propagation();
                            let mut collapsed = collapsed;
                            collapsed.set(false);
                            if let Some(workspace_id) = workspace_id.clone() {
                                selected_workspace.set(workspace_id);
                            }
                            spawn(async move {
                                let _ = blocking::unblock(move || {
                                    local_settings::persist_fields([(
                                        "sidebar_collapsed",
                                        json!(false),
                                    )])
                                })
                                .await;
                            });
                        })
                        .child(
                            label()
                                .font_size(13.)
                                .font_weight(FontWeight::SEMI_BOLD)
                                .color(if is_active { TEXT } else { MUTED })
                                .text(initial),
                        ),
                ),
        );
    }
    rail = rail.child(project_list).child(
        rect()
            .width(Size::fill())
            .height(Size::px(92.))
            .vertical()
            .content(Content::Flex)
            .main_align(Alignment::Center)
            .cross_align(Alignment::Center)
            .spacing(8.)
            .border(
                Border::new()
                    .width(BorderWidth {
                        top: 1.,
                        right: 0.,
                        bottom: 0.,
                        left: 0.,
                    })
                    .fill(SIDEBAR_BORDER),
            )
            .child(
                TooltipContainer::new(Tooltip::new_text("Add Project"))
                    .position(AttachedPosition::Right)
                    .delay(Duration::from_millis(300))
                    .child(sidebar_toolbar_button(
                        "collapsed-add-project",
                        icons::lucide::folder_plus(),
                        move |event: Event<PointerEventData>| {
                            event.stop_propagation();
                            action_dialog_error.set(None);
                            action_dialog.set(Some(ActionDialog::AddProject));
                        },
                    )),
            )
            .child(
                TooltipContainer::new(Tooltip::new_text("Open Settings"))
                    .position(AttachedPosition::Right)
                    .delay(Duration::from_millis(300))
                    .child(sidebar_toolbar_button(
                        "collapsed-open-settings",
                        icons::lucide::settings(),
                        move |event: Event<PointerEventData>| {
                            event.stop_propagation();
                            settings_open.set(true);
                        },
                    )),
            ),
    );
    rail.into_element()
}

fn sidebar_section_row(
    key: &'static str,
    title: &'static str,
    icon: Bytes,
    count: usize,
    collapsed: bool,
    hovered: State<Option<String>>,
    action: impl Into<EventHandler<Event<PointerEventData>>>,
) -> Element {
    let is_hovered = hovered.read().as_deref() == Some(key);
    let mut enter = hovered;
    let mut leave = hovered;
    rect()
        .width(Size::fill())
        .padding(Gaps::new(2., 8., 2., 8.))
        .child(
            rect()
                .key(key)
                .width(Size::fill())
                .height(Size::px(32.))
                .horizontal()
                .content(Content::Flex)
                .cross_align(Alignment::Center)
                .spacing(6.)
                .padding(Gaps::new(0., 8., 0., 8.))
                .background(if is_hovered {
                    SIDEBAR_HOVER
                } else {
                    SIDEBAR_BACKGROUND
                })
                .corner_radius(8.)
                .a11y_role(AccessibilityRole::Button)
                .a11y_alt(title)
                .on_pointer_enter(move |_| {
                    Cursor::set(CursorIcon::Pointer);
                    enter.set(Some(key.to_string()));
                })
                .on_pointer_leave(move |_| {
                    Cursor::set(CursorIcon::default());
                    leave.set(None);
                })
                .on_pointer_down(action)
                .child(
                    SvgViewer::new(icon)
                        .width(Size::px(14.))
                        .height(Size::px(14.))
                        .color(MUTED),
                )
                .child(
                    label()
                        .font_size(13.)
                        .font_weight(FontWeight::SEMI_BOLD)
                        .color(if is_hovered { TEXT } else { MUTED })
                        .text(title),
                )
                .child(rect().width(Size::flex(1.)).child(""))
                .child(
                    label()
                        .font_size(10.)
                        .font_weight(FontWeight::MEDIUM)
                        .color(FAINT)
                        .text(count.to_string()),
                )
                .child(
                    SvgViewer::new(if collapsed {
                        icons::lucide::chevron_down()
                    } else {
                        icons::lucide::chevron_up()
                    })
                    .width(Size::px(14.))
                    .height(Size::px(14.))
                    .color(MUTED),
                ),
        )
        .into()
}

#[allow(clippy::too_many_arguments)]
fn sidebar_project_row(
    project_id: String,
    name: String,
    count: usize,
    collapsed: bool,
    supports_linked_workspaces: bool,
    hovered: State<Option<String>>,
    bridge: RuntimeBridge,
    prefs: &SidebarViewPrefs,
    action_controls: SidebarActionControls,
    new_workspace_dialog: State<Option<ActionDialog>>,
) -> Element {
    let key = format!("project:{project_id}");
    let is_hovered = hovered.read().as_deref() == Some(key.as_str());
    let mut enter = hovered;
    let mut leave = hovered;
    let project_id_for_toggle = project_id.clone();
    let mut collapsed_ids = prefs.collapsed_project_ids.clone();
    if collapsed {
        collapsed_ids.remove(&project_id_for_toggle);
    } else {
        collapsed_ids.insert(project_id_for_toggle.clone());
    }
    let bridge_for_toggle = bridge.clone();
    let project_id_for_menu = project_id.clone();
    let project_name_for_menu = name.clone();
    let project_id_for_add = project_id;
    let mut new_workspace_dialog_for_add = new_workspace_dialog;
    rect()
        .width(Size::fill())
        .padding(Gaps::new(2., 8., 2., 8.))
        .child(
            rect()
                .key(key.clone())
                .width(Size::fill())
                .height(Size::px(32.))
                .horizontal()
                .content(Content::Flex)
                .cross_align(Alignment::Center)
                .spacing(6.)
                .padding(Gaps::new(0., 6., 0., 8.))
                .background(if is_hovered {
                    SIDEBAR_HOVER
                } else {
                    SIDEBAR_BACKGROUND
                })
                .corner_radius(8.)
                .a11y_role(AccessibilityRole::Button)
                .a11y_alt(format!("Project {name}"))
                .on_pointer_enter(move |_| {
                    Cursor::set(CursorIcon::Pointer);
                    enter.set(Some(key.clone()));
                })
                .on_pointer_leave(move |_| {
                    Cursor::set(CursorIcon::default());
                    leave.set(None);
                })
                .on_pointer_down(move |event: Event<PointerEventData>| {
                    event.stop_propagation();
                    update_sidebar_pref(
                        bridge_for_toggle.clone(),
                        "collapsedProjectIds",
                        string_set_json(&collapsed_ids),
                    );
                })
                .on_secondary_down(move |event: Event<PressEventData>| {
                    event.stop_propagation();
                    open_sidebar_project_menu(
                        project_id_for_menu.clone(),
                        project_name_for_menu.clone(),
                        action_controls,
                        new_workspace_dialog,
                    );
                })
                .child(
                    SvgViewer::new(if collapsed {
                        icons::lucide::folder()
                    } else {
                        icons::lucide::folder_open()
                    })
                    .width(Size::px(14.))
                    .height(Size::px(14.))
                    .color(MUTED),
                )
                .child(
                    label()
                        .font_size(13.)
                        .font_weight(FontWeight::SEMI_BOLD)
                        .color(if is_hovered { TEXT } else { MUTED })
                        .text(name),
                )
                .child(rect().width(Size::flex(1.)).child(""))
                .child(
                    label()
                        .font_size(10.)
                        .font_weight(FontWeight::MEDIUM)
                        .color(FAINT)
                        .text(count.to_string()),
                )
                .child(
                    SvgViewer::new(if collapsed {
                        icons::lucide::chevron_down()
                    } else {
                        icons::lucide::chevron_up()
                    })
                    .width(Size::px(14.))
                    .height(Size::px(14.))
                    .color(MUTED),
                )
                .maybe_child(supports_linked_workspaces.then(|| {
                    TooltipContainer::new(Tooltip::new_text("New Workspace in This Project"))
                        .position(AttachedPosition::Bottom)
                        .delay(Duration::from_millis(350))
                        .child(
                            rect()
                                .width(Size::px(24.))
                                .height(Size::px(24.))
                                .center()
                                .corner_radius(4.)
                                .a11y_role(AccessibilityRole::Button)
                                .a11y_alt("New Workspace in This Project")
                                .on_pointer_enter(|_| Cursor::set(CursorIcon::Pointer))
                                .on_pointer_down(move |event: Event<PointerEventData>| {
                                    event.stop_propagation();
                                    let mut target = action_controls.new_workspace_project_id;
                                    target.set(Some(project_id_for_add.clone()));
                                    new_workspace_dialog_for_add
                                        .set(Some(ActionDialog::NewWorkspace));
                                })
                                .child(
                                    SvgViewer::new(icons::lucide::plus())
                                        .width(Size::px(14.))
                                        .height(Size::px(14.))
                                        .color(MUTED),
                                ),
                        )
                })),
        )
        .into()
}

#[allow(clippy::too_many_arguments)]
fn sidebar_workspace_row(
    workspace: SidebarWorkspaceRow,
    selected_id: &str,
    selected_workspace: State<String>,
    selected_tab_request: State<Option<String>>,
    active_tab_id: Option<&str>,
    hovered: State<Option<String>>,
    bridge: RuntimeBridge,
    prefs: &SidebarViewPrefs,
    action_controls: SidebarActionControls,
) -> Element {
    let key = format!(
        "workspace:{}:{}",
        if workspace.is_pinned_copy {
            "pinned"
        } else {
            "regular"
        },
        workspace.id
    );
    let selected = selected_id == workspace.id;
    let is_hovered = hovered.read().as_deref() == Some(key.as_str());
    let mut enter = hovered;
    let mut leave = hovered;
    let mut selected_for_press = selected_workspace;
    let workspace_id_for_press = workspace.id.clone();
    let workspace_for_menu = workspace.clone();
    let bridge_for_menu = bridge.clone();
    let prefs_for_menu = prefs.clone();
    let mut content = rect()
        .width(Size::fill())
        .vertical()
        .content(Content::Flex)
        .spacing(4.)
        .padding(Gaps::new(6., 8., 6., 8.))
        .background(if selected {
            SURFACE_RAISED
        } else if is_hovered {
            SIDEBAR_HOVER
        } else {
            SIDEBAR_BACKGROUND
        })
        .corner_radius(8.)
        .a11y_role(AccessibilityRole::Button)
        .a11y_alt(format!("Workspace {}", workspace.name))
        .on_pointer_enter(move |_| {
            Cursor::set(CursorIcon::Pointer);
            enter.set(Some(key.clone()));
        })
        .on_pointer_leave(move |_| {
            Cursor::set(CursorIcon::default());
            leave.set(None);
        })
        .on_pointer_down(move |event: Event<PointerEventData>| {
            event.stop_propagation();
            selected_for_press.set(workspace_id_for_press.clone());
        })
        .on_secondary_down(move |event: Event<PressEventData>| {
            event.stop_propagation();
            open_sidebar_workspace_menu(
                workspace_for_menu.clone(),
                bridge_for_menu.clone(),
                prefs_for_menu.clone(),
                action_controls,
            );
        });

    let mut identity = rect()
        .width(Size::flex(1.))
        .horizontal()
        .content(Content::Flex)
        .cross_align(Alignment::Center)
        .spacing(6.)
        .child(
            label()
                .font_size(13.)
                .font_weight(FontWeight::SEMI_BOLD)
                .color(TEXT)
                .max_lines(1)
                .text(workspace.name.clone()),
        );
    if workspace.show_project_chip {
        identity = identity.child(workspace_meta_icon(
            icons::lucide::folder(),
            workspace.project_name.clone(),
        ));
    }
    if workspace.is_default {
        identity = identity.child(workspace_meta_icon(
            icons::lucide::house(),
            "Default Workspace".to_string(),
        ));
    }
    if workspace.is_pinned {
        identity = identity.child(workspace_meta_icon(
            icons::lucide::pin(),
            "Pinned Workspace".to_string(),
        ));
    }
    identity = identity.child(workspace_meta_icon(
        icons::lucide::git_branch(),
        workspace.branch_label.clone(),
    ));
    if !workspace.tag_names.is_empty() {
        identity = identity.child(workspace_tag_indicator(workspace.tag_names.clone()));
    }
    if let Some(host_id) = workspace.host_id.clone() {
        identity = identity.child(workspace_meta_icon(
            icons::lucide::server(),
            format!("Host: {host_id}"),
        ));
    }

    let mut heading = rect()
        .width(Size::fill())
        .horizontal()
        .content(Content::Flex)
        .cross_align(Alignment::Center)
        .spacing(8.)
        .child(sidebar_agent_state_indicator(
            workspace.aggregate_state(),
            selected || workspace.has_terminal_tabs,
            13.,
        ))
        .child(identity);
    if !workspace.agent_runs.is_empty() {
        heading = heading.child(workspace_agent_summary_control(
            &workspace,
            bridge.clone(),
            prefs,
        ));
    }
    if workspace.visible_child_count > 0 && !workspace.is_pinned_copy {
        heading = heading.child(workspace_children_control(
            &workspace,
            bridge.clone(),
            prefs,
        ));
    }
    content = content.child(heading);

    if workspace.agents_expanded && !workspace.agent_runs.is_empty() {
        let mut agent_rows = rect()
            .width(Size::fill())
            .vertical()
            .content(Content::Flex)
            .padding(Gaps::new(20., 0., 0., 0.));
        for run in workspace.agent_runs.clone() {
            let is_active = active_tab_id == Some(run.tab_id.as_str());
            agent_rows = agent_rows.child(sidebar_agent_run_row(
                workspace.id.clone(),
                run,
                selected_workspace,
                selected_tab_request,
                is_active,
                hovered,
                bridge.clone(),
            ));
        }
        content = content.child(agent_rows);
    }

    rect()
        .width(Size::fill())
        .padding(Gaps::new(
            2.,
            8.,
            2.,
            8. + (workspace.depth.min(4) as f32 * 12.),
        ))
        .child(content)
        .into()
}

fn workspace_meta_icon(icon: Bytes, tooltip: String) -> Element {
    TooltipContainer::new(Tooltip::new_text(tooltip))
        .position(AttachedPosition::Bottom)
        .delay(Duration::from_millis(350))
        .child(
            SvgViewer::new(icon)
                .width(Size::px(13.))
                .height(Size::px(13.))
                .color(FAINT),
        )
        .into()
}

fn workspace_tag_indicator(tags: Vec<String>) -> Element {
    TooltipContainer::new(Tooltip::new_text(tags.join(", ")))
        .position(AttachedPosition::Bottom)
        .delay(Duration::from_millis(350))
        .child(
            rect()
                .horizontal()
                .cross_align(Alignment::Center)
                .spacing(2.)
                .child(
                    SvgViewer::new(icons::lucide::tag())
                        .width(Size::px(13.))
                        .height(Size::px(13.))
                        .color(FAINT),
                )
                .child(
                    label()
                        .font_size(10.)
                        .color(FAINT)
                        .text(tags.len().to_string()),
                ),
        )
        .into()
}

fn workspace_agent_summary_control(
    workspace: &SidebarWorkspaceRow,
    bridge: RuntimeBridge,
    prefs: &SidebarViewPrefs,
) -> Element {
    let tooltip = if workspace.agents_expanded {
        "Hide Agent Runs".to_string()
    } else if workspace.agent_runs.len() == 1 {
        workspace.agent_runs[0].description.clone()
    } else {
        "Show Agent Runs".to_string()
    };
    let mut groups = Vec::<(AgentRunState, Vec<&SidebarAgentRun>)>::new();
    for state in [
        AgentRunState::Waiting,
        AgentRunState::Blocked,
        AgentRunState::Interrupted,
        AgentRunState::Working,
        AgentRunState::Done,
    ] {
        let runs = workspace
            .agent_runs
            .iter()
            .filter(|run| run.state == state)
            .collect::<Vec<_>>();
        if !runs.is_empty() {
            groups.push((state, runs));
        }
    }
    let mut expanded = prefs.expanded_workspace_ids.clone();
    if workspace.agents_expanded {
        expanded.remove(&workspace.id);
    } else {
        expanded.insert(workspace.id.clone());
    }
    let mut control = rect()
        .height(Size::px(24.))
        .horizontal()
        .content(Content::Flex)
        .cross_align(Alignment::Center)
        .spacing(6.)
        .padding(Gaps::new(2., 4., 2., 4.))
        .corner_radius(4.)
        .a11y_role(AccessibilityRole::Button)
        .a11y_alt(tooltip.clone())
        .on_pointer_enter(|_| Cursor::set(CursorIcon::Pointer))
        .on_pointer_leave(|_| Cursor::set(CursorIcon::default()));
    for (state, runs) in groups.into_iter().take(3) {
        control = control.child(workspace_agent_group_cluster(state, &runs));
    }
    let bridge_for_toggle = bridge;
    let control = control
        .child(
            SvgViewer::new(if workspace.agents_expanded {
                icons::lucide::chevron_up()
            } else {
                icons::lucide::chevron_down()
            })
            .width(Size::px(12.))
            .height(Size::px(12.))
            .color(MUTED),
        )
        .on_pointer_down(move |event: Event<PointerEventData>| {
            event.stop_propagation();
            update_sidebar_pref(
                bridge_for_toggle.clone(),
                "expandedWorkspaceIds",
                string_set_json(&expanded),
            );
        });
    TooltipContainer::new(Tooltip::new_text(tooltip))
        .position(AttachedPosition::Bottom)
        .delay(Duration::from_millis(350))
        .child(control)
        .into()
}

fn workspace_agent_group_cluster(state: AgentRunState, runs: &[&SidebarAgentRun]) -> Element {
    let mut agent_types = runs
        .iter()
        .map(|run| run.agent_type.clone())
        .collect::<Vec<_>>();
    agent_types.sort_unstable();
    agent_types.dedup();
    agent_types.truncate(3);
    let hidden_count = runs.len().saturating_sub(agent_types.len());
    let stack_width = 14. + agent_types.len().saturating_sub(1) as f32 * 10.;
    let mut stack = rect().width(Size::px(stack_width)).height(Size::px(14.));
    for (index, agent_type) in agent_types.into_iter().enumerate() {
        stack = stack.child(
            rect()
                .position(Position::new_absolute().left(index as f32 * 10.))
                .width(Size::px(14.))
                .height(Size::px(14.))
                .center()
                .corner_radius(7.)
                .background(SIDEBAR_BACKGROUND)
                .border(Border::new().width(1.).fill(SIDEBAR_BORDER))
                .child(agent_identity_icon(agent_type.as_str(), 9.)),
        );
    }
    rect()
        .horizontal()
        .content(Content::Flex)
        .cross_align(Alignment::Center)
        .spacing(2.)
        .child(sidebar_agent_state_indicator(Some(state), false, 11.))
        .child(stack)
        .maybe_child((hidden_count > 0).then(|| {
            label()
                .font_size(10.)
                .color(FAINT)
                .text(format!("+{hidden_count}"))
        }))
        .into()
}

fn workspace_children_control(
    workspace: &SidebarWorkspaceRow,
    bridge: RuntimeBridge,
    prefs: &SidebarViewPrefs,
) -> Element {
    let tooltip = if workspace.children_collapsed {
        "Show Child Workspaces"
    } else {
        "Hide Child Workspaces"
    };
    let mut collapsed = prefs.collapsed_parent_workspace_ids.clone();
    if workspace.children_collapsed {
        collapsed.remove(&workspace.id);
    } else {
        collapsed.insert(workspace.id.clone());
    }
    TooltipContainer::new(Tooltip::new_text(tooltip))
        .position(AttachedPosition::Bottom)
        .delay(Duration::from_millis(350))
        .child(
            rect()
                .height(Size::px(24.))
                .horizontal()
                .content(Content::Flex)
                .cross_align(Alignment::Center)
                .spacing(2.)
                .padding(Gaps::new(2., 4., 2., 4.))
                .corner_radius(4.)
                .a11y_role(AccessibilityRole::Button)
                .a11y_alt(tooltip)
                .on_pointer_enter(|_| Cursor::set(CursorIcon::Pointer))
                .on_pointer_leave(|_| Cursor::set(CursorIcon::default()))
                .on_pointer_down(move |event: Event<PointerEventData>| {
                    event.stop_propagation();
                    update_sidebar_pref(
                        bridge.clone(),
                        "collapsedParentWorkspaceIds",
                        string_set_json(&collapsed),
                    );
                })
                .child(
                    SvgViewer::new(icons::lucide::git_fork())
                        .width(Size::px(12.))
                        .height(Size::px(12.))
                        .color(MUTED),
                )
                .child(
                    label()
                        .font_size(10.)
                        .font_weight(FontWeight::SEMI_BOLD)
                        .color(MUTED)
                        .text(workspace.visible_child_count.to_string()),
                )
                .child(
                    SvgViewer::new(if workspace.children_collapsed {
                        icons::lucide::chevron_right()
                    } else {
                        icons::lucide::chevron_down()
                    })
                    .width(Size::px(12.))
                    .height(Size::px(12.))
                    .color(MUTED),
                ),
        )
        .into()
}

fn sidebar_agent_run_row(
    workspace_id: String,
    run: SidebarAgentRun,
    selected_workspace: State<String>,
    selected_tab_request: State<Option<String>>,
    is_active: bool,
    hovered: State<Option<String>>,
    bridge: RuntimeBridge,
) -> Element {
    let hover_key = format!("agent:{}", run.tab_id);
    let is_hovered = hovered.read().as_deref() == Some(hover_key.as_str());
    let actions_visible = is_hovered || is_active;
    let mut hover_enter = hovered;
    let mut hover_leave = hovered;
    let mut selected_workspace = selected_workspace;
    let mut selected_tab = selected_tab_request;
    let workspace_for_select = workspace_id;
    let tab_for_select = run.tab_id.clone();
    let tab_for_close = run.tab_id.clone();
    let bridge_for_close = bridge;
    rect()
        .width(Size::fill())
        .height(Size::px(28.))
        .horizontal()
        .content(Content::Flex)
        .cross_align(Alignment::Center)
        .spacing(6.)
        .padding(Gaps::new(4., 4., 4., 6.))
        .background(if is_active {
            SIDEBAR_AGENT_ACTIVE
        } else if is_hovered {
            SIDEBAR_HOVER
        } else {
            SIDEBAR_BACKGROUND
        })
        .corner_radius(4.)
        .a11y_role(AccessibilityRole::Button)
        .a11y_alt(run.description.clone())
        .on_pointer_enter(move |_| {
            Cursor::set(CursorIcon::Pointer);
            hover_enter.set(Some(hover_key.clone()));
        })
        .on_pointer_leave(move |_| {
            Cursor::set(CursorIcon::default());
            hover_leave.set(None);
        })
        .on_pointer_down(move |event: Event<PointerEventData>| {
            event.stop_propagation();
            selected_workspace.set(workspace_for_select.clone());
            selected_tab.set(Some(tab_for_select.clone()));
        })
        .child(sidebar_agent_state_indicator(Some(run.state), false, 12.))
        .child(agent_identity_icon(run.agent_type.as_str(), 13.))
        .child(
            label()
                .font_size(10.)
                .font_weight(if is_active {
                    FontWeight::SEMI_BOLD
                } else {
                    FontWeight::MEDIUM
                })
                .color(if is_active { TEXT } else { MUTED })
                .max_lines(1)
                .text(run.description),
        )
        .child(rect().width(Size::flex(1.)).child(""))
        .child(
            TooltipContainer::new(Tooltip::new_text("Close Terminal"))
                .position(AttachedPosition::Top)
                .delay(Duration::from_millis(350))
                .child(
                    rect()
                        .width(Size::px(20.))
                        .height(Size::px(20.))
                        .center()
                        .corner_radius(4.)
                        .a11y_role(AccessibilityRole::Button)
                        .a11y_alt("Close Terminal")
                        .opacity(if actions_visible { 1. } else { 0. })
                        .on_pointer_down(move |event: Event<PointerEventData>| {
                            event.stop_propagation();
                            let _ = bridge_for_close
                                .send_ordered("tab.remove", json!({"id": tab_for_close}));
                        })
                        .child(
                            SvgViewer::new(icons::lucide::x())
                                .width(Size::px(12.))
                                .height(Size::px(12.))
                                .color(MUTED),
                        ),
                ),
        )
        .into()
}

fn sidebar_agent_state_indicator(
    state: Option<AgentRunState>,
    idle_active: bool,
    size: f32,
) -> Element {
    match state {
        Some(AgentRunState::Working) => CircularLoader::new()
            .size((size - 2.).max(6.))
            .into_element(),
        Some(state) => {
            let (icon, color) = match state {
                AgentRunState::Waiting => (icons::lucide::bell(), (245, 158, 11)),
                AgentRunState::Blocked => (icons::lucide::bell(), (248, 113, 113)),
                AgentRunState::Interrupted => (icons::lucide::circle_x(), (248, 113, 113)),
                AgentRunState::Done => (icons::lucide::circle_check(), SUCCESS),
                AgentRunState::Working => unreachable!(),
            };
            TooltipContainer::new(Tooltip::new_text(state.label()))
                .position(AttachedPosition::Bottom)
                .delay(Duration::from_millis(350))
                .child(
                    SvgViewer::new(icon)
                        .width(Size::px(size))
                        .height(Size::px(size))
                        .color(color),
                )
                .into()
        }
        None => rect()
            .width(Size::px(size))
            .height(Size::px(size))
            .center()
            .child(
                rect()
                    .width(Size::px(8.))
                    .height(Size::px(8.))
                    .corner_radius(4.)
                    .background(if idle_active { SUCCESS } else { FAINT }),
            )
            .into(),
    }
}

fn agent_identity_icon(agent_type: &str, size: f32) -> Element {
    match agent_type {
        "claude" => SvgViewer::new(Bytes::from_static(CLAUDE_ICON))
            .width(Size::px(size))
            .height(Size::px(size))
            .into_element(),
        "copilot" => SvgViewer::new(Bytes::from_static(COPILOT_ICON))
            .width(Size::px(size))
            .height(Size::px(size))
            .color(MUTED)
            .into_element(),
        "cursor" => ImageViewer::new(("sidebar-agent-cursor", CURSOR_ICON))
            .width(Size::px(size))
            .height(Size::px(size))
            .into_element(),
        "agy" => ImageViewer::new(("sidebar-agent-agy", ANTIGRAVITY_ICON))
            .width(Size::px(size))
            .height(Size::px(size))
            .into_element(),
        "opencode" => ImageViewer::new(("sidebar-agent-opencode", OPENCODE_ICON))
            .width(Size::px(size))
            .height(Size::px(size))
            .into_element(),
        "pi" => SvgViewer::new(Bytes::from_static(PI_ICON))
            .width(Size::px(size))
            .height(Size::px(size))
            .color(MUTED)
            .into_element(),
        "amp" => ImageViewer::new(("sidebar-agent-amp", AMP_ICON))
            .width(Size::px(size))
            .height(Size::px(size))
            .into_element(),
        "grok" => SvgViewer::new(Bytes::from_static(GROK_ICON))
            .width(Size::px(size))
            .height(Size::px(size))
            .color(MUTED)
            .into_element(),
        "kimi" => SvgViewer::new(Bytes::from_static(KIMI_ICON))
            .width(Size::px(size))
            .height(Size::px(size))
            .color(MUTED)
            .into_element(),
        "minimax" | "miniMax" => SvgViewer::new(Bytes::from_static(MINIMAX_ICON))
            .width(Size::px(size))
            .height(Size::px(size))
            .color(MUTED)
            .into_element(),
        "zai" => SvgViewer::new(Bytes::from_static(ZAI_ICON))
            .width(Size::px(size))
            .height(Size::px(size))
            .color(MUTED)
            .into_element(),
        _ => SvgViewer::new(Bytes::from_static(CODEX_ICON))
            .width(Size::px(size))
            .height(Size::px(size))
            .color(MUTED)
            .into_element(),
    }
}

fn string_set_json(values: &HashSet<String>) -> Value {
    let mut values = values.iter().cloned().collect::<Vec<_>>();
    values.sort();
    json!(values)
}

fn filter_live_sidebar_agent_presence(
    presence: &[Value],
    tabs_by_workspace: &HashMap<String, Vec<Value>>,
) -> Vec<Value> {
    presence
        .iter()
        .filter(|presence| {
            let Some(workspace_id) = presence.get("workspaceId").and_then(Value::as_str) else {
                return false;
            };
            let Some(tab_id) = presence.get("tabId").and_then(Value::as_str) else {
                return false;
            };
            let Some(terminal_session_id) =
                presence.get("terminalSessionId").and_then(Value::as_str)
            else {
                return false;
            };
            tabs_by_workspace
                .get(workspace_id)
                .into_iter()
                .flatten()
                .any(|tab| {
                    tab.get("id").and_then(Value::as_str) == Some(tab_id)
                        && tab.get("workspaceId").and_then(Value::as_str) == Some(workspace_id)
                        && tab.get("kind").and_then(Value::as_str) == Some("terminal")
                        && tab
                            .get("payload")
                            .and_then(|payload| payload.get("terminalSessionId"))
                            .and_then(Value::as_str)
                            == Some(terminal_session_id)
                })
        })
        .cloned()
        .collect()
}

fn update_sidebar_pref(bridge: RuntimeBridge, key: &'static str, value: Value) {
    update_sidebar_prefs(bridge, vec![(key, value)]);
}

fn update_sidebar_prefs(bridge: RuntimeBridge, updates: Vec<(&'static str, Value)>) {
    spawn(async move {
        let Ok(record) = bridge.request("workbenchViewPrefs.get", json!({})).await else {
            return;
        };
        let revision = record.get("revision").cloned().unwrap_or(Value::Null);
        let mut prefs = record
            .get("prefs")
            .cloned()
            .unwrap_or_else(|| record.clone());
        let Some(object) = prefs.as_object_mut() else {
            return;
        };
        for (key, value) in updates {
            object.insert(key.to_string(), value);
        }
        let _ = bridge
            .request(
                "workbenchViewPrefs.update",
                json!({"expectedRevision": revision, "prefs": prefs}),
            )
            .await;
    });
}

fn open_sidebar_action_dialog(controls: SidebarActionControls, dialog: SidebarActionDialog) {
    let initial_value = if matches!(
        dialog.kind,
        SidebarActionKind::RenameProject | SidebarActionKind::RenameWorkspace
    ) {
        dialog.display_name.clone()
    } else {
        String::new()
    };
    // Context menus dispatch their press before the pointer sequence fully
    // unwinds. Mounting a full-screen dismiss barrier in that same dispatch
    // makes the opening click immediately close the dialog again.
    spawn_forever(async move {
        Timer::after(Duration::from_millis(100)).await;
        let mut value = controls.value;
        let mut tags = controls.selected_tags;
        let mut parent = controls.selected_parent;
        let mut error = controls.error;
        let mut open = controls.dialog;
        value.set(initial_value);
        tags.set(dialog.tag_ids.clone());
        parent.set(dialog.current_parent_id.clone());
        error.set(None);
        open.set(Some(dialog));
    });
}

fn workspace_sidebar_action(
    workspace: &SidebarWorkspaceRow,
    kind: SidebarActionKind,
) -> SidebarActionDialog {
    SidebarActionDialog {
        kind,
        target_id: workspace.id.clone(),
        display_name: workspace.name.clone(),
        branch: workspace.branch_label.clone(),
        delete_branch: !workspace.reuses_existing_branch,
        current_parent_id: workspace.parent_id.clone(),
        tag_ids: workspace.tag_ids.iter().cloned().collect(),
    }
}

fn open_sidebar_project_menu(
    project_id: String,
    project_name: String,
    controls: SidebarActionControls,
    new_workspace_dialog: State<Option<ActionDialog>>,
) {
    let project_id_for_workspace = project_id.clone();
    let rename_dialog = SidebarActionDialog::project(
        SidebarActionKind::RenameProject,
        project_id.clone(),
        project_name.clone(),
    );
    let remove_dialog =
        SidebarActionDialog::project(SidebarActionKind::RemoveProject, project_id, project_name);
    ContextMenu::open_from_down(
        Menu::new()
            .child(sidebar_menu_action(
                icons::lucide::pencil(),
                "Rename",
                TEXT,
                move || {
                    ContextMenu::close();
                    open_sidebar_action_dialog(controls, rename_dialog.clone());
                },
            ))
            .child(sidebar_menu_action(
                icons::lucide::plus(),
                "New Workspace",
                TEXT,
                move || {
                    ContextMenu::close();
                    let mut target = controls.new_workspace_project_id;
                    let project_id = project_id_for_workspace.clone();
                    let mut dialog = new_workspace_dialog;
                    spawn_forever(async move {
                        Timer::after(Duration::from_millis(100)).await;
                        target.set(Some(project_id));
                        dialog.set(Some(ActionDialog::NewWorkspace));
                    });
                },
            ))
            .child(sidebar_menu_divider())
            .child(sidebar_menu_action(
                icons::lucide::trash_2(),
                "Remove Project",
                (248, 113, 113),
                move || {
                    ContextMenu::close();
                    open_sidebar_action_dialog(controls, remove_dialog.clone());
                },
            )),
    );
}

fn sidebar_menu_entry(icon: Bytes, text: &'static str, color: (u8, u8, u8)) -> Element {
    rect()
        .width(Size::px(204.))
        .height(Size::px(22.))
        .horizontal()
        .content(Content::Flex)
        .cross_align(Alignment::Center)
        .spacing(8.)
        .child(
            SvgViewer::new(icon)
                .width(Size::px(16.))
                .height(Size::px(16.))
                .color(color),
        )
        .child(label().font_size(13.).color(color).text(text))
        .into()
}

fn sidebar_menu_action(
    icon: Bytes,
    text: &'static str,
    color: (u8, u8, u8),
    on_action: impl Fn() + Clone + 'static,
) -> Element {
    let action_for_pointer = on_action.clone();
    MenuButton::new()
        .child(
            rect()
                .width(Size::px(204.))
                .height(Size::px(22.))
                .horizontal()
                .content(Content::Flex)
                .cross_align(Alignment::Center)
                .spacing(8.)
                .a11y_role(AccessibilityRole::MenuItem)
                .a11y_alt(text)
                .on_pointer_down(move |event: Event<PointerEventData>| {
                    event.stop_propagation();
                    action_for_pointer();
                })
                .on_press(move |event: Event<PressEventData>| {
                    event.stop_propagation();
                    on_action();
                })
                .child(
                    SvgViewer::new(icon)
                        .width(Size::px(16.))
                        .height(Size::px(16.))
                        .color(color),
                )
                .child(label().font_size(13.).color(color).text(text)),
        )
        .into()
}

fn sidebar_menu_divider() -> Element {
    rect()
        .width(Size::px(228.))
        .height(Size::px(1.))
        .background(BORDER)
        .into()
}

fn open_sidebar_workspace_menu(
    workspace: SidebarWorkspaceRow,
    bridge: RuntimeBridge,
    _prefs: SidebarViewPrefs,
    controls: SidebarActionControls,
) {
    let pin_label = if workspace.is_pinned {
        "Unpin Workspace"
    } else {
        "Pin Workspace"
    };
    let rename_dialog = workspace_sidebar_action(&workspace, SidebarActionKind::RenameWorkspace);
    let tags_dialog = workspace_sidebar_action(&workspace, SidebarActionKind::ManageTags);
    let parent_dialog = workspace_sidebar_action(&workspace, SidebarActionKind::SetParent);
    let sleep_dialog = workspace_sidebar_action(&workspace, SidebarActionKind::SleepWorkspace);
    let remove_dialog = workspace_sidebar_action(&workspace, SidebarActionKind::RemoveWorkspace);
    let workspace_id_for_pin = workspace.id.clone();
    let next_pinned = !workspace.is_pinned;
    let bridge_for_pin = bridge.clone();
    let path_for_copy = workspace.path.clone();
    let path_for_reveal = workspace.path.clone();
    let workspace_id_for_browser = workspace.id.clone();
    let workspace_path_for_browser = workspace.path.clone();
    let bridge_for_browser = bridge.clone();
    let bridge_for_clear_parent = bridge;
    let mut menu = Menu::new()
        .child(sidebar_menu_action(
            icons::lucide::pencil(),
            "Rename",
            TEXT,
            move || {
                ContextMenu::close();
                open_sidebar_action_dialog(controls, rename_dialog.clone());
            },
        ))
        .child(sidebar_menu_action(
            if workspace.is_pinned {
                icons::lucide::pin_off()
            } else {
                icons::lucide::pin()
            },
            pin_label,
            TEXT,
            move || {
                ContextMenu::close();
                let bridge = bridge_for_pin.clone();
                let workspace_id = workspace_id_for_pin.clone();
                spawn_forever(async move {
                    let _ = bridge
                        .request(
                            "workspace.setPinned",
                            json!({"id": workspace_id, "isPinned": next_pinned}),
                        )
                        .await;
                });
            },
        ))
        .child(sidebar_menu_action(
            icons::lucide::tag(),
            "Manage Tags",
            TEXT,
            move || {
                ContextMenu::close();
                open_sidebar_action_dialog(controls, tags_dialog.clone());
            },
        ))
        .child(sidebar_menu_action(
            icons::lucide::link(),
            "Set Parent Workspace",
            TEXT,
            move || {
                ContextMenu::close();
                open_sidebar_action_dialog(controls, parent_dialog.clone());
            },
        ));
    if let Some(parent_id) = workspace.parent_id.clone() {
        let workspace_id = workspace.id.clone();
        let bridge = bridge_for_clear_parent.clone();
        menu = menu.child(
            sidebar_menu_action(
                icons::lucide::x(),
                "Clear Parent Workspace",
                TEXT,
                move || {
                    ContextMenu::close();
                    let bridge = bridge.clone();
                    let workspace_id = workspace_id.clone();
                    let parent_id = parent_id.clone();
                    spawn_forever(async move {
                        let _ = bridge
                            .request(
                                "workspaceRelation.unlink",
                                json!({"parentWorkspaceId": parent_id, "childWorkspaceId": workspace_id}),
                            )
                            .await;
                    });
                },
            ),
        );
    }
    menu = menu
        .child(sidebar_menu_divider())
        .child(sidebar_menu_action(
            icons::lucide::external_link(),
            "Open in Browser",
            TEXT,
            move || {
                ContextMenu::close();
                let bridge = bridge_for_browser.clone();
                let workspace_id = workspace_id_for_browser.clone();
                let workspace_path = workspace_path_for_browser.clone();
                spawn_forever(async move {
                    if let Ok(value) = bridge
                        .request(
                            "workspace.repositoryWebUrl",
                            json!({"workspaceId": workspace_id, "workspacePath": workspace_path}),
                        )
                        .await
                        && let Some(remote) = value.get("remoteUrl").and_then(Value::as_str)
                        && let Some(url) = normalize_repository_web_url(remote)
                    {
                        let _ = blocking::unblock(move || open::that(url)).await;
                    }
                });
            },
        ))
        .child(sidebar_menu_action(
            icons::lucide::folder_open(),
            "Open in Finder",
            TEXT,
            move || {
                ContextMenu::close();
                let _ = reveal_in_file_manager(std::path::Path::new(&path_for_reveal));
            },
        ))
        .child(sidebar_menu_action(
            icons::lucide::copy(),
            "Copy Path",
            TEXT,
            move || {
                ContextMenu::close();
                let _ = Clipboard::set(path_for_copy.clone());
            },
        ))
        .child(sidebar_menu_divider())
        .child(sidebar_menu_action(
            icons::lucide::moon(),
            "Sleep",
            TEXT,
            move || {
                ContextMenu::close();
                open_sidebar_action_dialog(controls, sleep_dialog.clone());
            },
        ));
    menu = if workspace.is_default {
        menu.child(MenuButton::new().child(sidebar_menu_entry(
            icons::lucide::trash_2(),
            "Remove",
            FAINT,
        )))
    } else {
        menu.child(sidebar_menu_action(
            icons::lucide::trash_2(),
            "Remove",
            TEXT,
            move || {
                ContextMenu::close();
                open_sidebar_action_dialog(controls, remove_dialog.clone());
            },
        ))
    };
    ContextMenu::open_from_down(menu);
}

fn normalize_repository_web_url(remote: &str) -> Option<String> {
    let remote = remote.trim();
    if remote.is_empty() {
        return None;
    }
    let normalized = if let Some(rest) = remote.strip_prefix("git@") {
        let (host, path) = rest.split_once(':')?;
        format!("https://{host}/{path}")
    } else if let Some(rest) = remote.strip_prefix("ssh://git@") {
        format!("https://{rest}")
    } else {
        remote.to_string()
    };
    Some(normalized.trim_end_matches(".git").to_string())
}

fn sidebar_view_options_overlay(
    open: State<bool>,
    bridge: RuntimeBridge,
    prefs: SidebarViewPrefs,
    snapshot: Option<WorkbenchSnapshot>,
    project_query: State<String>,
    tag_query: State<String>,
) -> Element {
    let mut open_for_barrier = open;
    let mut open_for_close = open;
    let mut panel = rect()
        .width(Size::px(460.))
        .max_height(Size::px(680.))
        .vertical()
        .content(Content::Flex)
        .spacing(12.)
        .padding(Gaps::new(12., 16., 16., 16.))
        .background(SURFACE_RAISED)
        .border(Border::new().width(1.).fill(BORDER))
        .corner_radius(10.)
        .on_pointer_down(|event: Event<PointerEventData>| event.stop_propagation())
        .child(
            rect()
                .width(Size::fill())
                .horizontal()
                .content(Content::Flex)
                .cross_align(Alignment::Center)
                .child(
                    label()
                        .font_size(14.)
                        .font_weight(FontWeight::SEMI_BOLD)
                        .color(TEXT)
                        .text("View Options"),
                )
                .child(rect().width(Size::flex(1.)).child(""))
                .child(
                    rect()
                        .width(Size::px(30.))
                        .height(Size::px(30.))
                        .center()
                        .corner_radius(6.)
                        .a11y_role(AccessibilityRole::Button)
                        .a11y_alt("Close View Options")
                        .on_pointer_enter(|_| Cursor::set(CursorIcon::Pointer))
                        .on_pointer_leave(|_| Cursor::set(CursorIcon::default()))
                        .on_pointer_down(move |event: Event<PointerEventData>| {
                            event.stop_propagation();
                            open_for_close.set(false);
                        })
                        .child(
                            SvgViewer::new(icons::lucide::x())
                                .width(Size::px(16.))
                                .height(Size::px(16.))
                                .color(MUTED),
                        ),
                ),
        )
        .child(
            rect()
                .width(Size::fill())
                .vertical()
                .content(Content::Flex)
                .spacing(6.)
                .child(sidebar_options_label("Group By"))
                .child(
                    rect()
                        .width(Size::fill())
                        .horizontal()
                        .content(Content::Flex)
                        .spacing(0.)
                        .child(sidebar_option_button(
                            "None",
                            prefs.group_by == SidebarGroupBy::None,
                            {
                                let bridge = bridge.clone();
                                move |_| {
                                    update_sidebar_pref(bridge.clone(), "groupBy", json!("none"))
                                }
                            },
                        ))
                        .child(sidebar_option_button(
                            "Project",
                            prefs.group_by == SidebarGroupBy::Project,
                            {
                                let bridge = bridge.clone();
                                move |_| {
                                    update_sidebar_pref(bridge.clone(), "groupBy", json!("project"))
                                }
                            },
                        )),
                ),
        );

    if prefs.group_by == SidebarGroupBy::Project {
        panel = panel
            .child(sidebar_options_sort_row(
                "Sort Projects By",
                prefs.project_sort,
                "projectSort",
                bridge.clone(),
            ))
            .child(sidebar_options_sort_row(
                "Then Workspaces By",
                prefs.workspace_sort,
                "workspaceSort",
                bridge.clone(),
            ));
    } else {
        panel = panel.child(sidebar_options_sort_row(
            "Sort Workspaces By",
            prefs.workspace_sort,
            "workspaceSort",
            bridge.clone(),
        ));
    }

    panel = panel
        .child(
            rect()
                .width(Size::fill())
                .vertical()
                .content(Content::Flex)
                .spacing(6.)
                .child(sidebar_options_label("Show Workspaces"))
                .child(
                    rect()
                        .width(Size::fill())
                        .horizontal()
                        .content(Content::Flex)
                        .spacing(0.)
                        .child(sidebar_option_button(
                            "All",
                            prefs.workspace_kind == SidebarWorkspaceKind::All,
                            {
                                let bridge = bridge.clone();
                                move |_| {
                                    update_sidebar_pref(
                                        bridge.clone(),
                                        "workspaceKindFilter",
                                        json!("all"),
                                    )
                                }
                            },
                        ))
                        .child(sidebar_option_button(
                            "Default",
                            prefs.workspace_kind == SidebarWorkspaceKind::DefaultOnly,
                            {
                                let bridge = bridge.clone();
                                move |_| {
                                    update_sidebar_pref(
                                        bridge.clone(),
                                        "workspaceKindFilter",
                                        json!("defaultOnly"),
                                    )
                                }
                            },
                        ))
                        .child(sidebar_option_button(
                            "Non-Default",
                            prefs.workspace_kind == SidebarWorkspaceKind::NonDefaultOnly,
                            {
                                let bridge = bridge.clone();
                                move |_| {
                                    update_sidebar_pref(
                                        bridge.clone(),
                                        "workspaceKindFilter",
                                        json!("nonDefaultOnly"),
                                    )
                                }
                            },
                        )),
                ),
        )
        .child(sidebar_checkbox_row(
            "Repeat Pinned Workspaces",
            prefs.show_pinned_workspaces_below,
            {
                let bridge = bridge.clone();
                move |_| {
                    update_sidebar_pref(
                        bridge.clone(),
                        "showPinnedWorkspacesBelow",
                        json!(!prefs.show_pinned_workspaces_below),
                    )
                }
            },
        ));

    if let Some(snapshot) = snapshot {
        panel = panel
            .child(sidebar_options_divider())
            .child(sidebar_project_filter_section(
                snapshot.projects,
                &prefs,
                bridge.clone(),
                project_query,
            ))
            .child(sidebar_options_divider())
            .child(sidebar_tag_filter_section(
                snapshot.tags,
                &prefs,
                bridge.clone(),
                tag_query,
            ));
    }

    rect()
        .position(Position::new_absolute())
        .layer(Layer::Overlay)
        .width(Size::percent(100.))
        .height(Size::percent(100.))
        .background(Color::from_af32rgb(0.8, 0, 0, 0))
        .on_pointer_down(move |_| open_for_barrier.set(false))
        .child(
            rect()
                .position(Position::new_absolute())
                .width(Size::percent(100.))
                .height(Size::percent(100.))
                .center()
                .child(
                    ScrollView::new()
                        .width(Size::px(460.))
                        .height(Size::Inner)
                        .max_height(Size::px(680.))
                        .child(panel),
                ),
        )
        .into()
}

fn sidebar_options_label(text: impl Into<String>) -> Element {
    label()
        .font_size(10.)
        .font_weight(FontWeight::SEMI_BOLD)
        .color(FAINT)
        .text(text.into())
        .into()
}

fn sidebar_options_divider() -> Element {
    rect()
        .width(Size::fill())
        .height(Size::px(1.))
        .background(SIDEBAR_BORDER)
        .into()
}

fn sidebar_filter_section_header(
    title: &'static str,
    selected_count: usize,
    pref_key: &'static str,
    bridge: RuntimeBridge,
) -> Element {
    let clear_enabled = selected_count > 0;
    rect()
        .width(Size::fill())
        .height(Size::px(24.))
        .horizontal()
        .content(Content::Flex)
        .cross_align(Alignment::Center)
        .child(sidebar_options_label(title))
        .maybe_child((selected_count > 0).then(|| {
            rect()
                .min_width(Size::px(16.))
                .height(Size::px(16.))
                .margin(Gaps::new(6., 0., 0., 0.))
                .padding(Gaps::new(4., 0., 4., 0.))
                .center()
                .background(BORDER)
                .corner_radius(8.)
                .child(
                    label()
                        .font_size(9.)
                        .font_weight(FontWeight::SEMI_BOLD)
                        .color(MUTED)
                        .text(selected_count.to_string()),
                )
        }))
        .child(rect().width(Size::flex(1.)).child(""))
        .child(
            rect()
                .height(Size::px(24.))
                .padding(Gaps::new(8., 0., 8., 0.))
                .center()
                .corner_radius(4.)
                .a11y_role(AccessibilityRole::Button)
                .a11y_alt(format!("Clear {title}"))
                .on_pointer_enter(move |_| {
                    Cursor::set(if clear_enabled {
                        CursorIcon::Pointer
                    } else {
                        CursorIcon::default()
                    })
                })
                .on_pointer_leave(|_| Cursor::set(CursorIcon::default()))
                .on_pointer_down(move |event: Event<PointerEventData>| {
                    event.stop_propagation();
                    if clear_enabled {
                        update_sidebar_pref(bridge.clone(), pref_key, json!([]));
                    }
                })
                .child(
                    label()
                        .font_size(10.)
                        .color(if clear_enabled { MUTED } else { FAINT })
                        .text("Clear"),
                ),
        )
        .into()
}

fn sidebar_filter_input(
    value: State<String>,
    placeholder: &'static str,
    on_submit: impl Fn(String) + 'static,
) -> Element {
    Input::new(value)
        .width(Size::fill())
        .placeholder(placeholder)
        .compact()
        .filled()
        .theme_layout(
            InputLayoutThemePartial::new()
                .corner_radius(CornerRadius::new_all(6.))
                .inner_margin(Gaps::new(8., 6., 8., 6.)),
        )
        .theme_colors(
            InputColorsThemePartial::new()
                .background(SURFACE)
                .focus_background(SURFACE)
                .border_fill(SIDEBAR_BORDER)
                .focus_border_fill(BORDER)
                .color(TEXT)
                .placeholder_color(FAINT),
        )
        .leading(
            SvgViewer::new(icons::lucide::plus())
                .width(Size::px(12.))
                .height(Size::px(12.))
                .color(FAINT),
        )
        .on_submit(on_submit)
        .into()
}

fn sidebar_filter_chip(
    label_text: String,
    action: impl Into<EventHandler<Event<PointerEventData>>>,
) -> Element {
    rect()
        .height(Size::px(24.))
        .horizontal()
        .content(Content::Flex)
        .cross_align(Alignment::Center)
        .spacing(4.)
        .padding(Gaps::new(7., 0., 5., 0.))
        .background(SURFACE)
        .border(Border::new().width(1.).fill(SIDEBAR_BORDER))
        .corner_radius(12.)
        .a11y_role(AccessibilityRole::Button)
        .a11y_alt(format!("Remove {label_text}"))
        .on_pointer_enter(|_| Cursor::set(CursorIcon::Pointer))
        .on_pointer_leave(|_| Cursor::set(CursorIcon::default()))
        .on_pointer_down(action)
        .child(
            label()
                .font_size(10.)
                .color(MUTED)
                .max_lines(1)
                .text(label_text),
        )
        .child(
            SvgViewer::new(icons::lucide::x())
                .width(Size::px(11.))
                .height(Size::px(11.))
                .color(FAINT),
        )
        .into()
}

fn sidebar_filter_choice_row(
    label_text: String,
    tag: bool,
    action: impl Into<EventHandler<Event<PointerEventData>>>,
) -> Element {
    rect()
        .width(Size::fill())
        .height(Size::px(28.))
        .horizontal()
        .content(Content::Flex)
        .cross_align(Alignment::Center)
        .spacing(8.)
        .padding(Gaps::new(8., 6., 8., 6.))
        .corner_radius(4.)
        .a11y_role(AccessibilityRole::Button)
        .a11y_alt(label_text.clone())
        .on_pointer_enter(|_| Cursor::set(CursorIcon::Pointer))
        .on_pointer_leave(|_| Cursor::set(CursorIcon::default()))
        .on_pointer_down(action)
        .child(if tag {
            SvgViewer::new(icons::lucide::tag())
                .width(Size::px(12.))
                .height(Size::px(12.))
                .color(FAINT)
                .into_element()
        } else {
            rect()
                .width(Size::px(6.))
                .height(Size::px(6.))
                .background(FAINT)
                .corner_radius(3.)
                .into_element()
        })
        .child(
            label()
                .font_size(11.)
                .color(TEXT)
                .max_lines(1)
                .text(label_text),
        )
        .into()
}

fn sidebar_filter_empty(message: impl Into<String>) -> Element {
    rect()
        .width(Size::fill())
        .height(Size::px(34.))
        .center()
        .child(label().font_size(10.).color(FAINT).text(message.into()))
        .into()
}

fn sidebar_project_filter_section(
    mut projects: Vec<Project>,
    prefs: &SidebarViewPrefs,
    bridge: RuntimeBridge,
    project_query: State<String>,
) -> Element {
    projects.sort_by(|left, right| {
        left.name
            .to_lowercase()
            .cmp(&right.name.to_lowercase())
            .then_with(|| left.name.cmp(&right.name))
            .then_with(|| left.id.cmp(&right.id))
    });
    let normalized_query = project_query.read().trim().to_lowercase();
    let selected = projects
        .iter()
        .filter(|project| prefs.selected_project_ids.contains(&project.id))
        .cloned()
        .collect::<Vec<_>>();
    let available = projects
        .into_iter()
        .filter(|project| !prefs.selected_project_ids.contains(&project.id))
        .filter(|project| {
            normalized_query.is_empty() || project.name.to_lowercase().contains(&normalized_query)
        })
        .collect::<Vec<_>>();

    let mut section = rect()
        .width(Size::fill())
        .vertical()
        .content(Content::Flex)
        .spacing(8.)
        .child(sidebar_filter_section_header(
            "Projects",
            selected.len(),
            "selectedProjectIds",
            bridge.clone(),
        ));
    if !selected.is_empty() {
        let mut chips = rect().horizontal().content(Content::Flex).spacing(6.);
        for project in selected {
            let mut selected_ids = prefs.selected_project_ids.clone();
            selected_ids.remove(&project.id);
            let bridge_for_remove = bridge.clone();
            chips = chips.child(sidebar_filter_chip(
                project.name,
                move |event: Event<PointerEventData>| {
                    event.stop_propagation();
                    update_sidebar_pref(
                        bridge_for_remove.clone(),
                        "selectedProjectIds",
                        string_set_json(&selected_ids),
                    );
                },
            ));
        }
        section = section.child(
            ScrollView::new()
                .direction(Direction::Horizontal)
                .show_scrollbar(false)
                .width(Size::fill())
                .height(Size::px(24.))
                .child(chips),
        );
    }

    let first_available_id = available.first().map(|project| project.id.clone());
    let query_for_submit = project_query;
    let selected_ids_for_submit = prefs.selected_project_ids.clone();
    let bridge_for_submit = bridge.clone();
    section = section.child(sidebar_filter_input(
        project_query,
        "Add Project…",
        move |_| {
            if let Some(project_id) = first_available_id.clone() {
                let mut next_selected_ids = selected_ids_for_submit.clone();
                next_selected_ids.insert(project_id);
                update_sidebar_pref(
                    bridge_for_submit.clone(),
                    "selectedProjectIds",
                    string_set_json(&next_selected_ids),
                );
                let mut query = query_for_submit;
                query.set(String::new());
            }
        },
    ));

    if available.is_empty() {
        let message = if !normalized_query.is_empty() {
            format!("No Projects Match \"{normalized_query}\"")
        } else if !prefs.selected_project_ids.is_empty() {
            "All Projects Selected".to_string()
        } else {
            "No Projects Yet".to_string()
        };
        section = section.child(sidebar_filter_empty(message));
    } else {
        let available_height = (available.len() as f32 * 28.).min(240.);
        let mut rows = rect().width(Size::fill()).vertical();
        for project in available {
            let mut selected_ids = prefs.selected_project_ids.clone();
            selected_ids.insert(project.id.clone());
            let bridge_for_pick = bridge.clone();
            let mut query_for_pick = project_query;
            rows = rows.child(sidebar_filter_choice_row(
                project.name,
                false,
                move |event: Event<PointerEventData>| {
                    event.stop_propagation();
                    query_for_pick.set(String::new());
                    update_sidebar_pref(
                        bridge_for_pick.clone(),
                        "selectedProjectIds",
                        string_set_json(&selected_ids),
                    );
                },
            ));
        }
        section = section.child(
            ScrollView::new()
                .width(Size::fill())
                .height(Size::px(available_height))
                .show_scrollbar(available_height >= 240.)
                .child(rows),
        );
    }
    section.into()
}

fn sidebar_tag_filter_section(
    mut tags: Vec<WorkspaceTag>,
    prefs: &SidebarViewPrefs,
    bridge: RuntimeBridge,
    tag_query: State<String>,
) -> Element {
    tags.sort_by(|left, right| {
        left.name
            .to_lowercase()
            .cmp(&right.name.to_lowercase())
            .then_with(|| left.name.cmp(&right.name))
            .then_with(|| left.id.cmp(&right.id))
    });
    let normalized_query = tag_query.read().trim().to_lowercase();
    let selected = tags
        .iter()
        .filter(|tag| prefs.selected_tag_ids.contains(&tag.id))
        .cloned()
        .collect::<Vec<_>>();
    let available = tags
        .into_iter()
        .filter(|tag| !prefs.selected_tag_ids.contains(&tag.id))
        .filter(|tag| {
            normalized_query.is_empty() || tag.name.to_lowercase().contains(&normalized_query)
        })
        .collect::<Vec<_>>();

    let mut section = rect()
        .width(Size::fill())
        .vertical()
        .content(Content::Flex)
        .spacing(8.)
        .child(sidebar_filter_section_header(
            "Tags",
            selected.len(),
            "selectedTagIds",
            bridge.clone(),
        ));
    if !selected.is_empty() {
        let mut chips = rect().horizontal().content(Content::Flex).spacing(6.);
        for tag in selected {
            let mut selected_ids = prefs.selected_tag_ids.clone();
            selected_ids.remove(&tag.id);
            let bridge_for_remove = bridge.clone();
            chips = chips.child(sidebar_filter_chip(
                tag.name,
                move |event: Event<PointerEventData>| {
                    event.stop_propagation();
                    update_sidebar_pref(
                        bridge_for_remove.clone(),
                        "selectedTagIds",
                        string_set_json(&selected_ids),
                    );
                },
            ));
        }
        section = section.child(
            ScrollView::new()
                .direction(Direction::Horizontal)
                .show_scrollbar(false)
                .width(Size::fill())
                .height(Size::px(24.))
                .child(chips),
        );
    }

    let first_available_id = available.first().map(|tag| tag.id.clone());
    let query_for_submit = tag_query;
    let selected_ids_for_submit = prefs.selected_tag_ids.clone();
    let bridge_for_submit = bridge.clone();
    section = section.child(sidebar_filter_input(tag_query, "Add Tag…", move |_| {
        if let Some(tag_id) = first_available_id.clone() {
            let mut next_selected_ids = selected_ids_for_submit.clone();
            next_selected_ids.insert(tag_id);
            update_sidebar_pref(
                bridge_for_submit.clone(),
                "selectedTagIds",
                string_set_json(&next_selected_ids),
            );
            let mut query = query_for_submit;
            query.set(String::new());
        }
    }));

    if available.is_empty() {
        let message = if !normalized_query.is_empty() {
            format!("No Tags Match \"{normalized_query}\"")
        } else if !prefs.selected_tag_ids.is_empty() {
            "All Tags Selected".to_string()
        } else {
            "No Tags Yet".to_string()
        };
        section = section.child(sidebar_filter_empty(message));
    } else {
        let available_height = (available.len() as f32 * 28.).min(160.);
        let mut rows = rect().width(Size::fill()).vertical();
        for tag in available {
            let mut selected_ids = prefs.selected_tag_ids.clone();
            selected_ids.insert(tag.id.clone());
            let bridge_for_pick = bridge.clone();
            let mut query_for_pick = tag_query;
            rows = rows.child(sidebar_filter_choice_row(
                tag.name,
                true,
                move |event: Event<PointerEventData>| {
                    event.stop_propagation();
                    query_for_pick.set(String::new());
                    update_sidebar_pref(
                        bridge_for_pick.clone(),
                        "selectedTagIds",
                        string_set_json(&selected_ids),
                    );
                },
            ));
        }
        section = section.child(
            ScrollView::new()
                .width(Size::fill())
                .height(Size::px(available_height))
                .show_scrollbar(available_height >= 160.)
                .child(rows),
        );
    }
    section.into()
}

fn sidebar_options_sort_row(
    title: &'static str,
    selected: SidebarSortBy,
    pref_key: &'static str,
    bridge: RuntimeBridge,
) -> Element {
    let selected_label = match selected {
        SidebarSortBy::Name => "Name",
        SidebarSortBy::Recent => "Recent",
        SidebarSortBy::Activity => "Agent Activity",
    };
    let bridge_for_menu = bridge;
    rect()
        .width(Size::fill())
        .height(Size::px(28.))
        .horizontal()
        .content(Content::Flex)
        .cross_align(Alignment::Center)
        .child(
            label()
                .width(Size::flex(1.))
                .font_size(11.)
                .color(MUTED)
                .text(title),
        )
        .child(
            rect()
                .height(Size::px(26.))
                .min_width(Size::px(96.))
                .horizontal()
                .content(Content::Flex)
                .cross_align(Alignment::Center)
                .main_align(Alignment::End)
                .spacing(4.)
                .padding(Gaps::new(8., 4., 8., 4.))
                .corner_radius(6.)
                .a11y_role(AccessibilityRole::Button)
                .a11y_alt(format!("{title}: {selected_label}"))
                .on_pointer_enter(|_| Cursor::set(CursorIcon::Pointer))
                .on_pointer_leave(|_| Cursor::set(CursorIcon::default()))
                .on_pointer_down(move |event: Event<PointerEventData>| {
                    event.stop_propagation();
                    open_sidebar_sort_menu(selected, pref_key, bridge_for_menu.clone());
                })
                .child(label().font_size(11.).color(MUTED).text(selected_label))
                .child(
                    SvgViewer::new(icons::lucide::chevron_down())
                        .width(Size::px(14.))
                        .height(Size::px(14.))
                        .color(FAINT),
                ),
        )
        .into()
}

fn open_sidebar_sort_menu(selected: SidebarSortBy, pref_key: &'static str, bridge: RuntimeBridge) {
    let mut menu = Menu::new();
    for (label_text, value, key) in [
        ("Name", SidebarSortBy::Name, "name"),
        ("Recent", SidebarSortBy::Recent, "recent"),
        ("Agent Activity", SidebarSortBy::Activity, "activity"),
    ] {
        let bridge_for_pointer = bridge.clone();
        let bridge_for_press = bridge.clone();
        let pointer_action = move || {
            ContextMenu::close();
            update_sidebar_pref(bridge_for_pointer.clone(), pref_key, json!(key));
        };
        let press_action = move || {
            ContextMenu::close();
            update_sidebar_pref(bridge_for_press.clone(), pref_key, json!(key));
        };
        menu = menu.child(
            MenuButton::new().child(
                rect()
                    .width(Size::px(160.))
                    .height(Size::px(24.))
                    .horizontal()
                    .content(Content::Flex)
                    .cross_align(Alignment::Center)
                    .spacing(8.)
                    .a11y_role(AccessibilityRole::MenuItem)
                    .a11y_alt(label_text)
                    .on_pointer_down(move |event: Event<PointerEventData>| {
                        event.stop_propagation();
                        pointer_action();
                    })
                    .on_press(move |event: Event<PressEventData>| {
                        event.stop_propagation();
                        press_action();
                    })
                    .child(
                        rect()
                            .width(Size::px(14.))
                            .height(Size::px(14.))
                            .center()
                            .maybe_child((selected == value).then(|| {
                                SvgViewer::new(icons::lucide::check())
                                    .width(Size::px(12.))
                                    .height(Size::px(12.))
                                    .color(MUTED)
                            })),
                    )
                    .child(label().font_size(12.).color(TEXT).text(label_text)),
            ),
        );
    }
    ContextMenu::open_from_down(menu);
}

fn sidebar_option_button(
    label_text: &'static str,
    selected: bool,
    action: impl Into<EventHandler<Event<PointerEventData>>>,
) -> Element {
    rect()
        .width(Size::flex(1.))
        .height(Size::px(30.))
        .center()
        .padding(Gaps::new(0., 8., 0., 8.))
        .background(if selected { BORDER } else { SURFACE })
        .border(Border::new().width(1.).fill(SIDEBAR_BORDER))
        .corner_radius(4.)
        .a11y_role(AccessibilityRole::Button)
        .a11y_alt(label_text)
        .on_pointer_enter(|_| Cursor::set(CursorIcon::Pointer))
        .on_pointer_leave(|_| Cursor::set(CursorIcon::default()))
        .on_pointer_down(action)
        .child(
            label()
                .font_size(10.)
                .color(if selected { TEXT } else { MUTED })
                .text(label_text),
        )
        .into()
}

fn sidebar_checkbox_row(
    label_text: impl Into<String>,
    checked: bool,
    action: impl Into<EventHandler<Event<PointerEventData>>>,
) -> Element {
    let label_text = label_text.into();
    rect()
        .width(Size::fill())
        .height(Size::px(28.))
        .horizontal()
        .content(Content::Flex)
        .cross_align(Alignment::Center)
        .spacing(8.)
        .a11y_role(AccessibilityRole::CheckBox)
        .a11y_alt(label_text.clone())
        .on_pointer_enter(|_| Cursor::set(CursorIcon::Pointer))
        .on_pointer_leave(|_| Cursor::set(CursorIcon::default()))
        .on_pointer_down(action)
        .child(
            rect()
                .width(Size::px(16.))
                .height(Size::px(16.))
                .center()
                .background(if checked { ACCENT } else { SURFACE })
                .border(
                    Border::new()
                        .width(1.)
                        .fill(if checked { ACCENT } else { BORDER }),
                )
                .corner_radius(4.)
                .maybe_child(checked.then(|| {
                    SvgViewer::new(icons::lucide::check())
                        .width(Size::px(11.))
                        .height(Size::px(11.))
                        .color(BACKGROUND)
                })),
        )
        .child(label().font_size(11.).color(TEXT).text(label_text))
        .into()
}

/// Runtime mode selector with the same split-button affordance as Flutter.
///
/// This compact selector keeps the menu in normal flow while it is open. That
/// makes the external-click close behavior deterministic even when the right
/// panel is being resized or the window is still settling after launch.
fn runtime_mode_selector(runtime_mode: State<String>) -> Element {
    let open = use_state(|| false);
    let selected = runtime_mode.read().clone();
    let mut open_for_button = open;
    let button = rect()
        .width(Size::px(122.))
        .height(Size::px(30.))
        .border(Border::new().width(1.).fill(BORDER))
        .corner_radius(6.)
        .padding(Gaps::new_all(6.))
        .a11y_role(AccessibilityRole::Button)
        .a11y_alt(format!("Runtime mode: {selected}"))
        .on_pointer_enter(|_| Cursor::set(CursorIcon::Pointer))
        .on_pointer_leave(|_| Cursor::set(CursorIcon::default()))
        .on_pointer_down(move |event: Event<PointerEventData>| {
            event.stop_propagation();
            open_for_button.toggle();
        })
        .child(
            rect()
                .interactive(false)
                .width(Size::fill())
                .horizontal()
                .content(Content::Flex)
                .cross_align(Alignment::Center)
                .child(label().font_size(12.).color(TEXT).text(selected))
                .child(rect().width(Size::flex(1.)).child(""))
                .child(
                    SvgViewer::new(icons::lucide::chevron_down())
                        .width(Size::px(14.))
                        .height(Size::px(14.))
                        .color(MUTED),
                ),
        );

    let mut open_for_global = open;
    let mut options = rect()
        .background((30, 30, 30))
        .border(Border::new().width(1.).fill(BORDER))
        .corner_radius(6.)
        .padding(Gaps::new_all(4.))
        .spacing(2.)
        .on_press(|event: Event<PressEventData>| event.stop_propagation())
        .on_global_pointer_press(move |_| open_for_global.set(false))
        .vertical();
    for mode in ["Local", "Remote", "SSH"] {
        let mut runtime_mode = runtime_mode;
        let mut open = open;
        options = options.child(
            rect()
                .width(Size::fill())
                .height(Size::px(28.))
                .corner_radius(4.)
                .padding(Gaps::new_all(6.))
                .a11y_role(AccessibilityRole::Button)
                .a11y_alt(mode)
                .on_pointer_enter(|_| Cursor::set(CursorIcon::Pointer))
                .on_pointer_leave(|_| Cursor::set(CursorIcon::default()))
                .on_press(move |event: Event<PressEventData>| {
                    event.stop_propagation();
                    runtime_mode.set(mode.to_string());
                    open.set(false);
                })
                .child(
                    rect()
                        .interactive(false)
                        .child(label().font_size(12.).color(TEXT).text(mode)),
                ),
        );
    }

    rect()
        .width(Size::px(122.))
        .vertical()
        .spacing(4.)
        .child(button)
        .maybe_child(open().then_some(options))
        .into()
}

fn agent_status_bar(
    state: &FutureState<Result<Value, String>>,
    settings: &QuotaSettings,
    bridge: RuntimeBridge,
    refresh_revision: State<u64>,
    reset_confirmation: State<Option<CodexResetOffer>>,
    reset_error: State<Option<String>>,
    active_status_popover: State<Option<String>>,
) -> Element {
    let snapshots = enabled_quota_snapshots(quota_snapshots(state), settings, true);
    let content = if snapshots.is_empty() {
        rect()
            .height(Size::px(26.))
            .horizontal()
            .cross_align(Alignment::Center)
            .spacing(6.)
            .maybe_child(
                (!matches!(state, FutureState::Fulfilled(_)))
                    .then(|| CircularLoader::new().size(12.)),
            )
            .child(label().font_size(9.).color(FAINT).text(
                if matches!(state, FutureState::Fulfilled(Err(_))) {
                    "Quotas Unavailable"
                } else {
                    "Loading Quotas"
                },
            ))
            .into_element()
    } else {
        rect()
            .horizontal()
            .content(Content::Flex)
            .cross_align(Alignment::Center)
            .children(snapshots.into_iter().map(|snapshot| {
                quota_provider_card::QuotaAgentChip::new(
                    snapshot,
                    bridge.clone(),
                    refresh_revision,
                    reset_confirmation,
                    reset_error,
                    active_status_popover,
                )
            }))
            .into_element()
    };
    ScrollView::new()
        .direction(Direction::Horizontal)
        .show_scrollbar(false)
        .width(Size::flex(3.))
        .height(Size::px(26.))
        .child(content)
        .into()
}

fn quota_snapshots(state: &FutureState<Result<Value, String>>) -> Vec<Value> {
    match state {
        FutureState::Fulfilled(Ok(value)) => value
            .get("snapshots")
            .and_then(Value::as_array)
            .cloned()
            .unwrap_or_default(),
        _ => Vec::new(),
    }
}

fn enabled_quota_snapshots(
    snapshots: Vec<Value>,
    settings: &QuotaSettings,
    pinned_only: bool,
) -> Vec<Value> {
    let mut by_provider = HashMap::<String, Vec<Value>>::new();
    for snapshot in snapshots {
        by_provider
            .entry(quota_provider(&snapshot).to_string())
            .or_default()
            .push(snapshot);
    }
    let mut visible = Vec::new();
    for provider in &settings.enabled_providers {
        let Some(candidates) = by_provider.remove(provider) else {
            continue;
        };
        if provider == "claude" {
            let mut by_account = candidates
                .into_iter()
                .map(|snapshot| (quota_account(&snapshot).to_string(), snapshot))
                .collect::<HashMap<_, _>>();
            if settings.claude_default_enabled
                && let Some(snapshot) = by_account.remove("default")
            {
                visible.push(snapshot);
            }
            for profile in &settings.claude_profiles {
                if let Some(snapshot) = by_account.remove(&profile.profile) {
                    visible.push(snapshot);
                }
            }
            let mut remaining = by_account.into_values().collect::<Vec<_>>();
            remaining.sort_by_key(|snapshot| quota_account(snapshot).to_string());
            visible.extend(remaining);
        } else if let Some(snapshot) = candidates.into_iter().next() {
            visible.push(snapshot);
        }
    }
    if pinned_only {
        visible.retain(|snapshot| settings.is_pinned(&quota_pin_key(snapshot)));
    }
    visible
}

fn quota_provider(snapshot: &Value) -> &str {
    snapshot
        .get("provider")
        .and_then(Value::as_str)
        .unwrap_or("provider")
}

fn quota_account(snapshot: &Value) -> &str {
    snapshot
        .get("accountId")
        .or_else(|| snapshot.get("account_id"))
        .and_then(Value::as_str)
        .unwrap_or("default")
}

fn quota_pin_key(snapshot: &Value) -> String {
    snapshot
        .get("pinKey")
        .or_else(|| snapshot.get("pin_key"))
        .and_then(Value::as_str)
        .map(str::to_string)
        .unwrap_or_else(|| {
            let provider = quota_provider(snapshot);
            if provider == "claude" {
                format!("claude:{}", quota_account(snapshot))
            } else {
                provider.to_string()
            }
        })
}

fn quota_overview_panel(
    snapshots: Vec<Value>,
    settings: State<QuotaSettings>,
    reset_confirmation: State<Option<CodexResetOffer>>,
    reset_error: State<Option<String>>,
    bridge: RuntimeBridge,
) -> Element {
    let current = settings.read().clone();
    let snapshots = enabled_quota_snapshots(snapshots, &current, false);
    let reset_rows = snapshots
        .iter()
        .filter(|snapshot| codex_reset_offer(snapshot).is_some())
        .count();
    let panel_height = quota_overview_panel_height(snapshots.len(), reset_rows);
    let mut rows = rect()
        .width(Size::fill())
        .vertical()
        .content(Content::Flex)
        .spacing(0.)
        .padding(Gaps::new(4., 0., 4., 0.));
    if snapshots.is_empty() {
        rows = rows.child(label().font_size(11.).color(MUTED).text("No Quota Data"));
    }
    for snapshot in snapshots {
        let provider = quota_provider(&snapshot).to_string();
        let display_name = snapshot
            .get("displayName")
            .and_then(Value::as_str)
            .unwrap_or(provider.as_str())
            .to_string();
        let name = if provider == "claude" {
            format!("Claude Code {display_name}")
        } else {
            display_name
        };
        let pin_key = quota_pin_key(&snapshot);
        let pinned = current.is_pinned(&pin_key);
        let mut next = current.clone();
        next.toggle_pin(&pin_key);
        let mut settings_for_pin = settings;
        let bridge_for_pin = bridge.clone();
        let previous_for_failure = current.clone();
        let readings = quota_readings(&snapshot);
        let reset_offer = codex_reset_offer(&snapshot);
        let mut row = rect()
            .width(Size::fill())
            .min_height(Size::px(18.))
            .horizontal()
            .content(Content::Flex)
            .cross_align(Alignment::Center)
            .spacing(6.)
            .padding(Gaps::new(0., 8., 0., 8.))
            .maybe_child(provider_icon_for_name(&provider))
            .child(
                label()
                    .font_size(10.)
                    .font_family("JetBrains Mono")
                    .font_weight(FontWeight::SEMI_BOLD)
                    .color(TEXT)
                    .max_lines(1)
                    .text(name),
            )
            .child(rect().width(Size::flex(1.)).child(""));
        for (reading, percent) in readings {
            row = row.child(
                rect()
                    .horizontal()
                    .cross_align(Alignment::Center)
                    .spacing(2.)
                    .child(
                        label()
                            .font_size(9.)
                            .font_family("JetBrains Mono")
                            .color(FAINT)
                            .text(reading),
                    )
                    .child(
                        label()
                            .font_size(10.)
                            .font_family("JetBrains Mono")
                            .font_weight(FontWeight::SEMI_BOLD)
                            .color(quota_percent_color(&snapshot, percent))
                            .text(format!("{percent:.0}%")),
                    ),
            );
        }
        row = row.child(
            rect()
                .key(format!("quota-pin-{pin_key}-{pinned}"))
                .width(Size::px(18.))
                .height(Size::px(18.))
                .center()
                .corner_radius(4.)
                .a11y_role(AccessibilityRole::Button)
                .a11y_alt(if pinned {
                    "Unpin From Status Bar"
                } else {
                    "Pin To Status Bar"
                })
                .on_pointer_enter(|_| Cursor::set(CursorIcon::Pointer))
                .on_pointer_leave(|_| Cursor::set(CursorIcon::default()))
                .on_pointer_down(move |event: Event<PointerEventData>| {
                    event.stop_propagation();
                    settings_for_pin.set(next.clone());
                    let bridge = bridge_for_pin.clone();
                    let payload = next.payload();
                    let mut settings_for_failure = settings_for_pin;
                    let previous = previous_for_failure.clone();
                    spawn(async move {
                        if bridge
                            .request("runtimeSettings.update", payload)
                            .await
                            .is_err()
                        {
                            settings_for_failure.set(previous);
                        }
                    });
                })
                .child(
                    TooltipContainer::new(Tooltip::new_text(if pinned {
                        "Unpin From Status Bar"
                    } else {
                        "Pin To Status Bar"
                    }))
                    .position(AttachedPosition::Top)
                    .delay(Duration::from_millis(350))
                    .child(
                        rect().interactive(false).center().child(
                            SvgViewer::new(if pinned {
                                icons::lucide::pin()
                            } else {
                                icons::lucide::pin_off()
                            })
                            .width(Size::px(11.))
                            .height(Size::px(11.))
                            .color(if pinned { MUTED } else { FAINT }),
                        ),
                    ),
                ),
        );
        let mut entry = rect().width(Size::fill()).vertical().child(row);
        if let Some(offer) = reset_offer {
            entry = entry.child(codex_reset_summary_row(
                offer,
                reset_confirmation,
                reset_error,
            ));
        }
        rows = rows.child(entry);
    }
    ScrollView::new()
        .width(Size::fill())
        .height(Size::px(panel_height))
        .child(rows)
        .into()
}

fn quota_overview_panel_height(snapshot_count: usize, reset_rows: usize) -> f32 {
    if snapshot_count == 0 {
        56.
    } else {
        // Each regular row has an 18px extent and the container contributes
        // 4px of vertical padding on both sides, matching Flutter's rendered
        // density. Using 19px here left a visible blank strip at the bottom.
        (8. + snapshot_count as f32 * 18. + reset_rows as f32 * 28.).min(480.)
    }
}

fn codex_reset_offer(snapshot: &Value) -> Option<CodexResetOffer> {
    if quota_provider(snapshot) != "codex" {
        return None;
    }
    let credits = snapshot.get("rateLimitResetCredits")?;
    Some(CodexResetOffer {
        available_count: credits
            .get("availableCount")
            .and_then(Value::as_i64)
            .unwrap_or_default()
            .max(0),
        next_expires_at: credits.get("nextExpiresAt").and_then(Value::as_i64),
        offer_revision: credits
            .get("offerRevision")
            .and_then(Value::as_str)
            .unwrap_or_default()
            .to_string(),
        can_consume: credits
            .get("canConsume")
            .and_then(Value::as_bool)
            .unwrap_or(false),
    })
}

fn codex_reset_summary_row(
    offer: CodexResetOffer,
    mut confirmation: State<Option<CodexResetOffer>>,
    mut error: State<Option<String>>,
) -> Element {
    let enabled = offer.available_count > 0 && offer.can_consume;
    let label_text = format!(
        "{} Rate-Limit {} Available",
        offer.available_count,
        if offer.available_count == 1 {
            "Reset"
        } else {
            "Resets"
        }
    );
    let expiry = codex_reset_expiry_text(offer.next_expires_at);
    let offer_for_press = offer;
    rect()
        .width(Size::fill())
        .height(Size::px(28.))
        .horizontal()
        .content(Content::Flex)
        .cross_align(Alignment::Center)
        .padding(Gaps::new(1., 8., 1., 8.))
        .child(
            rect()
                .vertical()
                .spacing(1.)
                .child(
                    label()
                        .font_size(9.)
                        .font_family("JetBrains Mono")
                        .font_weight(FontWeight::SEMI_BOLD)
                        .color(MUTED)
                        .text(label_text),
                )
                .maybe_child(expiry.map(|expiry| {
                    label()
                        .font_size(8.)
                        .font_family("JetBrains Mono")
                        .color(FAINT)
                        .text(expiry)
                })),
        )
        .child(rect().width(Size::flex(1.)).child(""))
        .maybe_child((offer_for_press.available_count > 0).then(|| {
            rect()
                .height(Size::px(22.))
                .padding(Gaps::new(0., 6., 0., 6.))
                .center()
                .corner_radius(4.)
                .a11y_role(AccessibilityRole::Button)
                .a11y_alt("Use Reset")
                .on_pointer_enter(move |_| {
                    Cursor::set(if enabled {
                        CursorIcon::Pointer
                    } else {
                        CursorIcon::default()
                    })
                })
                .on_pointer_leave(|_| Cursor::set(CursorIcon::default()))
                .on_pointer_down(move |event: Event<PointerEventData>| {
                    event.stop_propagation();
                    if enabled {
                        error.set(None);
                        confirmation.set(Some(offer_for_press.clone()));
                    }
                })
                .child(
                    label()
                        .font_size(10.)
                        .font_weight(FontWeight::SEMI_BOLD)
                        .color(if enabled { ACCENT } else { FAINT })
                        .text("Use Reset"),
                )
        }))
        .into()
}

fn codex_reset_expiry_text(expires_at: Option<i64>) -> Option<String> {
    let expires_at = DateTime::<Utc>::from_timestamp_millis(expires_at?)?;
    let remaining = expires_at.signed_duration_since(Utc::now());
    if remaining.num_milliseconds() <= 0 {
        return Some("Next Reset Expired".to_string());
    }
    if remaining.num_days() > 0 {
        return Some(format!(
            "Next Reset Expires In {}d {}h",
            remaining.num_days(),
            remaining.num_hours() % 24
        ));
    }
    if remaining.num_hours() > 0 {
        return Some(format!(
            "Next Reset Expires In {}h {}m",
            remaining.num_hours(),
            remaining.num_minutes() % 60
        ));
    }
    Some(format!(
        "Next Reset Expires In {}m",
        remaining.num_minutes().clamp(1, 59)
    ))
}

fn codex_reset_confirmation_overlay(
    bridge: RuntimeBridge,
    confirmation: State<Option<CodexResetOffer>>,
    action_busy: State<bool>,
    action_error: State<Option<String>>,
    refresh_revision: State<u64>,
) -> Option<Element> {
    let offer = confirmation.read().clone()?;
    let busy_now = *action_busy.read();
    let error_now = action_error.read().clone();
    let mut confirmation_for_cancel = confirmation;
    let mut confirmation_for_submit = confirmation;
    let mut busy = action_busy;
    let mut error = action_error;
    let mut refresh = refresh_revision;
    let mut confirmation_for_barrier = confirmation;
    Some(
        rect()
            .position(Position::new_absolute())
            .layer(Layer::Overlay)
            .width(Size::percent(100.))
            .height(Size::percent(100.))
            .background(Color::from_af32rgb(0.72, 0, 0, 0))
            .on_pointer_down(move |_| {
                if !busy_now {
                    confirmation_for_barrier.set(None);
                }
            })
            .child(
                rect()
                    .position(Position::new_absolute())
                    .width(Size::percent(100.))
                    .height(Size::percent(100.))
                    .center()
                    .child(
                        rect()
                            .width(Size::px(440.))
                            .vertical()
                            .spacing(14.)
                            .padding(Gaps::new_all(20.))
                            .background(SURFACE)
                            .border(Border::new().width(1.).fill(BORDER))
                            .corner_radius(8.)
                            .on_pointer_down(|event: Event<PointerEventData>| {
                                event.stop_propagation()
                            })
                            .child(
                                label()
                                    .font_size(15.)
                                    .font_weight(FontWeight::SEMI_BOLD)
                                    .color(TEXT)
                                    .text("Use Codex Reset"),
                            )
                            .child(
                                label()
                                    .font_size(12.)
                                    .color(MUTED)
                                    .max_lines(4)
                                    .text(
                                        "Use One Codex Rate-Limit Reset Credit? Alera Will Re-Check The Active Account And Offer Before Applying It.",
                                    ),
                            )
                            .maybe_child(error_now.map(|message| {
                                label()
                                    .font_size(11.)
                                    .color((248, 113, 113))
                                    .max_lines(3)
                                    .text(message)
                            }))
                            .child(
                                rect()
                                    .horizontal()
                                    .main_align(Alignment::End)
                                    .spacing(8.)
                                    .child(
                                        rect()
                                            .a11y_role(AccessibilityRole::Button)
                                            .a11y_alt("Cancel")
                                            .on_pointer_enter(|_| {
                                                Cursor::set(CursorIcon::Pointer)
                                            })
                                            .on_pointer_leave(|_| {
                                                Cursor::set(CursorIcon::default())
                                            })
                                            .on_pointer_down(
                                                move |event: Event<PointerEventData>| {
                                                    event.stop_propagation();
                                                    if !busy_now {
                                                        error.set(None);
                                                        confirmation_for_cancel.set(None);
                                                    }
                                                },
                                            )
                                            .child(Button::new().child("Cancel")),
                                    )
                                    .child(
                                        rect()
                                            .a11y_role(AccessibilityRole::Button)
                                            .a11y_alt("Use Reset")
                                            .on_pointer_enter(|_| {
                                                Cursor::set(CursorIcon::Pointer)
                                            })
                                            .on_pointer_leave(|_| {
                                                Cursor::set(CursorIcon::default())
                                            })
                                            .on_pointer_down(
                                                move |event: Event<PointerEventData>| {
                                                    event.stop_propagation();
                                                    if busy_now {
                                                        return;
                                                    }
                                                    busy.set(true);
                                                    error.set(None);
                                                    let bridge = bridge.clone();
                                                    let offer_revision =
                                                        offer.offer_revision.clone();
                                                    spawn(async move {
                                                        match bridge
                                                            .request_with_timeout(
                                                                "agentQuota.consumeCodexResetCredit",
                                                                json!({"offerRevision": offer_revision}),
                                                                Duration::from_secs(90),
                                                            )
                                                            .await
                                                        {
                                                            Ok(_) => {
                                                                confirmation_for_submit.set(None);
                                                                let next_revision = refresh
                                                                    .read()
                                                                    .saturating_add(1);
                                                                refresh.set(next_revision);
                                                            }
                                                            Err(message) => {
                                                                error.set(Some(message))
                                                            }
                                                        }
                                                        busy.set(false);
                                                    });
                                                },
                                            )
                                            .child(Button::new().filled().child(if busy_now {
                                                CircularLoader::new().size(13.).into_element()
                                            } else {
                                                label().text("Use Reset").into_element()
                                            })),
                                    ),
                            ),
                    ),
            )
            .into_element(),
    )
}

fn quota_readings(snapshot: &Value) -> Vec<(String, f64)> {
    let provider = quota_provider(snapshot);
    let windows = snapshot
        .get("windows")
        .and_then(Value::as_array)
        .into_iter()
        .flatten()
        .map(|reading| (reading, false));
    let buckets = snapshot
        .get("buckets")
        .and_then(Value::as_array)
        .into_iter()
        .flatten()
        .map(|reading| (reading, true));
    let mut readings = windows
        .chain(buckets)
        .filter_map(|(reading, is_bucket)| {
            let full_label = reading
                .get("label")
                .or_else(|| reading.get("name"))
                .or_else(|| reading.get("fullLabel"))
                .and_then(Value::as_str)?;
            let remaining_percent = reading
                .get("remainingPercent")
                .or_else(|| reading.get("remaining_percent"))
                .and_then(Value::as_f64)
                .or_else(|| {
                    reading
                        .get("usedPercent")
                        .or_else(|| reading.get("used_percent"))
                        .and_then(Value::as_f64)
                        .map(|used| 100. - used)
                })?
                .clamp(0., 100.);
            Some((
                compact_quota_label(provider, full_label, is_bucket),
                remaining_percent,
                quota_reading_order(provider, full_label),
            ))
        })
        .collect::<Vec<_>>();
    readings.sort_by_key(|reading| reading.2);
    readings
        .into_iter()
        .map(|(label, remaining_percent, _)| (label, remaining_percent))
        .collect()
}

fn compact_quota_label(provider: &str, label: &str, is_bucket: bool) -> String {
    let lower = label.to_lowercase();
    if provider == "claude" && lower.contains("fable") {
        return "F".to_string();
    }
    if is_bucket && provider == "antigravity" {
        let group = if lower.contains("gemini") { "G" } else { "C/G" };
        return format!("{group}·{}", short_quota_label(label));
    }
    if is_bucket && provider == "zai" && lower.contains("mcp") {
        return "MCP".to_string();
    }
    if is_bucket && provider == "minimax" {
        let model = strip_ascii_case_suffix(label.trim(), " Weekly")
            .trim_start_matches(|character: char| character.is_whitespace());
        let model = strip_ascii_case_prefix(model, "MiniMax-").trim();
        let compact_model = match model.to_lowercase().as_str() {
            "general" => "G".to_string(),
            "video" => "V".to_string(),
            _ if model.chars().count() <= 6 => model.to_string(),
            _ => compact_model_label(model),
        };
        return format!("{compact_model}·{}", short_quota_label(label));
    }
    short_quota_label(label)
}

fn strip_ascii_case_prefix<'a>(value: &'a str, prefix: &str) -> &'a str {
    value
        .get(..prefix.len())
        .filter(|candidate| candidate.eq_ignore_ascii_case(prefix))
        .and_then(|_| value.get(prefix.len()..))
        .unwrap_or(value)
}

fn strip_ascii_case_suffix<'a>(value: &'a str, suffix: &str) -> &'a str {
    value
        .len()
        .checked_sub(suffix.len())
        .and_then(|start| value.get(start..).map(|candidate| (start, candidate)))
        .filter(|(_, candidate)| candidate.eq_ignore_ascii_case(suffix))
        .and_then(|(start, _)| value.get(..start))
        .unwrap_or(value)
}

fn compact_model_label(value: &str) -> String {
    let characters = value.chars().collect::<Vec<_>>();
    for index in 0..characters.len() {
        if !matches!(characters[index], 'm' | 'M') {
            continue;
        }
        let mut end = index + 1;
        let mut saw_digit = false;
        while end < characters.len() && (characters[end].is_ascii_digit() || characters[end] == '.')
        {
            saw_digit |= characters[end].is_ascii_digit();
            end += 1;
        }
        if saw_digit {
            return characters[index..end].iter().collect();
        }
    }
    value.chars().take(6).collect()
}

fn short_quota_label(label: &str) -> String {
    let lower = label.to_lowercase();
    if lower.contains("5 hour") || lower.contains("5h") {
        "5H".to_string()
    } else if lower.contains("week") {
        "W".to_string()
    } else if lower.contains("month") {
        "M".to_string()
    } else if lower.contains("day") {
        "D".to_string()
    } else if label.len() <= 4 {
        label.to_uppercase()
    } else {
        "Q".to_string()
    }
}

fn quota_reading_order(provider: &str, label: &str) -> u8 {
    let lower = label.to_lowercase();
    if provider == "claude" {
        if lower.contains("5 hour") || lower.contains("5h") {
            return 0;
        }
        if lower.contains("fable") {
            return 2;
        }
        if lower.contains("week") {
            return 1;
        }
    }
    if provider == "antigravity" {
        let group = if lower.contains("gemini") { 0 } else { 10 };
        let window = u8::from(!(lower.contains("5 hour") || lower.contains("5h")));
        return group + window;
    }
    if lower.contains("5 hour") || lower.contains("5h") {
        0
    } else if lower.contains("week") {
        1
    } else if lower.contains("month") {
        2
    } else {
        3
    }
}

fn quota_percent_color(snapshot: &Value, percent: f64) -> (u8, u8, u8) {
    let status = snapshot
        .get("status")
        .and_then(Value::as_str)
        .unwrap_or("available");
    if matches!(status, "error" | "unavailable") || percent < 20. {
        (248, 113, 113)
    } else if status == "stale" {
        FAINT
    } else if percent < 50. {
        (245, 158, 11)
    } else {
        SUCCESS
    }
}

fn runtime_host_config(
    terminal: &settings_terminal_state::StoredTerminalSettings,
    lifecycle: &FreyaRuntimeHostSettings,
    status: Option<&Value>,
) -> RuntimeHostStartConfig {
    let positive = |value: i64, fallback: u64| {
        u64::try_from(value)
            .ok()
            .filter(|value| *value > 0)
            .unwrap_or(fallback)
    };
    let crash_reporting = status
        .and_then(|value| value.get("diagnostics"))
        .and_then(|value| value.get("crashReportingEnabled"))
        .and_then(Value::as_bool)
        .unwrap_or(lifecycle.crash_reporting_enabled);
    RuntimeHostStartConfig {
        empty_shutdown_delay_seconds: positive(lifecycle.host_empty_shutdown_delay_seconds, 30),
        detached_session_shutdown_delay_seconds: positive(
            lifecycle.host_detached_shutdown_delay_seconds,
            3_600,
        ),
        scrollback_bytes: positive(terminal.terminal_host_scrollback_bytes, 10_000_000),
        login_shell: terminal.terminal_login_shell,
        crash_reporting,
    }
}

fn merge_runtime_status(
    current: Option<Value>,
    result: Result<Value, String>,
) -> (Option<Value>, Option<String>) {
    match result {
        Ok(value) => (Some(value), None),
        Err(error) => (current, Some(error)),
    }
}

fn start_runtime_host(
    bridge: RuntimeBridge,
    state: RuntimeActionState,
    config: RuntimeHostStartConfig,
) {
    let mut busy = state.busy;
    let mut force_required = state.force_required;
    let mut message = state.message;
    let mut restart_after_stop = state.restart_after_stop;
    busy.set(true);
    force_required.set(None);
    message.set(None);
    restart_after_stop.set(false);
    spawn(async move {
        let result = bridge.start_host(config).await;
        if result.is_ok() {
            Timer::after(Duration::from_millis(500)).await;
        }
        let status = match result {
            Ok(()) => {
                bridge
                    .request_with_timeout("status.get", json!({}), Duration::from_secs(30))
                    .await
            }
            Err(error) => Err(error),
        };
        let succeeded = status.is_ok();
        let mut snapshot = state.snapshot;
        let mut error_state = state.error;
        let current = snapshot.read().clone();
        let (next_snapshot, error) = merge_runtime_status(current, status);
        snapshot.set(next_snapshot);
        error_state.set(error.clone());
        message.set(if succeeded {
            Some("Runtime Started".to_string())
        } else {
            None
        });
        busy.set(false);
    });
}

fn stop_runtime_host(
    bridge: RuntimeBridge,
    state: RuntimeActionState,
    force: bool,
    restart_after_stop: bool,
    config: RuntimeHostStartConfig,
) {
    let mut busy = state.busy;
    let mut force_required = state.force_required;
    let mut message = state.message;
    let mut restart_state = state.restart_after_stop;
    busy.set(true);
    message.set(None);
    restart_state.set(restart_after_stop);
    spawn(async move {
        match bridge
            .request("host.shutdown", json!({"force": force}))
            .await
        {
            Ok(_) if restart_after_stop => {
                force_required.set(None);
                wait_until_runtime_stopped(&bridge).await;
                match bridge.start_host(config).await {
                    Ok(()) => {
                        Timer::after(Duration::from_millis(500)).await;
                        let status = bridge
                            .request_with_timeout("status.get", json!({}), Duration::from_secs(30))
                            .await;
                        let succeeded = status.is_ok();
                        let mut snapshot = state.snapshot;
                        let mut error_state = state.error;
                        let current = snapshot.read().clone();
                        let (next_snapshot, error) = merge_runtime_status(current, status);
                        snapshot.set(next_snapshot);
                        error_state.set(error.clone());
                        message.set(if succeeded {
                            Some("Runtime Updated".to_string())
                        } else {
                            None
                        });
                    }
                    Err(error) => {
                        let mut error_state = state.error;
                        error_state.set(Some(error));
                        message.set(None);
                    }
                }
                restart_state.set(false);
            }
            Ok(_) => {
                force_required.set(None);
                wait_until_runtime_stopped(&bridge).await;
                let mut error = state.error;
                error.set(Some("Runtime Host Is Stopped".to_string()));
                message.set(Some("Runtime Stopped".to_string()));
                restart_state.set(false);
            }
            Err(error) if !force && runtime_shutdown_is_busy(&error) => {
                force_required.set(Some(error.clone()));
                message.set(None);
            }
            Err(error) => {
                force_required.set(None);
                message.set(Some(error));
                restart_state.set(false);
            }
        }
        busy.set(false);
    });
}

async fn wait_until_runtime_stopped(bridge: &RuntimeBridge) {
    let deadline = Instant::now() + Duration::from_secs(8);
    while Instant::now() < deadline {
        if bridge
            .request_with_timeout("status.get", json!({}), Duration::from_secs(1))
            .await
            .is_err()
        {
            return;
        }
        Timer::after(Duration::from_millis(100)).await;
    }
}

fn runtime_shutdown_is_busy(error: &str) -> bool {
    let normalized = error.to_ascii_lowercase();
    normalized.contains("retry with --force")
        && (normalized.contains("active agent")
            || normalized.contains("active terminal session")
            || normalized.contains("active background job")
            || normalized.contains("active push subscription"))
}

fn runtime_force_confirmation_overlay(
    bridge: RuntimeBridge,
    state: RuntimeActionState,
    config: RuntimeHostStartConfig,
) -> Option<Element> {
    let message = state.force_required.read().clone()?;
    let busy = *state.busy.read();
    let restart_after_stop = *state.restart_after_stop.read();
    let mut force_for_cancel = state.force_required;
    let mut restart_for_cancel = state.restart_after_stop;
    let mut message_for_cancel = state.message;
    let mut force_for_barrier = state.force_required;
    let mut restart_for_barrier = state.restart_after_stop;
    let mut message_for_barrier = state.message;
    Some(
        rect()
            .position(Position::new_absolute())
            .layer(Layer::Overlay)
            .width(Size::percent(100.))
            .height(Size::percent(100.))
            .background(Color::from_af32rgb(0.72, 0, 0, 0))
            .on_pointer_down(move |_| {
                if !busy {
                    force_for_barrier.set(None);
                    restart_for_barrier.set(false);
                    message_for_barrier.set(None);
                }
            })
            .child(
                rect()
                    .position(Position::new_absolute())
                    .width(Size::percent(100.))
                    .height(Size::percent(100.))
                    .center()
                    .child(
                        rect()
                            .width(Size::px(430.))
                            .vertical()
                            .spacing(14.)
                            .padding(Gaps::new_all(20.))
                            .background(SURFACE_RAISED)
                            .border(Border::new().width(1.).fill(BORDER))
                            .corner_radius(8.)
                            .on_pointer_down(|event: Event<PointerEventData>| {
                                event.stop_propagation()
                            })
                            .child(
                                label()
                                    .font_size(15.)
                                    .font_weight(FontWeight::SEMI_BOLD)
                                    .color(TEXT)
                                    .text("Force Stop Runtime"),
                            )
                            .child(
                                label()
                                    .font_size(12.)
                                    .color(MUTED)
                                    .max_lines(6)
                                    .text(format!("{message} Force Stop Terminates Them.")),
                            )
                            .child(
                                rect()
                                    .horizontal()
                                    .main_align(Alignment::End)
                                    .spacing(8.)
                                    .child(runtime_action_button(
                                        "Cancel",
                                        !busy,
                                        false,
                                        false,
                                        move |event: Event<PointerEventData>| {
                                            event.stop_propagation();
                                            if !busy {
                                                force_for_cancel.set(None);
                                                restart_for_cancel.set(false);
                                                message_for_cancel.set(None);
                                            }
                                        },
                                    ))
                                    .child(runtime_action_button(
                                        "Force Stop",
                                        !busy,
                                        true,
                                        busy,
                                        move |event: Event<PointerEventData>| {
                                            event.stop_propagation();
                                            if !busy {
                                                stop_runtime_host(
                                                    bridge.clone(),
                                                    state,
                                                    true,
                                                    restart_after_stop,
                                                    config.clone(),
                                                );
                                            }
                                        },
                                    )),
                            ),
                    ),
            )
            .into_element(),
    )
}

fn runtime_action_button(
    label_text: &'static str,
    enabled: bool,
    danger: bool,
    loading: bool,
    action: impl Into<EventHandler<Event<PointerEventData>>>,
) -> Element {
    rect()
        .height(Size::px(28.))
        .min_width(Size::px(58.))
        .padding(Gaps::new(9., 0., 9., 0.))
        .center()
        .background(if danger {
            Color::from_af32rgb(0., 0, 0, 0)
        } else if label_text == "Start" || label_text == "Update Runtime" {
            ACCENT.into()
        } else {
            Color::from_af32rgb(0., 0, 0, 0)
        })
        .border(
            Border::new()
                .width(1.)
                .fill(if danger { (248, 113, 113) } else { BORDER }),
        )
        .corner_radius(6.)
        .a11y_role(AccessibilityRole::Button)
        .a11y_alt(label_text)
        .on_pointer_enter(move |_| {
            Cursor::set(if enabled {
                CursorIcon::Pointer
            } else {
                CursorIcon::default()
            })
        })
        .on_pointer_leave(|_| Cursor::set(CursorIcon::default()))
        .maybe(enabled, |button| button.on_pointer_down(action))
        .child(if loading {
            CircularLoader::new().size(13.).into_element()
        } else {
            label()
                .font_size(10.)
                .color(if danger {
                    (248, 113, 113)
                } else if label_text == "Start" || label_text == "Update Runtime" {
                    BACKGROUND
                } else {
                    TEXT
                })
                .text(label_text)
                .into_element()
        })
        .into_element()
}

fn runtime_status_actions(
    bridge: RuntimeBridge,
    state: RuntimeActionState,
    config: RuntimeHostStartConfig,
) -> Element {
    let running = state.snapshot.read().is_some() && state.error.read().is_none();
    let busy = *state.busy.read();
    let status_snapshot = state.snapshot.read();
    let status_value = status_snapshot.as_ref();
    let update_available = status_value.is_some_and(runtime_update_available);
    let stop_is_destructive = status_value.is_some_and(|value| {
        value
            .get("activeSessions")
            .and_then(Value::as_i64)
            .unwrap_or_default()
            > 0
            || value
                .get("activeAgents")
                .and_then(Value::as_i64)
                .unwrap_or_default()
                > 0
    });
    let mut revision = state.revision;
    let bridge_for_start = bridge.clone();
    let state_for_start = state;
    let bridge_for_stop = bridge.clone();
    let state_for_stop = state;
    let bridge_for_update = bridge;
    let state_for_update = state;
    let config_for_start = config.clone();
    let config_for_stop = config.clone();
    let config_for_update = config;

    let mut actions = rect()
        .width(Size::fill())
        .horizontal()
        .main_align(Alignment::End)
        .spacing(6.)
        .child(runtime_action_button(
            "Refresh",
            !busy,
            false,
            false,
            move |event: Event<PointerEventData>| {
                event.stop_propagation();
                let next = revision.read().saturating_add(1);
                revision.set(next);
            },
        ));
    if running {
        actions = actions.child(runtime_action_button(
            "Stop",
            !busy,
            stop_is_destructive,
            busy,
            move |event: Event<PointerEventData>| {
                event.stop_propagation();
                if !busy {
                    stop_runtime_host(
                        bridge_for_stop.clone(),
                        state_for_stop,
                        false,
                        false,
                        config_for_stop.clone(),
                    );
                }
            },
        ));
        if update_available {
            actions = actions.child(runtime_action_button(
                "Update Runtime",
                !busy,
                false,
                busy,
                move |event: Event<PointerEventData>| {
                    event.stop_propagation();
                    if !busy {
                        stop_runtime_host(
                            bridge_for_update.clone(),
                            state_for_update,
                            false,
                            true,
                            config_for_update.clone(),
                        );
                    }
                },
            ));
        }
    } else {
        actions = actions.child(runtime_action_button(
            "Start",
            !busy,
            false,
            busy,
            move |event: Event<PointerEventData>| {
                event.stop_propagation();
                if !busy {
                    start_runtime_host(
                        bridge_for_start.clone(),
                        state_for_start,
                        config_for_start.clone(),
                    );
                }
            },
        ));
    }

    rect()
        .width(Size::fill())
        .vertical()
        .spacing(8.)
        .maybe_child(state.error.read().clone().map(|error| {
            label()
                .font_size(10.)
                .color((248, 113, 113))
                .max_lines(5)
                .text(error)
        }))
        .maybe_child(state.message.read().clone().map(|message| {
            label()
                .font_size(10.)
                .color(MUTED)
                .max_lines(5)
                .text(message)
        }))
        .child(actions)
        .into_element()
}

fn runtime_metrics(state: Option<&Value>, error: Option<&str>) -> Vec<(String, String)> {
    let running = state.is_some() && error.is_none();
    let status = if running {
        "Running"
    } else if state.is_none() && error.is_none() {
        "Checking"
    } else {
        "Stopped"
    };
    let version = state
        .and_then(|value| {
            value
                .get("runtimeHostVersion")
                .or_else(|| value.get("version"))
                .and_then(Value::as_str)
        })
        .map(version_label)
        .unwrap_or_else(|| "-".to_string());
    let bundled_version = version_label(env!("CARGO_PKG_VERSION"));
    let host_commit = state
        .and_then(|value| value.get("runtimeHostCommit"))
        .and_then(Value::as_str);
    let bundled_commit = option_env!("ALERA_BUILD_COMMIT").unwrap_or("unknown");
    let versions_match = state
        .and_then(|value| value.get("runtimeHostVersion"))
        .and_then(Value::as_str)
        .is_some_and(|host| compare_runtime_host_versions(env!("CARGO_PKG_VERSION"), host).is_eq());
    let build_mismatch = running
        && versions_match
        && matches!(
            (known_commit(host_commit), known_commit(Some(bundled_commit))),
            (Some(host), Some(bundled)) if host != bundled
        );
    let lifecycle = state
        .and_then(|value| value.get("persistent"))
        .and_then(Value::as_bool)
        .filter(|persistent| *persistent)
        .map(|_| "Persistent".to_string());
    let sessions = state
        .and_then(|value| value.get("activeSessions"))
        .and_then(Value::as_i64)
        .unwrap_or_default()
        .to_string();
    let agents = state
        .and_then(|value| value.get("activeAgents"))
        .and_then(Value::as_i64)
        .unwrap_or_default()
        .to_string();
    let mut metrics = vec![
        ("Status".to_string(), status.to_string()),
        ("Host Version".to_string(), version),
        ("Bundled Version".to_string(), bundled_version),
        ("Sessions".to_string(), sessions),
        ("Agents".to_string(), agents),
    ];
    if build_mismatch {
        metrics.insert(3, ("Host Build".to_string(), build_label(host_commit)));
        metrics.insert(
            4,
            (
                "Bundled Build".to_string(),
                build_label(Some(bundled_commit)),
            ),
        );
    }
    if let Some(lifecycle) = lifecycle {
        let index = if build_mismatch { 5 } else { 3 };
        metrics.insert(index, ("Lifecycle".to_string(), lifecycle));
    }
    metrics
}

fn runtime_update_available(value: &Value) -> bool {
    let Some(host_version) = value
        .get("runtimeHostVersion")
        .and_then(Value::as_str)
        .filter(|version| !version.trim().is_empty())
    else {
        return false;
    };
    match compare_runtime_host_versions(env!("CARGO_PKG_VERSION"), host_version) {
        std::cmp::Ordering::Greater => true,
        std::cmp::Ordering::Less => false,
        std::cmp::Ordering::Equal => matches!(
            (
                known_commit(value.get("runtimeHostCommit").and_then(Value::as_str)),
                known_commit(option_env!("ALERA_BUILD_COMMIT")),
            ),
            (Some(host), Some(bundled)) if host != bundled
        ),
    }
}

fn compare_runtime_host_versions(left: &str, right: &str) -> std::cmp::Ordering {
    match (parse_semver_core(left), parse_semver_core(right)) {
        (Some(left), Some(right)) => left.cmp(&right),
        (Some(_), None) => std::cmp::Ordering::Greater,
        (None, Some(_)) => std::cmp::Ordering::Less,
        (None, None) => left.cmp(right),
    }
}

fn parse_semver_core(value: &str) -> Option<[u64; 3]> {
    let value = value.trim().trim_start_matches(['v', 'V']);
    if value.is_empty() {
        return None;
    }
    let core = value.split(['-', '+']).next()?;
    let parts = core.split('.').collect::<Vec<_>>();
    if parts.is_empty() || parts.len() > 3 {
        return None;
    }
    let mut numbers = [0_u64; 3];
    for (index, part) in parts.into_iter().enumerate() {
        numbers[index] = part.parse().ok()?;
    }
    Some(numbers)
}

fn known_commit(value: Option<&str>) -> Option<&str> {
    value.filter(|value| {
        let value = value.trim();
        !value.is_empty() && !value.eq_ignore_ascii_case("unknown")
    })
}

fn build_label(value: Option<&str>) -> String {
    known_commit(value)
        .map(|value| value.chars().take(7).collect())
        .unwrap_or_else(|| "-".to_string())
}

fn version_label(version: &str) -> String {
    let version = version.trim();
    if version.is_empty() {
        "-".to_string()
    } else if version.starts_with(['v', 'V']) {
        version.to_string()
    } else {
        format!("v{version}")
    }
}

fn quota_status_chip() -> Element {
    rect()
        .interactive(false)
        .horizontal()
        .cross_align(Alignment::Center)
        .child(
            SvgViewer::new(icons::lucide::gauge())
                .width(Size::px(13.))
                .height(Size::px(13.))
                .color(MUTED),
        )
        .into()
}

fn resource_status_chip(
    snapshot: Option<&Value>,
    workbench: Option<&WorkbenchSnapshot>,
) -> Element {
    let warming = snapshot
        .and_then(|value| value.get("warming"))
        .and_then(Value::as_bool)
        .unwrap_or(true);
    let memory = (!warming)
        .then(|| {
            snapshot
                .and_then(|value| value.pointer("/totals/memoryBytes"))
                .and_then(Value::as_u64)
        })
        .flatten();
    let known_tabs = workbench
        .into_iter()
        .flat_map(|workbench| &workbench.tabs)
        .filter(|tab| tab.kind == "terminal")
        .flat_map(|tab| {
            [
                Some(tab.id.as_str()),
                tab.payload.get("terminalSessionId").and_then(Value::as_str),
            ]
        })
        .flatten()
        .collect::<HashSet<_>>();
    let sessions = snapshot
        .and_then(|value| value.get("sessions"))
        .and_then(Value::as_array)
        .cloned()
        .unwrap_or_default();
    let session_count = sessions
        .iter()
        .filter(|session| {
            session
                .get("sessionId")
                .or_else(|| session.get("tabId"))
                .and_then(Value::as_str)
                .is_some_and(|id| known_tabs.contains(id))
        })
        .count();
    let orphan_count = sessions.len().saturating_sub(session_count);
    rect()
        .interactive(false)
        .horizontal()
        .content(Content::Flex)
        .cross_align(Alignment::Center)
        .spacing(6.)
        .padding(Gaps::new(0., 2., 0., 2.))
        .child(
            SvgViewer::new(icons::lucide::activity())
                .width(Size::px(13.))
                .height(Size::px(13.))
                .color(MUTED),
        )
        .child(
            label()
                .font_size(10.)
                .font_family("JetBrains Mono")
                .color(TEXT)
                .text(format_resource_memory(memory)),
        )
        .child(
            SvgViewer::new(icons::lucide::terminal())
                .width(Size::px(11.))
                .height(Size::px(11.))
                .color(MUTED),
        )
        .child(
            label()
                .font_size(10.)
                .font_family("JetBrains Mono")
                .color(TEXT)
                .text(session_count.to_string()),
        )
        .maybe_child((orphan_count > 0).then(|| {
            label()
                .font_size(10.)
                .font_family("JetBrains Mono")
                .color((245, 158, 11))
                .text(format!("({orphan_count})"))
        }))
        .into()
}

fn format_resource_memory(bytes: Option<u64>) -> String {
    let Some(bytes) = bytes else {
        return "-".to_string();
    };
    const KIB: f64 = 1024.;
    const MIB: f64 = KIB * 1024.;
    const GIB: f64 = MIB * 1024.;
    let bytes = bytes as f64;
    if bytes < MIB {
        format!("{:.0} KB", bytes / KIB)
    } else if bytes < GIB {
        format!("{:.1} MB", bytes / MIB)
    } else {
        format!("{:.2} GB", bytes / GIB)
    }
}

fn runtime_status_chip(state: Option<&Value>, error: Option<&str>) -> Element {
    let (text, color) = match (state, error) {
        (_, Some(_)) => ("Runtime Error".to_string(), (248, 113, 113)),
        (Some(value), None) if runtime_update_available(value) => {
            ("Update Available".to_string(), (245, 158, 11))
        }
        (Some(value), None) => {
            let version = value
                .get("runtimeHostVersion")
                .or_else(|| value.get("version"))
                .and_then(Value::as_str)
                .map(version_label);
            (
                version.map_or_else(
                    || "Runtime Running".to_string(),
                    |version| format!("Runtime {version}"),
                ),
                SUCCESS,
            )
        }
        (None, None) => ("Runtime".to_string(), MUTED),
    };
    rect()
        .interactive(false)
        .horizontal()
        .content(Content::Flex)
        .cross_align(Alignment::Center)
        .spacing(6.)
        .padding(Gaps::new(0., 2., 0., 2.))
        .child(
            SvgViewer::new(icons::lucide::server())
                .width(Size::px(13.))
                .height(Size::px(13.))
                .color(color),
        )
        .child(
            label()
                .font_size(10.)
                .font_family("JetBrains Mono")
                .color(color)
                .text(text),
        )
        .into()
}

/// A status popover mirrors Flutter's quota/resource/runtime controls:
/// hovering opens it after a short delay, leaving it visible briefly avoids
/// accidental dismissal while moving into the panel, and clicking pins it
/// until the trigger or an external surface is pressed.
#[allow(clippy::too_many_arguments)]
fn status_popover(
    kind: &'static str,
    icon: Bytes,
    heading: impl Into<String>,
    metrics: Vec<(String, String)>,
    footer: Option<Element>,
    open: State<bool>,
    trigger_content: Element,
    exclusivity: Option<(String, State<Option<String>>)>,
) -> Element {
    let heading = heading.into();
    let trigger_alt = format!("{heading} status");
    let pinned = use_state(|| false);
    let hovering = use_state(|| false);
    let entered_at = use_state(|| None::<Instant>);
    let left_at = use_state(|| None::<Instant>);
    let hover_suppressed = use_state(|| false);
    let trigger_bounds = use_state(|| None::<(f64, f64, f64, f64)>);
    let panel_bounds = use_state(|| None::<(f64, f64, f64, f64)>);

    // Keep the hover timing in the Freya task executor instead of using a
    // blocking thread.  This leaves pointer and keyboard events responsive
    // while the 350ms open and 2s close windows are pending.
    // Keep the hover timer in a component-owned task instead of `use_future`.
    // The latter exposes an extra FutureState signal that can be written while
    // the tab tree is rendering; the timer itself only updates the popover's
    // own signals and is cancelled when this component is unmounted.
    let exclusivity_for_timer = exclusivity.clone();
    use_hook(move || {
        let mut open = open;
        let pinned = pinned;
        let hovering = hovering;
        let entered_at = entered_at;
        let mut left_at = left_at;
        let mut hover_suppressed = hover_suppressed;
        let exclusivity = exclusivity_for_timer;
        spawn(async move {
            loop {
                Timer::after(Duration::from_millis(50)).await;
                if let Some((key, active)) = exclusivity.as_ref().cloned() {
                    let another_is_active = active
                        .read()
                        .as_deref()
                        .is_some_and(|active_key| active_key != key);
                    if another_is_active {
                        if open() {
                            open.set(false);
                        }
                        if pinned() {
                            let mut pinned = pinned;
                            pinned.set(false);
                        }
                        if hover_suppressed() {
                            hover_suppressed.set(false);
                        }
                        continue;
                    }
                }
                if pinned() {
                    continue;
                }
                if hovering() && !hover_suppressed() {
                    let should_open = {
                        let started = *entered_at.read();
                        started
                            .is_some_and(|started| started.elapsed() >= Duration::from_millis(350))
                    };
                    if should_open && !open() {
                        if let Some((key, mut active)) = exclusivity.as_ref().cloned() {
                            active.set(Some(key));
                        }
                        open.set(true);
                    }
                } else {
                    let should_close = {
                        let left = *left_at.read();
                        left.is_some_and(|left| left.elapsed() >= Duration::from_secs(2))
                    };
                    if should_close {
                        if open() {
                            open.set(false);
                        }
                        if let Some((key, mut active)) = exclusivity.as_ref().cloned()
                            && active.read().as_deref() == Some(key.as_str())
                        {
                            active.set(None);
                        }
                        left_at.set(None);
                    }
                }
            }
        });
    });

    let set_hovered = |hovering: bool,
                       mut hovering_state: State<bool>,
                       mut entered_at: State<Option<Instant>>,
                       mut left_at: State<Option<Instant>>,
                       mut hover_suppressed: State<bool>| {
        move |_| {
            Cursor::set(if hovering {
                CursorIcon::Pointer
            } else {
                CursorIcon::default()
            });
            hovering_state.set(hovering);
            if hovering {
                if !hover_suppressed() {
                    entered_at.set(Some(Instant::now()));
                }
                left_at.set(None);
            } else {
                hover_suppressed.set(false);
                left_at.set(Some(Instant::now()));
            }
        }
    };

    let mut open_for_button = open;
    let mut pinned_for_button = pinned;
    let mut hovering_for_button = hovering;
    let mut entered_for_button = entered_at;
    let mut left_for_button = left_at;
    let mut suppressed_for_button = hover_suppressed;
    let mut trigger_bounds_for_size = trigger_bounds;
    let exclusivity_for_button = exclusivity.clone();
    let panel_icon = icon.clone();
    let status_divider = Border::new()
        .width(BorderWidth {
            top: 0.,
            right: if kind == "Quota Provider" { 1. } else { 0. },
            bottom: 0.,
            left: if kind == "Quota Provider" { 0. } else { 1. },
        })
        .fill(BORDER);
    let button = rect()
        .width(Size::Inner)
        .height(Size::px(28.))
        .padding(Gaps::new(0., 6., 0., 6.))
        .border(status_divider)
        .corner_radius(5.)
        .a11y_role(AccessibilityRole::Button)
        .a11y_alt(trigger_alt)
        .on_sized(move |event: Event<SizedEventData>| {
            let area = event.area;
            trigger_bounds_for_size.set(Some((
                area.min_x() as f64,
                area.min_y() as f64,
                area.max_x() as f64,
                area.max_y() as f64,
            )));
        })
        .on_pointer_enter(set_hovered(
            true,
            hovering_for_button,
            entered_for_button,
            left_for_button,
            hover_suppressed,
        ))
        .on_pointer_leave(set_hovered(
            false,
            hovering_for_button,
            entered_for_button,
            left_for_button,
            hover_suppressed,
        ))
        .on_pointer_down(move |event: Event<PointerEventData>| {
            event.stop_propagation();
            let now_pinned = pinned_for_button.toggled();
            let was_open = *open_for_button.read();
            let now_open = now_pinned || !was_open;
            open_for_button.set(now_open);
            if let Some((key, mut active)) = exclusivity_for_button.clone() {
                if now_open {
                    active.set(Some(key));
                } else if active.read().as_deref() == Some(key.as_str()) {
                    active.set(None);
                }
            }
            if now_pinned {
                suppressed_for_button.set(false);
                hovering_for_button.set(true);
                entered_for_button.set(Some(Instant::now()));
                left_for_button.set(None);
            } else if was_open {
                // A second click explicitly closes the pinned panel. Keep the
                // pointer marked as present, but clear its entry timestamp so
                // the hover timer cannot immediately reopen it. A real leave
                // and re-entry starts a fresh hover window.
                hovering_for_button.set(true);
                suppressed_for_button.set(true);
                entered_for_button.set(None);
                left_for_button.set(None);
            }
        })
        .child(trigger_content);

    let mut open_for_global = open;
    let mut pinned_for_global = pinned;
    let mut hovering_for_global = hovering;
    let mut entered_for_global = entered_at;
    let mut left_for_global = left_at;
    let mut suppressed_for_global = hover_suppressed;
    let mut open_for_panel_press = open;
    let mut pinned_for_panel_press = pinned;
    let mut hovering_for_panel_press = hovering;
    let mut entered_for_panel_press = entered_at;
    let mut left_for_panel_press = left_at;
    let mut suppressed_for_panel_press = hover_suppressed;
    let exclusivity_for_panel_press = exclusivity.clone();
    let trigger_bounds_for_global = trigger_bounds;
    let panel_bounds_for_global = panel_bounds;
    let mut panel_bounds_for_size = panel_bounds;
    let exclusivity_for_global = exclusivity;
    // The status controls sit at the trailing edge of the shell.  Anchoring
    // every popover to the trigger's trailing edge keeps Quotas and Resources
    // inside the window as well as Runtime instead of letting their fixed
    // width overflow past the right edge.
    let detailed_resources = kind == "Resources";
    let detailed_quotas = kind == "Quotas";
    let detailed_quota_provider = kind == "Quota Provider";
    let detailed_runtime = kind == "Runtime";
    let detailed_panel = detailed_resources || detailed_quotas || detailed_quota_provider;
    let runtime_running = kind == "Runtime"
        && metrics
            .iter()
            .any(|(name, value)| name == "Status" && value == "Running");
    let quota_provider_left = {
        let bounds = *trigger_bounds.read();
        bounds
            .map(|(left, _, right, _)| ((left + right) / 2. - 180.).max(8.))
            .unwrap_or(8.)
    };
    let panel_position = if detailed_quotas {
        Position::new_global().bottom(38.).left(8.)
    } else if detailed_quota_provider {
        Position::new_global()
            .bottom(38.)
            .left(quota_provider_left as f32)
    } else {
        Position::new_absolute().bottom(38.).right(0.)
    };
    let panel = rect()
        .position(panel_position)
        .layer(Layer::Overlay)
        .width(Size::px(if detailed_resources {
            resource_manager::PANEL_WIDTH
        } else if detailed_quotas {
            380.
        } else if detailed_quota_provider {
            360.
        } else if detailed_runtime {
            240.
        } else {
            238.
        }))
        .maybe(detailed_resources, |panel| {
            panel.height(Size::px(420.)).content(Content::Flex)
        })
        .maybe(detailed_quotas, |panel| panel.max_height(Size::px(480.)))
        .maybe(detailed_quota_provider, |panel| {
            panel.max_height(Size::px(480.))
        })
        .maybe(detailed_runtime, |panel| panel.max_height(Size::px(360.)))
        .background(SURFACE_RAISED)
        .border(Border::new().width(1.).fill(BORDER))
        .corner_radius(if detailed_runtime { 10. } else { 8. })
        .maybe(detailed_runtime, |panel| {
            panel.shadow(Shadow::new().x(0.).y(8.).blur(16.).color((0, 0, 0, 0.08)))
        })
        .padding(if detailed_panel {
            Gaps::new_all(0.)
        } else if detailed_runtime {
            Gaps::new_all(12.)
        } else {
            Gaps::new_all(10.)
        })
        .spacing(if detailed_panel || detailed_runtime {
            0.
        } else {
            7.
        })
        .vertical()
        .on_sized(move |event: Event<SizedEventData>| {
            let area = event.area;
            panel_bounds_for_size.set(Some((
                area.min_x() as f64,
                area.min_y() as f64,
                area.max_x() as f64,
                area.max_y() as f64,
            )));
        })
        .on_pointer_enter(set_hovered(
            true,
            hovering_for_global,
            entered_for_global,
            left_for_global,
            hover_suppressed,
        ))
        .on_pointer_leave(set_hovered(
            false,
            hovering_for_global,
            entered_for_global,
            left_for_global,
            hover_suppressed,
        ))
        .on_pointer_down(move |event: Event<PointerEventData>| {
            event.stop_propagation();
            pinned_for_panel_press.set(true);
            open_for_panel_press.set(true);
            suppressed_for_panel_press.set(false);
            hovering_for_panel_press.set(true);
            entered_for_panel_press.set(None);
            left_for_panel_press.set(None);
            if let Some((key, mut active)) = exclusivity_for_panel_press.clone() {
                active.set(Some(key));
            }
        })
        .on_global_pointer_press(move |event: Event<PointerEventData>| {
            let point = event.global_location();
            let inside = [
                *trigger_bounds_for_global.read(),
                *panel_bounds_for_global.read(),
            ]
            .into_iter()
            .flatten()
            .any(|(left, top, right, bottom)| {
                point.x >= left && point.x <= right && point.y >= top && point.y <= bottom
            });
            if !inside {
                open_for_global.set(false);
                pinned_for_global.set(false);
                entered_for_global.set(None);
                left_for_global.set(None);
                hovering_for_global.set(false);
                suppressed_for_global.set(false);
                if let Some((key, mut active)) = exclusivity_for_global.clone()
                    && active.read().as_deref() == Some(key.as_str())
                {
                    active.set(None);
                }
            }
        })
        .maybe_child((!detailed_quotas && !detailed_quota_provider).then(|| {
            rect()
                .maybe(detailed_resources, |header| {
                    header
                        .height(Size::px(36.))
                        .padding(Gaps::new(12., 0., 12., 0.))
                        .border(
                            Border::new()
                                .width(BorderWidth {
                                    top: 0.,
                                    right: 0.,
                                    bottom: 1.,
                                    left: 0.,
                                })
                                .fill(BORDER),
                        )
                })
                .maybe(detailed_runtime, |header| {
                    header.height(Size::px(28.)).cross_align(Alignment::Start)
                })
                .horizontal()
                .content(Content::Flex)
                .cross_align(Alignment::Center)
                .spacing(6.)
                .maybe_child(detailed_resources.then(|| {
                    SvgViewer::new(panel_icon)
                        .width(Size::px(13.))
                        .height(Size::px(13.))
                        .color(MUTED)
                }))
                .child(
                    label()
                        .font_size(if detailed_runtime { 13. } else { 12. })
                        .maybe(detailed_runtime, |label| {
                            label.font_weight(FontWeight::SEMI_BOLD)
                        })
                        .color(TEXT)
                        .text(heading),
                )
                .child(rect().width(Size::flex(1.)).child(""))
                .maybe_child((!detailed_resources && !detailed_runtime).then(|| {
                    label()
                        .font_size(10.)
                        .color(if runtime_running { SUCCESS } else { MUTED })
                        .text(if kind == "Runtime" {
                            if runtime_running {
                                "● running"
                            } else {
                                "● stopped"
                            }
                        } else {
                            "live"
                        })
                }))
        }))
        .children(metrics.iter().map(|(name, value)| {
            rect()
                .width(Size::fill())
                .maybe(detailed_runtime, |row| row.min_height(Size::px(20.)))
                .horizontal()
                .content(Content::Flex)
                .cross_align(Alignment::Center)
                .spacing(if detailed_runtime { 8. } else { 6. })
                .maybe_child(status_metric_icon(kind, name))
                .child(
                    label()
                        .maybe(detailed_runtime, |label| label.width(Size::px(116.)))
                        .font_size(if detailed_runtime { 12. } else { 11. })
                        .color(MUTED)
                        .text(name.clone()),
                )
                .maybe_child((!detailed_runtime).then(|| rect().width(Size::flex(1.)).child("")))
                .child(
                    label()
                        .maybe(detailed_runtime, |label| label.width(Size::flex(1.)))
                        .font_size(11.)
                        .maybe(detailed_runtime, |label| {
                            label.font_family("JetBrains Mono")
                        })
                        .color(
                            if detailed_runtime && name == "Status" && value == "Running" {
                                SUCCESS
                            } else {
                                TEXT
                            },
                        )
                        .text(value.clone()),
                )
        }))
        .maybe_child(footer.map(|footer| {
            if detailed_runtime {
                rect()
                    .width(Size::fill())
                    .padding(Gaps::new(12., 0., 0., 0.))
                    .child(footer)
                    .into_element()
            } else {
                footer
            }
        }));

    rect()
        .width(Size::Inner)
        .vertical()
        .child(button)
        .maybe_child(open().then_some(panel))
        .into_element()
}

/// Resolve the provider mark used by quota rows and the compact agent strip.
/// Profile aliases such as `Default` and `leynierdev` are Claude profiles in
/// the runtime payload, so they intentionally use the Claude mark as well.
fn provider_icon_for_name(name: &str) -> Option<Element> {
    provider_icon_for_name_size(name, 15.)
}

fn provider_icon_for_name_size(name: &str, size: f32) -> Option<Element> {
    let normalized = name.trim().to_ascii_lowercase();
    let (kind, source, is_svg) = if normalized.contains("antigravity") {
        ("antigravity", ANTIGRAVITY_ICON, false)
    } else if normalized.contains("claude")
        || normalized == "default"
        || normalized.starts_with("leynier")
    {
        ("claude", CLAUDE_ICON, true)
    } else if normalized.contains("codex") {
        ("codex", CODEX_ICON, true)
    } else if normalized.contains("grok") {
        ("grok", GROK_ICON, true)
    } else if normalized.contains("kimi") {
        ("kimi", KIMI_ICON, true)
    } else if normalized.contains("minimax") {
        ("minimax", MINIMAX_ICON, true)
    } else if normalized.contains("z.ai") || normalized.contains("zai") {
        ("zai", ZAI_ICON, true)
    } else if normalized.contains("cursor") {
        ("cursor", CURSOR_ICON, false)
    } else {
        return None;
    };

    let icon = if is_svg {
        SvgViewer::new((kind, source))
            .show_loader(false)
            .width(Size::px(size))
            .height(Size::px(size))
            .color(TEXT)
            .into_element()
    } else {
        ImageViewer::new((kind, source))
            .width(Size::px(size))
            .height(Size::px(size))
            .into_element()
    };
    Some(icon)
}

fn status_metric_icon(kind: &str, name: &str) -> Option<Element> {
    (kind == "Quotas")
        .then(|| provider_icon_for_name(name))
        .flatten()
}

fn app_display_name() -> &'static str {
    if std::env::var("ALERA_APP_ID").is_ok_and(|app_id| app_id.ends_with(".dev")) {
        "Alera Dev"
    } else {
        "Alera"
    }
}

fn runtime_dir() -> PathBuf {
    std::env::var_os("ALERA_RUNTIME_DIR")
        .map(PathBuf::from)
        .or_else(|| {
            dirs::data_local_dir().map(|data| data.join("dev.leynier.alera").join("terminal_host"))
        })
        .expect("failed to resolve the Alera runtime directory")
}

#[cfg(test)]
mod headless_tests {
    use freya::{icons, prelude::*};
    use freya_testing::prelude::*;

    #[test]
    fn new_workspace_options_preserve_ids_while_showing_labels() {
        let options = vec![
            "Alera::project-alera".to_string(),
            "Website::project-website".to_string(),
        ];
        assert_eq!(super::option_id(&options[0]), Some("project-alera"));
        assert_eq!(
            super::option_for_id(&options, "project-website").as_deref(),
            Some("Website::project-website")
        );
        assert_eq!(
            super::first_option_id(&options).as_deref(),
            Some("project-alera")
        );
        assert_eq!(super::option_id("No Parent"), None);
    }

    #[test]
    fn new_workspace_profile_options_require_the_runtime_items_envelope() {
        let response = serde_json::json!({
            "items": [
                {"id": "codex", "name": "Codex"},
                {"id": "claude", "name": "Claude Code"}
            ]
        });
        assert_eq!(
            super::parse_agent_profile_options(&response).unwrap(),
            vec!["Codex::codex", "Claude Code::claude"]
        );
        assert!(super::parse_agent_profile_options(&serde_json::json!([])).is_err());
        assert!(
            super::parse_agent_profile_options(&serde_json::json!({"items": [{"id": "codex"}]}))
                .is_err()
        );
    }

    #[test]
    fn new_workspace_manual_payload_validates_modes_and_relation() {
        let create = super::manual_workspace_request(
            "project-1",
            "main",
            "feature/parity",
            "Parity",
            "Alera / Main - main::workspace-main",
            false,
        )
        .unwrap();
        assert_eq!(create["projectId"], "project-1");
        assert_eq!(create["sourceBranch"], "main");
        assert_eq!(create["branch"], "feature/parity");
        assert_eq!(create["parentWorkspaceId"], "workspace-main");
        assert_eq!(create["name"], "Parity");
        assert_eq!(create["reuseExistingBranch"], false);
        assert_eq!(create["deferSetup"], true);

        let reuse = super::manual_workspace_request(
            "project-1",
            "",
            "existing-branch",
            "",
            "No Parent",
            true,
        )
        .unwrap();
        assert!(reuse.get("sourceBranch").is_none());
        assert!(reuse.get("parentWorkspaceId").is_none());
        assert_eq!(reuse["reuseExistingBranch"], true);
        assert!(
            super::manual_workspace_request("project-1", "", "", "", "No Parent", true)
                .unwrap_err()
                .contains("Existing Branch")
        );
        assert!(
            super::manual_workspace_request(
                "project-1",
                "",
                "feature/parity",
                "",
                "No Parent",
                false,
            )
            .unwrap_err()
            .contains("Source Branch")
        );
    }

    #[test]
    fn new_workspace_runtime_payloads_require_identity_and_workspace_ids() {
        assert_eq!(
            super::workspace_identity_from_payload(&serde_json::json!({
                "workspaceName": "Parity",
                "branchName": "feature/parity"
            }))
            .unwrap(),
            ("Parity".to_string(), "feature/parity".to_string())
        );
        assert!(
            super::workspace_identity_from_payload(&serde_json::json!({
                "workspaceName": "Parity"
            }))
            .is_err()
        );
        assert_eq!(
            super::workspace_id_from_payload(
                &serde_json::json!({"workspace": {"id": "workspace-1"}})
            )
            .unwrap(),
            "workspace-1"
        );
        assert!(super::workspace_id_from_payload(&serde_json::json!({})).is_err());
        assert!(super::looks_like_workspace_collision(
            "A workspace for branch already exists"
        ));
        assert!(!super::looks_like_workspace_collision("Permission denied"));
    }

    #[test]
    fn freya_headless_renderer_mounts_a_component() {
        let mut runner = launch_test(|| rect().child(label().text("Alera")));
        runner.sync_and_update();
        assert!(
            runner
                .find(|_, element| {
                    Label::try_downcast(element).filter(|label| label.text.as_ref() == "Alera")
                })
                .is_some()
        );
        let _ = runner.render();
    }

    #[test]
    fn runtime_mode_selector_opens_and_changes_mode() {
        let mut runner = launch_test(|| {
            let mode = use_state(|| "Local".to_string());
            super::runtime_mode_selector(mode)
        });
        runner.sync_and_update();
        let local = runner
            .find(|node, element| {
                Label::try_downcast(element)
                    .filter(|label| label.text.as_ref() == "Local")
                    .map(|_| node)
            })
            .expect("selected runtime mode");
        let area = local.layout().area;
        runner.press_cursor((area.min_x() as f64 + 8., area.min_y() as f64 + 8.));
        runner.poll_n(std::time::Duration::from_millis(5), 100);
        runner.sync_and_update();
        assert!(
            runner
                .find(|_, element| {
                    Label::try_downcast(element).filter(|label| label.text.as_ref() == "SSH")
                })
                .is_some()
        );
        let remote = runner
            .find(|node, element| {
                Label::try_downcast(element)
                    .filter(|label| label.text.as_ref() == "Remote")
                    .map(|_| node)
            })
            .expect("remote runtime option");
        let area = remote.layout().area;
        runner.click_cursor(area.center().to_f64());
        runner.poll_n(std::time::Duration::from_millis(5), 100);
        runner.sync_and_update();
        assert!(
            runner
                .find(|_, element| {
                    Label::try_downcast(element).filter(|label| label.text.as_ref() == "Remote")
                })
                .is_some()
        );
        assert!(
            runner
                .find(|_, element| {
                    Label::try_downcast(element).filter(|label| label.text.as_ref() == "SSH")
                })
                .is_none()
        );
    }

    #[test]
    fn runtime_status_matches_host_versions_counts_and_update_rules() {
        let current = serde_json::json!({
            "runtimeHostVersion": env!("CARGO_PKG_VERSION"),
            "runtimeHostCommit": "unknown",
            "persistent": true,
            "activeSessions": 2,
            "activeAgents": 1,
        });
        let metrics = super::runtime_metrics(Some(&current), None);
        assert!(metrics.contains(&("Status".to_string(), "Running".to_string())));
        assert!(metrics.contains(&("Lifecycle".to_string(), "Persistent".to_string())));
        assert!(metrics.contains(&("Sessions".to_string(), "2".to_string())));
        assert!(metrics.contains(&("Agents".to_string(), "1".to_string())));
        assert!(!super::runtime_update_available(&current));

        let stale = serde_json::json!({
            "runtimeHostVersion": "999.0.0",
            "runtimeHostCommit": "unknown",
        });
        assert!(
            !super::runtime_update_available(&stale),
            "a newer running host must never be downgraded"
        );
        let older = serde_json::json!({
            "runtimeHostVersion": "0.0.1",
            "runtimeHostCommit": "unknown",
        });
        assert!(super::runtime_update_available(&older));
    }

    #[test]
    fn runtime_versions_compare_semver_cores_without_lexical_downgrades() {
        use std::cmp::Ordering;

        assert_eq!(
            super::compare_runtime_host_versions("v1.10.0", "1.9.9"),
            Ordering::Greater
        );
        assert_eq!(
            super::compare_runtime_host_versions("1.2.0-rc.1", "v1.2+build"),
            Ordering::Equal
        );
        assert_eq!(
            super::compare_runtime_host_versions("1", "1.0.0"),
            Ordering::Equal
        );
    }

    #[test]
    fn runtime_status_errors_retain_the_last_successful_snapshot() {
        let current = serde_json::json!({
            "runtimeHostVersion": "0.1.0",
            "activeSessions": 2,
        });
        let (snapshot, error) = super::merge_runtime_status(
            Some(current.clone()),
            Err("Runtime Host Is Stopped".to_string()),
        );
        assert_eq!(snapshot, Some(current));
        assert_eq!(error.as_deref(), Some("Runtime Host Is Stopped"));
    }

    #[test]
    fn force_stop_is_only_armed_for_runtime_busy_errors() {
        assert!(super::runtime_shutdown_is_busy(
            "Runtime host has 1 active agent(s), 0 active terminal session(s), 0 active background job(s), and 0 active push subscription(s). Retry with --force to stop it."
        ));
        assert!(!super::runtime_shutdown_is_busy(
            "Alera Runtime Is Unavailable."
        ));
        assert!(!super::runtime_shutdown_is_busy(
            "Permission denied. Retry with --force to continue."
        ));
    }

    #[test]
    fn runtime_start_config_uses_persisted_terminal_and_lifecycle_values() {
        let terminal = super::settings_terminal_state::StoredTerminalSettings {
            terminal_host_scrollback_bytes: 42_000_000,
            terminal_login_shell: false,
            ..Default::default()
        };
        let lifecycle = super::FreyaRuntimeHostSettings {
            host_empty_shutdown_delay_seconds: 45,
            host_detached_shutdown_delay_seconds: 7_200,
            crash_reporting_enabled: false,
        };
        let status = serde_json::json!({
            "diagnostics": {"crashReportingEnabled": true},
        });
        let config = super::runtime_host_config(&terminal, &lifecycle, Some(&status));
        assert_eq!(config.empty_shutdown_delay_seconds, 45);
        assert_eq!(config.detached_session_shutdown_delay_seconds, 7_200);
        assert_eq!(config.scrollback_bytes, 42_000_000);
        assert!(!config.login_shell);
        assert!(config.crash_reporting);
    }

    #[test]
    fn stopped_runtime_metrics_keep_versions_and_counts_visible() {
        let current = serde_json::json!({
            "runtimeHostVersion": "0.1.0",
            "activeSessions": 2,
            "activeAgents": 1,
        });
        let metrics = super::runtime_metrics(Some(&current), Some("host stopped"));
        assert!(metrics.contains(&("Status".to_string(), "Stopped".to_string())));
        assert!(metrics.contains(&("Host Version".to_string(), "v0.1.0".to_string())));
        assert!(metrics.contains(&("Sessions".to_string(), "2".to_string())));
        assert!(metrics.contains(&("Agents".to_string(), "1".to_string())));
    }

    #[test]
    fn runtime_build_labels_hide_unknown_and_shorten_known_commits() {
        assert_eq!(super::build_label(None), "-");
        assert_eq!(super::build_label(Some("unknown")), "-");
        assert_eq!(super::build_label(Some("1234567890abcdef")), "1234567");
        assert_eq!(super::version_label("0.1.0"), "v0.1.0");
        assert_eq!(super::version_label("v0.1.0"), "v0.1.0");
    }

    #[test]
    fn status_popover_pins_on_click_and_closes_outside() {
        let mut runner = launch_test(|| {
            let open = use_state(|| false);
            super::status_popover(
                "Resources",
                icons::lucide::activity(),
                "Resource Manager",
                vec![("Codex".to_string(), "97% available".to_string())],
                None,
                open,
                rect().child(label().text("Usage")).into(),
                None,
            )
        });
        runner.sync_and_update();
        let usage = runner
            .find(|node, element| {
                Label::try_downcast(element)
                    .filter(|label| label.text.as_ref() == "Usage")
                    .map(|_| node)
            })
            .expect("quota status button");
        runner.press_cursor(usage.layout().area.center().to_f64());
        runner.sync_and_update();
        assert!(
            runner
                .find(|_, element| {
                    Label::try_downcast(element)
                        .filter(|label| label.text.as_ref() == "Resource Manager")
                })
                .is_some()
        );
        runner.press_cursor(usage.layout().area.center().to_f64());
        runner.sync_and_update();
        assert!(
            runner
                .find(|_, element| {
                    Label::try_downcast(element)
                        .filter(|label| label.text.as_ref() == "Resource Manager")
                })
                .is_none(),
            "a second trigger click closes the pinned popover"
        );
        runner.poll_n(std::time::Duration::from_millis(10), 50);
        runner.sync_and_update();
        assert!(
            runner
                .find(|_, element| {
                    Label::try_downcast(element)
                        .filter(|label| label.text.as_ref() == "Resource Manager")
                })
                .is_none(),
            "the hover timer must not reopen a popover after its second-click close"
        );
        runner.press_cursor(usage.layout().area.center().to_f64());
        runner.sync_and_update();
        assert!(
            runner
                .find(|_, element| {
                    Label::try_downcast(element)
                        .filter(|label| label.text.as_ref() == "Resource Manager")
                })
                .is_some()
        );
        runner.move_cursor((490., 10.));
        runner.sync_and_update();
        runner.click_cursor((490., 10.));
        runner.sync_and_update();
        assert!(
            runner
                .find(|_, element| {
                    Label::try_downcast(element)
                        .filter(|label| label.text.as_ref() == "Resource Manager")
                })
                .is_none()
        );
    }

    #[test]
    fn status_popovers_keep_only_one_card_open() {
        let mut runner = launch_test(|| {
            let first_open = use_state(|| false);
            let second_open = use_state(|| false);
            let active = use_state(|| None::<String>);
            rect()
                .vertical()
                .child(super::status_popover(
                    "Runtime",
                    icons::lucide::gauge(),
                    "First Card",
                    Vec::new(),
                    None,
                    first_open,
                    rect().child(label().text("First Trigger")).into(),
                    Some(("first".to_string(), active)),
                ))
                .child(super::status_popover(
                    "Runtime",
                    icons::lucide::server(),
                    "Second Card",
                    Vec::new(),
                    None,
                    second_open,
                    rect().child(label().text("Second Trigger")).into(),
                    Some(("second".to_string(), active)),
                ))
        });
        runner.sync_and_update();
        let first = runner
            .find(|node, element| {
                Label::try_downcast(element)
                    .filter(|label| label.text.as_ref() == "First Trigger")
                    .map(|_| node)
            })
            .expect("first status trigger");
        runner.press_cursor(first.layout().area.center().to_f64());
        runner.sync_and_update();
        assert!(
            runner
                .find(|_, element| {
                    Label::try_downcast(element).filter(|label| label.text.as_ref() == "First Card")
                })
                .is_some()
        );

        let second = runner
            .find(|node, element| {
                Label::try_downcast(element)
                    .filter(|label| label.text.as_ref() == "Second Trigger")
                    .map(|_| node)
            })
            .expect("second status trigger");
        runner.press_cursor(second.layout().area.center().to_f64());
        runner.poll_n(std::time::Duration::from_millis(5), 20);
        runner.sync_and_update();
        assert!(
            runner
                .find(|_, element| {
                    Label::try_downcast(element).filter(|label| label.text.as_ref() == "First Card")
                })
                .is_none()
        );
        assert!(
            runner
                .find(|_, element| {
                    Label::try_downcast(element)
                        .filter(|label| label.text.as_ref() == "Second Card")
                })
                .is_some()
        );
    }

    #[test]
    fn provider_marks_cover_all_quota_providers_and_profiles() {
        for name in [
            "Claude Code",
            "Default",
            "leynierdev",
            "Codex",
            "Cursor",
            "Grok Build",
            "Kimi",
            "MiniMax",
            "Z.ai",
            "Antigravity",
        ] {
            assert!(
                super::provider_icon_for_name(name).is_some(),
                "missing provider mark for {name}"
            );
        }
        assert!(super::provider_icon_for_name("Status").is_none());
    }

    #[test]
    fn quota_overview_height_uses_the_flutter_row_density() {
        assert_eq!(super::quota_overview_panel_height(0, 0), 56.);
        assert_eq!(super::quota_overview_panel_height(9, 1), 198.);
        assert_eq!(super::quota_overview_panel_height(30, 0), 480.);
    }

    #[test]
    fn quota_readings_convert_used_percent_and_match_flutter_labels() {
        let antigravity = serde_json::json!({
            "provider": "antigravity",
            "buckets": [
                {"name": "Claude And GPT Models - Weekly", "usedPercent": 40.0},
                {"name": "Gemini Models - Weekly", "usedPercent": 25.0},
                {"name": "Gemini Models - 5 Hour", "usedPercent": 10.0}
            ]
        });
        assert_eq!(
            super::quota_readings(&antigravity),
            vec![
                ("G·5H".to_string(), 90.0),
                ("G·W".to_string(), 75.0),
                ("C/G·W".to_string(), 60.0),
            ]
        );

        let minimax = serde_json::json!({
            "provider": "minimax",
            "buckets": [
                {"name": "MiniMax-General Weekly", "usedPercent": 8.0},
                {"name": "MiniMax-M2.1 Weekly", "remainingPercent": 77.0}
            ]
        });
        assert_eq!(
            super::quota_readings(&minimax),
            vec![("G·W".to_string(), 92.0), ("M2.1·W".to_string(), 77.0)]
        );

        let zai = serde_json::json!({
            "provider": "zai",
            "buckets": [{"name": "MCP Weekly", "usedPercent": 12.0}]
        });
        assert_eq!(super::quota_readings(&zai), vec![("MCP".to_string(), 88.0)]);

        let codex = serde_json::json!({
            "provider": "codex",
            "rateLimitResetCredits": {
                "availableCount": 1,
                "nextExpiresAt": 4_102_444_800_000_i64,
                "offerRevision": "offer-1",
                "canConsume": true
            }
        });
        assert_eq!(
            super::codex_reset_offer(&codex),
            Some(super::CodexResetOffer {
                available_count: 1,
                next_expires_at: Some(4_102_444_800_000),
                offer_revision: "offer-1".to_string(),
                can_consume: true,
            })
        );
    }

    #[test]
    fn source_tree_rows_match_flutter_directory_order_and_depth() {
        let entry = |path: &str| super::GitChangeView {
            path: path.to_string(),
            old_path: None,
            area: "unstaged".to_string(),
            status: "Modified".to_string(),
            added: None,
            removed: None,
        };
        let rows =
            super::source_tree_rows(vec![entry("src/main.rs"), entry("src/ui/panel.rs")], true);

        assert!(matches!(
            &rows[0],
            super::SourceTreeRowView::Directory {
                path,
                depth: 0,
                file_count: 2,
                ..
            } if path == "src"
        ));
        assert!(matches!(
            &rows[1],
            super::SourceTreeRowView::File { change, depth: 1 }
                if change.path == "src/main.rs"
        ));
        assert!(matches!(
            &rows[2],
            super::SourceTreeRowView::Directory { path, depth: 1, .. }
                if path == "src/ui"
        ));
        assert_eq!(
            super::source_tree_ancestor_keys("unstaged", "src/ui/panel.rs"),
            ["unstaged:src", "unstaged:src/ui"]
        );
    }

    #[test]
    fn folder_projects_require_and_resolve_the_shared_source_control_root() {
        let record = serde_json::json!({
            "prefs": {
                "sourceControlRootByWorkspaceId": {
                    "workspace-1": "apps/web"
                }
            }
        });
        let scope = super::source_control_scope_from_prefs(
            "folder",
            "workspace-1",
            "/workspace",
            Some(&record),
        )
        .expect("shared root should enable source control");

        assert_eq!(scope.workspace_path, "/workspace");
        assert_eq!(scope.path, "/workspace/apps/web");
        assert_eq!(scope.relative_root.as_deref(), Some("apps/web"));
        assert!(
            super::source_control_scope_from_prefs(
                "folder",
                "workspace-2",
                "/workspace",
                Some(&record),
            )
            .is_none()
        );
    }

    #[test]
    fn pull_request_numbers_parse_from_numbers_hashes_and_urls() {
        assert_eq!(super::parse_pull_request_number("42"), Some(42));
        assert_eq!(super::parse_pull_request_number("#42"), Some(42));
        assert_eq!(
            super::parse_pull_request_number("https://github.com/openai/codex/pull/42/"),
            Some(42)
        );
        assert_eq!(super::parse_pull_request_number("#0"), None);
        assert_eq!(super::parse_pull_request_number("not-a-review"), None);
    }

    #[test]
    fn generated_pull_request_details_match_the_gpui_parser() {
        assert_eq!(
            super::parse_pull_request_details("Improve source control.\n\n- Add roots"),
            (
                "Improve source control".to_string(),
                "- Add roots".to_string()
            )
        );
        assert_eq!(
            super::parse_pull_request_details("Thinking...\nUpdate project\nDetails"),
            ("Update project".to_string(), "Details".to_string())
        );
        assert_eq!(
            super::parse_pull_request_details(""),
            ("Update Project".to_string(), String::new())
        );
    }

    #[test]
    fn pull_request_actions_follow_review_state() {
        assert_eq!(
            super::pull_request_action_options(true, "OPEN"),
            [
                super::PullRequestReviewAction::MarkReady,
                super::PullRequestReviewAction::Close,
                super::PullRequestReviewAction::Unlink,
            ]
        );
        assert_eq!(
            super::pull_request_action_options(false, "MERGED"),
            [super::PullRequestReviewAction::Unlink]
        );
    }

    #[test]
    fn pull_request_checks_use_the_same_status_groups_as_gpui() {
        let check = |bucket: &str| alera_desktop_core::ForgeCheck {
            name: "CI".to_string(),
            _state: bucket.to_string(),
            bucket: bucket.to_string(),
            link: None,
            description: None,
            workflow: None,
        };
        assert_eq!(super::forge_check_group(&check("failure")), "Failing");
        assert_eq!(
            super::forge_check_group(&check("in_progress")),
            "In Progress"
        );
        assert_eq!(super::forge_check_group(&check("success")), "Successful");
    }

    #[test]
    fn search_empty_state_never_invents_file_results() {
        let result = super::parse_workspace_search_view(&serde_json::json!({
            "files": [],
            "totalMatches": 0,
            "truncated": false,
        }))
        .expect("valid empty search response");

        assert!(result.files.is_empty());
        assert_eq!(result.total_matches, 0);
    }

    #[test]
    fn explorer_drag_accepts_only_other_non_descendant_directories() {
        assert!(super::explorer_can_drop("README.md", "docs"));
        assert!(super::explorer_can_drop("src/main.rs", "tests"));
        assert!(!super::explorer_can_drop("src", "src"));
        assert!(!super::explorer_can_drop("src", "src/widgets"));
        assert!(!super::explorer_can_drop("", "src"));
    }

    #[test]
    fn search_parser_preserves_locations_tokens_and_replacement_previews() {
        let result = super::parse_workspace_search_view(&serde_json::json!({
            "files": [{
                "relativePath": "src/main.rs",
                "contentToken": "token-1",
                "matches": [{
                    "id": "match-1",
                    "line": 7,
                    "column": 3,
                    "matchLength": 5,
                    "lineContent": "hello world",
                    "displayColumn": 2,
                    "displayMatchLength": 5,
                    "replacementPreview": "hola world"
                }]
            }],
            "totalMatches": 1,
            "truncated": false,
        }))
        .expect("valid search response");

        assert_eq!(result.files[0].content_token, "token-1");
        assert_eq!(result.files[0].matches[0].line, 7);
        assert_eq!(result.files[0].matches[0].column, 3);
        assert_eq!(result.files[0].matches[0].match_length, 5);
        assert_eq!(
            result.files[0].matches[0].replacement_preview.as_deref(),
            Some("hola world")
        );
    }

    #[test]
    fn search_line_preview_matches_flutter_character_ranges() {
        let item = super::WorkspaceSearchMatchView {
            id: "match-1".to_string(),
            line: 1,
            column: 3,
            match_length: 2,
            line_content: "á package  ".to_string(),
            display_column: Some(3),
            display_match_length: Some(7),
            replacement_preview: Some("crate".to_string()),
        };

        assert_eq!(
            super::workspace_search_line_preview(&item),
            super::WorkspaceSearchLinePreview {
                before: "á ".to_string(),
                matched: "package".to_string(),
                replacement: Some("crate".to_string()),
                after: String::new(),
            }
        );
    }

    #[test]
    fn search_tree_rows_match_flutter_directory_order_depth_and_collapse() {
        let search_match = |id: &str| super::WorkspaceSearchMatchView {
            id: id.to_string(),
            line: 1,
            column: 1,
            match_length: 1,
            line_content: id.to_string(),
            display_column: None,
            display_match_length: None,
            replacement_preview: None,
        };
        let file = |path: &str, ids: &[&str]| super::WorkspaceSearchFileView {
            relative_path: path.to_string(),
            content_token: format!("token:{path}"),
            matches: ids.iter().map(|id| search_match(id)).collect(),
        };
        let result = super::WorkspaceSearchView {
            files: vec![
                file("src/ui/panel.rs", &["panel"]),
                file("README.md", &["readme"]),
                file("src/main.rs", &["main-1", "main-2"]),
            ],
            total_matches: 4,
            truncated: false,
        };

        let rows = super::workspace_search_rows(&result, &std::collections::HashSet::new(), true);
        assert!(matches!(
            &rows[0],
            super::WorkspaceSearchRow::Directory {
                path,
                depth: 0,
                match_count: 3,
                ..
            } if path == "src"
        ));
        assert!(matches!(
            &rows[1],
            super::WorkspaceSearchRow::Directory { path, depth: 1, .. }
                if path == "src/ui"
        ));
        assert!(matches!(
            &rows[2],
            super::WorkspaceSearchRow::File { file, depth: 2, .. }
                if file.relative_path == "src/ui/panel.rs"
        ));
        assert!(matches!(
            &rows[4],
            super::WorkspaceSearchRow::File { file, depth: 1, .. }
                if file.relative_path == "src/main.rs"
        ));
        assert!(rows.iter().any(|row| matches!(
            row,
            super::WorkspaceSearchRow::File { file, depth: 0, .. }
                if file.relative_path == "README.md"
        )));

        let collapsed = std::collections::HashSet::from(["dir:src".to_string()]);
        let collapsed_rows = super::workspace_search_rows(&result, &collapsed, true);
        assert_eq!(collapsed_rows.len(), 3);
        let tree_keys = super::workspace_search_collapsible_keys(Some(&result), true);
        assert!(tree_keys.contains("dir:src"));
        assert!(tree_keys.contains("dir:src/ui"));
        assert!(tree_keys.contains("file:README.md"));
        let list_keys = super::workspace_search_collapsible_keys(Some(&result), false);
        assert!(list_keys.iter().all(|key| key.starts_with("file:")));
        assert_eq!(list_keys.len(), 3);
    }

    #[test]
    fn search_replace_feedback_reports_partial_and_full_conflicts() {
        let partial = super::workspace_search_replace_message(&serde_json::json!({
            "filesChanged": 1,
            "matchesReplaced": 2,
            "conflicts": [{
                "relativePath": "src/main.rs",
                "reason": "File changed on disk"
            }]
        }));
        assert_eq!(
            partial,
            "Replaced 2 Matches. 1 File Skipped. src/main.rs: File changed on disk"
        );

        let skipped = super::workspace_search_replace_message(&serde_json::json!({
            "filesChanged": 0,
            "matchesReplaced": 0,
            "conflicts": [
                {"relativePath": "a.txt", "reason": "Changed"},
                {"relativePath": "b.txt", "reason": "Missing"}
            ]
        }));
        assert_eq!(skipped, "Replace Skipped 2 Files. a.txt: Changed");
    }

    #[test]
    fn replace_all_requires_a_second_click_for_the_same_preview() {
        let candidate = ("hello".to_string(), "hola".to_string(), 4);
        assert!(super::workspace_search_requires_replace_confirmation(
            None, &candidate
        ));
        assert!(!super::workspace_search_requires_replace_confirmation(
            Some(&candidate),
            &candidate
        ));
        assert!(super::workspace_search_requires_replace_confirmation(
            Some(&("hello".to_string(), "bonjour".to_string(), 4)),
            &candidate
        ));
    }

    #[test]
    fn ai_text_runtime_patch_preserves_unedited_fields() {
        let settings = serde_json::json!({
            "aiTextGeneration": {
                "enabled": true,
                "agent": "claude",
                "customCommand": "existing",
                "timeoutSeconds": 600,
            }
        });
        let patched = super::merged_runtime_ai_text_setting(
            &settings,
            "enabled",
            serde_json::Value::Bool(false),
        );

        assert_eq!(patched["enabled"], false);
        assert_eq!(patched["agent"], "claude");
        assert_eq!(patched["customCommand"], "existing");
        assert_eq!(patched["timeoutSeconds"], 600);
    }

    #[test]
    fn sidebar_agent_presence_requires_the_matching_live_terminal_tab() {
        let presence = vec![
            serde_json::json!({
                "workspaceId": "workspace-1",
                "tabId": "tab-live",
                "terminalSessionId": "session-live",
                "agentType": "codex",
                "state": "working"
            }),
            serde_json::json!({
                "workspaceId": "workspace-1",
                "tabId": "tab-closed",
                "terminalSessionId": "session-closed",
                "agentType": "claude",
                "state": "done"
            }),
        ];
        let tabs = std::collections::HashMap::from([(
            "workspace-1".to_string(),
            vec![serde_json::json!({
                "id": "tab-live",
                "workspaceId": "workspace-1",
                "kind": "terminal",
                "payload": {"terminalSessionId": "session-live"}
            })],
        )]);

        let filtered = super::filter_live_sidebar_agent_presence(&presence, &tabs);

        assert_eq!(filtered.len(), 1);
        assert_eq!(filtered[0]["tabId"], "tab-live");
    }
}
