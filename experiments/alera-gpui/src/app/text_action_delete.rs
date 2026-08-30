use gpui::{AnyElement, Context, FontWeight, InteractiveElement as _, IntoElement as _, MouseButton, ParentElement as _, StatefulInteractiveElement as _, Styled as _, Window, div, px};
use gpui_component::FocusTrapElement as _;

use super::AleraApp;
use crate::{design_system::{self, ButtonKind}, theme};

impl AleraApp {
    pub(super) fn request_text_action_delete(&mut self, id: String, window: &mut Window, cx: &mut Context<Self>) {
        if self.settings_state.loading || !self.settings_state.text_actions.iter().any(|action| action.id == id) { return; }
        self.text_actions_menu = None;
        self.text_actions_delete_epoch = self.text_actions_delete_epoch.wrapping_add(1);
        self.text_actions_delete_id = Some(id);
        self.text_actions_confirm_previous_focus = window.focused(cx);
        self.text_actions_confirm_focus.focus(window, cx);
        cx.notify();
    }

    pub(super) fn cancel_text_action_delete(&mut self, window: &mut Window, cx: &mut Context<Self>) {
        self.text_actions_delete_id = None;
        self.text_actions_delete_epoch = self.text_actions_delete_epoch.wrapping_add(1);
        if let Some(focus) = self.text_actions_confirm_previous_focus.take() { focus.focus(window, cx); }
        cx.notify();
    }

    pub(super) fn render_text_action_delete_dialog(&self, cx: &mut Context<Self>) -> AnyElement {
        let Some(id) = self.text_actions_delete_id.clone() else { return div().into_any_element(); };
        let epoch = self.text_actions_delete_epoch;
        let outside_id = id.clone();
        let cancel_id = id.clone();
        let dialog = design_system::dialog_shell("delete-text-action-dialog", "Delete Text Action", 420.0)
            .p(px(19.0)).rounded(px(12.0))
            .on_mouse_down(MouseButton::Left, |_, _, cx| cx.stop_propagation())
            .child(div().text_size(px(14.0)).line_height(px(21.0)).font_weight(FontWeight::MEDIUM).child("Delete Text Action"))
            .child(div().mt(px(12.0)).text_size(px(13.0)).text_color(theme::text_muted()).child("This action and its settings will be removed."))
            .child(div().mt(px(20.0)).flex().items_center().gap(px(8.0))
                .child(design_system::button("cancel-text-action-delete", "Cancel", ButtonKind::Text, false).flex_1()
                    .on_click(cx.listener(move |this, _, window, cx| {
                        if matches_request(this.text_actions_delete_id.as_deref(), this.text_actions_delete_epoch, &cancel_id, epoch) { this.cancel_text_action_delete(window, cx); }
                    })))
                .child(design_system::button("confirm-text-action-delete", "Delete", ButtonKind::Destructive, self.settings_state.loading).flex_1()
                    .on_click(cx.listener(move |this, _, window, cx| {
                        if !matches_request(this.text_actions_delete_id.as_deref(), this.text_actions_delete_epoch, &id, epoch) || this.settings_state.loading { return; }
                        this.text_actions_delete_id = None;
                        this.text_actions_delete_epoch = this.text_actions_delete_epoch.wrapping_add(1);
                        this.text_actions_confirm_previous_focus = None;
                        this.delete_text_action(id.clone(), window, cx);
                        this.settings_search_input.update(cx, |input, cx| input.focus(window, cx));
                    }))));
        div().id("text-action-delete-backdrop").absolute().inset_0().occlude()
            .flex().items_center().justify_center().bg(theme::overlay_scrim())
            .on_mouse_down(MouseButton::Left, cx.listener(move |this, _, window, cx| {
                if matches_request(this.text_actions_delete_id.as_deref(), this.text_actions_delete_epoch, &outside_id, epoch) { this.cancel_text_action_delete(window, cx); }
            }))
            .child(div().id("text-action-delete-dialog-semantics").role(gpui::Role::Dialog).aria_label("Delete Text Action. This action and its settings will be removed.")
                .child(dialog.focus_trap("text-action-delete-focus", &self.text_actions_confirm_focus)))
            .into_any_element()
    }
}

fn matches_request(current: Option<&str>, current_epoch: u64, target: &str, epoch: u64) -> bool {
    current == Some(target) && current_epoch == epoch
}

#[cfg(test)]
mod tests {
    #[test]
    fn text_action_delete_rejects_closed_reopened_or_retargeted_confirmation() {
        assert!(super::matches_request(Some("a"), 1, "a", 1));
        assert!(!super::matches_request(None, 1, "a", 1));
        assert!(!super::matches_request(Some("b"), 1, "a", 1));
        assert!(!super::matches_request(Some("a"), 3, "a", 1));
    }
}
