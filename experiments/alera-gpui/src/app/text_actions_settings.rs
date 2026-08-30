use gpui::{
    div, prelude::FluentBuilder as _, px, AnyElement, Context, CursorStyle,
    InteractiveElement as _, IntoElement, ParentElement as _, Role, SharedString,
    StatefulInteractiveElement as _, Styled as _, Window,
};
use gpui_component::input::Textarea;
use gpui_component::scroll::ScrollableElement as _;
use uuid::Uuid;

use super::settings_panes::settings_master_resize_handle;
use super::{AleraApp, SettingsMasterResizeTarget, TextActionSetting};
use crate::design_system::{self, ButtonKind};
use crate::icons::{icon, AleraIcon};
use crate::theme;

impl AleraApp {
    pub(super) fn new_text_action(&mut self, window: &mut Window, cx: &mut Context<Self>) {
        self.text_actions_creating_new = true;
        self.text_actions_selected_id = Some(Uuid::new_v4().to_string());
        self.text_actions_error = None;
        for input in [
            &self.text_actions_name_input,
            &self.text_actions_agent_input,
            &self.text_actions_model_input,
            &self.text_actions_reasoning_input,
        ] {
            input.update(cx, |input, cx| input.set_value("", window, cx));
        }
        self.text_actions_prompt_input
            .update(cx, |input, cx| input.set_value("", window, cx));
        cx.notify();
    }

    pub(super) fn select_text_action(
        &mut self,
        id: String,
        window: &mut Window,
        cx: &mut Context<Self>,
    ) {
        let Some(action) = self
            .settings_state
            .text_actions
            .iter()
            .find(|action| action.id == id)
            .cloned()
        else {
            return;
        };
        self.text_actions_creating_new = false;
        self.text_actions_selected_id = Some(id);
        self.text_actions_error = None;
        self.seed_text_action_inputs(&action, window, cx);
        cx.notify();
    }

    fn seed_text_action_inputs(
        &mut self,
        action: &TextActionSetting,
        window: &mut Window,
        cx: &mut Context<Self>,
    ) {
        self.text_actions_name_input
            .update(cx, |input, cx| input.set_value(&action.name, window, cx));
        self.text_actions_prompt_input
            .update(cx, |input, cx| input.set_value(&action.prompt, window, cx));
        self.text_actions_agent_input.update(cx, |input, cx| {
            input.set_value(
                action.agent_override.as_deref().unwrap_or_default(),
                window,
                cx,
            )
        });
        self.text_actions_model_input.update(cx, |input, cx| {
            input.set_value(
                action.model_override.as_deref().unwrap_or_default(),
                window,
                cx,
            )
        });
        let reasoning = action
            .model_override
            .as_deref()
            .and_then(|model| action.reasoning_by_model.get(model))
            .cloned()
            .unwrap_or_default();
        self.text_actions_reasoning_input
            .update(cx, |input, cx| input.set_value(reasoning, window, cx));
    }

    pub(super) fn toggle_text_action(&mut self, id: String, enabled: bool, cx: &mut Context<Self>) {
        if let Some(action) = self
            .settings_state
            .text_actions
            .iter_mut()
            .find(|action| action.id == id)
        {
            action.enabled = enabled;
            self.persist_text_actions(cx);
        }
    }

    pub(super) fn duplicate_text_action(&mut self, id: String, cx: &mut Context<Self>) {
        let Some(source) = self
            .settings_state
            .text_actions
            .iter()
            .find(|action| action.id == id)
            .cloned()
        else {
            return;
        };
        let mut name = format!("{} Copy", source.name.trim());
        let names = self
            .settings_state
            .text_actions
            .iter()
            .map(|action| action.name.to_ascii_lowercase())
            .collect::<std::collections::BTreeSet<_>>();
        let mut suffix = 2;
        while names.contains(&name.to_ascii_lowercase()) {
            name = format!("{} Copy {suffix}", source.name.trim());
            suffix += 1;
        }
        let clone = TextActionSetting {
            id: Uuid::new_v4().to_string(),
            name,
            ..source
        };
        let index = self
            .settings_state
            .text_actions
            .iter()
            .position(|action| action.id == id)
            .map(|index| index + 1)
            .unwrap_or(self.settings_state.text_actions.len());
        self.settings_state
            .text_actions
            .insert(index, clone.clone());
        self.text_actions_selected_id = Some(clone.id.clone());
        self.text_actions_creating_new = false;
        self.persist_text_actions(cx);
        cx.notify();
    }

