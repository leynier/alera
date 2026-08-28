use gpui::{Context, Window};
use serde_json::json;

use super::AleraApp;
use crate::forge_service::ForgeAction;

impl AleraApp {
    pub(super) fn link_existing_review(&mut self, cx: &mut Context<Self>) {
        let raw = self.forge_link_input.read(cx).value().trim().to_string();
        let number = raw
            .trim_start_matches('#')
            .trim_end_matches('/')
            .rsplit('/')
            .next()
            .and_then(|value| value.parse::<u64>().ok());
        let Some(number) = number else {
            self.forge_form_error = Some("Enter A PR Number Or URL".into());
            cx.notify();
            return;
        };
        self.forge_form_error = None;
        let Some(workspace_id) = self.selected_workspace_id.clone() else {
            return;
        };
        let host = if self.forge_snapshot.host.is_empty() {
            "github.com"
        } else {
            &self.forge_snapshot.host
        };
        let url = format!(
            "https://{host}/{}/pull/{number}",
            self.forge_snapshot.repo_slug
        );
        self.forge_busy = true;
        let bridge = self.bridge.clone();
        cx.spawn(async move |this, cx| {
            let result = bridge
                .request(
                    "linkedReview.upsert",
                    json!({
                        "workspaceId": workspace_id,
                        "dismissed": false,
                        "provider": "github",
                        "number": number,
                        "url": url,
                        "linkedAt": chrono::Utc::now().to_rfc3339(),
                    }),
                )
                .await;
            let Some(this) = this.upgrade() else {
                return;
            };
            this.update(cx, |this, cx| {
                this.forge_busy = false;
                match result {
                    Ok(_) => {
                        this.forge_link_form_open = false;
                        this.forge_form_error = None;
                        this.local_message = Some("Pull Request Linked".into());
                        this.refresh_forge(cx);
                    }
                    Err(error) => {
                        this.local_message = Some(error.into());
                        cx.notify();
                    }
                }
            });
        })
        .detach();
    }

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
}
