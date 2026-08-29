use std::cell::{Cell, RefCell};
use std::collections::{BTreeMap, BTreeSet, VecDeque};
use std::sync::atomic::AtomicBool;
use std::sync::Arc;
use std::time::{Duration, Instant};

use gpui::{
    px, AppContext as _, Bounds, Context, Entity, FocusHandle, ListAlignment, ListState, Pixels,
    Point, ScrollAnchor, ScrollHandle, SharedString, Subscription, Task, UniformListScrollHandle,
    Window,
};
use gpui_component::input::{EditorState, InputEvent, InputState, TextareaState};
use gpui_component::select::{SearchableVec, SelectEvent, SelectState};
use gpui_component::IndexPath;
use serde_json::Value;

mod add_project_dialog;
mod automations;
mod agent_canvas;
mod agent_profile_settings;
mod agent_profile_settings_actions;
mod agent_profile_settings_catalog;
mod agent_profile_settings_confirmation;
mod agent_profile_settings_controls;
mod agent_profile_settings_discovery;
mod agent_profile_settings_keyboard;
mod agent_profile_settings_persistence;
mod agent_profile_settings_removal;
mod agent_profile_record;
mod agent_profile_removal;
mod agent_profile_settings_render;
mod ai_text_settings_catalog;
mod app_helpers;
mod app_init;
mod app_lifecycle;
mod app_menu_dialog;
mod claude_profile_dialog;
mod command_terminal;
mod codex_surface;
mod context_pull_request;
mod context_pull_request_comments;
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
mod file_preview_tabs;
mod forge_actions;
mod forge_stack;
mod forge_stack_render;
mod forge_surface;
mod git_diff_surface;
mod git_diff_tab_actions;
mod git_surface;
mod keyboard_actions;
mod keyboard_settings;
mod keyboard_settings_actions;
mod keyboard_settings_render;
mod keep_alive;
mod markdown_preview_images;
mod mobile_access;
mod mobile_driver;
mod preview_surface;
mod project_actions;
mod project_config_settings;
mod reading_diff;
mod reading_diff_pull_request;
mod quick_open;
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
mod status_usage;
mod tab_actions;
mod tab_dialog;
mod tab_menus;
mod tab_strip;
mod terminal_composer;
mod terminal_input;
mod terminal_surface;
mod terminal_toolbar;
mod terminal_toolbar_menu;
mod terminal_pulse;
mod text_actions_execution;
mod text_actions_settings;
mod toast;
mod welcome_dashboard;
mod workbench;
mod workbench_layout;
mod workspace_actions;
mod workspace_manual_dialog;
mod workspace_manual_rows;
mod workspace_prompt_actions;
mod workspace_prompt_agent_launch;
mod workspace_prompt_dropdown;
mod workspace_surface;

use crate::activity::{ContextPanel, SettingsPane, StatusPopover};
use crate::forge_service::{ForgeService, ForgeSnapshot};
use crate::model::WorkbenchSnapshot;
use crate::reading_diff_service::{
    ReadingDiffProgress, ReadingDiffRequest, ReadingDiffResult, ReadingDiffService,
};
use crate::runtime_bridge::{BridgeEvent, RuntimeBridge};
use crate::terminal::{TerminalLink, TerminalSession};
use crate::workspace_git::{GitDiffResult, GitSnapshot};
use crate::workspace_service::{
    EditorDocument, ExplorerGitStatusSnapshot, SearchResults, WorkspaceService,
};
use agent_profile_settings::AgentProfileSettingsState;
use command_terminal::CommandTerminalState;
use keyboard_settings::KeyboardSettingsUiState;
use mobile_access::MobileAccessState;
use project_config_settings::ProjectConfigSettingsState;
use run_policy::RunExecutionPolicy;
use settings_select_option::SettingsSelectOption;
use settings_state::{SettingsState, TextActionSetting};
use settings_store::SettingsStore;
use state_types::*;
use status_data::StatusData;
use terminal_surface::TerminalFrameView;
use workspace_actions::PendingWorkspaceSetup;
use workspace_prompt_actions::PromptWorkspaceCreation;
use workspace_prompt_dropdown::{AgentProfileOption, WorkspacePromptDropdown};
use workspace_surface::{ExplorerRow, PreviewAsset};

