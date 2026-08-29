use std::time::Duration;

use gpui::{
    div, prelude::FluentBuilder as _, px, AnyElement, AppContext as _, Context, CursorStyle,
    Entity, InteractiveElement as _, IntoElement, KeyDownEvent, MouseButton,
    ParentElement as _, Role, SharedString, StatefulInteractiveElement as _, Styled as _, Window,
};
use gpui_component::input::{Input, InputEvent, Textarea, TextareaState};
use gpui_component::scroll::ScrollableElement as _;
use gpui_component::text::TextView;
use serde_json::{json, Value};

use super::AleraApp;
use crate::design_system::{self, ButtonKind};
use crate::icons::{icon, loading_indicator, AleraIcon};
use crate::model::WorkspaceTab;
use crate::theme;
use super::markdown_preview_images::with_markdown_images;

const CODEX_TAB_KIND: &str = "codex";

impl AleraApp {
    pub(super) fn ensure_codex_state(&mut self, window: &mut Window, cx: &mut Context<Self>) {
        let codex_tabs = self
            .snapshot
            .tabs
            .iter()
            .filter(|tab| tab.kind == CODEX_TAB_KIND)
            .map(|tab| tab.id.clone())
            .collect::<std::collections::BTreeSet<_>>();
        self.codex_opening_tabs
            .retain(|tab_id| codex_tabs.contains(tab_id));
        self.codex_snapshots.retain(|tab_id, _| codex_tabs.contains(tab_id));
        self.codex_thread_ids
            .retain(|tab_id, _| codex_tabs.contains(tab_id));
        self.codex_recovery
            .retain(|tab_id, _| codex_tabs.contains(tab_id));
        self.codex_composer_inputs
            .retain(|tab_id, _| codex_tabs.contains(tab_id));
        self.codex_queued_messages
            .retain(|tab_id, _| codex_tabs.contains(tab_id));
        for tab in self
            .snapshot
            .tabs
            .iter()
            .filter(|tab| tab.kind == CODEX_TAB_KIND)
        {
            if let Some(snapshot) = tab.payload.get("codexSnapshot") {
                if snapshot.is_object() {
                    self.codex_snapshots
                        .entry(tab.id.clone())
                        .or_insert_with(|| snapshot.clone());
                }
            }
            if !self.codex_composer_inputs.contains_key(&tab.id) {
                let tab_id = tab.id.clone();
                let input = cx.new(|cx| {
                    TextareaState::new(window, cx)
                        .placeholder("Message Codex")
                        .auto_grow(1, 6)
                        .soft_wrap(true)
                });
                self._subscriptions.push(cx.subscribe_in(
                    &input,
                    window,
                    move |_, _, event: &InputEvent, _, cx| {
                        if matches!(event, InputEvent::Change) {
                            let _ = &tab_id;
                            cx.notify();
                        }
                    },
                ));
                self.codex_composer_inputs.insert(tab.id.clone(), input);
            }
        }
        let selected_codex = self
            .selected_tab_id
            .as_deref()
            .and_then(|id| self.snapshot.tabs.iter().find(|tab| tab.id == id))
            .filter(|tab| tab.kind == CODEX_TAB_KIND)
            .map(|tab| tab.id.clone());
        if let Some(tab_id) = selected_codex {
            if self.codex_sessions_supported.is_none() && !self.codex_capabilities_loading {
                self.load_codex_capabilities(cx);
            }
            if !self.codex_snapshots.contains_key(&tab_id)
                && !self.codex_opening_tabs.contains(&tab_id)
            {
                self.open_codex_thread(tab_id.clone(), cx);
            }
            if !self.codex_catalogs_loaded && !self.codex_catalogs_loading {
                self.load_codex_catalogs(&tab_id, cx);
            }
            if let Some(path) = self
                .snapshot
                .tabs
                .iter()
                .find(|tab| tab.id == tab_id)
                .and_then(|tab| self.snapshot.workspace(&tab.workspace_id))
                .map(|workspace| workspace.path.clone())
            {
                if self.codex_saved_prompts_workspace.as_deref() != Some(path.as_str())
                    && !self.codex_saved_prompts_loading
                {
                    self.load_codex_saved_prompts(path, cx);
                }
            }
        }
    }

    fn load_codex_capabilities(&mut self, cx: &mut Context<Self>) {
        self.codex_capabilities_loading = true;
        let bridge = self.bridge.clone();
        cx.spawn(async move |this, cx| {
            let result = bridge.request("status.get", json!({})).await;
            let _ = this.update(cx, |this, cx| {
                this.codex_capabilities_loading = false;
                let capabilities = result
                    .ok()
                    .and_then(|value| value.get("runtimeCapabilities").cloned())
                    .and_then(|value| value.as_array().cloned())
                    .unwrap_or_default();
                this.codex_sessions_supported = Some(capabilities.iter().any(|value| {
                    value.as_str() == Some("codexSessionsV1")
                }));
                this.codex_turn_policy_supported = Some(capabilities.iter().any(|value| {
                    value.as_str() == Some("codexTurnPolicyV2")
                }));
                cx.notify();
            });
        })
        .detach();
    }

    fn load_codex_saved_prompts(&mut self, workspace_path: String, cx: &mut Context<Self>) {
        self.codex_saved_prompts_loading = true;
        self.codex_saved_prompts_workspace = Some(workspace_path.clone());
        let task = cx.background_executor().spawn(async move {
            alera_native::api::workspace_files::list_codex_saved_prompts(workspace_path)
        });
        cx.spawn(async move |this, cx| {
            let result = task.await;
            let _ = this.update(cx, |this, cx| {
                this.codex_saved_prompts_loading = false;
                this.codex_saved_prompts = result.unwrap_or_default();
                cx.notify();
            });
        })
        .detach();
    }

    fn open_codex_thread(&mut self, tab_id: String, cx: &mut Context<Self>) {
        self.codex_opening_tabs.insert(tab_id.clone());
        let bridge = self.bridge.clone();
        cx.spawn(async move |this, cx| {
            let result = bridge
                .request_with_timeout(
                    "codex.thread.open",
                    json!({"tabId": tab_id}),
                    Duration::from_secs(30),
                )
                .await;
            let _ = this.update(cx, |this, cx| {
                this.codex_opening_tabs.remove(&tab_id);
                match result {
                    Ok(value) => {
                        this.apply_codex_session_response(&tab_id, &value);
                        if let Some(snapshot) = value.get("snapshot") {
                            this.codex_snapshots.insert(tab_id.clone(), snapshot.clone());
                        }
                        this.codex_error = None;
                    }
                    Err(error) => this.codex_error = Some(error.into()),
                }
                cx.notify();
            });
        })
        .detach();
        cx.notify();
    }

    fn apply_codex_session_response(&mut self, tab_id: &str, value: &Value) {
        if let Some(thread_id) = value
            .get("threadId")
            .and_then(Value::as_str)
            .filter(|id| !id.is_empty())
        {
            self.codex_thread_ids
                .insert(tab_id.to_owned(), thread_id.to_owned());
        }
        if let Some(recovery_value) = value.get("recovery") {
            if recovery_value.is_object() {
                let recovery = recovery_value;
                self.codex_recovery
                    .insert(tab_id.to_owned(), recovery.clone());
            } else {
                self.codex_recovery.remove(tab_id);
            }
        }
        if let Some(configuration) = value.get("configuration").and_then(Value::as_object) {
            if let Some(model) = configuration.get("selectedModel").and_then(Value::as_str) {
                self.codex_selected_model = Some(model.to_owned());
            }
            if let Some(reasoning) = configuration.get("reasoningEffort").and_then(Value::as_str) {
                self.codex_reasoning_effort = reasoning.to_owned();
            }
            if let Some(speed) = configuration.get("speedMode").and_then(Value::as_str) {
                self.codex_speed_mode = speed.to_owned();
            }
            if let Some(permission) = configuration.get("permissionMode").and_then(Value::as_str) {
                self.codex_permission_mode = permission.to_owned();
            }
            if let Some(plan) = configuration.get("planMode").and_then(Value::as_bool) {
                self.codex_plan_mode = plan;
            }
            if let Some(mode) = configuration
                .get("collaborationMode")
                .and_then(Value::as_str)
            {
                self.codex_collaboration_mode = Some(mode.to_owned());
            }
        }
    }

