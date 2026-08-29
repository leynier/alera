use gpui::{
    div, prelude::FluentBuilder as _, px, AnyElement, Context, CursorStyle, Entity,
    InteractiveElement as _, IntoElement, ParentElement as _, Role, SharedString,
    StatefulInteractiveElement as _, Styled as _, Toggled, Window,
};
use gpui_component::input::{InputState, Textarea};
use gpui_component::scroll::ScrollableElement as _;
use serde_json::{json, Map, Value};
use uuid::Uuid;

use super::AleraApp;
use crate::design_system::{self, ButtonKind};
use crate::icons::{icon, loading_indicator, AleraIcon};
use crate::theme;

const AUTOMATION_FINAL_RUN_STATUSES: &[&str] = &[
    "success",
    "failure",
    "blocked",
    "timeout",
    "cancelled",
    "precheckSkipped",
    "misfireSkipped",
    "overlapSkipped",
    "queueLimitSkipped",
];

impl AleraApp {
    pub(crate) fn open_automations_dialog(&mut self, window: &mut Window, cx: &mut Context<Self>) {
        self.show_automations_dialog = true;
        self.automations_error = None;
        self.automation_detail = None;
        self.automation_selected_id = None;
        self.automation_state_filter = None;
        self.automation_include_trashed = false;
        self.automation_search_input
            .update(cx, |input, cx| input.set_value("", window, cx));
        self.load_automations(cx);
        cx.notify();
    }

    pub(crate) fn close_automations_dialog(&mut self, cx: &mut Context<Self>) {
        self.show_automations_dialog = false;
        self.automation_editor_open = false;
        self.automation_editor_error = None;
        self.automations_error = None;
        cx.notify();
    }

    pub(super) fn load_automations(&mut self, cx: &mut Context<Self>) {
        if self.automations_loading {
            return;
        }
        self.automations_loading = true;
        self.automations_error = None;
        let bridge = self.bridge.clone();
        let include_trashed = self.automation_include_trashed;
        let search = self
            .automation_search_input
            .read(cx)
            .value()
            .trim()
            .to_owned();
        cx.spawn(async move |this, cx| {
            let result = bridge
                .request(
                    "automation.list",
                    json!({
                        "includeTrashed": include_trashed,
                        "search": if search.is_empty() { Value::Null } else { Value::String(search) },
                    }),
                )
                .await;
            let Some(this) = this.upgrade() else {
                return;
            };
            this.update(cx, |this, cx| {
                this.automations_loading = false;
                match result {
                    Ok(payload) => {
                        this.automations = payload
                            .get("items")
                            .and_then(Value::as_array)
                            .cloned()
                            .unwrap_or_default();
                        let selected = this.automation_selected_id.clone();
                        let selected = selected.filter(|id| {
                            this.automations
                                .iter()
                                .any(|item| value_string(item, "id").as_deref() == Some(id))
                        });
                        this.automation_selected_id = selected.or_else(|| {
                            this.automations
                                .first()
                                .and_then(|item| value_string(item, "id"))
                        });
                        if let Some(id) = this.automation_selected_id.clone() {
                            this.load_automation_detail(id, cx);
                        } else {
                            this.automation_detail = None;
                        }
                    }
                    Err(error) => this.automations_error = Some(error.into()),
                }
                cx.notify();
            });
        })
        .detach();
    }

    fn load_automation_detail(&mut self, id: String, cx: &mut Context<Self>) {
        self.automation_selected_id = Some(id.clone());
        self.automation_detail_loading = true;
        let bridge = self.bridge.clone();
        cx.spawn(async move |this, cx| {
            let result = bridge.request("automation.show", json!({"id": id})).await;
            let Some(this) = this.upgrade() else {
                return;
            };
            this.update(cx, |this, cx| {
                this.automation_detail_loading = false;
                match result {
                    Ok(value) => this.automation_detail = Some(value),
                    Err(error) => this.automations_error = Some(error.into()),
                }
                cx.notify();
            });
        })
        .detach();
        cx.notify();
    }

    fn run_automation_request(
        &mut self,
        request: &'static str,
        payload: Value,
        message: &'static str,
        cx: &mut Context<Self>,
    ) {
        if self.automation_action_busy {
            return;
        }
        self.automation_action_busy = true;
        self.automations_error = None;
        let bridge = self.bridge.clone();
        let selected = self.automation_selected_id.clone();
        cx.spawn(async move |this, cx| {
            let result = bridge.request(request, payload).await;
            let Some(this) = this.upgrade() else {
                return;
            };
            this.update(cx, |this, cx| {
                this.automation_action_busy = false;
                match result {
                    Ok(_) => {
                        this.local_message = Some(message.into());
                        this.local_message_started_at = Some(std::time::Instant::now());
                        this.load_automations(cx);
                        if let Some(id) = selected {
                            this.load_automation_detail(id, cx);
                        }
                    }
                    Err(error) => this.automations_error = Some(error.into()),
                }
                cx.notify();
            });
        })
        .detach();
        cx.notify();
    }

    fn open_automation_editor(
        &mut self,
        initial: Option<Value>,
        window: &mut Window,
        cx: &mut Context<Self>,
    ) {
        let automation = initial
            .as_ref()
            .and_then(|value| value.get("automation"))
            .or(initial.as_ref());
        self.automation_editor_id = automation.and_then(|value| value_string(value, "id"));
        set_input_value(
            &self.automation_editor_name_input,
            automation
                .and_then(|value| value_string(value, "name"))
                .unwrap_or_else(|| "Daily Automation".to_owned()),
            window,
            cx,
        );
        set_input_value(
            &self.automation_editor_slug_input,
            automation
                .and_then(|value| value_string(value, "slug"))
                .unwrap_or_else(|| "daily-automation".to_owned()),
            window,
            cx,
        );
        set_input_value(
            &self.automation_editor_description_input,
            automation
                .and_then(|value| value_string(value, "description"))
                .unwrap_or_default(),
            window,
            cx,
        );
        set_input_value(
            &self.automation_editor_cron_input,
            automation
                .and_then(|value| nested_string(value, "schedule", "recurring", "cron"))
                .unwrap_or_else(|| "0 9 * * 1-5".to_owned()),
            window,
            cx,
        );
        set_input_value(
            &self.automation_editor_workspace_input,
            automation
                .and_then(|value| target_string(value, &["workspaceId", "sourceWorkspaceId"]))
                .or_else(|| self.selected_workspace_id.clone())
                .unwrap_or_default(),
            window,
            cx,
        );
        set_input_value(
            &self.automation_editor_profile_input,
            automation
                .and_then(|value| target_string(value, &["agentProfileId"]))
                .or_else(|| self.settings_state.default_agent_profile_id.clone())
                .unwrap_or_default(),
            window,
            cx,
        );
        let prompt = automation
            .and_then(|value| value_string(value, "promptTemplate"))
            .unwrap_or_else(|| "Review the current workspace and report the result.".to_owned());
        self.automation_editor_prompt_input
            .update(cx, |input, cx| input.set_value(prompt, window, cx));
        self.automation_editor_error = None;
        self.automation_editor_open = true;
        cx.notify();
    }

