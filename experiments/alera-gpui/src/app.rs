use gpui::{
    AppContext as _, Context, Entity, FocusHandle, SharedString, Subscription, Task, Window,
};
use gpui_component::input::{InputEvent, InputState};
use serde_json::Value;

mod ai_text_surface;
mod forge_actions;
mod forge_surface;
mod git_surface;
mod preview_surface;
mod runtime_actions;
mod runtime_features;
mod search_surface;
mod shell;
mod terminal_surface;
mod workbench;
mod workspace_surface;

use crate::activity::Activity;
use crate::forge_service::{ForgeService, ForgeSnapshot};
use crate::model::WorkbenchSnapshot;
use crate::runtime_bridge::{BridgeEvent, RuntimeBridge};
use crate::terminal::TerminalSession;
use crate::workspace_git::GitSnapshot;
use crate::workspace_service::{EditorDocument, SearchResults, WorkspaceService};
use runtime_features::RuntimeFeatureState;
use workspace_surface::{ExplorerRow, PreviewAsset};

pub struct AleraApp {
    bridge: RuntimeBridge,
    snapshot: WorkbenchSnapshot,
    selected_workspace_id: Option<String>,
    selected_tab_id: Option<String>,
    connection_label: SharedString,
    error: Option<SharedString>,
    refresh_generation: u64,
    terminal_generation: u64,
    terminal_session: Option<TerminalSession>,
    terminal_focus: FocusHandle,
    activity: Activity,
    runtime_feature: RuntimeFeatureState,
    workspace_service: WorkspaceService,
    explorer_rows: Vec<ExplorerRow>,
    editor_document: Option<EditorDocument>,
    opened_file_path: Option<String>,
    preview_asset: Option<PreviewAsset>,
    show_preview: bool,
    editor_input: Entity<InputState>,
    editor_dirty: bool,
    search_input: Entity<InputState>,
    replace_input: Entity<InputState>,
    commit_input: Entity<InputState>,
    forge_title_input: Entity<InputState>,
    forge_body_input: Entity<InputState>,
    forge_base_input: Entity<InputState>,
    forge_comment_input: Entity<InputState>,
    ai_prompt_input: Entity<InputState>,
    runtime_verb_input: Entity<InputState>,
    runtime_payload_input: Entity<InputState>,
    search_results: SearchResults,
    replace_confirmation: Option<(String, String, u32)>,
    git_snapshot: GitSnapshot,
    git_discard_armed: bool,
    git_discard_path_armed: Option<String>,
    forge_service: ForgeService,
    forge_snapshot: ForgeSnapshot,
    forge_generation: u64,
    forge_busy: bool,
    forge_danger_armed: Option<String>,
    ai_generation: Option<Value>,
    ai_operation_id: Option<String>,
    ai_busy: bool,
    runtime_action_output: Option<Value>,
    runtime_action_busy: bool,
    runtime_action_armed: Option<String>,
    local_generation: u64,
    local_busy: bool,
    local_message: Option<SharedString>,
    _subscriptions: Vec<Subscription>,
    _event_task: Task<()>,
}