    fn load_codex_catalogs(&mut self, tab_id: &str, cx: &mut Context<Self>) {
        self.codex_catalogs_loading = true;
        let bridge = self.bridge.clone();
        let tab_id = tab_id.to_owned();
        cx.spawn(async move |this, cx| {
            let models = bridge.request("codex.model.list", json!({})).await;
            let modes = bridge
                .request("codex.collaborationModes.list", json!({}))
                .await;
            let skills = bridge
                .request("codex.skills.list", json!({"tabId": tab_id}))
                .await;
            let apps = bridge
                .request("codex.apps.list", json!({"tabId": tab_id}))
                .await;
            let _ = this.update(cx, |this, cx| {
                this.codex_catalogs_loading = false;
                this.codex_catalogs_loaded = true;
                if let Ok(value) = models {
                    this.codex_models = codex_items(&value);
                }
                if let Ok(value) = modes {
                    this.codex_collaboration_modes = codex_items(&value);
                }
                if let Ok(value) = skills {
                    this.codex_skills = codex_items(&value);
                }
                if let Ok(value) = apps {
                    this.codex_apps = codex_items(&value);
                }
                cx.notify();
            });
        })
        .detach();
    }

    pub(super) fn handle_codex_notification(
        &mut self,
        payload: &Value,
        window: &mut Window,
        cx: &mut Context<Self>,
    ) {
        let Some(tab_id) = payload.get("tabId").and_then(Value::as_str) else {
            return;
        };
        let Some(snapshot) = payload.get("snapshot").filter(|value| value.is_object()) else {
            return;
        };
        self.apply_codex_session_response(tab_id, payload);
        self.codex_snapshots
            .insert(tab_id.to_owned(), snapshot.clone());
        if let Some(tab) = self.snapshot.tabs.iter_mut().find(|tab| tab.id == tab_id) {
            if let Some(object) = tab.payload.as_object_mut() {
                object.insert("codexSnapshot".to_owned(), snapshot.clone());
                if let Some(thread_id) = payload.get("threadId").and_then(Value::as_str) {
                    object.insert("codexThreadId".to_owned(), Value::String(thread_id.to_owned()));
                }
            }
        }
        if active_codex_turn(snapshot).is_none() {
            self.start_next_queued_codex_message(tab_id.to_owned(), window, cx);
        }
        cx.notify();
    }

    pub(super) fn create_codex_tab(&mut self, cx: &mut Context<Self>) {
        if self.tab_mutation_busy {
            return;
        }
        let Some(workspace_id) = self.selected_workspace_id.clone() else {
            return;
        };
        let bridge = self.bridge.clone();
        let mut layout = self.snapshot.layout.clone();
        self.tab_mutation_busy = true;
        if let Some(layout) = layout.as_mut() {
            layout.active_group_id = layout.active_group_id.clone();
        }
        cx.spawn(async move |this, cx| {
            let result = bridge
                .request_with_timeout(
                    "codex.tab.create",
                    json!({"workspaceId": workspace_id}),
                    Duration::from_secs(10),
                )
                .await;
            let result = match result {
                Ok(tab) => {
                    let tab_id = tab.get("id").and_then(Value::as_str).map(str::to_owned);
                    if let (Some(tab_id), Some(layout)) = (tab_id.as_ref(), layout.as_mut()) {
                        layout.add_tab_to_active_group(tab_id.clone());
                    }
                    if let Some(layout) = layout {
                        super::tab_actions::persist_layout(&bridge, Some(layout))
                            .await
                            .map(|_| tab)
                    } else {
                        Ok(tab)
                    }
                }
                Err(error) => Err(error),
            };
            let _ = this.update(cx, |this, cx| {
                this.tab_mutation_busy = false;
                match result {
                    Ok(tab) => {
                        this.selected_tab_id = tab
                            .get("id")
                            .and_then(Value::as_str)
                            .map(str::to_owned);
                        this.refresh(cx);
                    }
                    Err(error) => this.local_message = Some(error.into()),
                }
                cx.notify();
            });
        })
        .detach();
    }

    fn new_codex_thread(&mut self, tab_id: &str, cx: &mut Context<Self>) {
        self.run_codex_session_command(tab_id, "codex.thread.new", cx);
    }

    fn clear_codex_thread(&mut self, tab_id: &str, cx: &mut Context<Self>) {
        self.run_codex_session_command(tab_id, "codex.thread.clear", cx);
    }

    fn run_codex_session_command(
        &mut self,
        tab_id: &str,
        request_type: &'static str,
        cx: &mut Context<Self>,
    ) {
        if self.codex_session_action_busy.contains(tab_id) {
            return;
        }
        self.codex_session_action_busy.insert(tab_id.to_owned());
        let bridge = self.bridge.clone();
        let tab_id = tab_id.to_owned();
        let cwd = self
            .snapshot
            .tabs
            .iter()
            .find(|tab| tab.id == tab_id)
            .and_then(|tab| self.snapshot.workspace(&tab.workspace_id))
            .map(|workspace| workspace.path.clone());
        cx.spawn(async move |this, cx| {
            let result = bridge
                .request(
                    request_type,
                    json!({
                        "tabId": tab_id,
                        "cwd": cwd,
                    }),
                )
                .await;
            let _ = this.update(cx, |this, cx| {
                this.codex_session_action_busy.remove(&tab_id);
                match result {
                    Ok(value) => {
                        this.apply_codex_session_response(&tab_id, &value);
                        if let Some(snapshot) = value.get("snapshot") {
                            this.codex_snapshots.insert(tab_id.clone(), snapshot.clone());
                        }
                        this.codex_error = None;
                    }
                    Err(error) => this.codex_error = Some(error.into()),
                }
                cx.notify();
            });
        })
        .detach();
        cx.notify();
    }

    pub(super) fn open_codex_resume_picker(&mut self, tab_id: &str, cx: &mut Context<Self>) {
        if self.codex_session_action_busy.contains(tab_id) {
            return;
        }
        self.codex_resume_dialog_tab = Some(tab_id.to_owned());
        self.codex_resume_threads.clear();
        self.codex_resume_next_cursor = None;
        self.codex_resume_workspace_only = true;
        self.codex_resume_error = None;
        self.load_codex_resume_threads(tab_id.to_owned(), false, cx);
        cx.notify();
    }

    pub(super) fn load_codex_resume_threads(
        &mut self,
        tab_id: String,
        append: bool,
        cx: &mut Context<Self>,
    ) {
        if self.codex_resume_loading || self.codex_resume_dialog_tab.as_deref() != Some(tab_id.as_str()) {
            return;
        }
        let workspace_id = self
            .snapshot
            .tabs
            .iter()
            .find(|tab| tab.id == tab_id)
            .map(|tab| tab.workspace_id.clone());
        let search_term = self
            .codex_resume_search_input
            .read(cx)
            .value()
            .trim()
            .to_owned();
        let scope_workspace = self.codex_resume_workspace_only;
        let cursor = append.then(|| self.codex_resume_next_cursor.clone()).flatten();
        if append && cursor.is_none() {
            return;
        }
        self.codex_resume_loading = true;
        let bridge = self.bridge.clone();
        cx.spawn(async move |this, cx| {
            let result = bridge
                .request(
                    "codex.thread.list",
                    json!({
                        "scope": if scope_workspace { "workspace" } else { "all" },
                        "workspaceId": if scope_workspace { workspace_id } else { None::<String> },
                        "searchTerm": (!search_term.is_empty()).then_some(search_term),
                        "cursor": cursor,
                        "limit": 20,
                    }),
                )
                .await;
            let _ = this.update(cx, |this, cx| {
                this.codex_resume_loading = false;
                if this.codex_resume_dialog_tab.as_deref() != Some(tab_id.as_str()) {
                    return;
                }
                match result {
                    Ok(value) => {
                        let items = value
                            .get("items")
                            .or_else(|| value.get("threads"))
                            .or_else(|| value.get("data"))
                            .and_then(Value::as_array)
                            .cloned()
                            .unwrap_or_default();
                        if append {
                            this.codex_resume_threads.extend(items);
                        } else {
                            this.codex_resume_threads = items;
                        }
                        this.codex_resume_next_cursor = value
                            .get("nextCursor")
                            .and_then(Value::as_str)
                            .filter(|cursor| !cursor.is_empty())
                            .map(str::to_owned);
                        this.codex_resume_error = None;
                    }
                    Err(error) => this.codex_resume_error = Some(error.into()),
                }
                cx.notify();
            });
        })
        .detach();
    }

