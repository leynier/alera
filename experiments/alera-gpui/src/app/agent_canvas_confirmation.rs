use gpui::{AnyElement, Context, FocusHandle, FontWeight, InteractiveElement as _, IntoElement as _, MouseButton, ParentElement as _, Role, StatefulInteractiveElement as _, Styled as _, Window, div, px};
use gpui_component::FocusTrapElement as _;
use serde_json::{Value, json};
use uuid::Uuid;

use super::{AleraApp, agent_canvas_catalog};
use super::agent_canvas_ui_actions::CanvasActionContext;
use crate::{design_system::{self, ButtonKind}, theme};

#[derive(Clone, Copy)]
pub(super) enum CanvasConfirmationKind { Close, Remove, ControlledAction, DestructiveAction }

impl CanvasConfirmationKind {
    fn title(self) -> &'static str { match self { Self::Close => "Close Agent Canvas?", Self::Remove => "Remove Agent Canvas?", Self::ControlledAction => "Confirm Action", Self::DestructiveAction => "Confirm Destructive Action" } }
    fn label(self) -> &'static str { match self { Self::Close => "Close Canvas", Self::Remove => "Remove Canvas", _ => "Confirm" } }
    fn message(self) -> &'static str { match self { Self::Close => "Closing freezes the current revision and stops live updates for this canvas.", Self::Remove => "This removes the retained canvas and its event history.", Self::ControlledAction => "Confirm that you want to continue with this Agent Canvas action.", Self::DestructiveAction => "This action can change workspace or source control state." } }
    fn request(self) -> &'static str { match self { Self::Close => "agentCanvas.close", Self::Remove => "agentCanvas.remove", _ => "agentCanvas.action" } }
    fn accepts(self, canvas: &Value) -> bool {
        match self { Self::Close => matches!(canvas["state"].as_str(), Some("waiting" | "live")), Self::Remove => agent_canvas_catalog::is_history(canvas), _ => canvas["id"].as_str().is_some_and(|id| !id.is_empty()) }
    }
}

pub(super) struct CanvasConfirmation {
    request_id: Uuid,
    workspace_id: String,
    canvas_id: String,
    kind: CanvasConfirmationKind,
    focus: FocusHandle,
    previous_focus: Option<FocusHandle>,
    action: Option<(CanvasActionContext, Value)>,
}

impl AleraApp {
    pub(super) fn request_canvas_confirmation(&mut self, canvas_id: String, kind: CanvasConfirmationKind, window: &mut Window, cx: &mut Context<Self>) -> bool {
        let Some(workspace_id) = self.selected_workspace_id.clone() else { return false; };
        if self.agent_canvas_busy || !self.agent_canvas_values.iter().any(|canvas| canvas["id"] == canvas_id && kind.accepts(canvas)) { return false; }
        let previous_focus = window.focused(cx);
        let focus = cx.focus_handle();
        focus.focus(window, cx);
        self.agent_canvas_confirmation = Some(CanvasConfirmation { request_id: Uuid::new_v4(), workspace_id, canvas_id, kind, focus, previous_focus, action: None });
        cx.notify();
        true
    }

    pub(super) fn request_canvas_action_confirmation(&mut self, context: CanvasActionContext, action: Value, kind: CanvasConfirmationKind, window: &mut Window, cx: &mut Context<Self>) {
        if self.request_canvas_confirmation(context.canvas_id.clone(), kind, window, cx) {
            if let Some(confirmation) = self.agent_canvas_confirmation.as_mut() { confirmation.action = Some((context, action)); }
        }
    }

    pub(super) fn cancel_canvas_confirmation(&mut self, window: &mut Window, cx: &mut Context<Self>) {
        if let Some(confirmation) = self.agent_canvas_confirmation.take() {
            if let Some(focus) = confirmation.previous_focus { focus.focus(window, cx); }
            cx.notify();
        }
    }

