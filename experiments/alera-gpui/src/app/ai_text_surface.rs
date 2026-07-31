use std::time::{Duration, SystemTime, UNIX_EPOCH};

use gpui::{
    div, prelude::FluentBuilder as _, AnyElement, Context, CursorStyle, InteractiveElement as _,
    IntoElement as _, ParentElement as _, StatefulInteractiveElement as _, Styled as _,
};
use gpui_component::input::Input;
use serde_json::json;

use super::AleraApp;
use crate::theme;

impl AleraApp {
    fn generate_ai_text(&mut self, cx: &mut Context<Self>) {
        let prompt = self.ai_prompt_input.read(cx).value().trim().to_string();
        let project_id = self
            .selected_workspace_id
            .as_deref()
            .and_then(|id| self.snapshot.workspace(id))
            .map(|workspace| workspace.project_id.clone());
        let Some(project_id) = project_id else {
            self.local_message = Some("Select A Workspace First".into());
            cx.notify();
            return;
        };
        if prompt.is_empty() {
            self.local_message = Some("Enter An AI Text Prompt".into());
            cx.notify();
            return;
        }
        let operation_id = format!(
            "gpui-{}-{}",
            std::process::id(),
            SystemTime::now()
                .duration_since(UNIX_EPOCH)
                .unwrap_or_default()
                .as_millis()
        );
        self.ai_operation_id = Some(operation_id.clone());
        self.ai_busy = true;
        self.ai_generation = None;
        let bridge = self.bridge.clone();
        cx.spawn(async move |this, cx| {
            let result = bridge
                .request_with_timeout(
                    "aiText.workspaceIdentity.generate",
                    json!({
                        "operationId": operation_id,
                        "projectId": project_id,
                        "prompt": prompt,
                    }),
                    Duration::from_secs(600),
                )
                .await;
            let Some(this) = this.upgrade() else {
                return;
            };
            let _ = this.update(cx, |this, cx| {
                this.ai_busy = false;
                this.ai_operation_id = None;
                match result {
                    Ok(value) => {
                        this.ai_generation = Some(value);
                        this.local_message = Some("AI Text Generated".into());
                    }
                    Err(error) => this.local_message = Some(error.into()),
                }
                cx.notify();
            });
        })
        .detach();
    }

    fn cancel_ai_text(&mut self, cx: &mut Context<Self>) {
        let Some(operation_id) = self.ai_operation_id.clone() else {
            return;
        };
        let bridge = self.bridge.clone();
        cx.spawn(async move |this, cx| {
            let result = bridge
                .request("aiText.cancel", json!({"operationId": operation_id}))
                .await;
            let Some(this) = this.upgrade() else {
                return;
            };
            let _ = this.update(cx, |this, cx| {
                if result.is_ok() {
                    this.local_message = Some("AI Text Generation Canceled".into());
                }
                cx.notify();
            });
        })
        .detach();
    }

    pub(super) fn render_ai_text_surface(&self, cx: &mut Context<Self>) -> AnyElement {
        let output = self
            .ai_generation
            .as_ref()
            .map(|value| serde_json::to_string_pretty(value).unwrap_or_else(|_| value.to_string()))
            .unwrap_or_else(|| {
                if self.ai_busy {
                    "Generating With The Configured Agent".to_string()
                } else {
                    "No Generated Text Yet".to_string()
                }
            });
        div()
            .flex()
            .flex_col()
            .flex_1()
            .overflow_hidden()
            .p_5()
            .gap_3()
            .child(
                div()
                    .text_2xl()
                    .font_weight(gpui::FontWeight::SEMIBOLD)
                    .child("AI Text"),
            )
            .child(
                div()
                    .text_sm()
                    .text_color(theme::text_muted())
                    .child(
                        "Runs The Existing Alera AI Text Agent Through The Runtime Host. Accounts Remain Optional.",
                    ),
            )
            .child(
                div()
                    .h(gpui::px(140.0))
                    .child(Input::new(&self.ai_prompt_input).h_full()),
            )
            .child(
                div()
                    .flex()
                    .gap_2()
                    .child(
                        ai_button("ai-generate", "Generate Workspace Identity").on_click(
                            cx.listener(|this, _, _, cx| this.generate_ai_text(cx)),
                        ),
                    )
                    .when(self.ai_busy, |bar| {
                        bar.child(
                            ai_button("ai-cancel", "Cancel").on_click(
                                cx.listener(|this, _, _, cx| this.cancel_ai_text(cx)),
                            ),
                        )
                    }),
            )
            .child(
                div()
                    .id("ai-output")
                    .flex_1()
                    .overflow_y_scroll()
                    .rounded_lg()
                    .border_1()
                    .border_color(theme::border())
                    .bg(theme::surface())
                    .p_4()
                    .font_family("JetBrains Mono")
                    .text_sm()
                    .child(output),
            )
            .into_any_element()
    }
}

fn ai_button(id: &'static str, label: &'static str) -> gpui::Stateful<gpui::Div> {
    div()
        .id(id)
        .px_3()
        .py_2()
        .rounded_md()
        .bg(theme::surface_selected())
        .cursor(CursorStyle::PointingHand)
        .child(label)
}