    fn resume_codex_thread(
        &mut self,
        tab_id: &str,
        thread: Value,
        cx: &mut Context<Self>,
    ) {
        let Some(thread_id) = thread
            .get("threadId")
            .or_else(|| thread.get("id"))
            .and_then(Value::as_str)
            .filter(|id| !id.is_empty())
            .map(str::to_owned)
        else {
            return;
        };
        let cwd = self
            .snapshot
            .tabs
            .iter()
            .find(|tab| tab.id == tab_id)
            .and_then(|tab| self.snapshot.workspace(&tab.workspace_id))
            .map(|workspace| workspace.path.clone());
        self.codex_resume_dialog_tab = None;
        self.codex_session_action_busy.insert(tab_id.to_owned());
        let bridge = self.bridge.clone();
        let tab_id = tab_id.to_owned();
        cx.spawn(async move |this, cx| {
            let result = bridge
                .request(
                    "codex.thread.resume",
                    json!({
                        "tabId": tab_id,
                        "threadId": thread_id,
                        "cwd": cwd,
                        "limit": 20,
                    }),
                )
                .await;
            let _ = this.update(cx, |this, cx| {
                this.codex_session_action_busy.remove(&tab_id);
                match result {
                    Ok(value) => {
                        if value.get("alreadyBound").and_then(Value::as_bool) == Some(true) {
                            if let (Some(workspace_id), Some(bound_tab_id)) = (
                                value.get("boundWorkspaceId").and_then(Value::as_str),
                                value.get("boundTabId").and_then(Value::as_str),
                            ) {
                                this.select_workspace_tab(
                                    workspace_id.to_owned(),
                                    bound_tab_id.to_owned(),
                                    cx,
                                );
                            }
                        } else {
                            this.apply_codex_session_response(&tab_id, &value);
                            if let Some(snapshot) = value.get("snapshot") {
                                this.codex_snapshots.insert(tab_id.clone(), snapshot.clone());
                            }
                            this.codex_error = None;
                        }
                    }
                    Err(error) => this.codex_error = Some(error.into()),
                }
                cx.notify();
            });
        })
        .detach();
        cx.notify();
    }

    fn render_codex_recovery_banner(
        &self,
        tab_id: &str,
        recovery: &Value,
        cx: &mut Context<Self>,
    ) -> AnyElement {
        let message = recovery
            .get("message")
            .and_then(Value::as_str)
            .unwrap_or("The saved Codex context is no longer available.");
        let tab_id = tab_id.to_owned();
        div()
            .id("codex-thread-recovery")
            .flex()
            .items_center()
            .gap_2()
            .p_3()
            .border_b_1()
            .border_color(theme::warning())
            .bg(theme::surface_raised())
            .child(
                div()
                    .flex_1()
                    .text_sm()
                    .text_color(theme::text_muted())
                    .child(message.to_owned()),
            )
            .child(
                design_system::button(
                    "codex-recover-thread",
                    "Continue In New Thread",
                    ButtonKind::Filled,
                    false,
                )
                .on_click(cx.listener(move |this, _, _, cx| {
                    this.run_codex_session_command(&tab_id, "codex.thread.new", cx);
                })),
            )
            .into_any_element()
    }

    fn render_codex_resume_picker(&self, tab_id: &str, cx: &mut Context<Self>) -> AnyElement {
        let target_tab_id = tab_id.to_owned();
        let tab_id_for_close = tab_id.to_owned();
        let tab_id_for_more = tab_id.to_owned();
        let workspace_label = if self.codex_resume_workspace_only {
            "Workspace"
        } else {
            "All"
        };
        let body = div()
            .id("codex-resume-picker")
            .absolute()
            .inset_0()
            .flex()
            .items_center()
            .justify_center()
            .bg(theme::overlay_scrim())
            .on_mouse_down(MouseButton::Left, cx.listener(|this, _, _, cx| {
                this.codex_resume_dialog_tab = None;
                cx.notify();
            }))
            .child(
                design_system::dialog_shell("codex-resume-dialog", "Resume Codex Thread", 620.0)
                    .on_mouse_down(MouseButton::Left, |_, _, cx| cx.stop_propagation())
                    .child(
                        div()
                            .flex()
                            .gap_2()
                            .child(
                                design_system::button(
                                    "codex-resume-workspace",
                                    workspace_label,
                                    if self.codex_resume_workspace_only {
                                        ButtonKind::Filled
                                    } else {
                                        ButtonKind::Outlined
                                    },
                                    false,
                                )
                                .on_click(cx.listener(|this, _, _, cx| {
                                    if !this.codex_resume_workspace_only {
                                        this.codex_resume_workspace_only = true;
                                        this.codex_resume_next_cursor = None;
                                        if let Some(tab_id) = this.codex_resume_dialog_tab.clone() {
                                            this.load_codex_resume_threads(tab_id, false, cx);
                                        }
                                        cx.notify();
                                    }
                                })),
                            )
                            .child(
                                design_system::button(
                                    "codex-resume-all",
                                    "All",
                                    if self.codex_resume_workspace_only {
                                        ButtonKind::Outlined
                                    } else {
                                        ButtonKind::Filled
                                    },
                                    false,
                                )
                                .on_click(cx.listener(|this, _, _, cx| {
                                    if this.codex_resume_workspace_only {
                                        this.codex_resume_workspace_only = false;
                                        this.codex_resume_next_cursor = None;
                                        if let Some(tab_id) = this.codex_resume_dialog_tab.clone() {
                                            this.load_codex_resume_threads(tab_id, false, cx);
                                        }
                                        cx.notify();
                                    }
                                })),
                            )
                            .child(div().flex_1())
                            .child(
                                design_system::icon_button(
                                    "codex-resume-close",
                                    "Close",
                                    AleraIcon::Close,
                                    false,
                                    28.0,
                                    None,
                                    None,
                                )
                                .on_click(cx.listener(move |this, _, _, cx| {
                                    if this.codex_resume_dialog_tab.as_deref()
                                        == Some(tab_id_for_close.as_str())
                                    {
                                        this.codex_resume_dialog_tab = None;
                                        cx.notify();
                                    }
                                })),
                            ),
                    )
                    .child(Input::new(&self.codex_resume_search_input).h(px(34.0)))
                    .child(
                        div()
                            .mt_2()
                            .flex_1()
                            .min_h(px(240.0))
                            .overflow_y_scrollbar()
                            .children(self.codex_resume_threads.iter().enumerate().map(
                                |(index, thread)| {
                                    let value = thread.clone();
                                    let tab_id_for_row = target_tab_id.clone();
                                    let title = thread
                                        .get("title")
                                        .or_else(|| thread.get("name"))
                                        .or_else(|| thread.get("preview"))
                                        .and_then(Value::as_str)
                                        .unwrap_or("Untitled Codex Thread")
                                        .to_owned();
                                    let subtitle = [
                                        thread
                                            .get("workspaceName")
                                            .and_then(Value::as_str)
                                            .filter(|value| !value.is_empty()),
                                        thread
                                            .get("cwd")
                                            .and_then(Value::as_str)
                                            .filter(|value| !value.is_empty()),
                                        (thread
                                            .get("boundTabId")
                                            .and_then(Value::as_str)
                                            .filter(|value| !value.is_empty())
                                            .is_some())
                                        .then_some("Already Open"),
                                    ]
                                    .into_iter()
                                    .flatten()
                                    .collect::<Vec<_>>()
                                    .join(" / ");
                                    div()
                                        .id(SharedString::from(format!(
                                            "codex-resume-thread-{index}"
                                        )))
                                        .flex()
                                        .items_center()
                                        .gap_2()
                                        .h(px(54.0))
                                        .px_2()
                                        .rounded_md()
                                            .cursor(CursorStyle::PointingHand)
                                            .hover(|style| style.bg(theme::surface_selected()))
                                            .on_click(cx.listener(move |this, _, _, cx| {
                                                this.resume_codex_thread(
                                                &tab_id_for_row,
                                                value.clone(),
                                                cx,
                                            );
                                        }))
                                        .child(
                                            div()
                                                .flex()
                                                .flex_col()
                                                .flex_1()
                                                .overflow_hidden()
                                                .child(title)
                                                .child(
                                                    div()
                                                        .text_xs()
                                                        .text_color(theme::text_faint())
                                                        .text_ellipsis()
                                                        .child(subtitle),
                                                ),
                                        )
                                        .child(icon(
                                            AleraIcon::ChevronRight,
                                            14.0,
                                            theme::text_muted(),
                                        ))
                                },
                            )),
                    )
                    .when_some(self.codex_resume_error.clone(), |dialog, error| {
                        dialog.child(div().mt_2().text_color(theme::danger()).child(error))
                    })
                    .when(self.codex_resume_loading, |dialog| {
                        dialog.child(
                            div()
                                .mt_2()
                                .flex()
                                .items_center()
                                .gap_2()
                                .child(loading_indicator(14.0, theme::text_muted()))
                                .child("Loading Threads"),
                        )
                    })
                    .when(
                        !self.codex_resume_loading
                            && self.codex_resume_threads.is_empty()
                            && self.codex_resume_error.is_none(),
                        |dialog| dialog.child(div().mt_2().child("No Codex Threads Found")),
                    )
                    .when_some(self.codex_resume_next_cursor.clone(), |dialog, _| {
                        dialog.child(
                            design_system::button(
                                "codex-resume-load-more",
                                "Load More",
                                ButtonKind::Outlined,
                                self.codex_resume_loading,
                            )
                            .on_click(cx.listener(move |this, _, _, cx| {
                                this.load_codex_resume_threads(tab_id_for_more.clone(), true, cx);
                            })),
                        )
                    }),
            );
        // This keeps a stale menu's click from leaking into the workbench while
        // the dialog is open, matching Flutter's modal barrier semantics.
        body.into_any_element()
    }