    fn save_automation_editor(&mut self, _window: &mut Window, cx: &mut Context<Self>) {
        let name = self
            .automation_editor_name_input
            .read(cx)
            .value()
            .trim()
            .to_owned();
        let slug = self
            .automation_editor_slug_input
            .read(cx)
            .value()
            .trim()
            .to_owned();
        let prompt = self
            .automation_editor_prompt_input
            .read(cx)
            .value()
            .trim()
            .to_owned();
        let workspace_id = self
            .automation_editor_workspace_input
            .read(cx)
            .value()
            .trim()
            .to_owned();
        let profile_id = self
            .automation_editor_profile_input
            .read(cx)
            .value()
            .trim()
            .to_owned();
        if name.is_empty() || slug.is_empty() || prompt.is_empty() {
            self.automation_editor_error =
                Some("Name, slug, and prompt template are required.".into());
            cx.notify();
            return;
        }
        if workspace_id.is_empty() || profile_id.is_empty() {
            self.automation_editor_error =
                Some("A workspace and agent profile are required for a fresh tab target.".into());
            cx.notify();
            return;
        }
        let cron = self
            .automation_editor_cron_input
            .read(cx)
            .value()
            .trim()
            .to_owned();
        let description = self
            .automation_editor_description_input
            .read(cx)
            .value()
            .trim()
            .to_owned();
        let now = format_timestamp();
        let id = self
            .automation_editor_id
            .clone()
            .unwrap_or_else(|| Uuid::new_v4().to_string());
        let existing = self
            .automation_detail
            .as_ref()
            .and_then(|detail| detail.get("automation"))
            .cloned()
            .unwrap_or_else(|| json!({}));
        let mut definition = existing.as_object().cloned().unwrap_or_default();
        definition.insert("id".into(), Value::String(id.clone()));
        definition.insert("slug".into(), Value::String(slug));
        definition.insert("name".into(), Value::String(name));
        definition.insert("description".into(), Value::String(description));
        definition.insert("promptTemplate".into(), Value::String(prompt));
        definition.insert(
            "schedule".into(),
            json!({"recurring": {"cron": cron, "timezone": "UTC"}}),
        );
        definition.insert(
            "target".into(),
            json!({"freshTab": {"workspaceId": workspace_id, "agentProfileId": profile_id}}),
        );
        definition.entry("projectId").or_insert(Value::Null);
        definition.entry("tagIds").or_insert(json!([]));
        definition.entry("setupPolicy").or_insert(json!("wait"));
        definition
            .entry("cleanupPolicy")
            .or_insert(json!("preserve"));
        definition.entry("overlapPolicy").or_insert(json!("skip"));
        definition.entry("queueCap").or_insert(json!(10));
        definition
            .entry("inactivityTimeoutSeconds")
            .or_insert(json!(7200));
        definition
            .entry("heartbeatIntervalSeconds")
            .or_insert(json!(60));
        definition
            .entry("misfireGraceSeconds")
            .or_insert(json!(900));
        definition.entry("misfirePolicy").or_insert(json!("skip"));
        definition.entry("retryMaxAttempts").or_insert(json!(3));
        definition.entry("retryBackoffSeconds").or_insert(json!(60));
        definition
            .entry("circuitFailureThreshold")
            .or_insert(json!(3));
        definition.entry("circuitOpenSeconds").or_insert(json!(900));
        definition.entry("precheck").or_insert(Value::Null);
        definition.entry("notifyOnSuccess").or_insert(json!(false));
        definition.entry("state").or_insert(json!("draft"));
        definition.entry("revision").or_insert(json!(0));
        definition.entry("approvedRevision").or_insert(Value::Null);
        definition
            .entry("createdBy")
            .or_insert(json!({"kind": "humanDesktop"}));
        definition
            .entry("modifiedBy")
            .or_insert(json!({"kind": "humanDesktop"}));
        definition.entry("createdAt").or_insert(json!(now.clone()));
        definition.insert("updatedAt".into(), json!(now));
        self.automation_action_busy = true;
        self.automation_editor_error = None;
        self.automation_editor_open = false;
        let bridge = self.bridge.clone();
        cx.spawn(async move |this, cx| {
            let result = bridge
                .request("automation.upsert", json!({"automation": definition}))
                .await;
            let Some(this) = this.upgrade() else {
                return;
            };
            this.update(cx, |this, cx| {
                this.automation_action_busy = false;
                match result {
                    Ok(value) => {
                        this.automation_selected_id = value_string(&value, "id");
                        this.local_message = Some("Automation saved".into());
                        this.local_message_started_at = Some(std::time::Instant::now());
                        this.load_automations(cx);
                        if let Some(id) = this.automation_selected_id.clone() {
                            this.load_automation_detail(id, cx);
                        }
                    }
                    Err(error) => {
                        this.automation_editor_open = true;
                        this.automation_editor_error = Some(error.into());
                    }
                }
                cx.notify();
            });
        })
        .detach();
        cx.notify();
    }

    fn selected_automation(&self) -> Option<&Value> {
        let id = self.automation_selected_id.as_deref()?;
        self.automations
            .iter()
            .find(|automation| value_string(automation, "id").as_deref() == Some(id))
    }

    fn clone_selected_automation(&mut self, window: &mut Window, cx: &mut Context<Self>) {
        let Some(automation) = self.selected_automation().cloned() else {
            return;
        };
        let mut clone = automation.as_object().cloned().unwrap_or_default();
        clone.insert("id".into(), Value::String(Uuid::new_v4().to_string()));
        clone.insert(
            "slug".into(),
            Value::String(format!(
                "{}-copy",
                value_string(&automation, "slug").unwrap_or_default()
            )),
        );
        clone.insert(
            "name".into(),
            Value::String(format!(
                "{} Copy",
                value_string(&automation, "name").unwrap_or_default()
            )),
        );
        clone.insert("state".into(), json!("draft"));
        clone.insert("revision".into(), json!(0));
        clone.insert("approvedRevision".into(), Value::Null);
        self.open_automation_editor(Some(Value::Object(clone)), window, cx);
    }

    fn automation_export(&mut self, cx: &mut Context<Self>) {
        let bridge = self.bridge.clone();
        cx.spawn(async move |this, cx| {
            let result = bridge.request("automation.export", json!({})).await;
            let Some(this) = this.upgrade() else {
                return;
            };
            this.update(cx, |this, cx| {
                match result {
                    Ok(bundle) => {
                        cx.write_to_clipboard(gpui::ClipboardItem::new_string(bundle.to_string()));
                        this.local_message = Some("Automation catalog copied to clipboard".into());
                        this.local_message_started_at = Some(std::time::Instant::now());
                    }
                    Err(error) => this.automations_error = Some(error.into()),
                }
                cx.notify();
            });
        })
        .detach();
    }

    fn automation_import(&mut self, cx: &mut Context<Self>) {
        let Some(text) = cx.read_from_clipboard().and_then(|item| item.text()) else {
            self.automations_error =
                Some("The clipboard does not contain an automation catalog.".into());
            cx.notify();
            return;
        };
        let bundle: Value = match serde_json::from_str::<Value>(&text) {
            Ok(value) if value.is_object() => value,
            _ => {
                self.automations_error = Some("Catalog JSON must be an object.".into());
                cx.notify();
                return;
            }
        };
        let bridge = self.bridge.clone();
        self.automation_action_busy = true;
        cx.spawn(async move |this, cx| {
            let result = bridge
                .request("automation.import", json!({"bundle": bundle, "remap": {}}))
                .await;
            let Some(this) = this.upgrade() else {
                return;
            };
            this.update(cx, |this, cx| {
                this.automation_action_busy = false;
                match result {
                    Ok(_) => {
                        this.local_message = Some("Automation catalog imported as drafts".into());
                        this.local_message_started_at = Some(std::time::Instant::now());
                        this.load_automations(cx);
                    }
                    Err(error) => this.automations_error = Some(error.into()),
                }
                cx.notify();
            });
        })
        .detach();
    }

