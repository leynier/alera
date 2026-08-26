use std::time::{Duration, SystemTime, UNIX_EPOCH};

use gpui::{Context, SharedString, Window};
use serde_json::json;

use super::AleraApp;

impl AleraApp {
    pub(super) fn generate_commit_message(&mut self, window: &mut Window, cx: &mut Context<Self>) {
        if !self.settings_state.ai_text_enabled {
            return;
        }
        let has_staged = self
            .git_snapshot
            .changes
            .iter()
            .any(|change| change.area.eq_ignore_ascii_case("staged"));
        if !has_staged {
            self.local_message = Some("Stage Changes Before Generating A Commit Message".into());
            cx.notify();
            return;
        }
        if self.git_snapshot.has_conflicts || self.git_busy || self.source_commit_ai_busy {
            return;
        }
        let Some(workspace_path) = self.selected_source_control_path() else {
            return;
        };
        let operation_id = format!(
            "gpui-commit-{}-{}",
            std::process::id(),
            SystemTime::now()
                .duration_since(UNIX_EPOCH)
                .unwrap_or_default()
                .as_millis()
        );
        let initial_text = self.commit_input.read(cx).value().to_string();
        self.source_commit_ai_operation_id = Some(operation_id.clone());
        self.source_commit_ai_busy = true;
        self.local_message = None;
        let bridge = self.bridge.clone();
        cx.spawn_in(window, async move |this, cx| {
            let result = bridge
                .request_with_timeout(
                    "aiText.commitMessage.generate",
                    json!({
                        "operationId": operation_id,
                        "workspacePath": workspace_path,
                    }),
                    Duration::from_secs(600),
                )
                .await;
            let Some(this) = this.upgrade() else {
                return;
            };
            let _ = this.update_in(cx, move |this, window, cx| {
                this.source_commit_ai_busy = false;
                this.source_commit_ai_operation_id = None;
                match result {
                    Ok(value) => {
                        let text = value
                            .get("text")
                            .and_then(|value| value.as_str())
                            .unwrap_or_default()
                            .to_owned();
                        let agent = value
                            .get("agentLabel")
                            .and_then(|value| value.as_str())
                            .unwrap_or("AI");
                        if this.commit_input.read(cx).value().as_ref() == initial_text {
                            this.commit_input.update(cx, |input, cx| {
                                input.set_value(text, window, cx);
                            });
                            this.local_message =
                                Some(format!("Commit Message Generated With {agent}").into());
                        } else {
                            this.local_message = Some(
                                "Generated Message Was Not Applied Because The Field Changed"
                                    .into(),
                            );
                        }
                    }
                    Err(error) if error.contains("was canceled") => {
                        this.local_message = None;
                    }
                    Err(error) => this.local_message = Some(SharedString::from(error)),
                }
                cx.notify();
            });
        })
        .detach();
        cx.notify();
    }

    pub(super) fn cancel_commit_message_generation(&mut self, cx: &mut Context<Self>) {
        let Some(operation_id) = self.source_commit_ai_operation_id.clone() else {
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
                    this.local_message = Some("AI Commit Message Generation Canceled".into());
                }
                cx.notify();
            });
        })
        .detach();
    }
}
