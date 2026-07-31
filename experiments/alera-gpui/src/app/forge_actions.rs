use gpui::{Context, Window};

use super::AleraApp;
use crate::forge_service::ForgeAction;

impl AleraApp {
    pub(super) fn fill_review_fields(&mut self, window: &mut Window, cx: &mut Context<Self>) {
        let Some(review) = self.forge_snapshot.review.clone() else {
            return;
        };
        self.forge_title_input
            .update(cx, |input, cx| input.set_value(review.title, window, cx));
        self.forge_body_input
            .update(cx, |input, cx| input.set_value(review.body, window, cx));
        self.forge_base_input.update(cx, |input, cx| {
            input.set_value(review.base_branch, window, cx)
        });
    }

    pub(super) fn add_review_comment(&mut self, cx: &mut Context<Self>) {
        let Some(review) = self.forge_snapshot.review.as_ref() else {
            return;
        };
        let body = self.forge_comment_input.read(cx).value().trim().to_string();
        if body.is_empty() {
            return;
        }
        self.run_forge_action(
            ForgeAction::Comment {
                number: review.number,
                body,
            },
            cx,
        );
    }

    pub(super) fn confirm_forge_action(
        &mut self,
        key: &str,
        action: ForgeAction,
        cx: &mut Context<Self>,
    ) {
        if self.forge_danger_armed.as_deref() != Some(key) {
            self.forge_danger_armed = Some(key.to_string());
            self.local_message = Some(format!("Click {key} Again To Confirm").into());
            cx.notify();
            return;
        }
        self.run_forge_action(action, cx);
    }
}
