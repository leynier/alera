use gpui::{div, prelude::FluentBuilder as _, px, AnyElement, AppContext as _, Context, CursorStyle, InteractiveElement as _, IntoElement, ParentElement as _, Role, SharedString, StatefulInteractiveElement as _, Styled as _};
use gpui_component::scroll::ScrollableElement as _;
use gpui_component::tooltip::Tooltip;

use super::settings_panes::settings_master_resize_handle;
use super::{AleraApp, SettingsMasterResizeTarget};
use super::text_action_reorder::TextActionDrag;
use crate::design_system::{self, ButtonKind};
use crate::icons::{icon, AleraIcon};
use crate::theme;

impl AleraApp {
    pub(super) fn render_text_actions_settings_pane(&self, window: &mut gpui::Window, cx: &mut Context<Self>) -> AnyElement {
        let selected_id = self.text_actions_selected_id.clone();
        let actions = &self.settings_state.text_actions;
        let drag_order = std::sync::Arc::new(actions.iter().map(|action| action.id.clone()).collect());
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
            .h_full()
            .child(
                div()
                    .flex()
                    .items_center()
                    .h(px(26.0))
                    .flex_shrink_0()
                    .pl(px(4.0))
                    .mb(px(8.0))
                    .child(
                        div()
                            .text_size(px(13.0))
                            .font_weight(gpui::FontWeight::SEMIBOLD)
                            .child("Text Actions"),
                    )
                    .child(div().flex_1())
                    .child(
                        design_system::button_with_leading_icon(
                            "new-text-action",
                            "New Action",
                            ButtonKind::Filled,
                            false,
                            icon(AleraIcon::Add, 16.0, theme::on_accent()).into_any_element(),
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
                    .when(actions.is_empty(), |list| {
                        list.child(design_system::empty_state("empty-text-actions", AleraIcon::Text,
                            "No text actions", "Create an action to replace selected text with AI."))
                    })
                    .when(!actions.is_empty(), |list| {
                        list.rounded_lg().border_1()
                            .border_color(theme::border_subtle()).bg(theme::surface_selected())
                    })
                    .children(actions.iter().map(|action| {
                        let id = action.id.clone();
                        let duplicate_id = action.id.clone();
                        let toggle_id = action.id.clone();
                        let target_id = action.id.clone();
                        let drag = TextActionDrag { id: action.id.clone(), name: action.name.clone(), enabled: action.enabled,
                            width: self.settings_text_actions_master_width, order: std::sync::Arc::clone(&drag_order) };
                        let enabled = action.enabled;
                        let selected = selected_id_for_rows.as_deref() == Some(action.id.as_str());
                        div()
                            .id(SharedString::from(format!("text-action-row-{}", action.id)))
                            .role(Role::ListBoxOption)
                            .aria_label(action.name.clone())
                            .aria_selected(selected)
                            .flex()
                            .items_center()
                            .gap_1()
                            .px_2()
                            .py(px(6.0))
                            .cursor(CursorStyle::PointingHand)
                            .when(selected, |row| row.bg(theme::accent_subtle()))
                            .hover(|style| style.bg(theme::surface_raised()))
                            .drag_over::<TextActionDrag>(|style, _, _, _| style.bg(theme::accent_subtle()))
                            .on_drop(cx.listener(move |this, drag: &TextActionDrag, _, cx| {
                                this.reorder_text_action(drag, &target_id, cx);
                                cx.stop_propagation();
                            }))
                            .on_click(cx.listener(move |this, _, window, cx| {
                                this.select_text_action(id.clone(), window, cx);
                            }))
                            .child(div().id(SharedString::from(format!("drag-text-action-{}", action.id)))
                                .on_drag(drag, |drag, _, _, cx| cx.new(|_| drag.clone()))
                                .child(icon(AleraIcon::DragHandle, 16.0, theme::text_faint())))
                            .child(div().min_w_0().flex_1().child(div().text_ellipsis().text_size(px(13.0))
                                .font_weight(gpui::FontWeight::SEMIBOLD).child(action.name.clone())).when(
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
                                div().id(SharedString::from(format!("text-action-enabled-{}", action.id)))
                                    .role(Role::Switch).aria_label(format!("Enable {}", action.name))
                                    .aria_toggled(if enabled { gpui::Toggled::True } else { gpui::Toggled::False })
                                    .w(px(60.0)).h(px(40.0)).flex().items_center().justify_center()
                                    .on_click(cx.listener(move |this, _, _, cx| {
                                        this.toggle_text_action(toggle_id.clone(), !enabled, cx);
                                        cx.stop_propagation();
                                    })).child(design_system::switch(action.enabled, true)),
                            )
                            .child(design_system::icon_button(SharedString::from(format!("duplicate-text-action-{}", action.id)),
                                "Duplicate", AleraIcon::Duplicate, !self.settings_state.loading, 22.0, None, None)
                                .tooltip(|_, cx| cx.new(|_| Tooltip::new("Duplicate")).into())
                                .on_click(cx.listener(move |this, _, window, cx| {
                                    this.duplicate_text_action(duplicate_id.clone(), window, cx);
                                    cx.stop_propagation();
                                })))
                    })),
            );
        let detail = if selected.is_some() || self.text_actions_creating_new {
            self.render_text_action_editor(window, cx)
        } else {
            div().flex_1().min_w_0().min_h_0().child(design_system::empty_state(
                "unselected-text-action", AleraIcon::Text, "Select a text action", "Choose an action or create a new one."))
        };
        div()
            .relative()
            .flex()
            .flex_1()
            .size_full()
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