    fn confirm_canvas_request(&mut self, request_id: Uuid, window: &mut Window, cx: &mut Context<Self>) {
        if self.agent_canvas_busy || self.agent_canvas_confirmation.as_ref().map(|value| value.request_id) != Some(request_id) { return; }
        let Some(confirmation) = self.agent_canvas_confirmation.take() else { return; };
        let valid = self.selected_workspace_id.as_deref() == Some(&confirmation.workspace_id)
            && self.agent_canvas_values.iter().any(|canvas| canvas["id"] == confirmation.canvas_id && confirmation.kind.accepts(canvas))
            && confirmation.action.as_ref().is_none_or(|(context, _)| context.matches(self.selected_workspace_id.as_deref(), &self.agent_canvas_values));
        self.shell_focus.focus(window, cx);
        if valid {
            if let Some((context, mut action)) = confirmation.action {
                action["confirmed"] = json!(true);
                self.execute_canvas_ui_action(context, action, window, cx);
            } else {
                self.agent_canvas_action(confirmation.kind.request(), json!({"canvasId": confirmation.canvas_id}), cx);
            }
        } else {
            self.canvas_ui_message("This Agent Canvas is no longer available for that action.", cx);
        }
        cx.notify();
    }

    pub(super) fn render_canvas_confirmation(&self, cx: &mut Context<Self>) -> AnyElement {
        let Some(confirmation) = self.agent_canvas_confirmation.as_ref() else { return div().into_any_element(); };
        let request_id = confirmation.request_id;
        let kind = confirmation.kind;
        let dialog = design_system::dialog_shell("canvas-confirmation", kind.title(), 420.0).p(px(19.0)).rounded(px(12.0))
            .on_mouse_down(MouseButton::Left, |_, _, cx| cx.stop_propagation())
            .child(div().text_size(px(14.0)).line_height(px(21.0)).font_weight(FontWeight::MEDIUM).child(kind.title()))
            .child(div().mt(px(12.0)).text_size(px(13.0)).text_color(theme::text_muted()).child(kind.message()))
            .child(div().mt(px(20.0)).flex().items_center().gap(px(8.0))
                .child(design_system::button("canvas-confirm-cancel", "Cancel", ButtonKind::Text, false).flex_1()
                    .on_click(cx.listener(move |this, _, window, cx| {
                        if this.agent_canvas_confirmation.as_ref().map(|value| value.request_id) == Some(request_id) { this.cancel_canvas_confirmation(window, cx); }
                    })))
                .child(design_system::button("canvas-confirm-submit", kind.label(), match kind { CanvasConfirmationKind::Close | CanvasConfirmationKind::ControlledAction => ButtonKind::Filled, CanvasConfirmationKind::Remove | CanvasConfirmationKind::DestructiveAction => ButtonKind::Destructive }, self.agent_canvas_busy).flex_1()
                    .on_click(cx.listener(move |this, _, window, cx| this.confirm_canvas_request(request_id, window, cx)))));
        div().id("canvas-confirmation-backdrop")
            .absolute().inset_0().occlude().flex().items_center().justify_center().bg(theme::overlay_scrim())
            .on_mouse_down(MouseButton::Left, cx.listener(move |this, _, window, cx| {
                if this.agent_canvas_confirmation.as_ref().map(|value| value.request_id) == Some(request_id) { this.cancel_canvas_confirmation(window, cx); }
            }))
            .child(div().id("canvas-confirmation-semantics").role(Role::Dialog).aria_label(format!("{} {}", kind.title(), kind.message()))
                .child(dialog.focus_trap("canvas-confirmation-focus", &confirmation.focus))).into_any_element()
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn agent_canvas_confirmation_revalidates_action_against_live_state() {
        let live = json!({"state":"live"});
        let closed = json!({"state":"closed"});
        assert!(CanvasConfirmationKind::Close.accepts(&live));
        assert!(!CanvasConfirmationKind::Remove.accepts(&live));
        assert!(!CanvasConfirmationKind::Close.accepts(&closed));
        assert!(CanvasConfirmationKind::Remove.accepts(&closed));
        assert!(!CanvasConfirmationKind::Remove.accepts(&Value::Null));
    }
}
