use gpui::{AnyElement, AppContext as _, Context, Div, FontWeight, InteractiveElement as _, IntoElement as _, ParentElement as _, SharedString, StatefulInteractiveElement as _, Styled as _, div, px};
use gpui_component::{scroll::ScrollableElement as _, tooltip::Tooltip};
use serde_json::{Value, json};

use super::{AleraApp, agent_canvas_cards::badge, agent_canvas_confirmation::CanvasConfirmationKind, agent_canvas_document_view::document_view};
use crate::{design_system, icons::{AleraIcon, loading_indicator}, theme};

impl AleraApp {
    pub(super) fn render_agent_canvas_details(&self, canvas: &Value, cx: &mut Context<Self>) -> AnyElement {
        let id = canvas["id"].as_str().unwrap_or_default().to_owned();
        let active = matches!(canvas["state"].as_str(), Some("waiting" | "live"));
        let pinned = canvas["pinned"].as_bool().unwrap_or(false);
        let callback = self.canvas_action_handler(canvas, cx);
        let mut actions = Vec::new();
        if self.agent_canvas_busy {
            actions.push(loading_indicator(16.0, theme::text_muted()).into_any_element());
        } else {
            let pin_id = id.clone();
            actions.push(design_system::icon_button("canvas-pin", if pinned {"Unpin Canvas"} else {"Pin Canvas"}, if pinned {AleraIcon::PinOff} else {AleraIcon::Pin}, true, 22.0, None, None)
                .tooltip(move |_, cx| cx.new(move |_| Tooltip::new(if pinned {"Unpin Canvas"} else {"Pin Canvas"})).into())
                .on_click(cx.listener(move |this, _, _, cx| this.agent_canvas_action("agentCanvas.pin", json!({"canvasId":pin_id,"pinned":!pinned}), cx))).into_any_element());
            if active {
                let complete_id = id.clone();
                let close_id = id.clone();
                actions.push(design_system::icon_button("canvas-complete", "Complete Canvas", AleraIcon::CheckCheck, true, 22.0, None, None)
                    .tooltip(|_, cx| cx.new(|_| Tooltip::new("Complete Canvas")).into())
                    .on_click(cx.listener(move |this, _, _, cx| this.agent_canvas_action("agentCanvas.complete", json!({"canvasId":complete_id}), cx))).into_any_element());
                actions.push(design_system::icon_button("canvas-close", "Close Canvas", AleraIcon::Close, true, 22.0, None, None)
                    .tooltip(|_, cx| cx.new(|_| Tooltip::new("Close Canvas")).into())
                    .on_click(cx.listener(move |this, _, window, cx| { this.request_canvas_confirmation(close_id.clone(), CanvasConfirmationKind::Close, window, cx); })).into_any_element());
            } else {
                let remove_id = id.clone();
                actions.push(design_system::icon_button("canvas-remove", "Remove Canvas", AleraIcon::Delete, true, 22.0, None, None)
                    .tooltip(|_, cx| cx.new(|_| Tooltip::new("Remove Canvas")).into())
                    .on_click(cx.listener(move |this, _, window, cx| { this.request_canvas_confirmation(remove_id.clone(), CanvasConfirmationKind::Remove, window, cx); })).into_any_element());
            }
        }
        let header = details_header(canvas["title"].as_str().unwrap_or_default().to_owned(), canvas["revision"].as_u64().unwrap_or_default(), actions)
            .id(SharedString::from(format!("canvas-header-{id}")));
        details_frame(header.into_any_element(), document_view(canvas, self.agent_canvas_busy, callback)).into_any_element()
    }
}

pub(super) fn details_header(title: String, revision: u64, actions: Vec<AnyElement>) -> Div {
    div().w_full().min_w_0().flex().items_center().pt(px(6.0)).pb(px(4.0)).pl(px(8.0)).pr(px(4.0)).flex_shrink_0()
        .child(div().flex_1().min_w_0().text_ellipsis().text_size(px(13.0)).font_weight(FontWeight::MEDIUM).child(title))
        .child(badge(format!("Revision {revision}"))).child(div().w(px(4.0)).flex_shrink_0())
        .children(actions)
}

pub(super) fn details_frame(header: AnyElement, document: Div) -> Div {
    div().w_full().min_w_0().flex().flex_col().flex_1().min_h_0().child(header)
        .child(div().h(px(1.0)).flex_shrink_0().bg(theme::border()))
        .child(div().id("agent-canvas-document-scroll").w_full().min_w_0().flex_1().min_h_0().overflow_y_scrollbar().child(document))
}