    pub(super) fn render_codex_surface(&self, cx: &mut Context<Self>) -> AnyElement {
        let Some(tab) = self
            .selected_tab_id
            .as_deref()
            .and_then(|id| self.snapshot.tabs.iter().find(|tab| tab.id == id))
            .filter(|tab| tab.kind == CODEX_TAB_KIND)
        else {
            return div().into_any_element();
        };
        self.render_codex_surface_for(tab, cx)
    }

    pub(super) fn render_codex_surface_for(
        &self,
        tab: &WorkspaceTab,
        cx: &mut Context<Self>,
    ) -> AnyElement {
        let tab_id = tab.id.clone();
        let snapshot = self
            .codex_snapshots
            .get(&tab_id)
            .cloned()
            .or_else(|| tab.payload.get("codexSnapshot").cloned())
            .unwrap_or_else(|| json!({"events": [], "pendingRequests": []}));
        let opening = self.codex_opening_tabs.contains(&tab_id);
        let busy = active_codex_turn(&snapshot).is_some();
        let input = self.codex_composer_inputs.get(&tab_id).cloned();
        let error = self.codex_error.clone();
        let queued = self
            .codex_queued_messages
            .get(&tab_id)
            .cloned()
            .unwrap_or_default();
        div()
            .id(SharedString::from(format!("codex-surface-{tab_id}")))
            .flex()
            .flex_col()
            .flex_1()
            .min_h_0()
            .bg(theme::app_background())
            .child(self.render_codex_header(&tab_id, cx))
            .when(
                self.codex_resume_dialog_tab.as_deref() == Some(tab_id.as_str()),
                |surface| surface.child(self.render_codex_resume_picker(&tab_id, cx)),
            )
            .when_some(self.codex_recovery.get(&tab_id).cloned(), |surface, recovery| {
                surface.child(self.render_codex_recovery_banner(&tab_id, &recovery, cx))
            })
            .child(
                div()
                    .flex_1()
                    .min_h_0()
                    .overflow_y_scrollbar()
                    .child(if opening && snapshot_events(&snapshot).is_empty() {
                        div()
                            .flex()
                            .flex_1()
                            .items_center()
                            .justify_center()
                            .gap_2()
                            .child(loading_indicator(18.0, theme::text_muted()))
                            .child("Opening Codex Thread")
                            .into_any_element()
                    } else {
                        self.render_codex_timeline(&tab_id, &snapshot, cx)
                    }),
            )
            .when_some(error, |surface, error| {
                surface.child(
                    div()
                        .p_2()
                        .text_color(theme::danger())
                        .child(error),
                )
            })
            .when(!queued.is_empty(), |surface| {
                surface.child(self.render_codex_queue_bar(&tab_id, queued, cx))
            })
            .when_some(input, |surface, input| {
                surface.child(self.render_codex_composer(&tab_id, input, busy, cx))
            })
            .into_any_element()
    }

    fn render_codex_queue_bar(
        &self,
        tab_id: &str,
        messages: Vec<String>,
        cx: &mut Context<Self>,
    ) -> AnyElement {
        let tab_id = tab_id.to_owned();
        div()
            .id("codex-queue-bar")
            .flex()
            .items_center()
            .gap_1()
            .px_3()
            .py_2()
            .bg(theme::surface())
            .child(div().text_xs().text_color(theme::text_faint()).child("Queued Messages"))
            .children(messages.into_iter().enumerate().map(|(index, message)| {
                let tab_id = tab_id.clone();
                div()
                    .id(SharedString::from(format!("codex-queued-{index}")))
                    .flex()
                    .items_center()
                    .gap_1()
                    .max_w(px(240.0))
                    .px_2()
                    .py_1()
                    .rounded_md()
                    .border_1()
                    .border_color(theme::border_subtle())
                    .child(div().flex_1().text_ellipsis().child(message))
                    .child(
                        design_system::icon_button(
                            SharedString::from(format!("codex-queued-remove-{index}")),
                            "Remove Queued Message",
                            AleraIcon::Close,
                            true,
                            20.0,
                            None,
                            None,
                        )
                        .on_click(cx.listener(move |this, _, _, cx| {
                            if let Some(messages) = this.codex_queued_messages.get_mut(&tab_id) {
                                if index < messages.len() {
                                    messages.remove(index);
                                }
                                if messages.is_empty() {
                                    this.codex_queued_messages.remove(&tab_id);
                                }
                                cx.notify();
                            }
                        })),
                    )
            }))
            .into_any_element()
    }

    fn render_codex_header(&self, tab_id: &str, cx: &mut Context<Self>) -> AnyElement {
        let model_label = self
            .codex_selected_model
            .as_deref()
            .and_then(|id| {
                self.codex_models
                    .iter()
                    .find(|item| item_id(item).as_deref() == Some(id))
            })
            .and_then(|item| item_label(item))
            .unwrap_or_else(|| "Model".to_owned());
        let menu_open = self.codex_menu_open.clone();
        let tab_for_compact = tab_id.to_owned();
        let tab_for_review = tab_id.to_owned();
        let tab_for_plan = tab_id.to_owned();
        div()
            .id("codex-header")
            .relative()
            .flex()
            .items_center()
            .gap_1()
            .h(px(42.0))
            .px_2()
            .border_b_1()
            .border_color(theme::border_subtle())
            .child(self.codex_choice_button(tab_id, "model", model_label, cx))
            .when(!self.codex_skills.is_empty(), |header| {
                header.child(self.codex_choice_button(tab_id, "skills", "Skills".to_owned(), cx))
            })
            .when(!self.codex_apps.is_empty(), |header| {
                header.child(self.codex_choice_button(tab_id, "apps", "Apps".to_owned(), cx))
            })
            .child(self.codex_choice_button(
                tab_id,
                "commands",
                if self.codex_saved_prompts_loading {
                    "Commands…".to_owned()
                } else {
                    "Commands".to_owned()
                },
                cx,
            ))
            .when(!self.codex_collaboration_modes.is_empty(), |header| {
                header.child(self.codex_choice_button(
                    tab_id,
                    "collaboration",
                    self.codex_collaboration_mode
                        .clone()
                        .unwrap_or_else(|| "Collaboration".to_owned()),
                    cx,
                ))
            })
            .child(self.codex_choice_button(tab_id, "reasoning", format!("Reasoning: {}", self.codex_reasoning_effort), cx))
            .child(self.codex_choice_button(tab_id, "speed", format!("Speed: {}", self.codex_speed_mode), cx))
            .child(self.codex_choice_button(tab_id, "permission", format!("Permission: {}", self.codex_permission_mode), cx))
            .child(
                design_system::button("codex-plan-mode", "Plan", ButtonKind::Text, false)
                    .on_click(cx.listener(move |this, _, _, cx| {
                        this.codex_plan_mode = !this.codex_plan_mode;
                        this.codex_collaboration_mode = this.codex_plan_mode
                            .then_some("plan".to_owned())
                            .or_else(|| this.codex_collaboration_mode.clone().filter(|mode| mode != "plan"));
                        this.persist_codex_chat_settings(cx);
                        this.persist_codex_tab_configuration(&tab_for_plan, cx);
                        cx.notify();
                    })),
            )
            .child(div().flex_1())
            .child(
                design_system::icon_button("codex-compact", "Compact Context", AleraIcon::CollapseAll, false, 28.0, None, None)
                    .on_click(cx.listener(move |this, _, _, cx| this.compact_codex_thread(tab_for_compact.clone(), cx))),
            )
            .child(
                design_system::icon_button("codex-review", "Start Review", AleraIcon::CheckCheck, false, 28.0, None, None)
                    .on_click(cx.listener(move |this, _, _, cx| this.review_codex_thread(tab_for_review.clone(), cx))),
            )
            .child(
                design_system::icon_button("codex-raw-logs", "Raw Logs", AleraIcon::File, self.codex_raw_logs, 28.0, None, None)
                    .on_click(cx.listener(|this, _, _, cx| {
                        this.codex_raw_logs = !this.codex_raw_logs;
                        cx.notify();
                    })),
            )
            .when(menu_open.is_some(), |header| {
                header.child(self.render_codex_choice_menu(tab_id, menu_open.as_deref().unwrap(), cx))
            })
            .into_any_element()
    }