    pub(super) fn render_automations_dialog(&self, cx: &mut Context<Self>) -> AnyElement {
        let content = if self.automation_editor_open {
            self.render_automation_editor(cx)
        } else {
            self.render_automation_catalog(cx)
        };
        div()
            .absolute()
            .inset_0()
            .occlude()
            .flex()
            .items_center()
            .justify_center()
            .bg(theme::overlay_scrim())
            .on_mouse_down(
                gpui::MouseButton::Left,
                cx.listener(|this, _, _, cx| {
                    this.close_automations_dialog(cx);
                }),
            )
            .child(
                div()
                    .id("automations-dialog")
                    .role(Role::Dialog)
                    .aria_label("Automations")
                    .w(px(1180.0))
                    .h(px(680.0))
                    .max_w(px(1180.0))
                    .max_h(px(760.0))
                    .flex()
                    .flex_col()
                    .rounded_xl()
                    .border_1()
                    .border_color(theme::border_subtle())
                    .bg(theme::surface())
                    .shadow_lg()
                    .p_5()
                    .on_mouse_down(gpui::MouseButton::Left, |_, _, cx| cx.stop_propagation())
                    .child(content),
            )
            .into_any_element()
    }

    fn render_automation_catalog(&self, cx: &mut Context<Self>) -> AnyElement {
        let query = self
            .automation_search_input
            .read(cx)
            .value()
            .trim()
            .to_lowercase();
        let visible: Vec<Value> = self
            .automations
            .iter()
            .filter(|item| {
                let state = value_string(item, "state").unwrap_or_else(|| "draft".into());
                let name = value_string(item, "name")
                    .unwrap_or_default()
                    .to_lowercase();
                let slug = value_string(item, "slug")
                    .unwrap_or_default()
                    .to_lowercase();
                let description = value_string(item, "description")
                    .unwrap_or_default()
                    .to_lowercase();
                (self.automation_state_filter.is_none()
                    || self.automation_state_filter.as_deref() == Some(state.as_str()))
                    && (query.is_empty()
                        || name.contains(&query)
                        || slug.contains(&query)
                        || description.contains(&query))
            })
            .cloned()
            .collect();
        div()
            .flex()
            .flex_col()
            .flex_1()
            .min_h_0()
            .child(
                div()
                    .flex()
                    .items_center()
                    .gap_2()
                    .child(icon(AleraIcon::Workflow, 18.0, theme::text_muted()))
                    .child(
                        div()
                            .flex_1()
                            .text_lg()
                            .font_weight(gpui::FontWeight::SEMIBOLD)
                            .child("Automations"),
                    )
                    .child(
                        design_system::button_with_leading_icon(
                            "automation-new",
                            "New Automation",
                            ButtonKind::Filled,
                            self.automation_action_busy,
                            icon(AleraIcon::Add, 14.0, theme::on_accent()),
                        )
                        .on_click(cx.listener(|this, _, window, cx| {
                            this.open_automation_editor(None, window, cx);
                        })),
                    )
                    .child(
                        design_system::icon_button(
                            "automation-import",
                            "Import",
                            AleraIcon::Download,
                            !self.automation_action_busy,
                            30.0,
                            None,
                            None,
                        )
                        .on_click(cx.listener(|this, _, _, cx| this.automation_import(cx))),
                    )
                    .child(
                        design_system::icon_button(
                            "automation-export",
                            "Export",
                            AleraIcon::External,
                            !self.automation_action_busy,
                            30.0,
                            None,
                            None,
                        )
                        .on_click(cx.listener(|this, _, _, cx| this.automation_export(cx))),
                    )
                    .child(
                        design_system::icon_button(
                            "automation-close",
                            "Close",
                            AleraIcon::Close,
                            true,
                            30.0,
                            None,
                            None,
                        )
                        .on_click(cx.listener(|this, _, _, cx| this.close_automations_dialog(cx))),
                    ),
            )
            .child(
                div()
                    .mt_4()
                    .flex()
                    .items_center()
                    .gap_2()
                    .child(
                        div()
                            .flex_1()
                            .child(design_system::search_field(&self.automation_search_input, false)),
                    )
                    .child(self.automation_filter_button("All States", None, cx))
                    .child(self.automation_filter_button("Draft", Some("draft"), cx))
                    .child(self.automation_filter_button("Active", Some("active"), cx))
                    .child(self.automation_filter_button("Paused", Some("paused"), cx))
                    .child(
                        div()
                            .id("automation-trash-filter")
                            .focusable()
                            .tab_stop(true)
                            .role(Role::CheckBox)
                            .aria_label("Include Trash")
                            .aria_toggled(if self.automation_include_trashed {
                                Toggled::True
                            } else {
                                Toggled::False
                            })
                            .flex()
                            .items_center()
                            .gap_1()
                            .cursor(CursorStyle::PointingHand)
                            .on_click(cx.listener(|this, _, _, cx| {
                                this.automation_include_trashed = !this.automation_include_trashed;
                                this.load_automations(cx);
                            }))
                            .child(design_system::checkbox(self.automation_include_trashed, true, None))
                            .child("Trash"),
                    ),
            )
            .child(
                div()
                    .mt_4()
                    .flex()
                    .flex_1()
                    .min_h_0()
                    .gap_4()
                    .child(
                        div()
                            .w(px(330.0))
                            .flex_shrink_0()
                            .min_h_0()
                            .overflow_y_scrollbar()
                            .rounded_lg()
                            .border_1()
                            .border_color(theme::border_subtle())
                            .bg(theme::surface_selected())
                            .when(self.automations_loading && self.automations.is_empty(), |list| {
                                list.flex().items_center().justify_center().child(loading_indicator(22.0, theme::text_muted()))
                            })
                            .when(!self.automations_loading || !self.automations.is_empty(), |list| {
                                let rows = visible
                                    .iter()
                                    .map(|item| self.render_automation_list_row(item, cx))
                                    .collect::<Vec<_>>();
                                list.children(rows)
                            })
                            .when(self.automations.is_empty() && !self.automations_loading, |list| {
                                list.child(automation_empty_state("No Automations", "Create a schedule to run approved work in a runtime-owned target."))
                            }),
                    )
                    .child(div().w(px(1.0)).h_full().bg(theme::border_subtle()))
                    .child(div().flex_1().min_w_0().min_h_0().child(self.render_automation_detail(cx))),
            )
            .when_some(self.automations_error.clone(), |catalog, error| {
                catalog.child(div().mt_2().text_sm().text_color(theme::danger()).child(error))
            })
            .into_any_element()
    }

    fn automation_filter_button(
        &self,
        label: &'static str,
        state: Option<&'static str>,
        cx: &mut Context<Self>,
    ) -> gpui::Stateful<gpui::Div> {
        let selected = self.automation_state_filter.as_deref() == state;
        design_system::button(
            SharedString::from(format!("automation-filter-{label}")),
            label,
            if selected {
                ButtonKind::Elevated
            } else {
                ButtonKind::Text
            },
            false,
        )
        .on_click(cx.listener(move |this, _, _, cx| {
            this.automation_state_filter = state.map(str::to_owned);
            this.load_automations(cx);
        }))
    }

