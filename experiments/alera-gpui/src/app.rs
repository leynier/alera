use std::cell::Cell;
use std::collections::{BTreeMap, BTreeSet, VecDeque};
use std::time::{Duration, Instant};

use gpui::{
    px, AppContext as _, Bounds, Context, Entity, FocusHandle, Pixels, Point, ScrollAnchor,
    ScrollHandle, SharedString, Subscription, Task, Timer, Window,
};
use gpui_component::input::{InputEvent, InputState};
use gpui_component::select::{SearchableVec, SelectEvent, SelectState};
use gpui_component::IndexPath;
use serde_json::Value;

mod add_project_dialog;
mod agent_profile_settings;
mod agent_profile_settings_actions;
mod agent_profile_settings_catalog;
mod agent_profile_settings_confirmation;
mod agent_profile_settings_controls;
mod agent_profile_settings_discovery;
mod agent_profile_settings_keyboard;
mod agent_profile_settings_persistence;
mod agent_profile_settings_render;
mod ai_text_settings_catalog;
mod app_helpers;
mod app_init;
mod app_lifecycle;
mod claude_profile_dialog;
mod context_pull_request;
mod context_pull_request_ai;
mod context_pull_request_composer;
mod context_pull_request_review_actions;
mod context_sidebar;
mod context_source_control;
mod context_source_control_actions;
mod context_source_control_ai;
mod context_source_control_dialog;
mod context_source_control_groups;
mod context_source_history;
mod dialogs;
mod editor_actions;
mod explorer_actions;
mod explorer_dialog;
mod explorer_menu;
mod forge_actions;
mod forge_surface;
mod git_diff_surface;
mod git_diff_tab_actions;
mod git_surface;
mod keyboard_actions;
mod keyboard_settings;
mod keyboard_settings_actions;
mod keyboard_settings_render;
mod mobile_access;
mod mobile_driver;
mod preview_surface;
mod project_actions;
mod project_config_settings;
mod run_policy;
mod run_policy_dialog;
mod search_surface;
mod search_surface_rows;
mod settings_actions;
mod settings_dialog;
mod settings_panes;
mod settings_search_catalog;
mod settings_select_option;
mod settings_state;
mod settings_store;
mod shell;
mod sidebar_actions;
mod sidebar_dialog;
mod sidebar_listing;
mod sidebar_rows;
mod sidebar_view_options;
mod sidebar_view_options_components;
mod sidebar_view_prefs;
mod sidebar_view_sort_menu;
mod source_control_scope;
mod source_history_graph;
mod state_types;
mod status_bar;
mod status_data;
mod status_quota;
mod status_quota_provider;
mod status_resource;
mod status_resource_actions;
mod status_resource_components;
mod status_resource_dialog;
mod status_runtime;
mod tab_actions;
mod tab_dialog;
mod tab_menus;
mod tab_strip;
mod terminal_input;
mod terminal_surface;
mod toast;
mod welcome_dashboard;
mod workbench;
mod workbench_layout;
mod workspace_actions;
mod workspace_manual_dialog;
mod workspace_manual_rows;
mod workspace_prompt_actions;
mod workspace_prompt_dropdown;
mod workspace_surface;

use crate::activity::{ContextPanel, SettingsPane, StatusPopover};
use crate::forge_service::{ForgeService, ForgeSnapshot};
use crate::model::WorkbenchSnapshot;
use crate::runtime_bridge::{BridgeEvent, RuntimeBridge};
use crate::terminal::{TerminalLink, TerminalSession};
use crate::workspace_git::{GitDiffResult, GitSnapshot};
use crate::workspace_service::{
    EditorDocument, ExplorerGitStatusSnapshot, SearchResults, WorkspaceService,
};
use agent_profile_settings::AgentProfileSettingsState;
use keyboard_settings::KeyboardSettingsUiState;
use mobile_access::MobileAccessState;
use project_config_settings::ProjectConfigSettingsState;
use run_policy::RunExecutionPolicy;
use settings_select_option::SettingsSelectOption;
use settings_state::SettingsState;
use settings_store::SettingsStore;
use state_types::*;
use status_data::StatusData;
use workspace_prompt_actions::PromptWorkspaceCreation;
use workspace_prompt_dropdown::{AgentProfileOption, WorkspacePromptDropdown};
use workspace_surface::{ExplorerRow, PreviewAsset};

pub(crate) use keyboard_actions::register as register_keyboard_actions;