    pub(super) fn save_text_action(&mut self, window: &mut Window, cx: &mut Context<Self>) {
        let id = self
            .text_actions_selected_id
            .clone()
            .unwrap_or_else(|| Uuid::new_v4().to_string());
        let name = self.text_actions_name_input.read(cx).value().to_string();
        let prompt = self.text_actions_prompt_input.read(cx).value().to_string();
        let name = name.trim().to_owned();
        let prompt = prompt.trim().to_owned();
        if name.is_empty() || prompt.is_empty() {
            self.text_actions_error = Some("Action name and prompt are required.".into());
            cx.notify();
            return;
        }
        if self
            .settings_state
            .text_actions
            .iter()
            .any(|action| action.id != id && action.name.trim().eq_ignore_ascii_case(name.as_str()))
        {
            self.text_actions_error = Some("Action names must be unique.".into());
            cx.notify();
            return;
        }
        let agent_override = self
            .text_actions_agent_input
            .read(cx)
            .value()
            .to_string()
            .trim()
            .to_ascii_lowercase();
        let model_override = self
            .text_actions_model_input
            .read(cx)
            .value()
            .to_string()
            .trim()
            .to_owned();
        let reasoning = self
            .text_actions_reasoning_input
            .read(cx)
            .value()
            .to_string()
            .trim()
            .to_owned();
        let mut reasoning_by_model = std::collections::BTreeMap::new();
        if !model_override.is_empty() && !reasoning.is_empty() {
            reasoning_by_model.insert(model_override.clone(), reasoning);
        }
        let action = TextActionSetting {
            id: id.clone(),
            name,
            prompt,
            enabled: self
                .settings_state
                .text_actions
                .iter()
                .find(|candidate| candidate.id == id)
                .map(|candidate| candidate.enabled)
                .unwrap_or(true),
            agent_override: (!agent_override.is_empty()).then_some(agent_override),
            model_override: (!model_override.is_empty()).then_some(model_override),
            reasoning_by_model,
        };
        if self.text_actions_creating_new {
            self.settings_state.text_actions.push(action.clone());
        } else if let Some(existing) = self
            .settings_state
            .text_actions
            .iter_mut()
            .find(|candidate| candidate.id == id)
        {
            *existing = action.clone();
        } else {
            self.settings_state.text_actions.push(action.clone());
        }
        self.text_actions_creating_new = false;
        self.text_actions_selected_id = Some(id);
        self.text_actions_error = None;
        self.seed_text_action_inputs(&action, window, cx);
        self.persist_text_actions(cx);
        cx.notify();
    }

    pub(super) fn delete_text_action(&mut self, id: String, cx: &mut Context<Self>) {
        self.settings_state
            .text_actions
            .retain(|action| action.id != id);
        self.text_actions_selected_id = self
            .settings_state
            .text_actions
            .first()
            .map(|action| action.id.clone());
        self.text_actions_creating_new = false;
        self.persist_text_actions(cx);
        cx.notify();
    }

    fn persist_text_actions(&mut self, cx: &mut Context<Self>) {
        self.persist_settings();
        self.update_runtime_setting(
            "textActions",
            self.settings_state.runtime_text_actions_payload(),
            cx,
        );
    }