    fn render_automation_list_row(
        &self,
        item: &Value,
        cx: &mut Context<Self>,
    ) -> gpui::Stateful<gpui::Div> {
        let id = value_string(item, "id").unwrap_or_default();
        let selected = self.automation_selected_id.as_deref() == Some(id.as_str());
        let approved = value_i64(item, "approvedRevision")
            .is_some_and(|revision| value_i64(item, "revision") == Some(revision));
        let name = value_string(item, "name").unwrap_or_else(|| "Automation".into());
        let state = value_string(item, "state").unwrap_or_else(|| "draft".into());
        let schedule = if item
            .get("schedule")
            .and_then(|value| value.get("recurring"))
            .is_some()
        {
            "Recurring"
        } else {
            "One-time"
        };
        div()
            .id(SharedString::from(format!("automation-row-{id}")))
            .focusable()
            .tab_stop(true)
            .role(Role::ListItem)
            .aria_label(name.clone())
            .flex()
            .items_center()
            .gap_2()
            .p_3()
            .border_b_1()
            .border_color(theme::border_subtle())
            .bg(if selected {
                theme::accent_subtle()
            } else {
                theme::transparent()
            })
            .cursor(CursorStyle::PointingHand)
            .hover(|style| style.bg(theme::surface_raised()))
            .on_click(cx.listener(move |this, _, _, cx| {
                this.load_automation_detail(id.clone(), cx);
            }))
            .child(icon(
                if approved {
                    AleraIcon::CheckCheck
                } else {
                    AleraIcon::Warning
                },
                15.0,
                if approved {
                    theme::success()
                } else {
                    theme::warning()
                },
            ))
            .child(
                div()
                    .flex_1()
                    .min_w_0()
                    .child(
                        div()
                            .overflow_hidden()
                            .whitespace_nowrap()
                            .text_size(px(13.0))
                            .child(name),
                    )
                    .child(
                        div()
                            .mt(px(2.0))
                            .text_size(px(11.0))
                            .text_color(theme::text_muted())
                            .child(format!("{state} · {schedule}")),
                    ),
            )
    }

    fn render_automation_detail(&self, cx: &mut Context<Self>) -> AnyElement {
        let Some(detail) = self.automation_detail.as_ref() else {
            return automation_empty_state(
                "Select An Automation",
                "Choose an automation to inspect its schedule, target, and runs.",
            );
        };
        let Some(automation) = detail.get("automation") else {
            return automation_empty_state(
                "Automation Unavailable",
                "The runtime returned no automation definition.",
            );
        };
        if self.automation_detail_loading {
            return div()
                .flex()
                .flex_1()
                .items_center()
                .justify_center()
                .child(loading_indicator(22.0, theme::text_muted()))
                .into_any_element();
        }
        let id = value_string(automation, "id").unwrap_or_default();
        let name = value_string(automation, "name").unwrap_or_else(|| "Automation".into());
        let state = value_string(automation, "state").unwrap_or_else(|| "draft".into());
        let revision = value_i64(automation, "revision").unwrap_or_default();
        let approved = value_i64(automation, "approvedRevision") == Some(revision);
        let can_pause = state == "active";
        let can_resume = state == "paused";
        let runs = detail
            .get("runs")
            .and_then(Value::as_array)
            .cloned()
            .unwrap_or_default();
        let audit = detail
            .get("audit")
            .and_then(Value::as_array)
            .cloned()
            .unwrap_or_default();
        let id_for_refresh = id.clone();
        let id_for_edit = id.clone();
        let id_for_approve = id.clone();
        let id_for_run = id.clone();
        let id_for_pause = id.clone();
        let id_for_resume = id.clone();
        let id_for_trash = id.clone();
        let id_for_restore = id.clone();
        div()
            .id("automation-detail")
            .flex()
            .flex_col()
            .size_full()
            .min_h_0()
            .child(
                div()
                    .flex()
                    .items_center()
                    .gap_2()
                    .child(div().flex_1().text_lg().font_weight(gpui::FontWeight::SEMIBOLD).child(name))
                    .child(div().text_sm().text_color(theme::text_muted()).child(state.clone()))
                    .child(design_system::icon_button("automation-refresh", "Refresh", AleraIcon::Refresh, true, 28.0, None, None).on_click(cx.listener(move |this, _, _, cx| this.load_automation_detail(id_for_refresh.clone(), cx))))
                    .child(design_system::icon_button("automation-edit", "Edit", AleraIcon::Edit, !self.automation_action_busy, 28.0, None, None).on_click(cx.listener(move |this, _, window, cx| {
                        if let Some(detail) = this.automation_detail.clone() { this.open_automation_editor(Some(detail), window, cx); }
                        let _ = &id_for_edit;
                    })))
                    .child(design_system::icon_button("automation-clone", "Clone", AleraIcon::Duplicate, !self.automation_action_busy, 28.0, None, None).on_click(cx.listener(|this, _, window, cx| this.clone_selected_automation(window, cx)))),
            )
            .child(
                div()
                    .mt_3()
                    .flex()
                    .gap_2()
                    .children([
                        approved.then(|| design_system::button_with_leading_icon("automation-approved", "Approved", ButtonKind::Outlined, true, icon(AleraIcon::CheckCheck, 14.0, theme::success()))),
                        (!approved).then(|| design_system::button_with_leading_icon("automation-approve", "Approve", ButtonKind::Filled, self.automation_action_busy, icon(AleraIcon::CheckCheck, 14.0, theme::on_accent())).on_click(cx.listener(move |this, _, _, cx| this.run_automation_request("automation.approve", json!({"id": id_for_approve.clone(), "revision": revision}), "Automation approved", cx)))),
                        Some(design_system::button_with_leading_icon("automation-run-now", "Run Now", ButtonKind::Filled, self.automation_action_busy, icon(AleraIcon::Agent, 14.0, theme::on_accent())).on_click(cx.listener(move |this, _, _, cx| this.run_automation_request("automation.runNow", json!({"id": id_for_run.clone(), "precheck": true, "overlap": "skip", "draftTest": false}), "Automation run started", cx)))),
                        can_pause.then(|| design_system::button("automation-pause", "Pause", ButtonKind::Outlined, self.automation_action_busy).on_click(cx.listener(move |this, _, _, cx| this.run_automation_request("automation.pause", json!({"id": id_for_pause.clone(), "activeRuns": "continue-active"}), "Automation paused", cx)))),
                        can_resume.then(|| design_system::button("automation-resume", "Resume", ButtonKind::Outlined, self.automation_action_busy).on_click(cx.listener(move |this, _, _, cx| this.run_automation_request("automation.resume", json!({"id": id_for_resume.clone()}), "Automation resumed", cx)))),
                        (state != "trashed").then(|| design_system::button("automation-trash", "Trash", ButtonKind::Text, self.automation_action_busy).on_click(cx.listener(move |this, _, _, cx| this.run_automation_request("automation.trash", json!({"id": id_for_trash.clone()}), "Automation trashed", cx)))),
                        (state == "trashed").then(|| design_system::button("automation-restore", "Restore", ButtonKind::Text, self.automation_action_busy).on_click(cx.listener(move |this, _, _, cx| this.run_automation_request("automation.restore", json!({"id": id_for_restore.clone()}), "Automation restored", cx)))),
                    ].into_iter().flatten()),
            )
            .child(
                div()
                    .mt_4()
                    .flex()
                    .flex_1()
                    .min_h_0()
                    .overflow_y_scrollbar()
                    .child(
                        div()
                            .flex()
                            .flex_col()
                            .gap_3()
                            .pb_4()
                            .child(self.render_automation_info(automation))
                            .child(self.render_automation_runs(&runs, cx))
                            .child(self.render_automation_audit(&audit)),
                    ),
            )
            .into_any_element()
    }

