use std::time::{Duration, SystemTime, UNIX_EPOCH};

use gpui::{Context, SharedString, Window};
use serde_json::json;

use super::AleraApp;

impl AleraApp {
    pub(super) fn generate_pull_request_details(
        &mut self,
        window: &mut Window,
        cx: &mut Context<Self>,
    ) {
        if !self.settings_state.ai_text_enabled
            || self.forge_busy
            || self.forge_ai_busy
            || self.forge_snapshot.branch.is_empty()
        {
            return;
        }
        let base_branch = self.forge_base_input.read(cx).value().trim().to_owned();
        if base_branch.is_empty() {
            self.forge_form_error = Some("Base Branch Is Required".into());
            cx.notify();
            return;
        }
        let Some(workspace_path) = self.selected_source_control_path() else {
            return;
        };
        let operation_id = format!(
            "gpui-pull-request-{}-{}",
            std::process::id(),
            SystemTime::now()
                .duration_since(UNIX_EPOCH)
                .unwrap_or_default()
                .as_millis()
        );
        let head_branch = self.forge_snapshot.branch.clone();
        let initial_title = self.forge_title_input.read(cx).value().to_string();
        let initial_body = self.forge_body_input.read(cx).value().to_string();
        self.forge_ai_operation_id = Some(operation_id.clone());
        self.forge_ai_busy = true;
        self.forge_form_error = None;
        self.local_message = None;
        let bridge = self.bridge.clone();
        cx.spawn_in(window, async move |this, cx| {
            let result = bridge
                .request_with_timeout(
                    "aiText.pullRequestDetails.generate",
                    json!({
                        "operationId": operation_id,
                        "workspacePath": workspace_path,
                        "baseBranch": base_branch,
                        "headBranch": head_branch,
                    }),
                    Duration::from_secs(600),
                )
                .await;
            let Some(this) = this.upgrade() else {
                return;
            };
            let _ = this.update_in(cx, move |this, window, cx| {
                this.forge_ai_busy = false;
                this.forge_ai_operation_id = None;
                match result {
                    Ok(value) => {
                        let generated = value
                            .get("text")
                            .and_then(|value| value.as_str())
                            .unwrap_or_default();
                        let (title, body) = parse_pull_request_details(generated);
                        let fields_unchanged = this.forge_title_input.read(cx).value().as_ref()
                            == initial_title
                            && this.forge_body_input.read(cx).value().as_ref() == initial_body;
                        if fields_unchanged {
                            this.forge_title_input.update(cx, |input, cx| {
                                input.set_value(title, window, cx);
                            });
                            this.forge_body_input.update(cx, |input, cx| {
                                input.set_value(body, window, cx);
                            });
                            let agent = value
                                .get("agentLabel")
                                .and_then(|value| value.as_str())
                                .unwrap_or("AI");
                            this.local_message =
                                Some(format!("Pull Request Details Generated With {agent}").into());
                            this.forge_form_error = None;
                        } else {
                            this.local_message = Some(
                                "Generated Details Were Not Applied Because The Fields Changed"
                                    .into(),
                            );
                        }
                    }
                    Err(error) if error.contains("was canceled") => {
                        this.local_message = None;
                        this.forge_form_error = None;
                    }
                    Err(error) => {
                        let error = SharedString::from(error);
                        this.local_message = Some(error.clone());
                        this.forge_form_error = Some(error);
                    }
                }
                cx.notify();
            });
        })
        .detach();
        cx.notify();
    }

    pub(super) fn cancel_pull_request_generation(&mut self, cx: &mut Context<Self>) {
        let Some(operation_id) = self.forge_ai_operation_id.clone() else {
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
                    this.local_message = Some("AI Pull Request Details Generation Canceled".into());
                }
                cx.notify();
            });
        })
        .detach();
    }
}

fn parse_pull_request_details(raw: &str) -> (String, String) {
    let normalized = clean_generated_text(raw);
    let mut lines = normalized.lines();
    let subject = lines
        .next()
        .unwrap_or_default()
        .trim()
        .trim_end_matches('.');
    let title = if subject.is_empty() {
        "Update Project".to_owned()
    } else {
        subject
            .chars()
            .take(72)
            .collect::<String>()
            .trim()
            .to_owned()
    };
    let body = lines.collect::<Vec<_>>().join("\n").trim().to_owned();
    (title, body)
}

fn clean_generated_text(raw: &str) -> String {
    let mut text = raw.replace("\r\n", "\n").trim().to_owned();
    if let Some((first, rest)) = text.split_once('\n') {
        let first = first.trim().to_ascii_lowercase();
        if first.starts_with("generating")
            || first.starts_with("thinking")
            || first
                .chars()
                .all(|character| matches!(character, '.' | '…'))
        {
            text = rest.trim().to_owned();
        }
    }
    if text.starts_with("```") && text.ends_with("```") {
        if let Some(first_newline) = text.find('\n') {
            text = text[first_newline + 1..text.len() - 3].trim().to_owned();
        }
    }
    let trimmed = text.trim_start();
    for prefix in ["- ", "* "] {
        if let Some(value) = trimmed.strip_prefix(prefix) {
            return value.trim().to_owned();
        }
    }
    text.trim().to_owned()
}

#[cfg(test)]
mod tests {
    use super::parse_pull_request_details;

    #[test]
    fn parses_title_and_body() {
        assert_eq!(
            parse_pull_request_details("Improve source control.\n\n- Add roots"),
            (
                "Improve source control".to_owned(),
                "- Add roots".to_owned()
            )
        );
    }

    #[test]
    fn supplies_a_safe_fallback_title() {
        assert_eq!(
            parse_pull_request_details(""),
            ("Update Project".to_owned(), String::new())
        );
    }
}