    pub(super) fn render_text_actions_settings_pane(&self, cx: &mut Context<Self>) -> AnyElement {
        let selected_id = self.text_actions_selected_id.clone();
        let actions = self.settings_state.text_actions.clone();
        let selected = selected_id
            .as_deref()
            .and_then(|id| actions.iter().find(|action| action.id == id));
        let selected_id_for_rows = selected_id.clone();
        let master = div()
            .w(px(self.settings_text_actions_master_width))
            .flex_shrink_0()
            .flex()
            .flex_col()
            .min_h_0()
            .child(
                div()
                    .flex()
                    .items_center()
                    .h(px(34.0))
                    .child(
                        div()
                            .text_size(px(13.0))
                            .font_weight(gpui::FontWeight::SEMIBOLD)
                            .child("Text Actions"),
                    )
                    .child(div().flex_1())
                    .child(
                        design_system::icon_button(
                            "new-text-action",
                            "New Action",
                            AleraIcon::Add,
                            true,
                            30.0,
                            None,
                            None,
                        )
                        .on_click(cx.listener(|this, _, window, cx| {
                            this.new_text_action(window, cx);
                        })),
                    ),
            )
            .child(
                div()
                    .id("text-actions-list")
                    .flex_1()
                    .min_h_0()
                    .overflow_y_scrollbar()
                    .rounded_lg()
                    .border_1()
                    .border_color(theme::border_subtle())
                    .bg(theme::surface_selected())
                    .when(actions.is_empty(), |list| {
                        list.child(
                            div()
                                .p_4()
                                .text_size(px(12.0))
                                .text_color(theme::text_muted())
                                .child("No text actions."),
                        )
                    })
                    .children(actions.iter().enumerate().map(|(index, action)| {
                        let id = action.id.clone();
                        let duplicate_id = action.id.clone();
                        let enabled = action.enabled;
                        let selected = selected_id_for_rows.as_deref() == Some(action.id.as_str());
                        div()
                            .id(SharedString::from(format!("text-action-row-{index}")))
                            .role(Role::ListBoxOption)
                            .aria_label(action.name.clone())
                            .aria_selected(selected)
                            .flex()
                            .items_center()
                            .gap_1()
                            .px_2()
                            .py_2()
                            .cursor(CursorStyle::PointingHand)
                            .when(selected, |row| row.bg(theme::accent_subtle()))
                            .hover(|style| style.bg(theme::surface_raised()))
                            .on_click(cx.listener(move |this, _, window, cx| {
                                this.select_text_action(id.clone(), window, cx);
                            }))
                            .child(icon(AleraIcon::Tune, 14.0, theme::text_faint()))
                            .child(div().min_w_0().flex_1().child(action.name.clone()).when(
                                !enabled,
                                |row| {
                                    row.child(
                                        div()
                                            .text_size(crate::theme::caption_size())
                                            .text_color(theme::text_faint())
                                            .child("Disabled"),
                                    )
                                },
                            ))
                            .child(
                                design_system::switch(action.enabled, true)
                                    .id(SharedString::from(format!("text-action-enabled-{index}")))
                                    .on_click(cx.listener(move |this, _, _, cx| {
                                        this.toggle_text_action(duplicate_id.clone(), !enabled, cx);
                                        cx.stop_propagation();
                                    })),
                            )
                    })),
            );
        let detail = if let Some(action) = selected {
            let id = action.id.clone();
            let duplicate_id = id.clone();
            div().flex_1().min_w_0().min_h_0().child(
                div()
                    .flex()
                    .flex_col()
                    .size_full()
                    .overflow_y_scrollbar()
                    .child(
                        div()
                            .p_3()
                            .child(
                                div()
                                    .text_size(px(13.0))
                                    .font_weight(gpui::FontWeight::SEMIBOLD)
                                    .child("Action"),
                            )
                            .child(
                                div().mt_2().child(
                                    design_system::text_field(&self.text_actions_name_input)
                                        .label("Name"),
                                ),
                            )
                            .child(
                                div().mt_2().h(px(120.0)).child(
                                    Textarea::new(&self.text_actions_prompt_input)
                                        .aria_label("Prompt")
                                        .h_full(),
                                ),
                            )
                            .child(
                                div()
                                    .mt_2()
                                    .text_size(px(11.0))
                                    .text_color(theme::text_muted())
                                    .child("Prompt used to replace the selected text."),
                            ),
                    )
                    .child(
                        div()
                            .p_3()
                            .child(
                                div()
                                    .text_size(px(13.0))
                                    .font_weight(gpui::FontWeight::SEMIBOLD)
                                    .child("Agent"),
                            )
                            .child(
                                div().mt_2().child(
                                    design_system::text_field(&self.text_actions_agent_input)
                                        .label("Agent Override"),
                                ),
                            )
                            .child(
                                div().mt_2().child(
                                    design_system::text_field(&self.text_actions_model_input)
                                        .label("Model Override"),
                                ),
                            )
                            .child(
                                div().mt_2().child(
                                    design_system::text_field(&self.text_actions_reasoning_input)
                                        .label("Reasoning Override"),
                                ),
                            ),
                    )
                    .when_some(self.text_actions_error.clone(), |detail, error| {
                        detail.child(div().p_3().text_color(theme::danger()).child(error))
                    })
                    .child(
                        div()
                            .p_3()
                            .flex()
                            .justify_end()
                            .gap_2()
                            .child(
                                design_system::button(
                                    "duplicate-text-action",
                                    "Duplicate",
                                    crate::design_system::ButtonKind::Outlined,
                                    false,
                                )
                                .on_click(cx.listener(
                                    move |this, _, _, cx| {
                                        this.duplicate_text_action(duplicate_id.clone(), cx);
                                    },
                                )),
                            )
                            .child(
                                design_system::button(
                                    "delete-text-action",
                                    "Delete",
                                    crate::design_system::ButtonKind::Destructive,
                                    false,
                                )
                                .on_click(cx.listener(
                                    move |this, _, _, cx| {
                                        this.delete_text_action(id.clone(), cx);
                                    },
                                )),
                            )
                            .child(
                                design_system::button(
                                    "save-text-action",
                                    "Save",
                                    ButtonKind::Filled,
                                    false,
                                )
                                .on_click(cx.listener(
                                    |this, _, window, cx| {
                                        this.save_text_action(window, cx);
                                    },
                                )),
                            ),
                    ),
            )
        } else if self.text_actions_creating_new {
            let new_content = div()
                .p_3()
                .child(
                    div()
                        .text_size(px(13.0))
                        .font_weight(gpui::FontWeight::SEMIBOLD)
                        .child("New Text Action"),
                )
                .child(
                    div().mt_2().child(
                        design_system::text_field(&self.text_actions_name_input).label("Name"),
                    ),
                )
                .child(
                    div().mt_2().h(px(120.0)).child(
                        Textarea::new(&self.text_actions_prompt_input)
                            .aria_label("Prompt")
                            .h_full(),
                    ),
                )
                .child(
                    div().mt_2().child(
                        design_system::button(
                            "save-text-action-new",
                            "Save",
                            ButtonKind::Filled,
                            false,
                        )
                        .on_click(cx.listener(|this, _, window, cx| {
                            this.save_text_action(window, cx);
                        })),
                    ),
                );
            div().flex_1().min_w_0().child(new_content)
        } else {
            div()
                .flex_1()
                .flex()
                .items_center()
                .justify_center()
                .text_color(theme::text_muted())
                .child("Select a text action or create a new one.")
        };
        div()
            .relative()
            .flex()
            .flex_1()
            .min_h_0()
            .child(master)
            .child(settings_master_resize_handle(
                SettingsMasterResizeTarget::TextActions,
                cx,
            ))
            .child(detail)
            .into_any_element()
    }
}