    fn codex_choice_button(
        &self,
        tab_id: &str,
        kind: &str,
        label: String,
        cx: &mut Context<Self>,
    ) -> AnyElement {
        let key = format!("{tab_id}:{kind}");
        let id = key.clone();
        design_system::dropdown_trigger(
            SharedString::from(format!("codex-choice-{kind}")),
            label,
            self.codex_menu_open.as_deref() == Some(key.as_str()),
            true,
        )
        .on_click(cx.listener(move |this, _, _, cx| {
            this.codex_menu_open = if this.codex_menu_open.as_deref() == Some(id.as_str()) {
                None
            } else {
                Some(id.clone())
            };
            cx.notify();
        }))
        .into_any_element()
    }

    fn render_codex_choice_menu(
        &self,
        tab_id: &str,
        key: &str,
        cx: &mut Context<Self>,
    ) -> AnyElement {
        let kind = key.split_once(':').map(|(_, kind)| kind).unwrap_or(key);
        let values = match kind {
            "model" => self
                .codex_models
                .iter()
                .filter_map(|item| Some((item_id(item)?, item_label(item)?)))
                .collect::<Vec<_>>(),
            "reasoning" => ["low", "medium", "high", "xhigh"]
                .into_iter()
                .map(|value| (value.to_owned(), value.to_owned()))
                .collect(),
            "speed" => vec![("normal".to_owned(), "normal".to_owned()), ("fast".to_owned(), "fast".to_owned())],
            "permission" => vec![("on-request".to_owned(), "on-request".to_owned()), ("never".to_owned(), "never".to_owned())],
            "skills" => self
                .codex_skills
                .iter()
                .filter_map(|item| Some((item_id(item)?, item_label(item)?)))
                .collect::<Vec<_>>(),
            "apps" => self
                .codex_apps
                .iter()
                .filter_map(|item| Some((item_id(item)?, item_label(item)?)))
                .collect::<Vec<_>>(),
            "commands" => {
                let mut commands = [
                    ("new", "New Chat"),
                    ("clear", "Clear"),
                    ("resume", "Resume Thread"),
                    ("compact", "Compact Context"),
                    ("review", "Start Review"),
                    ("plan", "Toggle Plan"),
                    ("permissions", "Permissions"),
                    ("rename", "Rename"),
                    ("mention", "Mention File"),
                    ("skills", "Skills"),
                    ("apps", "Apps"),
                    ("status", "Status"),
                    ("logs", "Raw Logs"),
                ]
                .into_iter()
                .map(|(value, label)| (value.to_owned(), label.to_owned()))
                .collect::<Vec<_>>();
                commands.extend(
                    self.codex_saved_prompts
                        .iter()
                        .map(|prompt| (prompt.name.clone(), prompt.description.clone())),
                );
                commands
            }
            "collaboration" => self
                .codex_collaboration_modes
                .iter()
                .filter_map(|item| {
                    let value = item
                        .get("mode")
                        .or_else(|| item.get("id"))
                        .and_then(Value::as_str)?
                        .to_owned();
                    Some((value.clone(), value))
                })
                .collect::<Vec<_>>(),
            _ => Vec::new(),
        };
        let tab_id = tab_id.to_owned();
        div()
            .id("codex-choice-menu")
            .absolute()
            .top(px(38.0))
            .left(px(8.0))
            .min_w(px(180.0))
            .rounded_lg()
            .border_1()
            .border_color(theme::border())
            .bg(theme::surface_raised())
            .shadow_lg()
            .p_1()
            .on_mouse_down(MouseButton::Left, |_, _, cx| cx.stop_propagation())
            .children(values.into_iter().map(|(value, label)| {
                let value_for_click = value.clone();
                let kind = kind.to_owned();
                let tab_id_for_click = tab_id.clone();
                div()
                    .id(SharedString::from(format!("codex-choice-{kind}-{value}")))
                    .role(Role::MenuItem)
                    .flex()
                    .items_center()
                    .h(px(30.0))
                    .px_2()
                    .rounded_md()
                    .cursor(CursorStyle::PointingHand)
                    .hover(|style| style.bg(theme::surface_selected()))
                    .on_click(cx.listener(move |this, _, window, cx| {
                        this.select_codex_choice(
                            &tab_id_for_click,
                            &kind,
                            &value_for_click,
                            window,
                            cx,
                        );
                    }))
                    .child(label)
            }))
            .into_any_element()
    }

    fn select_codex_choice(
        &mut self,
        tab_id: &str,
        kind: &str,
        value: &str,
        window: &mut Window,
        cx: &mut Context<Self>,
    ) {
        match kind {
            "model" => self.codex_selected_model = Some(value.to_owned()),
            "reasoning" => self.codex_reasoning_effort = value.to_owned(),
            "speed" => self.codex_speed_mode = value.to_owned(),
            "permission" => self.codex_permission_mode = value.to_owned(),
            "skills" => self.insert_codex_token(tab_id, &format!("/skill {value}"), window, cx),
            "apps" => self.insert_codex_token(tab_id, &format!("/app {value}"), window, cx),
            "commands" => match value {
                "new" if self.codex_sessions_supported == Some(true) => {
                    self.new_codex_thread(tab_id, cx)
                }
                "clear" if self.codex_sessions_supported == Some(true) => {
                    self.clear_codex_thread(tab_id, cx)
                }
                "resume" if self.codex_sessions_supported == Some(true) => {
                    self.open_codex_resume_picker(tab_id, cx)
                }
                _ => self.insert_codex_token(tab_id, &format!("/{value} "), window, cx),
            },
            "collaboration" => {
                self.codex_collaboration_mode = Some(value.to_owned());
                self.codex_plan_mode = value.eq_ignore_ascii_case("plan");
            }
            _ => {}
        }
        self.persist_codex_chat_settings(cx);
        self.codex_menu_open = None;
        cx.notify();
    }

    fn persist_codex_chat_settings(&mut self, cx: &mut Context<Self>) {
        self.settings_state.codex_chat_selected_model = self.codex_selected_model.clone();
        self.settings_state.codex_chat_reasoning_effort = self.codex_reasoning_effort.clone();
        self.settings_state.codex_chat_speed_mode = self.codex_speed_mode.clone();
        self.settings_state.codex_chat_permission_mode = self.codex_permission_mode.clone();
        self.settings_state.codex_chat_plan_mode = self.codex_plan_mode;
        self.persist_settings();
        self.persist_shared_flutter_settings(
            self.settings_state.shared_flutter_local_payload(),
            cx,
        );
        if let Some(tab_id) = self
            .selected_tab_id
            .as_deref()
            .filter(|tab_id| self.snapshot.tabs.iter().any(|tab| tab.id == *tab_id && tab.kind == CODEX_TAB_KIND))
        {
            self.persist_codex_tab_configuration(tab_id, cx);
        }
    }

    fn persist_codex_tab_configuration(&self, tab_id: &str, cx: &mut Context<Self>) {
        let bridge = self.bridge.clone();
        let payload = json!({
            "tabId": tab_id,
            "configuration": {
                "selectedModel": self.codex_selected_model.clone(),
                "reasoningEffort": self.codex_reasoning_effort.clone(),
                "speedMode": self.codex_speed_mode.clone(),
                "permissionMode": self.codex_permission_mode.clone(),
                "planMode": self.codex_plan_mode,
                "collaborationMode": self.codex_collaboration_mode.clone(),
            }
        });
        cx.spawn(async move |_, _| {
            let _ = bridge.request("codex.tab.configure", payload).await;
        })
        .detach();
    }