    fn render_automation_info(&self, automation: &Value) -> gpui::Div {
        let schedule = nested_object(automation, "schedule", "recurring")
            .or_else(|| nested_object(automation, "schedule", "oneTime"))
            .unwrap_or_default();
        let target = automation
            .get("target")
            .and_then(Value::as_object)
            .and_then(|target| target.values().next())
            .and_then(Value::as_object)
            .cloned()
            .unwrap_or_default();
        let schedule_kind = if automation
            .get("schedule")
            .and_then(|value| value.get("recurring"))
            .is_some()
        {
            "Recurring"
        } else {
            "One-time"
        };
        let target_kind = automation
            .get("target")
            .and_then(Value::as_object)
            .and_then(|target| target.keys().next())
            .map(|key| match key.as_str() {
                "existingTab" => "Existing tab",
                "managedWorkspace" => "Managed workspace",
                _ => "Fresh tab",
            })
            .unwrap_or("Target");
        let rows = [
            ("Slug", value_string(automation, "slug").unwrap_or_default()),
            (
                "Schedule",
                format!(
                    "{schedule_kind} · {}",
                    schedule
                        .get("timezone")
                        .and_then(Value::as_str)
                        .unwrap_or("UTC")
                ),
            ),
            (
                "Cron / Time",
                schedule
                    .get("cron")
                    .or_else(|| schedule.get("at"))
                    .map(value_display)
                    .unwrap_or_else(|| "Not set".into()),
            ),
            (
                "Target",
                format!(
                    "{target_kind} · {}",
                    target
                        .get("workspaceId")
                        .or_else(|| target.get("sourceWorkspaceId"))
                        .map(value_display)
                        .unwrap_or_else(|| "Not set".into())
                ),
            ),
            (
                "Policies",
                format!(
                    "Setup {} · Overlap {} · Misfire {} · Cleanup {}",
                    value_string(automation, "setupPolicy").unwrap_or_else(|| "wait".into()),
                    value_string(automation, "overlapPolicy").unwrap_or_else(|| "skip".into()),
                    value_string(automation, "misfirePolicy").unwrap_or_else(|| "skip".into()),
                    value_string(automation, "cleanupPolicy").unwrap_or_else(|| "preserve".into())
                ),
            ),
            (
                "Limits",
                format!(
                    "Queue {} · Inactivity {}s · Heartbeat {}s · Retries {}",
                    value_i64(automation, "queueCap").unwrap_or(10),
                    value_i64(automation, "inactivityTimeoutSeconds").unwrap_or(7200),
                    value_i64(automation, "heartbeatIntervalSeconds").unwrap_or(60),
                    value_i64(automation, "retryMaxAttempts").unwrap_or(3)
                ),
            ),
            (
                "Revision",
                format!(
                    "{}{}",
                    value_i64(automation, "revision").unwrap_or_default(),
                    if value_i64(automation, "approvedRevision")
                        == value_i64(automation, "revision")
                    {
                        " · approved"
                    } else {
                        " · draft changes"
                    }
                ),
            ),
            (
                "Description",
                value_string(automation, "description").unwrap_or_default(),
            ),
            (
                "Prompt",
                value_string(automation, "promptTemplate").unwrap_or_default(),
            ),
        ];
        div()
            .rounded_lg()
            .border_1()
            .border_color(theme::border_subtle())
            .bg(theme::surface_selected())
            .p_3()
            .child(
                div()
                    .font_weight(gpui::FontWeight::SEMIBOLD)
                    .child("Overview"),
            )
            .children(
                rows.into_iter()
                    .filter(|(_, value)| !value.is_empty())
                    .map(|(label, value)| automation_info_row(label, value)),
            )
    }

    fn render_automation_runs(&self, runs: &[Value], cx: &mut Context<Self>) -> gpui::Div {
        let mut panel = div()
            .rounded_lg()
            .border_1()
            .border_color(theme::border_subtle())
            .bg(theme::surface_selected())
            .p_3()
            .child(div().font_weight(gpui::FontWeight::SEMIBOLD).child("Runs"));
        if runs.is_empty() {
            return panel.child(
                div()
                    .mt_2()
                    .text_sm()
                    .text_color(theme::text_muted())
                    .child("No runs yet."),
            );
        }
        for (index, run) in runs.iter().enumerate() {
            let status = value_string(run, "status").unwrap_or_else(|| "pending".into());
            let run_id = value_string(run, "id").unwrap_or_else(|| format!("run-{index}"));
            let final_status = AUTOMATION_FINAL_RUN_STATUSES.contains(&status.as_str());
            let target_identity = run
                .get("targetIdentity")
                .cloned()
                .unwrap_or_else(|| json!({}));
            let target_identity_for_wait = target_identity.clone();
            let target_identity_for_extend = target_identity.clone();
            let run_for_cancel = run_id.clone();
            let run_for_wait = run_id.clone();
            let run_for_extend = run_id.clone();
            let mut row = div()
                .mt_2()
                .p_2()
                .rounded_md()
                .border_1()
                .border_color(theme::border_subtle())
                .child(div().text_sm().child(format!(
                    "Run #{} · {status}",
                    value_i64(run, "number").unwrap_or(0)
                )))
                .child(
                    div()
                        .mt_1()
                        .text_xs()
                        .text_color(theme::text_muted())
                        .child(
                            value_string(run, "summary")
                                .or_else(|| value_string(run, "error"))
                                .unwrap_or_default(),
                        ),
                );
            if !final_status {
                row = row.child(
                    div()
                        .mt_2()
                        .flex()
                        .gap_2()
                        .child(design_system::button("automation-cancel-run", "Cancel", ButtonKind::Text, self.automation_action_busy).on_click(cx.listener(move |this, _, _, cx| this.run_automation_request("automation.cancel", json!({"run": run_for_cancel.clone(), "targetIdentity": target_identity.clone()}), "Automation cancellation requested", cx))))
                        .when(status == "waitingForUser", |actions| {
                            actions
                                .child(design_system::button("automation-resume-waiting", "Resume Waiting", ButtonKind::Text, self.automation_action_busy).on_click(cx.listener(move |this, _, _, cx| this.run_automation_request("automation.wait", json!({"run": run_for_wait.clone(), "targetIdentity": target_identity_for_wait.clone(), "waiting": false}), "Waiting run resumed", cx))))
                                .child(design_system::button("automation-extend-waiting", "Extend", ButtonKind::Text, self.automation_action_busy).on_click(cx.listener(move |this, _, _, cx| this.run_automation_request("automation.extend", json!({"run": run_for_extend.clone(), "targetIdentity": target_identity_for_extend.clone(), "seconds": 3600}), "Waiting run extended", cx))))
                        }),
                );
            }
            panel = panel.child(row);
        }
        panel
    }

    fn render_automation_audit(&self, events: &[Value]) -> gpui::Div {
        let mut panel = div()
            .rounded_lg()
            .border_1()
            .border_color(theme::border_subtle())
            .bg(theme::surface_selected())
            .p_3()
            .child(div().font_weight(gpui::FontWeight::SEMIBOLD).child("Audit"));
        if events.is_empty() {
            return panel.child(
                div()
                    .mt_2()
                    .text_sm()
                    .text_color(theme::text_muted())
                    .child("No audit events yet."),
            );
        }
        for event in events {
            panel = panel.child(
                div()
                    .mt_2()
                    .text_sm()
                    .child(value_string(event, "action").unwrap_or_else(|| "Event".into()))
                    .child(
                        div()
                            .mt_1()
                            .text_xs()
                            .text_color(theme::text_muted())
                            .child(format!(
                                "{} · {}",
                                value_string(event, "createdAt").unwrap_or_default(),
                                value_string(event, "actor").unwrap_or_default()
                            )),
                    ),
            );
        }
        panel
    }

