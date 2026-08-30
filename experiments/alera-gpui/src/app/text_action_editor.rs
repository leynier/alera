use gpui::{Context, InteractiveElement as _, IntoElement as _, ParentElement as _, StatefulInteractiveElement as _, Styled as _, Window, div, px, prelude::FluentBuilder as _};
use gpui_component::scroll::ScrollableElement as _;

use super::{AleraApp, text_action_editor_state::TextActionField};
use super::settings_panes::{exact_settings_group, exact_settings_row};
use crate::{design_system::{self, ButtonKind}, icons::{AleraIcon, icon}, theme};

impl AleraApp {
    pub(super) fn render_text_action_editor(&self, window: &mut Window, cx: &mut Context<Self>) -> gpui::Div {
        let action_id = self.text_actions_selected_id.clone().unwrap_or_default();
        let toggle_id = action_id.clone();
        let delete_id = action_id.clone();
        let enabled = self.text_actions_draft.enabled;
        let busy = self.settings_state.loading;
        let action = exact_settings_group("Action", "Define the reusable instruction and its availability.", vec![
            div().p(px(12.0))
                .child(design_system::text_field(&self.text_actions_name_input).label("Name")
                    .prefix(icon(AleraIcon::Text, 16.0, theme::text_muted()).into_any_element())),
            div().px(px(12.0)).pb(px(12.0))
                .child(design_system::AleraTextArea::new(&self.text_actions_prompt_input, "Prompt")),
            exact_settings_row("Enabled", "Show this action in the Text Actions menu.",
                div().id("text-action-draft-enabled").role(gpui::Role::Switch).aria_label("Enabled")
                    .aria_toggled(if enabled { gpui::Toggled::True } else { gpui::Toggled::False })
                    .w(px(60.0)).h(px(40.0)).flex().items_center().justify_center()
                    .on_click(cx.listener(move |this, _, _, cx| {
                        if !this.settings_state.loading && this.text_actions_selected_id.as_deref() == Some(toggle_id.as_str()) {
                            this.text_actions_draft.enabled = !enabled;
                            cx.notify();
                        }
                    })).child(design_system::switch(enabled, !busy))),
        ]);
        let mut agent_rows = vec![
            exact_settings_row("Agent", "Inherit the global AI Assist agent by default.", self.render_text_action_select(TextActionField::Agent, window, cx)),
            exact_settings_row("Model", "Inherit the selected model unless overridden.", self.render_text_action_select(TextActionField::Model, window, cx)),
        ];
        if !self.text_actions_draft.model(&self.settings_state).thinking_levels.is_empty() {
            agent_rows.push(exact_settings_row("Reasoning", "Reasoning effort for the effective model.", self.render_text_action_select(TextActionField::Reasoning, window, cx)));
        }
        let content = div().flex().flex_col().gap(px(16.0)).flex_shrink_0()
            .child(action)
            .child(exact_settings_group("Agent", "Choose which CLI and model run this action.", agent_rows))
            .when_some(self.text_actions_error.clone(), |content, error| {
                content.child(div().id("text-action-error").role(gpui::Role::Alert).aria_label(error.clone())
                    .text_size(px(12.0)).text_color(theme::danger()).child(error))
            })
            .child(div().flex().items_center()
                .when(!self.text_actions_creating_new, |buttons| buttons.child(
                    design_system::button_with_leading_icon("delete-text-action", "Delete", ButtonKind::Text, busy,
                        icon(AleraIcon::Delete, 16.0, theme::danger()).into_any_element())
                        .text_color(theme::danger()).on_click(cx.listener(move |this, _, window, cx| {
                            if this.text_actions_selected_id.as_deref() == Some(delete_id.as_str()) {
                                this.request_text_action_delete(delete_id.clone(), window, cx);
                            }
                        }))))
                .child(div().flex_1())
                .child(design_system::button_with_leading_icon("save-text-action", "Save", ButtonKind::Filled, busy,
                    icon(AleraIcon::Save, 16.0, theme::on_accent()).into_any_element())
                    .on_click(cx.listener(move |this, _, window, cx| {
                        if this.text_actions_selected_id.as_deref() == Some(action_id.as_str()) {
                            this.save_text_action(window, cx);
                        }
                    }))));
        div().flex_1().min_w_0().min_h_0().h_full().child(
            div().id("text-action-editor-scroll").size_full().overflow_y_scrollbar().child(content))
    }
}