    fn insert_codex_token(
        &mut self,
        tab_id: &str,
        token: &str,
        window: &mut Window,
        cx: &mut Context<Self>,
    ) {
        if let Some(input) = self.codex_composer_inputs.get(tab_id).cloned() {
            input.update(cx, |input, cx| input.insert(token, window, cx));
            input.update(cx, |input, cx| input.focus(window, cx));
        }
    }

    fn render_codex_timeline(
        &self,
        tab_id: &str,
        snapshot: &Value,
        cx: &mut Context<Self>,
    ) -> AnyElement {
        let mut content = div()
            .id("codex-timeline")
            .flex()
            .flex_col()
            .gap_2()
            .p_3();
        let cells = snapshot_cells(snapshot);
        let has_cells = !cells.is_empty();
        if !has_cells
            && snapshot_events(snapshot).is_empty()
            && snapshot_pending(snapshot).is_empty()
        {
            content = content.child(
                div()
                    .flex()
                    .items_center()
                    .justify_center()
                    .text_color(theme::text_muted())
                    .child("Ask Codex To Work On This Workspace."),
            );
        }
        for (index, cell) in cells.into_iter().enumerate() {
            let kind = cell.get("kind").and_then(Value::as_str).unwrap_or("event");
            let cell_id = cell
                .get("id")
                .and_then(Value::as_str)
                .map(str::to_owned)
                .unwrap_or_else(|| format!("cell-{index}"));
            let title = cell
                .get("title")
                .and_then(Value::as_str)
                .unwrap_or_else(|| codex_cell_label(kind))
                .to_owned();
            let body = cell
                .get("renderedMarkdownText")
                .and_then(Value::as_str)
                .or_else(|| cell.get("markdownText").and_then(Value::as_str))
                .or_else(|| cell.get("detailsText").and_then(Value::as_str))
                .unwrap_or_default()
                .to_owned();
            let details = cell
                .get("detailsText")
                .and_then(Value::as_str)
                .unwrap_or_default()
                .to_owned();
            let show_details = !details.is_empty() && details != body;
            let subtitle = cell
                .get("subtitle")
                .and_then(Value::as_str)
                .map(str::to_owned);
            let streaming = cell
                .get("isStreaming")
                .and_then(Value::as_bool)
                .unwrap_or(false);
            let collapsed = self.codex_collapsed_cells.contains(&cell_id)
                || cell
                    .get("isCollapsed")
                    .and_then(Value::as_bool)
                    .unwrap_or(false);
            let cell_id_for_click = cell_id.clone();
            let mut card = div()
                    .id(SharedString::from(format!("codex-cell-{index}")))
                    .rounded_lg()
                    .border_1()
                    .border_color(theme::border_subtle())
                    .bg(if kind == "userMessage" {
                        theme::surface_selected()
                    } else {
                        theme::surface()
                    })
                    .p_3()
                    .child(
                        div()
                            .id(SharedString::from(format!("codex-cell-header-{index}")))
                            .flex()
                            .items_center()
                            .gap_1()
                            .font_weight(gpui::FontWeight::SEMIBOLD)
                            .text_size(px(11.0))
                            .text_color(theme::text_muted())
                            .cursor(CursorStyle::PointingHand)
                            .on_click(cx.listener(move |this, _, _, cx| {
                                if !this.codex_collapsed_cells.remove(&cell_id_for_click) {
                                    this.codex_collapsed_cells.insert(cell_id_for_click.clone());
                                }
                                cx.notify();
                            }))
                            .child(title)
                            .when(streaming, |row| {
                                row.child(loading_indicator(12.0, theme::text_faint()))
                            }),
                    );
            if !collapsed {
                if let Some(subtitle) = subtitle {
                    card = card.child(
                        div()
                            .mt_1()
                            .text_xs()
                            .text_color(theme::text_faint())
                            .child(subtitle),
                    );
                }
                if !body.is_empty() {
                    card = card.child(
                        with_markdown_images(TextView::markdown(
                            SharedString::from(format!("codex-cell-body-{index}")),
                            body,
                        )),
                    );
                }
                if show_details {
                    card = card.child(
                        div()
                            .mt_2()
                            .rounded_md()
                            .bg(theme::app_background())
                            .p_2()
                            .font_family("JetBrains Mono")
                            .text_size(px(11.0))
                            .whitespace_normal()
                            .child(details),
                    );
                }
                if kind == "plan" && !streaming && self.codex_plan_mode {
                    card = card.child(
                        div()
                            .flex()
                            .gap_2()
                            .mt_2()
                            .child(
                                design_system::button(
                                    SharedString::from(format!("codex-implement-plan-{index}")),
                                    "Implement Plan",
                                    ButtonKind::Filled,
                                    false,
                                )
                                .on_click(cx.listener({
                                    let tab_id = tab_id.to_owned();
                                    move |this, _, window, cx| {
                                        if let Some(input) = this.codex_composer_inputs.get(&tab_id).cloned() {
                                            input.update(cx, |input, cx| input.set_value("Implement the plan.", window, cx));
                                            this.send_codex_message(&tab_id, window, cx);
                                        }
                                    }
                                })),
                            )
                            .child(
                                design_system::button(
                                    SharedString::from(format!("codex-decline-plan-{index}")),
                                    "Decline",
                                    ButtonKind::Outlined,
                                    false,
                                )
                                .on_click(cx.listener({
                                    let tab_id = tab_id.to_owned();
                                    move |this, _, window, cx| {
                                        if let Some(input) = this.codex_composer_inputs.get(&tab_id).cloned() {
                                            input.update(cx, |input, cx| input.set_value("Do not implement the plan.", window, cx));
                                            this.send_codex_message(&tab_id, window, cx);
                                        }
                                    }
                                })),
                            ),
                    );
                }
            }
            content = content.child(card);
        }
        if !has_cells {
        for (index, event) in snapshot_events(snapshot).into_iter().enumerate() {
            let method = event.get("method").and_then(Value::as_str).unwrap_or("event");
            let text = event_text(event).unwrap_or_else(|| method.to_owned());
            if !self.codex_raw_logs && text.trim().is_empty() {
                continue;
            }
            let label = codex_event_label(method, event);
            content = content.child(
                div()
                    .id(SharedString::from(format!("codex-event-{index}")))
                    .rounded_lg()
                    .border_1()
                    .border_color(theme::border_subtle())
                    .bg(if method.contains("user") {
                        theme::surface_selected()
                    } else {
                        theme::surface()
                    })
                    .p_3()
                    .child(
                        div()
                            .text_size(px(11.0))
                            .font_weight(gpui::FontWeight::SEMIBOLD)
                            .text_color(theme::text_muted())
                            .child(label),
                    )
                    .child(
                        div()
                            .mt_1()
                            .font_family("JetBrains Mono")
                            .text_size(px(12.0))
                            .whitespace_normal()
                            .child(if self.codex_raw_logs {
                                event.to_string()
                            } else {
                                text
                            }),
                    ),
            );
        }
        }
        for (index, request) in snapshot_pending(snapshot).into_iter().enumerate() {
            let request_id = request.get("id").cloned().unwrap_or(Value::Null);
            let request_id_for_click = request_id.clone();
            let method = request.get("method").and_then(Value::as_str).unwrap_or("request");
            let params = request.get("params").cloned().unwrap_or(Value::Null);
            let is_approval = method.contains("approval") || method.contains("permission");
            let approval_decisions = is_approval.then(|| approval_decisions(&params));
            content = content.child(
                div()
                    .id(SharedString::from(format!("codex-pending-{index}")))
                    .rounded_lg()
                    .border_1()
                    .border_color(theme::warning())
                    .bg(theme::surface_raised())
                    .p_3()
                    .child(
                        div()
                            .font_weight(gpui::FontWeight::SEMIBOLD)
                            .child(if is_approval {
                                "Codex Needs Approval"
                            } else {
                                "Codex Needs Your Input"
                            }),
                    )
                    .child(
                        div()
                            .mt_1()
                            .text_color(theme::text_muted())
                            .child(request_text(&params, method)),
                    )
                    .child({
                        let mut actions = div().flex().gap_2().mt_2();
                        if let Some(decisions) = approval_decisions {
                            for (decision, label, kind) in decisions {
                                let tab_id = tab_id.to_owned();
                                let request_id = request_id.clone();
                                let result = approval_result(&params, method, &decision);
                                actions = actions.child(
                                    design_system::button(
                                        SharedString::from(format!("codex-{decision}-{index}")),
                                        label,
                                        kind,
                                        false,
                                    )
                                    .on_click(cx.listener(move |this, _, _, cx| {
                                        this.respond_codex_request(
                                            &tab_id,
                                            request_id.clone(),
                                            result.clone(),
                                            cx,
                                        );
                                    })),
                                );
                            }
                        } else {
                            let tab_id = tab_id.to_owned();
                            actions = actions.child(
                                design_system::button(
                                    SharedString::from(format!("codex-cancel-{index}")),
                                    "Cancel",
                                    ButtonKind::Outlined,
                                    false,
                                )
                                .on_click(cx.listener(move |this, _, _, cx| {
                                    this.respond_codex_request(
                                        &tab_id,
                                        request_id_for_click.clone(),
                                        json!({"cancelled": true}),
                                        cx,
                                    );
                                })),
                            );
                        }
                        actions
                    }),
            );
        }
        content.into_any_element()
    }