    fn render_automation_editor(&self, cx: &mut Context<Self>) -> AnyElement {
        div()
            .flex()
            .flex_col()
            .flex_1()
            .min_h_0()
            .child(
                div()
                    .flex()
                    .items_center()
                    .child(div().flex_1().text_lg().font_weight(gpui::FontWeight::SEMIBOLD).child(if self.automation_editor_id.is_some() { "Edit Automation" } else { "New Automation" }))
                    .child(design_system::icon_button("close-automation-editor", "Close", AleraIcon::Close, true, 30.0, None, None).on_click(cx.listener(|this, _, _, cx| { this.automation_editor_open = false; this.automation_editor_error = None; cx.notify(); }))),
            )
            .child(
                div()
                    .mt_4()
                    .flex_1()
                    .min_h_0()
                    .overflow_y_scrollbar()
                    .child(
                        div()
                            .flex()
                            .flex_col()
                            .gap_3()
                            .pb_4()
                            .child(design_system::text_field(&self.automation_editor_name_input).label("Name"))
                            .child(design_system::text_field(&self.automation_editor_slug_input).label("Slug"))
                            .child(design_system::text_field(&self.automation_editor_description_input).label("Description"))
                            .child(div().child(div().mb_1().text_sm().text_color(theme::text_muted()).child("Prompt Template")).h(px(110.0)).child(Textarea::new(&self.automation_editor_prompt_input).h_full()))
                            .child(design_system::text_field(&self.automation_editor_cron_input).label("Five-field Cron"))
                            .child(design_system::text_field(&self.automation_editor_workspace_input).label("Workspace ID"))
                            .child(design_system::text_field(&self.automation_editor_profile_input).label("Agent Profile ID"))
                            .child(div().text_xs().text_color(theme::text_muted()).child("This GPUI editor creates a recurring fresh-tab automation. Existing definitions retain their complete runtime policies when edited."))
                            .when_some(self.automation_editor_error.clone(), |form, error| form.child(div().text_sm().text_color(theme::danger()).child(error))),
                    ),
            )
            .child(
                div()
                    .mt_4()
                    .flex()
                    .justify_end()
                    .gap_2()
                    .child(design_system::button("cancel-automation-editor", "Cancel", ButtonKind::Text, self.automation_action_busy).on_click(cx.listener(|this, _, _, cx| { if !this.automation_action_busy { this.automation_editor_open = false; this.automation_editor_error = None; cx.notify(); } })))
                    .child(design_system::button_with_loading("save-automation-editor", if self.automation_action_busy { "Saving" } else { "Save Automation" }, ButtonKind::Filled, self.automation_action_busy, self.automation_action_busy).on_click(cx.listener(|this, _, window, cx| this.save_automation_editor(window, cx)))),
            )
            .into_any_element()
    }

    pub(super) fn load_automation_settings(&mut self, cx: &mut Context<Self>) {
        if self.automation_settings_loading {
            return;
        }
        self.automation_settings_loading = true;
        let bridge = self.bridge.clone();
        cx.spawn(async move |this, cx| {
            let result = bridge.request("runtimeSettings.get", json!({})).await;
            let Some(this) = this.upgrade() else {
                return;
            };
            this.update(cx, |this, cx| {
                this.automation_settings_loading = false;
                this.automation_settings_loaded = true;
                match result {
                    Ok(value) => this.apply_automation_settings(&value),
                    Err(error) => this.automation_settings_error = Some(error.into()),
                }
                cx.notify();
            });
        })
        .detach();
    }

    fn apply_automation_settings(&mut self, value: &Value) {
        let Some(automation) = value.get("automation") else {
            return;
        };
        self.settings_state.automation_autostart = value_bool(automation, "autostart");
        self.settings_state.automation_run_retention_days =
            value_i64(automation, "runRetentionDays").unwrap_or(30);
        self.settings_state.automation_audit_retention_days =
            value_i64(automation, "auditRetentionDays").unwrap_or(90);
        self.settings_state.automation_trash_retention_days =
            value_i64(automation, "trashRetentionDays").unwrap_or(30);
    }

    pub(super) fn toggle_automation_autostart(&mut self, cx: &mut Context<Self>) {
        self.settings_state.automation_autostart = !self.settings_state.automation_autostart;
        self.save_automation_settings(cx);
    }

    pub(super) fn adjust_automation_retention(
        &mut self,
        kind: &'static str,
        delta: i64,
        cx: &mut Context<Self>,
    ) {
        let value = match kind {
            "run" => &mut self.settings_state.automation_run_retention_days,
            "audit" => &mut self.settings_state.automation_audit_retention_days,
            _ => &mut self.settings_state.automation_trash_retention_days,
        };
        *value = (*value + delta).clamp(1, 3650);
        self.save_automation_settings(cx);
    }

    fn save_automation_settings(&mut self, cx: &mut Context<Self>) {
        if self.automation_settings_saving {
            return;
        }
        self.automation_settings_saving = true;
        self.automation_settings_error = None;
        let bridge = self.bridge.clone();
        let payload = json!({"automation": {
            "autostart": self.settings_state.automation_autostart,
            "runRetentionDays": self.settings_state.automation_run_retention_days,
            "auditRetentionDays": self.settings_state.automation_audit_retention_days,
            "trashRetentionDays": self.settings_state.automation_trash_retention_days,
        }});
        cx.spawn(async move |this, cx| {
            let result = bridge.request("runtimeSettings.update", payload).await;
            let Some(this) = this.upgrade() else {
                return;
            };
            this.update(cx, |this, cx| {
                this.automation_settings_saving = false;
                if let Err(error) = result {
                    this.automation_settings_error = Some(error.into());
                }
                cx.notify();
            });
        })
        .detach();
    }