pub(crate) use keyboard_actions::register as register_keyboard_actions;

pub struct AleraApp {
    bridge: RuntimeBridge,
    snapshot: WorkbenchSnapshot,
    selected_workspace_id: Option<String>,
    workspace_selection_initialized: bool,
    pending_workspace_terminal_id: Option<String>,
    pending_workspace_setup: Option<PendingWorkspaceSetup>,
    pending_workspace_tab_id: Option<String>,
    worktree_navigation_back: Vec<String>,
    worktree_navigation_forward: Vec<String>,
    worktree_navigation_replaying: bool,
    selected_tab_id: Option<String>,
    tab_rename_input: Entity<InputState>,
    tab_rename_replace_pending: Option<String>,
    show_tab_rename_dialog: bool,
    tab_mutation_busy: bool,
    file_preview_open_path: Option<String>,
    file_preview_keep_after_open: bool,
    git_preview_open_key: Option<String>,
    git_preview_keep_after_open: bool,
    git_preview_last_key: Option<String>,
    git_preview_last_at: Option<Instant>,
    tab_close_armed: Option<Vec<String>>,
    workbench_menu: Option<WorkbenchMenu>,
    workbench_menu_focus: FocusHandle,
    workbench_menu_previous_focus: Option<FocusHandle>,
    workbench_menu_highlighted: usize,
    tab_drop_target: Option<TabDropTarget>,
    pane_drop_target: Option<PaneDropTarget>,
    tab_pointer_drag: Option<(String, String)>,
    tab_pointer_drag_generation: u64,
    tab_bar_bounds: BTreeMap<String, Bounds<Pixels>>,
    tab_chip_bounds: BTreeMap<(String, String), Bounds<Pixels>>,
    tab_strip_scroll_handles: RefCell<BTreeMap<String, ScrollHandle>>,
    pane_bounds: BTreeMap<String, Bounds<Pixels>>,
    split_resize: Option<SplitResizeState>,
    panel_resize: Option<PanelResizeState>,
    resize_persist_generation: u64,
    connection_label: SharedString,
    error: Option<SharedString>,
    refresh_generation: u64,
    terminal_sessions: BTreeMap<String, TerminalSession>,
    terminal_frame_views: BTreeMap<String, Entity<TerminalFrameView>>,
    terminal_search_input: Entity<InputState>,
    terminal_search: Option<TerminalSearchState>,
    terminal_composer_inputs: BTreeMap<String, Entity<TextareaState>>,
    terminal_composer_visible: BTreeSet<String>,
    terminal_composer_menu_open: Option<String>,
    terminal_composer_attachments: BTreeMap<String, Vec<TerminalComposerAttachment>>,
    terminal_composer_attachment_counter: u64,
    terminal_pulse_dialog_session: Option<String>,
    terminal_pulse_command_input: Entity<InputState>,
    terminal_pulse_delay_input: Entity<InputState>,
    terminal_pulse_armed: bool,
    terminal_pulse_append_enter: bool,
    terminal_pulse_busy: bool,
    terminal_pulse_error: Option<SharedString>,
    terminal_pulse_generation: u64,
    codex_opening_tabs: BTreeSet<String>,
    codex_snapshots: BTreeMap<String, Value>,
    codex_thread_ids: BTreeMap<String, String>,
    codex_history_next_cursor: BTreeMap<String, String>,
    codex_history_loading: BTreeSet<String>,
    codex_recovery: BTreeMap<String, Value>,
    codex_sessions_supported: Option<bool>,
    codex_turn_policy_supported: Option<bool>,
    codex_capabilities_loading: bool,
    codex_session_action_busy: BTreeSet<String>,
    codex_resume_dialog_tab: Option<String>,
    codex_resume_threads: Vec<Value>,
    codex_resume_next_cursor: Option<String>,
    codex_resume_workspace_only: bool,
    codex_resume_loading: bool,
    codex_resume_error: Option<SharedString>,
    codex_resume_search_input: Entity<InputState>,
    codex_composer_inputs: BTreeMap<String, Entity<TextareaState>>,
    codex_attachments: BTreeMap<String, Vec<String>>,
    codex_prompt_history: BTreeMap<String, Vec<String>>,
    codex_prompt_history_index: BTreeMap<String, usize>,
    codex_scroll_handle: ScrollHandle,
    codex_scroll_follow: bool,
    codex_working_collapsed: bool,
    codex_selected_model: Option<String>,
    codex_models: Vec<Value>,
    codex_collaboration_modes: Vec<Value>,
    codex_skills: Vec<Value>,
    codex_apps: Vec<Value>,
    codex_saved_prompts: Vec<alera_native::api::workspace_files::CodexSavedPrompt>,
    codex_saved_prompts_loading: bool,
    codex_saved_prompts_workspace: Option<String>,
    codex_catalogs_loaded: bool,
    codex_catalogs_loading: bool,
    codex_error: Option<SharedString>,
    codex_menu_open: Option<String>,
    codex_raw_logs: bool,
    codex_reasoning_effort: String,
    codex_speed_mode: String,
    codex_permission_mode: String,
    codex_plan_mode: bool,
    codex_collaboration_mode: Option<String>,
    codex_queued_messages: BTreeMap<String, Vec<String>>,
    codex_collapsed_cells: BTreeSet<String>,
    agent_canvas_loading: bool,
    agent_canvas_error: Option<SharedString>,
    agent_canvas_capabilities: Option<Value>,
    agent_canvas_values: Vec<Value>,
    agent_canvas_selected_id: Option<String>,
    agent_canvas_show_history: bool,
    agent_canvas_busy: bool,
    quick_open_input: Entity<InputState>,
    quick_open_open: bool,
    quick_open_loading: bool,
    quick_open_error: Option<SharedString>,
    quick_open_session: Option<alera_native::api::workspace_files::WorkspaceQuickOpenSession>,
    quick_open_matches: Vec<alera_native::api::workspace_files::WorkspaceQuickOpenMatch>,
    quick_open_selected_index: usize,
    quick_open_generation: u64,
    command_palette_input: Entity<InputState>,
    command_palette_open: bool,
    command_palette_selected_index: usize,
    command_terminal: Option<CommandTerminalState>,
    terminal_output_dirty_sessions: BTreeSet<String>,
    terminal_drivers: BTreeMap<String, mobile_driver::MobileTerminalDriver>,
    terminal_driver_collapsed: BTreeSet<String>,
    terminal_driver_reclaiming: BTreeSet<String>,
    terminal_character_width: f32,
    terminal_surface_bounds: BTreeMap<String, Bounds<Pixels>>,
    terminal_toolbar_viewport_bounds: BTreeMap<String, Bounds<Pixels>>,
    terminal_toolbar_drag: Option<terminal_toolbar::TerminalToolbarDrag>,
    terminal_toolbar_menu: Option<terminal_toolbar::TerminalToolbarMenu>,
    terminal_resize_pending: BTreeMap<String, (usize, usize)>,
    terminal_resize_generation: BTreeMap<String, u64>,
    terminal_output_frame_scheduled: bool,
    terminal_output_last_frame_at: Instant,
    terminal_app_foreground: bool,
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
    collapsed_sidebar_focus: FocusHandle,
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
    sidebar_active_only: bool,
    sidebar_repeat_pinned: bool,
    sidebar_sort_dropdown: Option<SidebarSortTarget>,
    sidebar_menu: Option<SidebarMenu>,
    sidebar_menu_position: Point<Pixels>,
    sidebar_dialog: Option<SidebarDialog>,
    sidebar_storage_impact: Option<WorkspaceStorageImpact>,
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
    keep_alive_active: bool,
    keep_alive_error: Option<SharedString>,
    keep_alive_busy: bool,
    keep_alive_generation: u64,
    /// Session-local acknowledgement of a completed agent run. Flutter keeps
    /// the warning dot until the tab is viewed, keyed by the run epoch.
    tab_completion_acknowledged: BTreeMap<String, String>,
    codex_reset_offer_revision: Option<String>,
    codex_reset_busy: bool,
    quota_tui_busy_key: Option<String>,
    show_agent_usage_dialog: bool,
    agent_usage_days: u32,
    agent_usage_loading: bool,
    agent_usage_error: Option<SharedString>,
    agent_usage_snapshot: Option<Value>,
    agent_usage_cache: BTreeMap<String, Value>,
    agent_usage_generation: u64,
    agent_usage_breakdown_mode: status_usage::UsageBreakdownMode,
    resource_sort_column: String,
    resource_collapsed_project_ids: BTreeSet<String>,
    resource_close_confirmation: Option<ResourceCloseConfirmation>,
    show_settings_dialog: bool,
    show_about_dialog: bool,
    settings_previous_focus: Option<FocusHandle>,
    settings_pane: SettingsPane,
    settings_project_master_width: f32,
    settings_agent_profiles_master_width: f32,
    settings_text_actions_master_width: f32,
    settings_master_resize: Option<SettingsMasterResizeState>,
    settings_scroll_handle: ScrollHandle,
    settings_scroll_last_offset: Cell<Pixels>,
    sidebar_scroll_handle: ScrollHandle,
    explorer_scroll_handle: UniformListScrollHandle,
    settings_group_anchors: SettingsGroupAnchors,
    settings_state: SettingsState,
    text_actions_selected_id: Option<String>,
    text_actions_creating_new: bool,
    text_actions_name_input: Entity<InputState>,
    text_actions_prompt_input: Entity<TextareaState>,
    text_actions_agent_input: Entity<InputState>,
    text_actions_model_input: Entity<InputState>,
    text_actions_reasoning_input: Entity<InputState>,
    text_actions_error: Option<SharedString>,
    text_action_operation_id: Option<String>,
    text_action_pending: Option<TextActionPending>,
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
    explorer_menu_focus: FocusHandle,
    explorer_menu_previous_focus: Option<FocusHandle>,
    explorer_selected_path: Option<String>,
    explorer_clipboard: Option<ExplorerClipboard>,
    explorer_drop_target: Option<String>,
    explorer_pointer_down: Option<String>,
    explorer_pointer_dragged: bool,
    explorer_pointer_double_clicked: bool,
    explorer_action_busy: bool,
    explorer_watch_generation: u64,
    editor_document: Option<EditorDocument>,
    editor_inputs: BTreeMap<String, Entity<EditorState>>,
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
    markdown_preview_content: BTreeMap<String, String>,
    preview_transforms: BTreeMap<String, PreviewTransform>,
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
    workspace_prompt_input: Entity<TextareaState>,
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
    settings_textareas: BTreeMap<String, Entity<TextareaState>>,
    settings_selects: BTreeMap<String, Entity<SelectState<SearchableVec<SettingsSelectOption>>>>,
    skill_runners: BTreeMap<String, String>,
    claude_profile_alias_input: Entity<InputState>,
    claude_profile_name_input: Entity<InputState>,
    claude_profile_usage_name_input: Entity<InputState>,
    show_claude_profile_dialog: bool,
    editing_claude_profile_index: Option<usize>,
    claude_profile_show_in_usage: bool,
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
    workspace_prompt_agent_launch_mutation_id: Option<String>,
    workspace_prompt_original_agent_launch_idempotent: Option<bool>,
    editor_input: Entity<EditorState>,
    editor_input_syncing: bool,
    editor_dirty: bool,
    editor_conflict: bool,
    editor_autosave_generation: u64,
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
    search_list_state: ListState,
    search_input_generation: u64,
    search_active_request_id: Option<String>,
    settings_search_generation: u64,
    commit_input: Entity<TextareaState>,
    source_amend_input: Entity<TextareaState>,
    source_control_filter_input: Entity<InputState>,
    source_control_filter_visible: bool,
    source_control_tree_mode: bool,
    source_control_group_mode: bool,
    source_control_menu_open: bool,
    source_control_menu_focus: FocusHandle,
    source_control_menu_previous_focus: Option<FocusHandle>,
    source_control_menu_highlighted: usize,
    source_control_collapsed_sections: BTreeSet<String>,
    source_control_collapsed_tree_nodes: BTreeSet<String>,
    forge_title_input: Entity<InputState>,
    forge_body_input: Entity<TextareaState>,
    forge_base_input: Entity<InputState>,
    forge_comment_input: Entity<TextareaState>,
    forge_link_input: Entity<InputState>,
    run_policy_reason_input: Entity<InputState>,
    show_execution_plans: bool,
    show_automations_dialog: bool,
    automations: Vec<Value>,
    automations_loading: bool,
    automations_error: Option<SharedString>,
    automation_selected_id: Option<String>,
    automation_detail: Option<Value>,
    automation_detail_loading: bool,
    automation_search_input: Entity<InputState>,
    automation_state_filter: Option<String>,
    automation_include_trashed: bool,
    automation_action_busy: bool,
    automation_editor_open: bool,
    automation_editor_id: Option<String>,
    automation_editor_name_input: Entity<InputState>,
    automation_editor_slug_input: Entity<InputState>,
    automation_editor_description_input: Entity<InputState>,
    automation_editor_prompt_input: Entity<TextareaState>,
    automation_editor_cron_input: Entity<InputState>,
    automation_editor_workspace_input: Entity<InputState>,
    automation_editor_profile_input: Entity<InputState>,
    automation_editor_error: Option<SharedString>,
    automation_settings_loading: bool,
    automation_settings_saving: bool,
    automation_settings_loaded: bool,
    automation_settings_error: Option<SharedString>,
    automation_profile_policy_id: Option<String>,
    automation_profile_policy_loading: bool,
    automation_profile_policy_error: Option<SharedString>,
    automation_profile_policy_activate: bool,
    automation_profile_policy_execute: bool,
    automation_project_policy_id: Option<String>,
    automation_project_policy_loading: bool,
    automation_project_policy_error: Option<SharedString>,
    automation_project_policy_local_approved: bool,
    automation_project_policy_restrictive: bool,
    automation_project_policy_repo_declared: bool,
    run_policies: Vec<RunExecutionPolicy>,
    run_policies_loading: bool,
    run_policy_busy_id: Option<String>,
    run_policy_error: Option<SharedString>,
    search_results: SearchResults,
    search_error: Option<SharedString>,
    git_snapshot: GitSnapshot,
    explorer_git_status: ExplorerGitStatusSnapshot,
    git_snapshot_loading: bool,
    git_snapshot_error: Option<SharedString>,
    git_diff: GitDiffResult,
    git_diff_loading_tab: Option<String>,
    git_diff_loaded_tab: Option<String>,
    git_diff_errors: BTreeMap<String, SharedString>,
    git_diff_image_sides: BTreeMap<(String, String), git_diff_surface::GitDiffImageSides>,
    git_diff_image_loading: BTreeSet<(String, String)>,
    reading_diff_service: ReadingDiffService,
    reading_diff_confirmation: Option<ReadingDiffRequest>,
    reading_diff_busy_key: Option<String>,
    reading_diff_progress: Option<ReadingDiffProgress>,
    reading_diff_results: BTreeMap<String, ReadingDiffResult>,
    reading_diff_errors: BTreeMap<String, SharedString>,
    reading_diff_show_original: BTreeSet<String>,
    reading_diff_cancel: Option<Arc<AtomicBool>>,
    git_history_expanded: bool,
    git_history_loaded_once: bool,
    git_history_height: f32,
    git_history_resize: Option<GitHistoryResizeState>,
    source_history_expanded_ids: BTreeSet<String>,
    source_history_loading_ids: BTreeSet<String>,
    source_history_action_menu: Option<context_source_history::SourceHistoryActionMenu>,
    source_history_menu_focus: FocusHandle,
    source_history_menu_previous_focus: Option<FocusHandle>,
    source_history_menu_highlighted: usize,
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
    forge_stack_editing: bool,
    forge_stack_workspace_editing: bool,
    forge_stack_selected_workspace_ids: BTreeSet<String>,
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
    forge_comment_saving_ids: BTreeSet<String>,
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