    fn render_codex_composer(
        &self,
        tab_id: &str,
        input: Entity<TextareaState>,
        busy: bool,
        cx: &mut Context<Self>,
    ) -> AnyElement {
        let tab_for_key = tab_id.to_owned();
        let tab_for_send = tab_id.to_owned();
        let tab_for_stop = tab_id.to_owned();
        div()
            .id("codex-composer")
            .p_3()
            .border_t_1()
            .border_color(theme::border_subtle())
            .bg(theme::surface_selected())
            .on_mouse_down(MouseButton::Left, |_, _, cx| cx.stop_propagation())
            .capture_key_down(cx.listener(move |this, event: &KeyDownEvent, window, cx| {
                if event.keystroke.key.eq_ignore_ascii_case("enter")
                    && !event.keystroke.modifiers.shift
                {
                    this.send_codex_message(&tab_for_key, window, cx);
                    cx.stop_propagation();
                }
            }))
            .child(
                Textarea::new(&input)
                    .aria_label("Message Codex")
                    .h(px(84.0))
                    .bordered(true),
            )
            .child(
                div()
                    .flex()
                    .items_center()
                    .justify_end()
                    .gap_2()
                    .mt_2()
                    .when(busy, |row| {
                        row.child(
                            design_system::button(
                                "codex-steer",
                                "Steer",
                                ButtonKind::Outlined,
                                false,
                            )
                            .on_click(cx.listener(move |this, _, window, cx| {
                                this.steer_codex_message(&tab_for_send, window, cx);
                            })),
                        )
                    })
                    .child(
                        design_system::icon_button(
                            "codex-send-stop",
                            if busy { "Stop" } else { "Send" },
                            if busy { AleraIcon::Stop } else { AleraIcon::Send },
                            false,
                            32.0,
                            None,
                            None,
                        )
                        .on_click(cx.listener(move |this, _, window, cx| {
                            if busy {
                                this.stop_codex_turn(&tab_for_stop, cx);
                            } else {
                                this.send_codex_message(&tab_for_stop, window, cx);
                            }
                        })),
                    ),
            )
            .into_any_element()
    }

    fn send_codex_message(&mut self, tab_id: &str, window: &mut Window, cx: &mut Context<Self>) {
        let Some(input) = self.codex_composer_inputs.get(tab_id).cloned() else {
            return;
        };
        let text = input.read(cx).value().to_string();
        if text.trim().is_empty() {
            return;
        }
        let snapshot = self.codex_snapshots.get(tab_id);
        if snapshot.is_some_and(|snapshot| active_codex_turn(snapshot).is_some()) {
            self.codex_queued_messages
                .entry(tab_id.to_owned())
                .or_default()
                .push(text);
            input.update(cx, |input, cx| input.set_value("", window, cx));
            cx.notify();
            return;
        }
        self.start_codex_turn(tab_id.to_owned(), text, window, cx);
    }

    fn start_codex_turn(
        &mut self,
        tab_id: String,
        text: String,
        window: &mut Window,
        cx: &mut Context<Self>,
    ) {
        let Some(input) = self.codex_composer_inputs.get(&tab_id).cloned() else {
            return;
        };
        let bridge = self.bridge.clone();
        let text = expand_saved_prompt(&text, &self.codex_saved_prompts);
        let model = self.codex_selected_model.clone();
        let reasoning = self.codex_reasoning_effort.clone();
        let speed = self.codex_speed_mode.clone();
        let permission = self.codex_permission_mode.clone();
        let plan = self.codex_plan_mode;
        let expected_thread_id = self.codex_thread_ids.get(&tab_id).cloned();
        let collaboration_mode = self
            .codex_collaboration_mode
            .clone()
            .or_else(|| plan.then_some("plan".to_owned()));
        self.codex_error = None;
        input.update(cx, |input, cx| input.set_value("", window, cx));
        cx.spawn_in(window, async move |this, cx| {
            let result = bridge
                .request_with_timeout(
                    "codex.turn.start",
                    json!({
                        "tabId": tab_id,
                        "expectedThreadId": expected_thread_id,
                        "input": [{"type": "text", "text": text}],
                        "model": model,
                        "reasoning": {"effort": reasoning},
                        "effort": reasoning,
                        "serviceTier": (speed == "fast").then_some("fast"),
                        "approvalPolicy": permission,
                        "collaborationMode": collaboration_mode.clone().map(|mode| json!({"mode": mode})),
                        "configuration": {
                            "selectedModel": model,
                            "reasoningEffort": reasoning,
                            "speedMode": speed,
                            "permissionMode": permission,
                            "planMode": plan,
                            "collaborationMode": collaboration_mode,
                        },
                    }),
                    Duration::from_secs(10),
                )
                .await;
            let _ = this.update_in(cx, move |this, _, cx| {
                if let Err(error) = result {
                    this.codex_error = Some(error.into());
                }
                cx.notify();
            });
        })
        .detach();
        cx.notify();
    }

    fn stop_codex_turn(&mut self, tab_id: &str, cx: &mut Context<Self>) {
        let Some(turn_id) = self
            .codex_snapshots
            .get(tab_id)
            .and_then(active_codex_turn)
        else {
            return;
        };
        let bridge = self.bridge.clone();
        let tab_id = tab_id.to_owned();
        cx.spawn(async move |this, cx| {
            let result = bridge
                .request("codex.turn.interrupt", json!({"tabId": tab_id, "turnId": turn_id}))
                .await;
            if let Some(this) = this.upgrade() {
                this.update(cx, |this, cx| {
                    if let Err(error) = result {
                        this.codex_error = Some(error.into());
                    }
                    cx.notify();
                });
            }
        })
        .detach();
    }

    fn steer_codex_message(&mut self, tab_id: &str, window: &mut Window, cx: &mut Context<Self>) {
        let Some(turn_id) = self.codex_snapshots.get(tab_id).and_then(active_codex_turn) else {
            return;
        };
        let Some(input) = self.codex_composer_inputs.get(tab_id).cloned() else {
            return;
        };
        let text = input.read(cx).value().to_string();
        if text.trim().is_empty() {
            return;
        }
        let bridge = self.bridge.clone();
        let tab_id = tab_id.to_owned();
        input.update(cx, |input, cx| input.set_value("", window, cx));
        cx.spawn(async move |this, cx| {
            let result = bridge
                .request(
                    "codex.turn.steer",
                    json!({"tabId": tab_id, "turnId": turn_id, "input": [{"type": "text", "text": text}]}),
                )
                .await;
            if let Some(this) = this.upgrade() {
                this.update(cx, |this, cx| {
                    if let Err(error) = result {
                        this.codex_error = Some(error.into());
                    }
                    cx.notify();
                });
            }
        })
        .detach();
    }

    fn start_next_queued_codex_message(
        &mut self,
        tab_id: String,
        window: &mut Window,
        cx: &mut Context<Self>,
    ) {
        let Some(messages) = self.codex_queued_messages.get_mut(&tab_id) else {
            return;
        };
        let Some(message) = messages.first().cloned() else {
            return;
        };
        messages.remove(0);
        if messages.is_empty() {
            self.codex_queued_messages.remove(&tab_id);
        }
        self.start_codex_turn(tab_id, message, window, cx);
    }

    fn compact_codex_thread(&mut self, tab_id: String, cx: &mut Context<Self>) {
        self.codex_simple_request("codex.thread.compact", json!({"tabId": tab_id}), cx);
    }

    fn review_codex_thread(&mut self, tab_id: String, cx: &mut Context<Self>) {
        self.codex_simple_request("codex.review.start", json!({"tabId": tab_id}), cx);
    }