    pub(super) fn render_automation_settings_group(
        settings: &super::settings_state::SettingsState,
        saving: bool,
        error: Option<SharedString>,
        cx: &mut Context<Self>,
    ) -> gpui::Div {
        let autostart = settings.automation_autostart;
        let run_retention_days = settings.automation_run_retention_days;
        let audit_retention_days = settings.automation_audit_retention_days;
        let trash_retention_days = settings.automation_trash_retention_days;
        let value_row =
            |title: &'static str, description: &'static str, kind: &'static str, value: i64| {
                let decrease = kind;
                let increase = kind;
                div()
                    .flex()
                    .items_center()
                    .min_h(px(69.0))
                    .p_4()
                    .border_b_1()
                    .border_color(theme::border_subtle())
                    .child(
                        div()
                            .flex_1()
                            .child(
                                div()
                                    .text_size(px(13.0))
                                    .font_weight(gpui::FontWeight::MEDIUM)
                                    .child(title),
                            )
                            .child(
                                div()
                                    .mt_1()
                                    .text_size(px(12.0))
                                    .text_color(theme::text_muted())
                                    .child(description),
                            ),
                    )
                    .child(
                        div()
                            .flex()
                            .items_center()
                            .gap_1()
                            .child(
                                design_system::icon_button(
                                    SharedString::from(format!("automation-{kind}-decrease")),
                                    "Decrease",
                                    AleraIcon::ChevronDown,
                                    true,
                                    26.0,
                                    None,
                                    None,
                                )
                                .on_click(cx.listener(
                                    move |this, _, _, cx| {
                                        this.adjust_automation_retention(decrease, -1, cx)
                                    },
                                )),
                            )
                            .child(
                                div()
                                    .w(px(48.0))
                                    .text_center()
                                    .text_size(px(13.0))
                                    .child(format!("{value} d")),
                            )
                            .child(
                                design_system::icon_button(
                                    SharedString::from(format!("automation-{kind}-increase")),
                                    "Increase",
                                    AleraIcon::ChevronUp,
                                    true,
                                    26.0,
                                    None,
                                    None,
                                )
                                .on_click(cx.listener(
                                    move |this, _, _, cx| {
                                        this.adjust_automation_retention(increase, 1, cx)
                                    },
                                )),
                            ),
                    )
            };
        let switch = design_system::switch(autostart, !saving)
            .id("automation-autostart")
            .focusable()
            .tab_stop(!saving)
            .role(Role::Switch)
            .aria_label("Start Automations At Login")
            .aria_toggled(if autostart {
                Toggled::True
            } else {
                Toggled::False
            })
            .on_click(cx.listener(|this, _, _, cx| this.toggle_automation_autostart(cx)));
        div()
            .child(div().ml_1().mb_4().child(div().text_size(px(13.0)).font_weight(gpui::FontWeight::SEMIBOLD).child("Automation History And Autostart")).child(div().mt_1().text_size(px(12.0)).text_color(theme::text_muted()).child("Keep scheduled work available without a window and control local retention.")))
            .child(div().overflow_hidden().rounded_lg().border_1().border_color(theme::border_subtle()).bg(theme::surface_selected()).child(super::settings_panes::exact_settings_row("Start Automations At Login", "Start the persistent local automation host when you sign in. This is off by default.", switch)).child(value_row("Run History Retention", "Keep final runs for at most this many days.", "run", run_retention_days)).child(value_row("Audit Retention", "Keep automation audit events for at most this many days.", "audit", audit_retention_days)).child(value_row("Trash Retention", "Permanently remove trashed definitions after this many days.", "trash", trash_retention_days)))
            .when_some(error, |group, error| group.child(div().mt_2().text_sm().text_color(theme::danger()).child(error)))
    }

    pub(super) fn load_automation_profile_policy(
        &mut self,
        profile_id: Option<&str>,
        cx: &mut Context<Self>,
    ) {
        let Some(profile_id) = profile_id.filter(|id| !id.is_empty()) else {
            self.automation_profile_policy_id = None;
            self.automation_profile_policy_error = None;
            self.automation_profile_policy_loading = false;
            return;
        };
        if self.automation_profile_policy_id.as_deref() == Some(profile_id)
            && !self.automation_profile_policy_loading
        {
            return;
        }
        let profile_id = profile_id.to_owned();
        self.automation_profile_policy_id = Some(profile_id.clone());
        self.automation_profile_policy_loading = true;
        self.automation_profile_policy_error = None;
        let bridge = self.bridge.clone();
        cx.spawn(async move |this, cx| {
            let result = bridge
                .request(
                    "automation.policy",
                    json!({"kind": "agent", "profileId": profile_id}),
                )
                .await;
            let Some(this) = this.upgrade() else {
                return;
            };
            this.update(cx, |this, cx| {
                this.automation_profile_policy_loading = false;
                match result {
                    Ok(value) => {
                        this.automation_profile_policy_activate =
                            value_bool(&value, "mayActivateOrEditActive");
                        this.automation_profile_policy_execute = value_bool(&value, "mayExecute");
                    }
                    Err(error) => this.automation_profile_policy_error = Some(error.into()),
                }
                cx.notify();
            });
        })
        .detach();
    }

    pub(super) fn load_automation_project_policy(
        &mut self,
        project_id: Option<&str>,
        cx: &mut Context<Self>,
    ) {
        let Some(project_id) = project_id.filter(|id| !id.is_empty()) else {
            self.automation_project_policy_id = None;
            self.automation_project_policy_error = None;
            self.automation_project_policy_loading = false;
            return;
        };
        if self.automation_project_policy_id.as_deref() == Some(project_id)
            && !self.automation_project_policy_loading
        {
            return;
        }
        let project_id = project_id.to_owned();
        self.automation_project_policy_id = Some(project_id.clone());
        self.automation_project_policy_loading = true;
        self.automation_project_policy_error = None;
        let bridge = self.bridge.clone();
        cx.spawn(async move |this, cx| {
            let result = bridge
                .request(
                    "automation.policy",
                    json!({"kind": "project", "projectId": project_id}),
                )
                .await;
            let Some(this) = this.upgrade() else {
                return;
            };
            this.update(cx, |this, cx| {
                this.automation_project_policy_loading = false;
                match result {
                    Ok(value) => {
                        this.automation_project_policy_local_approved =
                            value_bool(&value, "localApproved");
                        this.automation_project_policy_restrictive =
                            value_bool(&value, "restrictive");
                        this.automation_project_policy_repo_declared =
                            value_bool(&value, "repoDeclared");
                    }
                    Err(error) => this.automation_project_policy_error = Some(error.into()),
                }
                cx.notify();
            });
        })
        .detach();
    }

    fn save_automation_policy(&mut self, kind: &'static str, cx: &mut Context<Self>) {
        let (id_key, id, policy) = if kind == "agent" {
            let Some(id) = self.automation_profile_policy_id.clone() else {
                return;
            };
            (
                "profileId",
                id,
                json!({
                    "mayActivateOrEditActive": self.automation_profile_policy_activate,
                    "mayExecute": self.automation_profile_policy_execute,
                }),
            )
        } else {
            let Some(id) = self.automation_project_policy_id.clone() else {
                return;
            };
            (
                "projectId",
                id,
                json!({
                    "localApproved": self.automation_project_policy_local_approved,
                    "restrictive": self.automation_project_policy_restrictive,
                }),
            )
        };
        let bridge = self.bridge.clone();
        self.automation_action_busy = true;
        let payload = json!({"kind": kind, id_key: id, "policy": policy});
        cx.spawn(async move |this, cx| {
            let result = bridge.request("automation.policy", payload).await;
            let Some(this) = this.upgrade() else {
                return;
            };
            this.update(cx, |this, cx| {
                this.automation_action_busy = false;
                if let Err(error) = result {
                    if kind == "agent" {
                        this.automation_profile_policy_error = Some(error.into());
                    } else {
                        this.automation_project_policy_error = Some(error.into());
                    }
                }
                cx.notify();
            });
        })
        .detach();
    }

    pub(super) fn toggle_automation_profile_policy(
        &mut self,
        execute: bool,
        cx: &mut Context<Self>,
    ) {
        if execute {
            self.automation_profile_policy_execute = !self.automation_profile_policy_execute;
        } else {
            self.automation_profile_policy_activate = !self.automation_profile_policy_activate;
        }
        self.save_automation_policy("agent", cx);
    }

    pub(super) fn toggle_automation_project_policy(
        &mut self,
        restrictive: bool,
        cx: &mut Context<Self>,
    ) {
        if restrictive {
            self.automation_project_policy_restrictive =
                !self.automation_project_policy_restrictive;
        } else {
            self.automation_project_policy_local_approved =
                !self.automation_project_policy_local_approved;
        }
        self.save_automation_policy("project", cx);
    }

    pub(super) fn render_automation_profile_policy(&self, cx: &mut Context<Self>) -> gpui::Div {
        let loading = self.automation_profile_policy_loading;
        let activate = design_system::switch(
            self.automation_profile_policy_activate,
            !self.automation_action_busy,
        )
        .id("automation-profile-may-activate")
        .focusable()
        .tab_stop(!self.automation_action_busy)
        .role(Role::Switch)
        .aria_label("May Activate Or Edit Active Automations")
        .aria_toggled(if self.automation_profile_policy_activate {
            Toggled::True
        } else {
            Toggled::False
        })
        .on_click(cx.listener(|this, _, _, cx| this.toggle_automation_profile_policy(false, cx)));
        let execute = design_system::switch(
            self.automation_profile_policy_execute,
            !self.automation_action_busy,
        )
        .id("automation-profile-may-execute")
        .focusable()
        .tab_stop(!self.automation_action_busy)
        .role(Role::Switch)
        .aria_label("May Execute Automations")
        .aria_toggled(if self.automation_profile_policy_execute {
            Toggled::True
        } else {
            Toggled::False
        })
        .on_click(cx.listener(|this, _, _, cx| this.toggle_automation_profile_policy(true, cx)));
        let mut group = policy_group(
            "Automation Permissions",
            "Choose whether this profile may administer active definitions and execute them.",
        )
        .child(super::settings_panes::exact_settings_row(
            "May Activate Or Edit Active Automations",
            "Allow a managed agent using this profile to activate or edit an active definition.",
            activate,
        ))
        .child(super::settings_panes::exact_settings_row(
            "May Execute Automations",
            "Opt this profile into scheduled and manual automation execution.",
            execute,
        ));
        if loading {
            group = group.child(
                div()
                    .p_3()
                    .child(loading_indicator(14.0, theme::text_muted())),
            );
        }
        if let Some(error) = self.automation_profile_policy_error.clone() {
            group = group.child(
                div()
                    .p_3()
                    .text_sm()
                    .text_color(theme::danger())
                    .child(error),
            );
        }
        group
    }

    pub(super) fn render_automation_project_policy(&self, cx: &mut Context<Self>) -> gpui::Div {
        let repo = design_system::switch(self.automation_project_policy_repo_declared, false)
            .id("automation-project-repo-declared")
            .role(Role::Switch)
            .aria_label("Repository Declares Automations")
            .aria_toggled(if self.automation_project_policy_repo_declared {
                Toggled::True
            } else {
                Toggled::False
            });
        let restrictive = design_system::switch(
            self.automation_project_policy_restrictive,
            !self.automation_action_busy,
        )
        .id("automation-project-restrictive")
        .focusable()
        .tab_stop(!self.automation_action_busy)
        .role(Role::Switch)
        .aria_label("Require Local Approval")
        .aria_toggled(if self.automation_project_policy_restrictive {
            Toggled::True
        } else {
            Toggled::False
        })
        .on_click(cx.listener(|this, _, _, cx| this.toggle_automation_project_policy(true, cx)));
        let approved = design_system::switch(
            self.automation_project_policy_local_approved,
            !self.automation_action_busy,
        )
        .id("automation-project-local-approved")
        .focusable()
        .tab_stop(!self.automation_action_busy)
        .role(Role::Switch)
        .aria_label("Local Approval Granted")
        .aria_toggled(if self.automation_project_policy_local_approved {
            Toggled::True
        } else {
            Toggled::False
        })
        .on_click(cx.listener(|this, _, _, cx| this.toggle_automation_project_policy(false, cx)));
        let mut group = policy_group(
            "Automation Policy",
            "Repository declaration is read from alera.toml. Local approval can only restrict execution.",
        )
        .child(super::settings_panes::exact_settings_row(
            "Repository Declares Automations",
            if self.automation_project_policy_repo_declared {
                "The repository declares automation use in alera.toml."
            } else {
                "Add an automation declaration to alera.toml before execution."
            },
            repo,
        ))
        .child(super::settings_panes::exact_settings_row(
            "Require Local Approval",
            "Require an explicit human approval in addition to the repository declaration.",
            restrictive,
        ))
        .child(super::settings_panes::exact_settings_row(
            "Local Approval Granted",
            "Grant the local approval required by a restrictive project policy.",
            approved,
        ));
        if self.automation_project_policy_loading {
            group = group.child(
                div()
                    .p_3()
                    .child(loading_indicator(14.0, theme::text_muted())),
            );
        }
        if let Some(error) = self.automation_project_policy_error.clone() {
            group = group.child(
                div()
                    .p_3()
                    .text_sm()
                    .text_color(theme::danger())
                    .child(error),
            );
        }
        group
    }
}