impl AleraApp {
    pub fn new(bridge: RuntimeBridge, window: &mut Window, cx: &mut Context<Self>) -> Self {
        let events = bridge.events();
        let event_task = cx.spawn(async move |this, cx| {
            while let Ok(event) = events.recv().await {
                let Some(this) = this.upgrade() else {
                    break;
                };
                let should_refresh = match &event {
                    BridgeEvent::Connected => true,
                    BridgeEvent::Notification { name, .. } => is_snapshot_event(name),
                    _ => false,
                };
                let _ = this.update(cx, |this, cx| {
                    match event {
                        BridgeEvent::Connected => {
                            this.connection_label = "Runtime Connected".into();
                            this.error = None;
                        }
                        BridgeEvent::Unavailable => {
                            this.connection_label = "Runtime Unavailable".into();
                        }
                        BridgeEvent::Disconnected { reason } => {
                            this.connection_label = "Runtime Reconnecting".into();
                            this.error = Some(reason.into());
                        }
                        BridgeEvent::Notification { name, payload } => {
                            this.handle_terminal_notification(&name, &payload, cx);
                        }
                        BridgeEvent::TerminalOutput { session_id, data } => {
                            this.handle_terminal_output(&session_id, &data, cx);
                        }
                    }
                    if should_refresh {
                        this.refresh(cx);
                    }
                    cx.notify();
                });
            }
        });
        let terminal_focus = cx.focus_handle();
        let editor_input = cx.new(|cx| {
            InputState::new(window, cx)
                .code_editor("text")
                .soft_wrap(false)
        });
        let search_input = cx.new(|cx| InputState::new(window, cx).placeholder("Search Workspace"));
        let replace_input = cx.new(|cx| InputState::new(window, cx).placeholder("Replace With"));
        let commit_input = cx.new(|cx| InputState::new(window, cx).placeholder("Commit Message"));
        let forge_title_input =
            cx.new(|cx| InputState::new(window, cx).placeholder("Pull Request Title"));
        let forge_body_input = cx.new(|cx| {
            InputState::new(window, cx)
                .placeholder("Pull Request Description")
                .multi_line(true)
                .soft_wrap(true)
        });
        let forge_base_input = cx.new(|cx| InputState::new(window, cx).placeholder("Base Branch"));
        let forge_comment_input =
            cx.new(|cx| InputState::new(window, cx).placeholder("Add A Comment"));
        let ai_prompt_input = cx.new(|cx| {
            InputState::new(window, cx)
                .placeholder("Describe The Workspace Identity To Generate")
                .multi_line(true)
                .soft_wrap(true)
        });
        let runtime_verb_input =
            cx.new(|cx| InputState::new(window, cx).placeholder("Runtime Verb"));
        let runtime_payload_input = cx.new(|cx| {
            InputState::new(window, cx)
                .placeholder("JSON Object Payload")
                .multi_line(true)
                .soft_wrap(true)
        });
        let subscriptions = vec![cx.subscribe_in(
            &editor_input,
            window,
            |this, _, event: &InputEvent, _, cx| {
                if matches!(event, InputEvent::Change) && this.editor_document.is_some() {
                    this.editor_dirty = true;
                    cx.notify();
                }
            },
        )];
        let mut app = Self {
            bridge,
            snapshot: WorkbenchSnapshot::default(),
            selected_workspace_id: None,
            selected_tab_id: None,
            connection_label: "Runtime Connecting".into(),
            error: None,
            refresh_generation: 0,
            terminal_generation: 0,
            terminal_session: None,
            terminal_focus,
            activity: Activity::Workbench,
            runtime_feature: RuntimeFeatureState::default(),
            workspace_service: WorkspaceService::start(),
            explorer_rows: Vec::new(),
            editor_document: None,
            opened_file_path: None,
            preview_asset: None,
            show_preview: false,
            editor_input,
            editor_dirty: false,
            search_input,
            replace_input,
            commit_input,
            forge_title_input,
            forge_body_input,
            forge_base_input,
            forge_comment_input,
            ai_prompt_input,
            runtime_verb_input,
            runtime_payload_input,
            search_results: SearchResults::default(),
            replace_confirmation: None,
            git_snapshot: GitSnapshot::default(),
            git_discard_armed: false,
            git_discard_path_armed: None,
            forge_service: ForgeService::start(),
            forge_snapshot: ForgeSnapshot::default(),
            forge_generation: 0,
            forge_busy: false,
            forge_danger_armed: None,
            ai_generation: None,
            ai_operation_id: None,
            ai_busy: false,
            runtime_action_output: None,
            runtime_action_busy: false,
            runtime_action_armed: None,
            local_generation: 0,
            local_busy: false,
            local_message: None,
            _subscriptions: subscriptions,
            _event_task: event_task,
        };
        app.refresh(cx);
        app
    }

    fn refresh(&mut self, cx: &mut Context<Self>) {
        self.refresh_generation += 1;
        let generation = self.refresh_generation;
        let bridge = self.bridge.clone();
        let selected_workspace_id = self.selected_workspace_id.clone();
        cx.spawn(async move |this, cx| {
            let snapshot = WorkbenchSnapshot::load(&bridge, selected_workspace_id.as_deref()).await;
            let Some(this) = this.upgrade() else {
                return;
            };
            let _ = this.update(cx, |this, cx| {
                if generation != this.refresh_generation {
                    return;
                }
                match snapshot {
                    Ok(mut snapshot) => {
                        let next_workspace_id = this
                            .selected_workspace_id
                            .clone()
                            .filter(|id| snapshot.workspace(id).is_some())
                            .or_else(|| snapshot.first_workspace_id().map(str::to_string));
                        if this.selected_workspace_id != next_workspace_id {
                            this.selected_workspace_id = next_workspace_id;
                            this.selected_tab_id = None;
                            this.snapshot = snapshot;
                            this.refresh(cx);
                            return;
                        }
                        this.selected_tab_id = this
                            .selected_tab_id
                            .clone()
                            .filter(|id| snapshot.tabs.iter().any(|tab| &tab.id == id))
                            .or_else(|| snapshot.tabs.first().map(|tab| tab.id.clone()));
                        this.error = None;
                        snapshot.projects.sort_by(|a, b| a.name.cmp(&b.name));
                        this.snapshot = snapshot;
                        this.ensure_selected_terminal(cx);
                    }
                    Err(error) => this.error = Some(error.into()),
                }
                cx.notify();
            });
        })
        .detach();
    }

    pub(super) fn select_workspace(&mut self, workspace_id: String, cx: &mut Context<Self>) {
        if self.selected_workspace_id.as_deref() == Some(&workspace_id) {
            return;
        }
        self.selected_workspace_id = Some(workspace_id);
        self.selected_tab_id = None;
        self.ensure_selected_terminal(cx);
        self.reset_local_workspace(cx);
        self.refresh(cx);
        cx.notify();
    }

    pub(super) fn select_activity(&mut self, activity: Activity, cx: &mut Context<Self>) {
        if self.activity == activity {
            if activity.uses_runtime_catalog() {
                self.refresh_runtime_feature(cx);
            }
            return;
        }
        self.activity = activity;
        if activity.uses_runtime_catalog() {
            self.refresh_runtime_feature(cx);
        } else {
            self.refresh_local_activity(cx);
        }
        cx.notify();
    }
}

fn is_snapshot_event(name: &str) -> bool {
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