pub struct AleraApp {
    bridge: RuntimeBridge,
    snapshot: WorkbenchSnapshot,
    selected_workspace_id: Option<String>,
    pending_workspace_terminal_id: Option<String>,
    selected_tab_id: Option<String>,
    tab_rename_input: Entity<InputState>,
    tab_rename_replace_pending: Option<String>,
    show_tab_rename_dialog: bool,
    tab_mutation_busy: bool,
    tab_close_armed: Option<Vec<String>>,
    workbench_menu: Option<WorkbenchMenu>,
    tab_drop_target: Option<TabDropTarget>,
    pane_drop_target: Option<PaneDropTarget>,
    tab_pointer_drag: Option<(String, String)>,
    tab_pointer_drag_generation: u64,
    tab_bar_bounds: BTreeMap<String, Bounds<Pixels>>,
    tab_chip_bounds: BTreeMap<(String, String), Bounds<Pixels>>,
    pane_bounds: BTreeMap<String, Bounds<Pixels>>,
    split_resize: Option<SplitResizeState>,
    panel_resize: Option<PanelResizeState>,
    resize_persist_generation: u64,
    connection_label: SharedString,
    error: Option<SharedString>,
    refresh_generation: u64,
    terminal_sessions: BTreeMap<String, TerminalSession>,
    terminal_drivers: BTreeMap<String, mobile_driver::MobileTerminalDriver>,
    terminal_driver_collapsed: BTreeSet<String>,
    terminal_driver_reclaiming: BTreeSet<String>,
    terminal_character_width: f32,
    terminal_surface_bounds: BTreeMap<String, Bounds<Pixels>>,
    terminal_resize_pending: BTreeMap<String, (usize, usize)>,
    terminal_resize_generation: BTreeMap<String, u64>,
    terminal_output_frame_scheduled: bool,
    terminal_focus: FocusHandle,
    terminal_selection_drag: Option<String>,
    terminal_marked_text: Option<String>,
    terminal_scrollbar_drag: Option<String>,
    terminal_scrollbar_last_activity: BTreeMap<String, Instant>,
    terminal_hovered_link: Option<(String, TerminalLink)>,
    terminal_restart_confirmation: Option<String>,
    terminal_cursor_visible: bool,
    terminal_cursor_last_activity: Instant,
    sidebar_collapsed: bool,
    sidebar_width: f32,
    panel_resize_hovered: Option<PanelResizeTarget>,
    collapsed_project_ids: BTreeSet<String>,
    sidebar_collapsed_parent_workspace_ids: BTreeSet<String>,
    sidebar_expanded_workspace_ids: BTreeSet<String>,
    sidebar_pinned_collapsed: bool,
    sidebar_all_collapsed: bool,
    show_sidebar_view_options: bool,
    sidebar_group_by: SidebarGroupBy,
    sidebar_project_sort: SidebarSortBy,
    sidebar_workspace_sort: SidebarSortBy,
    sidebar_selected_project_ids: BTreeSet<String>,
    sidebar_view_selected_tag_ids: BTreeSet<String>,
    sidebar_workspace_kind: SidebarWorkspaceKind,
    sidebar_repeat_pinned: bool,
    sidebar_sort_dropdown: Option<SidebarSortTarget>,
    sidebar_menu: Option<SidebarMenu>,
    sidebar_menu_position: Point<Pixels>,
    sidebar_dialog: Option<SidebarDialog>,
    sidebar_action_input: Entity<InputState>,
    sidebar_tag_input: Entity<InputState>,
    sidebar_parent_filter_input: Entity<InputState>,
    sidebar_action_busy: bool,
    sidebar_hovered_agent_run_id: Option<String>,
    sidebar_selected_tag_ids: BTreeSet<String>,
    sidebar_selected_parent_id: Option<String>,
    sidebar_tag_delete_armed: Option<String>,
    sidebar_parent_dropdown_open: bool,
    context_panel: ContextPanel,
    context_sidebar_collapsed: bool,
    context_sidebar_width: f32,
    workbench_view_prefs_raw: Value,
    status_popover: StatusPopover,
    status_popover_pinned: bool,
    status_popover_trigger_hovered: Option<StatusPopover>,
    status_popover_panel_hovered: bool,
    status_popover_hover_suppressed: Option<StatusPopover>,
    status_popover_transition_generation: u64,
    status_popover_anchor_x: f32,
    status_data: StatusData,
    /// Session-local acknowledgement of a completed agent run. Flutter keeps
    /// the warning dot until the tab is viewed, keyed by the run epoch.
    tab_completion_acknowledged: BTreeMap<String, String>,
    codex_reset_offer_revision: Option<String>,
    codex_reset_busy: bool,
    quota_tui_busy_key: Option<String>,
    resource_sort_column: String,
    resource_collapsed_project_ids: BTreeSet<String>,
    resource_close_confirmation: Option<ResourceCloseConfirmation>,
    show_settings_dialog: bool,
    settings_previous_focus: Option<FocusHandle>,
    settings_pane: SettingsPane,
    settings_scroll_handle: ScrollHandle,
    settings_scroll_last_offset: Cell<Pixels>,
    explorer_scroll_handle: ScrollHandle,
    settings_group_anchors: SettingsGroupAnchors,
    settings_state: SettingsState,
    diagnostics_export_busy: bool,
    settings_store: SettingsStore,
    keyboard_settings: KeyboardSettingsUiState,
    mobile_access: MobileAccessState,
    project_config_settings: ProjectConfigSettingsState,
    ai_model_discovery_busy: BTreeSet<String>,
    ai_model_discovery_errors: BTreeMap<String, SharedString>,
    ai_model_auto_discovered: BTreeSet<String>,
    workspace_service: WorkspaceService,
    explorer_rows: Vec<ExplorerRow>,
    explorer_loaded_workspace_id: Option<String>,
    explorer_expanded_paths: BTreeSet<String>,
    explorer_hide_ignored: bool,
    explorer_name_input: Entity<InputState>,
    explorer_create_directory: Option<bool>,
    explorer_create_parent: String,
    explorer_rename_path: Option<String>,
    explorer_delete_path: Option<String>,
    explorer_menu: Option<ExplorerMenuTarget>,
    explorer_menu_position: Point<Pixels>,
    explorer_selected_path: Option<String>,
    explorer_clipboard: Option<ExplorerClipboard>,
    explorer_drop_target: Option<String>,
    explorer_action_busy: bool,
    explorer_watch_generation: u64,
    editor_document: Option<EditorDocument>,
    editor_inputs: BTreeMap<String, Entity<InputState>>,
    editor_documents: BTreeMap<String, EditorDocument>,
    editor_load_error_paths: BTreeSet<String>,
    editor_error_messages: BTreeMap<String, SharedString>,
    editor_buffer_text: BTreeMap<String, String>,
    editor_dirty_paths: BTreeSet<String>,
    editor_cursor_positions: BTreeMap<String, (u32, u32)>,
    opened_file_path: Option<String>,
    editor_loading_path: Option<String>,
    pending_editor_cursor: Option<(String, usize, usize, usize)>,
    preview_asset: Option<PreviewAsset>,
    editor_preview_assets: BTreeMap<String, PreviewAsset>,
    preview_scale: f32,
    preview_offset: Point<Pixels>,
    preview_drag: Option<PreviewDragState>,
    show_preview: bool,
    sidebar_filter_input: Entity<InputState>,
    sidebar_project_filter_input: Entity<InputState>,
    sidebar_view_tag_filter_input: Entity<InputState>,
    local_project_path_input: Entity<InputState>,
    clone_project_url_input: Entity<InputState>,
    clone_project_destination_input: Entity<InputState>,
    project_display_name_input: Entity<InputState>,
    add_project_mode: AddProjectMode,
    show_add_project_dialog: bool,
    add_project_busy: bool,
    workspace_prompt_input: Entity<InputState>,
    workspace_dropdown_search_input: Entity<InputState>,
    workspace_project_search_input: Entity<InputState>,
    workspace_branch_search_input: Entity<InputState>,
    workspace_branch_input: Entity<InputState>,
    workspace_name_input: Entity<InputState>,
    settings_search_input: Entity<InputState>,
    workspace_directory_input: Entity<InputState>,
    editor_theme_search_input: Entity<InputState>,
    terminal_theme_search_input: Entity<InputState>,
    settings_inputs: BTreeMap<String, Entity<InputState>>,
    settings_selects: BTreeMap<String, Entity<SelectState<SearchableVec<SettingsSelectOption>>>>,
    skill_runners: BTreeMap<String, String>,
    claude_profile_alias_input: Entity<InputState>,
    claude_profile_name_input: Entity<InputState>,
    show_claude_profile_dialog: bool,
    editing_claude_profile_index: Option<usize>,
    claude_profile_error: Option<String>,
    new_workspace_mode: NewWorkspaceMode,
    new_workspace_step: NewWorkspaceStep,
    selected_workspace_project_id: Option<String>,
    selected_workspace_source_branch: Option<String>,
    workspace_source_branches: Vec<String>,
    workspace_local_branches: Vec<String>,
    workspace_branches_loading: bool,
    workspace_reuse_existing_branch: bool,
    workspace_synced_name: Option<String>,
    workspace_prompt_dropdown: Option<WorkspacePromptDropdown>,
    workspace_selected_parent_id: Option<String>,
    workspace_agent_profiles: Vec<AgentProfileOption>,
    workspace_selected_agent_profile_id: Option<String>,
    workspace_profiles_loading: bool,
    agent_profile_settings: AgentProfileSettingsState,
    create_another_workspace: bool,
    show_new_workspace_dialog: bool,
    workspace_creation_busy: bool,
    workspace_prompt_phase: Option<&'static str>,
    workspace_prompt_active_operation_id: Option<String>,
    workspace_prompt_created: Option<PromptWorkspaceCreation>,
    editor_input: Entity<InputState>,
    editor_input_syncing: bool,
    editor_dirty: bool,
    editor_conflict: bool,
    search_input: Entity<InputState>,
    replace_input: Entity<InputState>,
    search_include_input: Entity<InputState>,
    search_exclude_input: Entity<InputState>,
    search_replace_expanded: bool,
    search_details_expanded: bool,
    search_error_is_query_failure: bool,
    search_case_sensitive: bool,
    search_whole_word: bool,
    search_use_regex: bool,
    search_preserve_case: bool,
    search_include_ignored: bool,
    search_view_as_tree: bool,
    search_collapsed_result_paths: BTreeSet<String>,
    search_input_generation: u64,
    settings_search_generation: u64,
    commit_input: Entity<InputState>,
    source_amend_input: Entity<InputState>,
    source_control_filter_input: Entity<InputState>,
    source_control_filter_visible: bool,
    source_control_tree_mode: bool,
    source_control_menu_open: bool,
    source_control_collapsed_sections: BTreeSet<String>,
    source_control_collapsed_tree_nodes: BTreeSet<String>,
    forge_title_input: Entity<InputState>,
    forge_body_input: Entity<InputState>,
    forge_base_input: Entity<InputState>,
    forge_comment_input: Entity<InputState>,
    forge_link_input: Entity<InputState>,
    run_policy_reason_input: Entity<InputState>,
    show_execution_plans: bool,
    run_policies: Vec<RunExecutionPolicy>,
    run_policies_loading: bool,
    run_policy_busy_id: Option<String>,
    run_policy_error: Option<SharedString>,
    search_results: SearchResults,
    search_error: Option<SharedString>,
    replace_confirmation: Option<(String, String, u32)>,
    git_snapshot: GitSnapshot,
    explorer_git_status: ExplorerGitStatusSnapshot,
    git_snapshot_loading: bool,
    git_snapshot_error: Option<SharedString>,
    git_diff: GitDiffResult,
    git_diff_loading_tab: Option<String>,
    git_diff_loaded_tab: Option<String>,
    git_history_expanded: bool,
    git_history_height: f32,
    git_history_resize: Option<GitHistoryResizeState>,
    source_history_expanded_ids: BTreeSet<String>,
    source_history_loading_ids: BTreeSet<String>,
    source_history_action_menu: Option<context_source_history::SourceHistoryActionMenu>,
    source_history_files: BTreeMap<String, Vec<crate::workspace_git::GitCommitChange>>,
    source_control_dialog: Option<context_source_control_dialog::SourceControlDialog>,
    git_discard_armed: bool,
    git_discard_path_armed: Option<String>,
    source_commit_ai_operation_id: Option<String>,
    source_commit_ai_busy: bool,
    source_commit_ai_hovered: bool,
    forge_service: ForgeService,
    forge_snapshot: ForgeSnapshot,
    forge_generation: u64,
    forge_busy: bool,
    forge_ai_operation_id: Option<String>,
    forge_ai_busy: bool,
    forge_ai_hovered: bool,
    forge_review_action: Option<context_pull_request_review_actions::PullRequestReviewAction>,
    forge_review_action_menu_open: bool,
    forge_review_confirmation: Option<context_pull_request_review_actions::PullRequestConfirmation>,
    forge_review_editing: bool,
    forge_review_base_menu_open: bool,
    forge_comment_composing: bool,
    forge_expanded_checks: BTreeSet<String>,
    forge_collapsed_check_groups: BTreeSet<String>,
    forge_base_menu_open: bool,
    forge_create_menu_open: bool,
    forge_create_draft: bool,
    forge_link_form_open: bool,
    forge_form_error: Option<SharedString>,
    forge_error: Option<SharedString>,
    runtime_action_busy: bool,
    runtime_action_armed: Option<String>,
    runtime_restart_after_stop: bool,
    search_generation: u64,
    git_generation: u64,
    explorer_generation: u64,
    editor_generation: u64,
    search_busy: bool,
    search_replacing: bool,
    git_busy: bool,
    explorer_busy: bool,
    editor_busy: bool,
    local_message: Option<SharedString>,
    local_message_started_at: Option<Instant>,
    local_message_timer_message: Option<SharedString>,
    toast_entries: VecDeque<(SharedString, Instant)>,
    _subscriptions: Vec<Subscription>,
    _event_task: Task<()>,
    _cursor_blink_task: Task<()>,
}