    fn codex_simple_request(&mut self, request_type: &str, payload: Value, cx: &mut Context<Self>) {
        let bridge = self.bridge.clone();
        let request_type = request_type.to_owned();
        cx.spawn(async move |this, cx| {
            let result = bridge.request(request_type, payload).await;
            if let Some(this) = this.upgrade() {
                this.update(cx, |this, cx| {
                    if let Err(error) = result {
                        this.codex_error = Some(error.into());
                    }
                    cx.notify();
                });
            }
        })
        .detach();
    }

    fn respond_codex_request(
        &mut self,
        tab_id: &str,
        request_id: Value,
        result_value: Value,
        cx: &mut Context<Self>,
    ) {
        let bridge = self.bridge.clone();
        let tab_id = tab_id.to_owned();
        cx.spawn(async move |this, cx| {
            let result = bridge
                .request("codex.response", json!({"tabId": tab_id, "requestId": request_id, "result": result_value}))
                .await;
            if let Some(this) = this.upgrade() {
                this.update(cx, |this, cx| {
                    if let Err(error) = result {
                        this.codex_error = Some(error.into());
                    }
                    cx.notify();
                });
            }
        })
        .detach();
    }
}

fn snapshot_events(snapshot: &Value) -> Vec<&Value> {
    snapshot
        .get("events")
        .and_then(Value::as_array)
        .map(|events| events.iter().collect())
        .unwrap_or_default()
}

fn snapshot_cells(snapshot: &Value) -> Vec<Value> {
    snapshot
        .get("timelineCells")
        .and_then(Value::as_array)
        .cloned()
        .unwrap_or_default()
}

fn codex_cell_label(kind: &str) -> &'static str {
    match kind {
        "userMessage" => "You",
        "assistantMessage" => "Codex",
        "progressText" => "Progress",
        "reasoning" => "Reasoning",
        "toolCall" => "Tool",
        "command" => "Command",
        "diff" => "Diff",
        "subAgent" => "Sub-Agent",
        "plan" => "Plan",
        "turnSeparator" => "Turn",
        "systemNotice" => "Notice",
        "questionAnswer" => "Answer",
        _ => "Event",
    }
}

fn snapshot_pending(snapshot: &Value) -> Vec<Value> {
    snapshot
        .get("pendingRequests")
        .and_then(Value::as_array)
        .cloned()
        .unwrap_or_default()
}

fn active_codex_turn(snapshot: &Value) -> Option<String> {
    snapshot
        .get("activeTurnId")
        .and_then(Value::as_str)
        .filter(|value| !value.is_empty())
        .map(str::to_owned)
}

fn expand_saved_prompt(
    input: &str,
    prompts: &[alera_native::api::workspace_files::CodexSavedPrompt],
) -> String {
    let trimmed = input.trim();
    let Some(rest) = trimmed.strip_prefix('/') else {
        return input.to_owned();
    };
    let mut parts = rest.splitn(2, char::is_whitespace);
    let name = parts.next().unwrap_or_default();
    let arguments = parts.next().unwrap_or_default().trim();
    let Some(prompt) = prompts
        .iter()
        .find(|prompt| prompt.name.eq_ignore_ascii_case(name))
    else {
        return input.to_owned();
    };
    let positional = arguments
        .split_whitespace()
        .map(str::to_owned)
        .collect::<Vec<_>>();
    let mut rendered = String::with_capacity(prompt.body.len() + arguments.len());
    let mut chars = prompt.body.chars().peekable();
    while let Some(character) = chars.next() {
        if character != '$' {
            rendered.push(character);
            continue;
        }
        if chars.peek() == Some(&'$') {
            chars.next();
            rendered.push('$');
            continue;
        }
        let mut token = String::new();
        while let Some(next) = chars.peek().copied() {
            if next.is_ascii_alphanumeric() || next == '_' || next == '-' {
                token.push(next);
                chars.next();
            } else {
                break;
            }
        }
        if token.eq_ignore_ascii_case("ARGUMENTS") {
            rendered.push_str(arguments);
        } else if let Ok(index) = token.parse::<usize>() {
            if let Some(value) = positional.get(index.saturating_sub(1)) {
                rendered.push_str(value);
            }
        } else if !token.is_empty() {
            if let Some((_, value)) = arguments.split_whitespace().find_map(|argument| {
                argument
                    .split_once('=')
                    .filter(|(key, _)| key.eq_ignore_ascii_case(&token))
            }) {
                rendered.push_str(value);
            }
        } else {
            rendered.push('$');
        }
    }
    rendered.trim().to_owned()
}

fn item_id(item: &Value) -> Option<String> {
    item.get("id")
        .or_else(|| item.get("model"))
        .or_else(|| item.get("name"))
        .and_then(Value::as_str)
        .map(str::to_owned)
}

fn item_label(item: &Value) -> Option<String> {
    item.get("displayName")
        .or_else(|| item.get("name"))
        .or_else(|| item.get("id"))
        .and_then(Value::as_str)
        .map(str::to_owned)
}

fn codex_items(value: &Value) -> Vec<Value> {
    value
        .get("data")
        .or_else(|| value.get("items"))
        .or_else(|| value.get("models"))
        .and_then(Value::as_array)
        .cloned()
        .unwrap_or_default()
}

fn event_text(event: &Value) -> Option<String> {
    for candidate in [
        event.pointer("/params/delta"),
        event.pointer("/params/text"),
        event.pointer("/params/item/text"),
        event.pointer("/params/item/content"),
        event.pointer("/params/item/message"),
        event.get("result"),
    ] {
        if let Some(text) = candidate.and_then(Value::as_str).filter(|text| !text.is_empty()) {
            return Some(text.to_owned());
        }
    }
    None
}

fn codex_event_label(method: &str, event: &Value) -> &'static str {
    let item_type = event
        .pointer("/params/item/type")
        .and_then(Value::as_str)
        .unwrap_or_default()
        .to_ascii_lowercase();
    if item_type.contains("user") || method.contains("user") {
        "You"
    } else if item_type.contains("agent") || item_type.contains("assistant") || method.contains("agentmessage") {
        "Codex"
    } else if method.contains("reason") {
        "Reasoning"
    } else if method.contains("command") {
        "Command"
    } else if method.contains("tool") {
        "Tool"
    } else if method.contains("plan") {
        "Plan"
    } else {
        "Event"
    }
}

fn request_text(params: &Value, method: &str) -> String {
    params
        .get("command")
        .or_else(|| params.get("question"))
        .or_else(|| params.get("reason"))
        .and_then(Value::as_str)
        .unwrap_or(method)
        .to_owned()
}

fn approval_decisions(params: &Value) -> Vec<(String, &'static str, ButtonKind)> {
    let values = params
        .get("availableDecisions")
        .and_then(Value::as_array)
        .map(|values| {
            values
                .iter()
                .filter_map(|value| {
                    value
                        .as_str()
                        .map(str::to_owned)
                        .or_else(|| value.as_object()?.keys().next().cloned())
                })
                .collect::<Vec<_>>()
        })
        .filter(|values| !values.is_empty())
        .unwrap_or_else(|| vec!["accept".to_owned(), "acceptForSession".to_owned(), "decline".to_owned()]);
    values
        .into_iter()
        .map(|decision| {
            let (label, kind) = match decision.as_str() {
                "accept" => ("Allow Once", ButtonKind::Filled),
                "acceptForSession" => ("Allow For Session", ButtonKind::Text),
                "acceptWithExecpolicyAmendment" => {
                    ("Allow Matching Commands", ButtonKind::Text)
                }
                "applyNetworkPolicyAmendment" => ("Apply Network Rule", ButtonKind::Text),
                "cancel" => ("Cancel Turn", ButtonKind::Outlined),
                "decline" => ("Decline", ButtonKind::Outlined),
                _ => ("Respond", ButtonKind::Text),
            };
            (decision, label, kind)
        })
        .collect()
}

fn approval_result(params: &Value, method: &str, decision: &str) -> Value {
    if !method.contains("permission") {
        return json!({"decision": decision});
    }
    let accepted = decision.starts_with("accept");
    json!({
        "permissions": if accepted {
            params.get("permissions").cloned().unwrap_or_else(|| json!({}))
        } else {
            json!({})
        },
        "scope": if decision == "acceptForSession" { "session" } else { "turn" },
    })
}

#[cfg(test)]
mod tests {
    use super::{active_codex_turn, codex_event_label};

    #[test]
    fn reads_active_turn_and_labels_events() {
        let snapshot = serde_json::json!({"activeTurnId": "turn-1"});
        assert_eq!(active_codex_turn(&snapshot).as_deref(), Some("turn-1"));
        assert_eq!(codex_event_label("turn/started", &snapshot), "Event");
    }
}
