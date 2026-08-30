use gpui::{
    div, prelude::FluentBuilder as _, px, AnyElement, Context, CursorStyle,
    InteractiveElement as _, IntoElement, ParentElement as _, Role, SharedString,
    StatefulInteractiveElement as _, Styled as _, Toggled, Window,
};
use gpui_component::FocusTrapElement as _;
use serde_json::{json, Value};
use uuid::Uuid;

use super::AleraApp;
use crate::design_system::{self, ButtonKind};
use crate::icons::{icon, loading_indicator, AleraIcon};
use crate::theme;
include!("automation_requests.rs");

impl AleraApp {
    pub(crate) fn open_automations_dialog(&mut self, window: &mut Window, cx: &mut Context<Self>) {
        if self.show_automations_dialog { return; }
        self.automation_previous_focus = window.focused(cx);
        self.automation_dialog_focus.focus(window, cx);
        self.automation_requests.reset_view();
        self.automations_loading = false;
        self.automation_detail_loading = false;
        self.automation_action_busy = false;
        self.automation_editor_open = false;
        self.automation_editor = None;
        self.automation_action_dialog = None;
        self.show_automations_dialog = true;
        self.automations_error = None;
        self.automation_detail = None;
        self.automation_detail_error = None;
        self.automation_detail_tab = Default::default();
        self.automation_selected_id = None;
        self.automation_filters = Default::default();
        self.automation_master_width = 240.0;
        self.automation_include_trashed = false;
        self.automation_search_input
            .update(cx, |input, cx| input.set_value("", window, cx));
        self.load_automations(cx);
        cx.notify();
    }

    pub(crate) fn close_automations_dialog(&mut self, window: &mut Window, cx: &mut Context<Self>) {
        gpui_base::TextSelection::clear(window, cx);
        if self.settings_master_resize.is_some_and(|resize| resize.target == super::SettingsMasterResizeTarget::Automations) {
            self.settings_master_resize = None;
        }
        self.automation_requests.reset_view();
        self.automations_loading = false;
        self.automation_detail_loading = false;
        self.automation_action_busy = false;
        self.show_automations_dialog = false;
        self.automation_editor_open = false;
        self.automation_editor = None;
        self.automation_action_dialog = None;
        self.automation_editor_error = None;
        self.automations_error = None;
        self.automation_previous_focus.take().unwrap_or_else(|| self.shell_focus.clone()).focus(window, cx);
        cx.notify();
    }


    pub(super) fn open_automation_editor(
        &mut self, initial: Option<Value>, window: &mut Window, cx: &mut Context<Self>,
    ) {
        if self.automation_action_busy || !self.show_automations_dialog || self.automation_action_dialog.is_some() { return; }
        self.automation_editor_definition = super::automation_request_epoch::editor_definition(initial.as_ref());
        self.automation_editor_id = value_string(&self.automation_editor_definition, "id");
        let form = super::automation_form::AutomationForm::from_definition(&self.automation_editor_definition, &format_timestamp());
        let mut editor = super::automation_editor_state::AutomationEditor::new(form, window, cx);
        editor.profiles_loading = true;
        let epoch = editor.epoch;
        self.automation_editor = Some(editor);
        self.automation_editor_error = None;
        self.automation_editor_open = true;
        self.automation_dialog_focus.focus(window, cx);
        let bridge = self.bridge.clone();
        cx.spawn(async move |this, cx| {
            let result = bridge.request("agentProfile.list", json!({})).await;
            let Some(this) = this.upgrade() else { return; };
            this.update(cx, |this, cx| {
                if !this.show_automations_dialog { return; }
                let Some(editor) = &mut this.automation_editor else { return; };
                if editor.epoch != epoch { return; }
                editor.profiles_loading = false;
                match result {
                    Ok(value) => editor.profiles = value["items"].as_array().into_iter().flatten()
                        .filter_map(|profile| Some((profile["id"].as_str()?.to_owned(), profile["name"].as_str()?.to_owned()))).collect(),
                    Err(error) => this.automation_editor_error = Some(format!("Could not load agent profiles: {error}").into()),
                }
                cx.notify();
            });
        }).detach();
        cx.notify();
    }