fn policy_group(title: &'static str, description: &'static str) -> gpui::Div {
    div()
        .child(
            div()
                .ml_1()
                .mb(px(10.0))
                .child(
                    div()
                        .text_size(px(13.0))
                        .font_weight(gpui::FontWeight::SEMIBOLD)
                        .child(title),
                )
                .child(
                    div()
                        .mt_1()
                        .text_size(px(12.0))
                        .text_color(theme::text_muted())
                        .child(description),
                ),
        )
        .child(
            div()
                .overflow_hidden()
                .rounded_lg()
                .border_1()
                .border_color(theme::border_subtle())
                .bg(theme::surface_selected()),
        )
}

fn set_input_value(
    input: &Entity<InputState>,
    value: String,
    window: &mut Window,
    cx: &mut Context<AleraApp>,
) {
    input.update(cx, |input, cx| input.set_value(value, window, cx));
}

fn value_string(value: &Value, key: &str) -> Option<String> {
    value.get(key).and_then(Value::as_str).map(str::to_owned)
}

fn value_i64(value: &Value, key: &str) -> Option<i64> {
    value
        .get(key)
        .and_then(|value| value.as_i64().or_else(|| value.as_str()?.parse().ok()))
}

fn value_bool(value: &Value, key: &str) -> bool {
    value.get(key).and_then(Value::as_bool).unwrap_or(false)
}

fn nested_string(value: &Value, outer: &str, inner: &str, key: &str) -> Option<String> {
    value
        .get(outer)?
        .get(inner)?
        .get(key)?
        .as_str()
        .map(str::to_owned)
}

fn nested_object(value: &Value, outer: &str, inner: &str) -> Option<Map<String, Value>> {
    value.get(outer)?.get(inner)?.as_object().cloned()
}

fn target_string(value: &Value, keys: &[&str]) -> Option<String> {
    let target = value
        .get("target")?
        .as_object()?
        .values()
        .next()?
        .as_object()?;
    keys.iter()
        .find_map(|key| target.get(*key).and_then(Value::as_str).map(str::to_owned))
}

fn value_display(value: &Value) -> String {
    value
        .as_str()
        .map(str::to_owned)
        .unwrap_or_else(|| value.to_string())
}

fn format_timestamp() -> String {
    chrono::Utc::now().to_rfc3339()
}

fn automation_info_row(label: &'static str, value: String) -> gpui::Div {
    div()
        .flex()
        .items_start()
        .py_1()
        .child(
            div()
                .w(px(135.0))
                .text_size(px(11.0))
                .text_color(theme::text_muted())
                .child(label),
        )
        .child(div().flex_1().text_size(px(12.0)).child(value))
}

fn automation_empty_state(title: &'static str, message: &'static str) -> AnyElement {
    div()
        .flex()
        .flex_1()
        .flex_col()
        .items_center()
        .justify_center()
        .gap_2()
        .child(icon(AleraIcon::Workflow, 28.0, theme::text_faint()))
        .child(div().font_weight(gpui::FontWeight::SEMIBOLD).child(title))
        .child(
            div()
                .max_w(px(360.0))
                .text_center()
                .text_size(px(12.0))
                .text_color(theme::text_muted())
                .child(message),
        )
        .into_any_element()
}
