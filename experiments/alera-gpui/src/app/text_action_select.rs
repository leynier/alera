use gpui::{AnyElement, Context, CursorStyle, InteractiveElement as _, IntoElement as _, ParentElement as _, Role, SharedString, StatefulInteractiveElement as _, Styled as _, Window, anchored, canvas, deferred, div, point, px, prelude::FluentBuilder as _};

use super::{AleraApp, text_action_editor_state::{TextActionField, TextActionMenu}};
use crate::{design_system, icons::{AleraIcon, icon}, theme};

impl AleraApp {
    pub(super) fn reconcile_text_action_menu(&mut self, window: &mut Window, cx: &mut Context<Self>) {
        if self.text_actions_menu.as_ref().is_some_and(|menu| self.text_action_menu_context(menu.field).as_ref() != Some(menu)) {
            let restore = self.text_actions_menu_focus.is_focused(window);
            self.close_text_action_menu(restore, window, cx);
        }
    }

    fn text_action_menu_context(&self, field: TextActionField) -> Option<TextActionMenu> {
        Some(TextActionMenu { epoch: self.text_actions_menu_epoch, action_id: self.text_actions_selected_id.clone()?, field,
            agent: self.text_actions_draft.agent(&self.settings_state).to_owned(), model: self.text_actions_draft.model_id(&self.settings_state) })
    }

    pub(super) fn close_text_action_menu(&mut self, restore_focus: bool, window: &mut Window, cx: &mut Context<Self>) {
        if let Some(menu) = self.text_actions_menu.take() {
            self.text_actions_menu_epoch = self.text_actions_menu_epoch.wrapping_add(1);
            if restore_focus && self.text_actions_selected_id.as_deref() == Some(menu.action_id.as_str()) {
                self.text_actions_field_focus[menu.field.index()].focus(window, cx);
            }
            cx.notify();
        }
    }

    fn choose_text_action_option(&mut self, menu: &TextActionMenu, value: Option<String>, window: &mut Window, cx: &mut Context<Self>) {
        if self.text_actions_menu.as_ref() != Some(menu) || self.text_action_menu_context(menu.field).as_ref() != Some(menu) { return; }
        if self.text_actions_draft.choose(menu.field, value, &self.settings_state) {
            self.text_actions_error = None;
            self.close_text_action_menu(true, window, cx);
        }
    }

    fn text_action_menu_key(&mut self, event: &gpui::KeyDownEvent, window: &mut Window, cx: &mut Context<Self>) {
        let Some(menu) = self.text_actions_menu.clone() else { return; };
        let choices = self.text_actions_draft.choices(menu.field, &self.settings_state);
        if choices.is_empty() { return; }
        match event.keystroke.key.as_str() {
            "up" => self.text_actions_menu_index = (self.text_actions_menu_index + choices.len() - 1) % choices.len(),
            "down" => self.text_actions_menu_index = (self.text_actions_menu_index + 1) % choices.len(),
            "home" => self.text_actions_menu_index = 0,
            "end" => self.text_actions_menu_index = choices.len() - 1,
            "enter" => { if let Some(choice) = choices.get(self.text_actions_menu_index) { self.choose_text_action_option(&menu, choice.value.clone(), window, cx); } }
            "escape" => self.close_text_action_menu(true, window, cx),
            _ => return,
        }
        self.text_actions_menu_scroll.scroll_to_item(self.text_actions_menu_index);
        cx.stop_propagation();
        cx.notify();
    }

    pub(super) fn render_text_action_select(&self, field: TextActionField, window: &mut Window, cx: &mut Context<Self>) -> AnyElement {
        let Some(context) = self.text_action_menu_context(field) else { return div().into_any_element(); };
        let expanded = self.text_actions_menu.as_ref() == Some(&context);
        let id = context.action_id.clone();
        let bounds = self.text_actions_field_bounds[field.index()].clone();
        let geometry = bounds.clone();
        let label = self.text_actions_draft.label(field, &self.settings_state);
        let busy = self.settings_state.loading;
        let trigger = design_system::dropdown_trigger(SharedString::from(format!("text-action-{}", field.label())), label, expanded, !busy)
                .track_focus(&self.text_actions_field_focus[field.index()])
                .on_click(cx.listener(move |this, _, window, cx| {
                    if this.settings_state.loading || this.text_actions_selected_id.as_deref() != Some(id.as_str()) { return; }
                    if this.text_actions_menu.as_ref().is_some_and(|menu| menu.field == field) {
                        this.close_text_action_menu(true, window, cx);
                    } else {
                        this.text_actions_menu_epoch = this.text_actions_menu_epoch.wrapping_add(1);
                        let Some(menu) = this.text_action_menu_context(field) else { return; };
                        let value = this.text_actions_draft.value(field, &this.settings_state);
                        this.text_actions_menu_index = this.text_actions_draft.choices(field, &this.settings_state).iter().position(|choice| choice.value == value).unwrap_or(0);
                        this.text_actions_menu = Some(menu);
                        this.text_actions_menu_scroll.set_offset(point(px(0.0), px(0.0)));
                        this.text_actions_menu_scroll.scroll_to_item(this.text_actions_menu_index);
                        this.text_actions_menu_focus.focus(window, cx);
                        cx.notify();
                    }
                }));
        measured_trigger(trigger, geometry, expanded)
            .id(SharedString::from(format!("text-action-{}-container", field.label())))
            .when(expanded, |container| {
                let position = bounds.get();
                container.child(deferred(anchored().position(position.bottom_left() + point(px(0.0), px(4.0)))
                    .snap_to_window_with_margin(px(8.0))
                    .child(self.render_text_action_menu(context, position.size.width.max(px(220.0)), window.viewport_size().height - px(16.0), cx))).with_priority(2))
            }).into_any_element()
    }

