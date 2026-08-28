use gpui::{
    div, px, AnyElement, Context, CursorStyle, InteractiveElement as _, IntoElement,
    ParentElement as _, Role, StatefulInteractiveElement as _, Styled as _,
};
use serde_json::json;

use super::AleraApp;
use crate::theme;

impl AleraApp {
    pub(super) fn terminate_resource_session(
        &mut self,
        session_id: String,
        cx: &mut Context<Self>,
    ) {
        let bridge = self.bridge.clone();
        cx.spawn(async move |this, cx| {
            let result = bridge
                .request("terminate", json!({"sessionId": session_id}))
                .await;
            let Some(this) = this.upgrade() else {
                return;
            };
            this.update(cx, |this, cx| {
                match result {
                    Ok(_) => {
                        this.refresh(cx);
                        this.refresh_resource_status(cx);
                    }
                    Err(error) => this.local_message = Some(error.into()),
                }
                cx.notify();
            });
        })
        .detach();
    }

    fn terminate_resource_sessions(&mut self, session_ids: Vec<String>, cx: &mut Context<Self>) {
        if session_ids.is_empty() {
            return;
        }
        let bridge = self.bridge.clone();
        cx.spawn(async move |this, cx| {
            let mut error = None;
            for session_id in session_ids {
                if let Err(next_error) = bridge
                    .request("terminate", json!({"sessionId": session_id}))
                    .await
                {
                    error = Some(next_error);
                }
            }
            let Some(this) = this.upgrade() else {
                return;
            };
            this.update(cx, |this, cx| {
                if let Some(error) = error {
                    this.local_message = Some(error.into());
                }
                this.refresh(cx);
                this.refresh_resource_status(cx);
                cx.notify();
            });
        })
        .detach();
    }

    pub(super) fn open_resource_session(
        &mut self,
        workspace_id: String,
        tab_id: String,
        cx: &mut Context<Self>,
    ) {
        if self.selected_workspace_id.as_deref() != Some(workspace_id.as_str()) {
            self.selected_workspace_id = Some(workspace_id);
            self.selected_tab_id = Some(tab_id);
            self.reset_local_workspace(cx);
            self.refresh(cx);
            return;
        }
        self.activate_workspace_tab(tab_id, cx);
    }

    pub(super) fn resource_orphan_footer(
        &self,
        count: usize,
        session_ids: Vec<String>,
        cx: &mut Context<Self>,
    ) -> AnyElement {
        div()
            .flex()
            .flex_shrink_0()
            .items_center()
            .h(px(34.0))
            .px_3()
            .border_t_1()
            .border_color(theme::border_subtle())
            .child(
                div()
                    .flex_1()
                    .text_sm()
                    .text_color(theme::warning())
                    .child(format!(
                        "{count} Orphan Terminal{}",
                        if count == 1 { "" } else { "s" }
                    )),
            )
            .child(
                div()
                    .id("resource-kill-all-orphans")
                    .focusable()
                    .tab_stop(true)
                    .role(Role::Button)
                    .aria_label("Kill All Orphan Terminals")
                    .h(px(26.0))
                    .px_2()
                    .flex()
                    .items_center()
                    .justify_center()
                    .rounded_md()
                    .text_sm()
                    .text_color(theme::warning())
                    .cursor(CursorStyle::PointingHand)
                    .hover(|style| style.bg(theme::surface_selected()))
                    .on_click(cx.listener(move |this, _, _, cx| {
                        this.terminate_resource_sessions(session_ids.clone(), cx);
                    }))
                    .child("Kill All"),
            )
            .into_any_element()
    }
}
