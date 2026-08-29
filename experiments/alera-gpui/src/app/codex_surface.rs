use std::time::Duration;

use gpui::{
    div, prelude::FluentBuilder as _, px, AnyElement, AppContext as _, Context, CursorStyle,
    Entity, InteractiveElement as _, IntoElement, KeyDownEvent, MouseButton,
    ParentElement as _, Role, SharedString, StatefulInteractiveElement as _, Styled as _, Window,
};
use gpui_component::input::{InputEvent, Textarea, TextareaState};
use gpui_component::scroll::ScrollableElement as _;
use serde_json::{json, Value};

use super::AleraApp;
use crate::design_system::{self, ButtonKind};
use crate::icons::{loading_indicator, AleraIcon};
use crate::model::WorkspaceTab;
use crate::theme;

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
            if !self.codex_snapshots.contains_key(&tab_id)
                && !self.codex_opening_tabs.contains(&tab_id)
            {
                self.open_codex_thread(tab_id, cx);
            }
            if !self.codex_catalogs_loaded && !self.codex_catalogs_loading {
                self.load_codex_catalogs(tab_id, cx);
            }
        }
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
        div()
            .id(SharedString::from(format!("codex-surface-{tab_id}")))
            .flex()
            .flex_col()
            .flex_1()
            .min_h_0()
            .bg(theme::app_background())
            .child(self.render_codex_header(&tab_id, cx))
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
            .when_some(input, |surface, input| {
                surface.child(self.render_codex_composer(&tab_id, input, busy, cx))
            })
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
                    .on_click(cx.listener(|this, _, _, cx| {
                        this.codex_plan_mode = !this.codex_plan_mode;
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
            "collaboration" => {
                self.codex_collaboration_mode = Some(value.to_owned());
                self.codex_plan_mode = value.eq_ignore_ascii_case("plan");
            }
            _ => {}
        }
        self.codex_menu_open = None;
        cx.notify();
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
            let title = cell
                .get("title")
                .and_then(Value::as_str)
                .unwrap_or_else(|| codex_cell_label(kind))
                .to_owned();
            let body = cell
                .get("markdownText")
                .and_then(Value::as_str)
                .or_else(|| cell.get("detailsText").and_then(Value::as_str))
                .unwrap_or_default()
                .to_owned();
            let subtitle = cell
                .get("subtitle")
                .and_then(Value::as_str)
                .map(str::to_owned);
            let streaming = cell
                .get("isStreaming")
                .and_then(Value::as_bool)
                .unwrap_or(false);
            content = content.child(
                div()
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
                            .flex()
                            .items_center()
                            .gap_1()
                            .font_weight(gpui::FontWeight::SEMIBOLD)
                            .text_size(px(11.0))
                            .text_color(theme::text_muted())
                            .child(title)
                            .when(streaming, |row| {
                                row.child(loading_indicator(12.0, theme::text_faint()))
                            }),
                    )
                    .when_some(subtitle, |card, subtitle| {
                        card.child(
                            div()
                                .mt_1()
                                .text_xs()
                                .text_color(theme::text_faint())
                                .child(subtitle),
                        )
                    })
                    .when(!body.is_empty(), |card| {
                        card.child(
                            div()
                                .mt_1()
                                .whitespace_normal()
                                .text_size(px(12.0))
                                .child(body),
                        )
                    }),
            );
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
                    .child(
                        div()
                            .flex()
                            .gap_2()
                            .mt_2()
                            .child(
                                design_system::button(
                                    SharedString::from(format!("codex-decline-{index}")),
                                    if is_approval { "Decline" } else { "Cancel" },
                                    ButtonKind::Outlined,
                                    false,
                                )
                                .on_click(cx.listener({
                                    let tab_id = tab_id.to_owned();
                                    move |this, _, _, cx| {
                                        this.respond_codex_request(
                                            &tab_id,
                                            request_id_for_click.clone(),
                                            json!({"decision": "decline"}),
                                            cx,
                                        );
                                    }
                                })),
                            )
                            .when(is_approval, |actions| {
                                actions.child(
                                    design_system::button(
                                        SharedString::from(format!("codex-approve-{index}")),
                                        "Approve",
                                        ButtonKind::Filled,
                                        false,
                                    )
                                    .on_click(cx.listener({
                                        let tab_id = tab_id.to_owned();
                                        let request_id = request_id.clone();
                                        move |this, _, _, cx| {
                                            this.respond_codex_request(
                                                &tab_id,
                                                request_id.clone(),
                                                json!({"decision": "accept"}),
                                                cx,
                                            );
                                        }
                                    })),
                                )
                            }),
                    ),
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
        let model = self.codex_selected_model.clone();
        let reasoning = self.codex_reasoning_effort.clone();
        let speed = self.codex_speed_mode.clone();
        let permission = self.codex_permission_mode.clone();
        let plan = self.codex_plan_mode;
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
                        "input": [{"type": "text", "text": text}],
                        "model": model,
                        "reasoning": {"effort": reasoning},
                        "effort": reasoning,
                        "serviceTier": (speed == "fast").then_some("fast"),
                        "approvalPolicy": permission,
                        "collaborationMode": collaboration_mode.map(|mode| json!({"mode": mode})),
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