    pub(super) fn save_automation_editor(&mut self, window: &mut Window, cx: &mut Context<Self>) {
        if self.automation_action_busy || !self.automation_editor_open { return; }
        let Some(editor) = &self.automation_editor else { return; };
        let id = self.automation_editor_id.clone().unwrap_or_else(|| Uuid::new_v4().to_string());
        let definition = match editor.snapshot(cx).definition(&self.automation_editor_definition, &id, &format_timestamp()) {
            Ok(value) => value,
            Err(error) => {
                self.automation_editor_error = Some(error.into());
                cx.notify();
                return;
            }
        };
        self.automation_action_busy = true;
        self.automation_editor_error = None;
        self.automation_dialog_focus.focus(window, cx);
        let bridge = self.bridge.clone();
        let view_epoch = self.automation_requests.view();
        let editor_epoch = self.automation_editor.as_ref().map(|editor| editor.epoch);
        let selected_before = self.automation_selected_id.clone();
        cx.spawn(async move |this, cx| {
            let result = bridge
                .request("automation.upsert", json!({"automation": definition}))
                .await;
            let Some(this) = this.upgrade() else {
                return;
            };
            this.update(cx, |this, cx| {
                if !this.automation_requests.accepts_view(view_epoch) || this.automation_editor.as_ref().map(|editor| editor.epoch) != editor_epoch { return; }
                this.automation_action_busy = false;
                match result {
                    Ok(value) => {
                        this.automation_editor_open = false;
                        this.automation_editor = None;
                        if this.automation_selected_id == selected_before {
                            this.automation_selected_id = value_string(&value, "id").or(Some(id.clone()));
                        }
                        this.local_message = Some("Automation saved".into());
                        this.local_message_started_at = Some(std::time::Instant::now());
                        this.refresh_automation_catalog_after_mutation(cx);
                    }
                    Err(error) => {
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

    pub(super) fn automation_export(&mut self, cx: &mut Context<Self>) {
        if !self.show_automations_dialog { return; }
        let bridge = self.bridge.clone();
        let view_epoch = self.automation_requests.view();
        cx.spawn(async move |this, cx| {
            let result = bridge.request("automation.export", json!({})).await;
            let Some(this) = this.upgrade() else {
                return;
            };
            this.update(cx, |this, cx| {
                if !this.automation_requests.accepts_view(view_epoch) { return; }
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

    pub(super) fn automation_import(&mut self, cx: &mut Context<Self>) {
        if self.automation_action_busy || !self.show_automations_dialog { return; }
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
        let view_epoch = self.automation_requests.view();
        self.automation_action_busy = true;
        cx.spawn(async move |this, cx| {
            let result = bridge
                .request("automation.import", json!({"bundle": bundle, "remap": {}}))
                .await;
            let Some(this) = this.upgrade() else {
                return;
            };
            this.update(cx, |this, cx| {
                if !this.automation_requests.accepts_view(view_epoch) { return; }
                this.automation_action_busy = false;
                match result {
                    Ok(_) => {
                        this.local_message = Some("Automation catalog imported as drafts".into());
                        this.local_message_started_at = Some(std::time::Instant::now());
                        this.refresh_automation_catalog_after_mutation(cx);
                    }
                    Err(error) => this.automations_error = Some(error.into()),
                }
                cx.notify();
            });
        })
        .detach();
    }

    pub(super) fn render_automations_dialog(&self, cx: &mut Context<Self>) -> AnyElement {
        let catalog = self.automation_modal_frame(self.render_automation_catalog(cx), false, cx);
        div().absolute().inset_0().child(catalog)
            .when(self.automation_editor_open,|root|root.child(self.automation_modal_frame(self.render_automation_editor(cx),true,cx)))
            .when(self.automation_action_dialog.is_some(),|root|root.child(self.render_automation_action_choice(cx))).into_any_element()
    }

    fn automation_modal_frame(&self, content: AnyElement, editor: bool, cx: &mut Context<Self>) -> AnyElement {
        let content = div().w_full().min_w_0().flex().flex_col().flex_1().min_h_0().child(content);
        let content = if editor || (!self.automation_editor_open && self.automation_action_dialog.is_none()) {
            content.focus_trap(if editor { "automation-editor-focus" } else { "automations-dialog-focus" }, &self.automation_dialog_focus).into_any_element()
        } else { content.into_any_element() };
        let title = if editor { if self.automation_editor_id.is_some() { "Edit Automation" } else { "New Automation" } } else { "Automations" };
        let view_epoch = self.automation_requests.view();
        let editor_epoch = self.automation_editor.as_ref().map(|editor| editor.epoch);
        automation_modal_surface(editor, title, content, cx.listener(move |this, _, window, cx| {
            if !this.automation_requests.accepts_view(view_epoch) { return; }
            if editor {
                if this.automation_editor.as_ref().map(|editor| editor.epoch) == editor_epoch { this.cancel_automation_editor(window, cx); }
            } else if !this.automation_editor_open && this.automation_action_dialog.is_none() {
                this.close_automations_dialog(window, cx);
            }
        })).into_any_element()
    }

    pub(super) fn render_automation_list_row(
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

    pub(super) fn render_automation_detail(&self, cx: &mut Context<Self>) -> AnyElement {
        if self.automation_detail_loading {
            return div()
                .flex()
                .flex_1()
                .items_center()
                .justify_center()
                .child(loading_indicator(22.0, theme::text_muted()))
                .into_any_element();
        }
        if let Some(error) = self.automation_detail_error.clone() {
            let id = self.automation_selected_id.clone();
            return design_system::empty_state_with_action("automation-detail-error", AleraIcon::Error, Some("Automation Unavailable".into()), error,
                Some(design_system::button("automation-detail-retry", "Retry", ButtonKind::Filled, false)
                    .on_click(cx.listener(move |this, _, _, cx| { if let Some(id) = &id { if this.automation_selected_id.as_ref() == Some(id) { this.load_automation_detail(id.clone(), cx); } } })).into_any_element())).into_any_element();
        }
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
        let id = value_string(automation, "id").unwrap_or_default();
        let name = value_string(automation, "name").unwrap_or_else(|| "Automation".into());
        let state = value_string(automation, "state").unwrap_or_else(|| "draft".into());
        let revision = value_i64(automation, "revision").unwrap_or_default();
        let approved = value_i64(automation, "approvedRevision") == Some(revision);
        let can_pause = state == "active";
        let can_resume = state == "paused";
        let id_for_refresh = id.clone();
        let id_for_edit = id.clone();
        let id_for_approve = id.clone();
        let id_for_run = id.clone();
        let id_for_pause = id.clone();
        let id_for_resume = id.clone();
        let id_for_trash = id.clone();
        let id_for_restore = id.clone();
        super::automation_detail_view::detail_frame()
            .child(
                div()
                    .w_full().min_w_0()
                    .flex()
                    .items_center()
                    .gap_2()
                    .child(div().flex_1().min_w_0().text_size(px(14.0)).font_weight(gpui::FontWeight::MEDIUM).child(name))
                    .child(div().text_size(crate::theme::body_size()).text_color(theme::text_muted()).child(state.clone()))
                    .child(design_system::icon_button("automation-refresh", "Refresh", AleraIcon::Refresh, true, 22.0, None, None).on_click(cx.listener(move |this, _, _, cx| this.load_automation_detail(id_for_refresh.clone(), cx))))
                    .child(design_system::icon_button("automation-edit", "Edit", AleraIcon::Edit, !self.automation_action_busy, 22.0, None, None).on_click(cx.listener(move |this, _, window, cx| {
                        if this.automation_selected_id.as_deref() != Some(id_for_edit.as_str()) { return; }
                        if let Some(automation) = this.selected_automation().cloned() {
                            this.open_automation_editor(Some(automation), window, cx);
                        }
                    })))
                    .child(design_system::icon_button("automation-clone", "Clone", AleraIcon::Duplicate, !self.automation_action_busy, 22.0, None, None).on_click(cx.listener(|this, _, window, cx| this.clone_selected_automation(window, cx)))),
            )
            .child(
                div()
                    .mt_3()
                    .flex().flex_wrap()
                    .gap_2()
                    .children([
                        (!approved).then(|| design_system::button_with_leading_icon("automation-approve", "Approve", ButtonKind::Filled, self.automation_action_busy, icon(AleraIcon::ShieldCheck, 16.0, theme::on_accent())).on_click(cx.listener(move |this, _, _, cx| this.run_automation_request("automation.approve", json!({"id": id_for_approve.clone(), "revision": revision}), "Automation approved", cx)))),
                        Some(design_system::button_with_leading_icon("automation-run-now", "Run Now", ButtonKind::Filled, self.automation_action_busy, icon(AleraIcon::Agent, 14.0, theme::on_accent())).on_click(cx.listener(move |this, _, window, cx| this.open_automation_action_choice(id_for_run.clone(), revision, super::automation_action_choice::ActionKind::RunNow, window, cx)))),
                        can_pause.then(|| design_system::button("automation-pause", "Pause", ButtonKind::Outlined, self.automation_action_busy).on_click(cx.listener(move |this, _, window, cx| this.open_automation_action_choice(id_for_pause.clone(), revision, super::automation_action_choice::ActionKind::Pause, window, cx)))),
                        (!can_pause).then(|| design_system::button("automation-resume", "Resume", ButtonKind::Outlined, self.automation_action_busy || !can_resume).on_click(cx.listener(move |this, _, _, cx| this.run_automation_request("automation.resume", json!({"id": id_for_resume.clone()}), "Automation resumed", cx)))),
                        (state != "trashed").then(|| design_system::button("automation-trash", "Trash", ButtonKind::Text, self.automation_action_busy).on_click(cx.listener(move |this, _, _, cx| this.run_automation_request("automation.trash", json!({"id": id_for_trash.clone()}), "Automation trashed", cx)))),
                        (state == "trashed").then(|| design_system::button("automation-restore", "Restore", ButtonKind::Text, self.automation_action_busy).on_click(cx.listener(move |this, _, _, cx| this.run_automation_request("automation.restore", json!({"id": id_for_restore.clone()}), "Automation restored", cx)))),
                    ].into_iter().flatten()),
            )
            .child(self.render_automation_detail_tabs(detail, cx))
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
            .when_some(error, |group, error| group.child(div().mt_2().text_size(crate::theme::body_size()).text_color(theme::danger()).child(error)))
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
                    .text_size(crate::theme::body_size())
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
                    .text_size(crate::theme::body_size())
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

fn format_timestamp() -> String {
    chrono::Utc::now().to_rfc3339()
}

pub(super) fn automation_modal_surface(editor:bool,title:&'static str,content:AnyElement,on_dismiss:impl Fn(&gpui::MouseDownEvent,&mut Window,&mut gpui::App)+'static)->gpui::Div{
    // Outside-capture handlers reach lower modals first. Decide on the
    // bubbled backdrop hit without consuming interior text-selection events.
    let bounds=std::rc::Rc::new(std::cell::Cell::new(gpui::Bounds::default()));
    let hit_bounds=bounds.clone();
    div().absolute().inset_0().occlude().flex().items_center().justify_center().bg(theme::overlay_scrim()).p(px(32.0))
        .on_mouse_down(gpui::MouseButton::Left,move|event,window,cx|{
            if !hit_bounds.get().contains(&event.position){on_dismiss(event,window,cx);cx.stop_propagation();}
        })
        .child(div().id(if editor{"automation-editor-dialog"}else{"automations-dialog"}).role(Role::Dialog).aria_label(title).relative()
            .w(px(if editor{560.0}else{1180.0})).h(px(if editor{520.0}else{720.0})).max_w_full().max_h_full().flex().flex_col()
            .rounded_xl().border_1().border_color(theme::border_subtle()).bg(theme::surface()).shadow_lg().p(px(19.0)).child(content)
            .child(gpui::canvas(move|measured,_,_|bounds.set(measured),|_,_,_,_|{}).absolute().top_0().left_0().size_full()))
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