    fn render_text_action_menu(&self, menu: TextActionMenu, width: gpui::Pixels, max_height: gpui::Pixels, cx: &mut Context<Self>) -> AnyElement {
        let selected = self.text_actions_draft.value(menu.field, &self.settings_state);
        let choices = self.text_actions_draft.choices(menu.field, &self.settings_state);
        let outside = menu.clone();
        div().id("text-action-options").role(Role::ListBox).aria_label(format!("{} Options", menu.field.label()))
            .track_focus(&self.text_actions_menu_focus).key_context("TextActionOptions")
            .on_key_down(cx.listener(Self::text_action_menu_key))
            .on_mouse_down_out(cx.listener(move |this, event: &gpui::MouseDownEvent, window, cx| {
                if this.text_actions_menu.as_ref() == Some(&outside) && !this.text_actions_field_bounds[outside.field.index()].get().contains(&event.position) {
                    this.close_text_action_menu(false, window, cx);
                    cx.stop_propagation();
                }
            }))
            .occlude().w(width).max_h(max_height).track_scroll(&self.text_actions_menu_scroll).overflow_y_scroll().p(px(11.0)).flex().flex_col()
            .rounded(px(6.0)).border_1().border_color(theme::border()).bg(theme::surface()).shadow_lg()
            .children(choices.into_iter().enumerate().map(|(index, choice)| {
                let checked = choice.value == selected;
                let context = menu.clone();
                div().id(("text-action-option", index)).role(Role::ListBoxOption).aria_label(choice.label.clone()).aria_selected(checked)
                    .cursor(CursorStyle::PointingHand).flex().items_center().flex_shrink_0().my(px(1.0)).px(px(8.0)).py(px(4.0)).rounded(px(10.0))
                    .when(index == self.text_actions_menu_index, |row| row.bg(theme::surface_raised()))
                    .hover(|style| style.bg(theme::surface_raised()))
                    .on_click(cx.listener(move |this, _, window, cx| this.choose_text_action_option(&context, choice.value.clone(), window, cx)))
                    .child(div().min_w_0().flex_1().text_size(px(13.0)).text_color(theme::text()).child(choice.label))
                    .when(checked, |row| row.child(icon(AleraIcon::Check, 16.0, theme::text())))
            })).into_any_element()
    }
}

fn measured_trigger(trigger: impl gpui::IntoElement, geometry: std::rc::Rc<std::cell::Cell<gpui::Bounds<gpui::Pixels>>>, expanded: bool) -> gpui::Div {
    div().relative().h(px(34.0)).w_full().child(trigger)
        .child(canvas(move |measured, window, _| {
            if geometry.replace(measured) != measured && expanded { window.request_animation_frame(); }
        }, |_, _, _, _| {}).absolute().top_0().left_0().size_full())
}

#[cfg(all(test, feature = "gpui-tests"))]
mod tests {
    use super::*;
    use gpui::{Render, TestAppContext};

    struct TriggerProbe { bounds: std::rc::Rc<std::cell::Cell<gpui::Bounds<gpui::Pixels>>> }

    impl Render for TriggerProbe {
        fn render(&mut self, _: &mut Window, _: &mut Context<Self>) -> impl gpui::IntoElement {
            div().w(px(400.0)).h(px(300.0)).p(px(20.0)).child(measured_trigger(
                div().w_full().h(px(34.0)).debug_selector(|| "text-action-trigger-probe".into()), self.bounds.clone(), false))
        }
    }

    #[gpui::test]
    fn text_action_dropdown_bounds_match_trigger_not_static_position_after_it(cx: &mut TestAppContext) {
        let bounds = std::rc::Rc::new(std::cell::Cell::new(gpui::Bounds::default()));
        let (_, cx) = cx.add_window_view(|_, _| TriggerProbe { bounds: bounds.clone() });
        cx.run_until_parked();
        cx.update(|window, cx| { let _ = window.draw(cx); });
        assert_eq!(bounds.get(), cx.debug_bounds("text-action-trigger-probe").unwrap());
        assert_eq!(bounds.get().bottom(), px(54.0));
    }
}
