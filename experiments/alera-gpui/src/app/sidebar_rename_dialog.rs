use gpui::{AnyElement, Context, Focusable as _, InteractiveElement as _, IntoElement as _, KeyDownEvent, MouseButton, ParentElement as _, StatefulInteractiveElement as _, Styled as _, Window, div, px};
use gpui_component::input::{Enter, InputEvent};
use gpui_component::FocusTrapElement as _;

use super::{AleraApp, SidebarDialogKind};
use crate::{design_system::{self, ButtonKind}, theme};

impl AleraApp {
    pub(super) fn handle_sidebar_rename_input(&mut self, event: &InputEvent, window: &mut Window, cx: &mut Context<Self>) {
        if !self.sidebar_dialog.as_ref().is_some_and(|dialog| matches!(dialog.kind, SidebarDialogKind::RenameProject | SidebarDialogKind::RenameWorkspace)) {
            return;
        }
        match event {
            InputEvent::PressEnter { .. } => self.submit_sidebar_dialog(window, cx),
            InputEvent::Change => { self.error = None; cx.notify(); }
            _ => cx.notify(),
        }
    }

    pub(super) fn restore_sidebar_dialog_focus(&mut self, window: &mut Window, cx: &mut Context<Self>) {
        if let Some(focus) = self.sidebar_dialog_previous_focus.take() {
            focus.focus(window, cx);
        } else {
            self.shell_focus.focus(window, cx);
        }
    }

    fn handle_sidebar_rename_key(&mut self, event: &KeyDownEvent, window: &mut Window, cx: &mut Context<Self>) {
        let handles = [self.sidebar_action_input.focus_handle(cx), self.sidebar_rename_button_focus[0].clone(), self.sidebar_rename_button_focus[1].clone()];
        let focused = handles.iter().position(|handle| handle.is_focused(window));
        match event.keystroke.key.as_str() {
            "tab" => {
                let next = match focused {
                    Some(index) if event.keystroke.modifiers.shift => (index + 2) % 3,
                    Some(index) => (index + 1) % 3,
                    None => 0,
                };
                handles[next].focus(window, cx);
            }
            "escape" => self.close_sidebar_dialog(window, cx),
            "enter" | "return" | "space" if focused == Some(1) => self.close_sidebar_dialog(window, cx),
            "enter" | "return" | "space" if focused == Some(2) => self.submit_sidebar_dialog(window, cx),
            _ => return,
        }
        cx.stop_propagation();
        cx.notify();
    }

    pub(super) fn render_sidebar_rename_dialog(&self, kind: SidebarDialogKind, cx: &mut Context<Self>) -> AnyElement {
        let (title, label) = if kind == SidebarDialogKind::RenameProject {
            ("Rename Project", "Project Name")
        } else {
            ("Rename Workspace", "Workspace Name")
        };
        div().absolute().inset_0().occlude().flex().items_center().justify_center().bg(theme::overlay_scrim())
            .on_mouse_down(MouseButton::Left, cx.listener(|this, _, window, cx| this.close_sidebar_dialog(window, cx)))
            .child(div().id("sidebar-rename-focus-root")
                .focus_trap("sidebar-rename-focus", &self.sidebar_rename_focus)
                .child(design_system::dialog_shell("sidebar-action-dialog", title, 420.0)
                .debug_selector(|| "sidebar-rename-dialog".into())
                .capture_key_down(cx.listener(Self::handle_sidebar_rename_key))
                // Input emits PressEnter and propagates its action. Consume the
                // action so it cannot fall back to a newline and clear validation.
                .on_action(|_: &Enter, _, cx| cx.stop_propagation())
                .on_mouse_down(MouseButton::Left, |_, _, cx| cx.stop_propagation())
                .child(div().text_size(px(14.0)).font_weight(gpui::FontWeight::MEDIUM).child(title))
                .child(div().mt(px(16.0)).child(design_system::text_field(&self.sidebar_action_input).label(label).error(self.error.clone())))
                .child(div().flex().items_center().justify_end().gap(px(8.0)).mt(px(20.0))
                    .child(design_system::button("sidebar-dialog-cancel", "Cancel", ButtonKind::Text, self.sidebar_action_busy)
                        .track_focus(&self.sidebar_rename_button_focus[0])
                        .focus_visible(|style| style.bg(theme::surface_selected()))
                        .debug_selector(|| "sidebar-rename-cancel".into())
                        .on_click(cx.listener(|this, _, window, cx| this.close_sidebar_dialog(window, cx))))
                    .child(design_system::button("sidebar-dialog-confirm", "Rename", ButtonKind::Filled, self.sidebar_action_busy)
                        .track_focus(&self.sidebar_rename_button_focus[1])
                        .focus_visible(|style| style.bg(theme::accent_hover()))
                        .debug_selector(|| "sidebar-rename-confirm".into())
                        .on_click(cx.listener(|this, _, window, cx| this.submit_sidebar_dialog(window, cx)))))))
            .into_any_element()
    }
}
