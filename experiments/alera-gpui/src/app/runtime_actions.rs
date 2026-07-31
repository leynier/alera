use std::time::Duration;

use gpui::{
    div, prelude::FluentBuilder as _, AnyElement, Context, CursorStyle, InteractiveElement as _,
    IntoElement as _, ParentElement as _, StatefulInteractiveElement as _, Styled as _,
};
use gpui_component::input::Input;
use serde_json::Value;

use super::AleraApp;
use crate::activity::Activity;
use crate::theme;

impl AleraApp {
    fn run_runtime_action(&mut self, cx: &mut Context<Self>) {
        let verb = self.runtime_verb_input.read(cx).value().trim().to_string();
        let raw_payload = self
            .runtime_payload_input
            .read(cx)
            .value()
            .trim()
            .to_string();
        if !runtime_action_allowed(self.activity, &verb) {
            self.local_message =
                Some(format!("Verb {verb} Is Not Allowed For {}", self.activity.label()).into());
            cx.notify();
            return;
        }
        let payload = if raw_payload.is_empty() {
            Value::Object(Default::default())
        } else {
            match serde_json::from_str::<Value>(&raw_payload) {
                Ok(Value::Object(object)) => Value::Object(object),
                Ok(_) => {
                    self.local_message = Some("Runtime Payload Must Be A JSON Object".into());
                    cx.notify();
                    return;
                }
                Err(error) => {
                    self.local_message = Some(format!("Invalid JSON Payload: {error}").into());
                    cx.notify();
                    return;
                }
            }
        };
        if is_destructive_verb(&verb) && self.runtime_action_armed.as_deref() != Some(&verb) {
            self.runtime_action_armed = Some(verb.clone());
            self.local_message = Some(format!("Click Run Again To Confirm {verb}").into());
            cx.notify();
            return;
        }
        self.runtime_action_armed = None;
        self.runtime_action_busy = true;
        self.runtime_action_output = None;
        let bridge = self.bridge.clone();
        let activity = self.activity;
        cx.spawn(async move |this, cx| {
            let result = bridge
                .request_with_timeout(verb.clone(), payload, Duration::from_secs(120))
                .await;
            let Some(this) = this.upgrade() else {
                return;
            };
            let _ = this.update(cx, |this, cx| {
                this.runtime_action_busy = false;
                match result {
                    Ok(value) => {
                        this.runtime_action_output = Some(value);
                        this.local_message = Some(format!("{verb} Completed").into());
                        if this.activity == activity {
                            this.refresh_runtime_feature(cx);
                        }
                    }
                    Err(error) => this.local_message = Some(error.into()),
                }
                cx.notify();
            });
        })
        .detach();
    }

    pub(super) fn render_runtime_action_console(&self, cx: &mut Context<Self>) -> AnyElement {
        let guide = action_guide(self.activity);
        let output = self
            .runtime_action_output
            .as_ref()
            .map(|value| serde_json::to_string_pretty(value).unwrap_or_else(|_| value.to_string()));
        div()
            .rounded_lg()
            .border_1()
            .border_color(theme::border())
            .bg(theme::surface())
            .p_4()
            .child(
                div()
                    .font_weight(gpui::FontWeight::SEMIBOLD)
                    .child("Runtime Action Console"),
            )
            .child(
                div()
                    .mt_1()
                    .text_xs()
                    .text_color(theme::text_muted())
                    .child(guide),
            )
            .child(
                div()
                    .mt_3()
                    .flex()
                    .gap_2()
                    .child(
                        div()
                            .w(gpui::relative(0.35))
                            .child(Input::new(&self.runtime_verb_input)),
                    )
                    .child(
                        div()
                            .flex_1()
                            .child(Input::new(&self.runtime_payload_input)),
                    )
                    .child(
                        div()
                            .id("runtime-action-run")
                            .px_3()
                            .py_2()
                            .rounded_md()
                            .bg(theme::surface_selected())
                            .cursor(CursorStyle::PointingHand)
                            .on_click(cx.listener(|this, _, _, cx| this.run_runtime_action(cx)))
                            .child(if self.runtime_action_busy {
                                "Running"
                            } else if self.runtime_action_armed.is_some() {
                                "Confirm Run"
                            } else {
                                "Run"
                            }),
                    ),
            )
            .when_some(output, |console, output| {
                console.child(
                    div()
                        .mt_3()
                        .font_family("JetBrains Mono")
                        .text_xs()
                        .text_color(theme::text_muted())
                        .child(output),
                )
            })
            .into_any_element()
    }
}

fn runtime_action_allowed(activity: Activity, verb: &str) -> bool {
    match activity {
        Activity::Agents => {
            verb.starts_with("agentProfile.")
                || verb.starts_with("agentQuota.")
                || verb == "runtimeSettings.update"
        }
        Activity::Resources => {
            matches!(verb, "resources.snapshot" | "terminate" | "restart")
        }
        Activity::Orchestration => verb.starts_with("orchestration."),
        Activity::Settings => matches!(
            verb,
            "runtimeSettings.update"
                | "workbenchViewPrefs.update"
                | "projectConfig.upsert"
                | "projectConfig.remove"
        ),
        Activity::Devices => {
            verb.starts_with("mobile.")
                && !verb.starts_with("mobile.cloud")
                && !verb.starts_with("mobile.account")
                && !verb.starts_with("mobile.emulator")
        }
        Activity::Diagnostics => matches!(
            verb,
            "status.get"
                | "cliRegistration.status"
                | "cliRegistration.install"
                | "shellEnvironment.reload"
        ),
        _ => false,
    }
}

fn is_destructive_verb(verb: &str) -> bool {
    [
        ".remove",
        ".delete",
        ".revoke",
        ".reset",
        ".cancel",
        ".interrupt",
        ".runStop",
        "terminate",
        "restart",
    ]
    .iter()
    .any(|part| verb.contains(part))
}

fn action_guide(activity: Activity) -> &'static str {
    match activity {
        Activity::Agents => {
            "Allowed: agentProfile.*, agentQuota.*, runtimeSettings.update. Example: agentProfile.launch with the existing profile launch payload."
        }
        Activity::Resources => {
            "Allowed: resources.snapshot, terminate, restart. Session mutations require a sessionId and destructive confirmation."
        }
        Activity::Orchestration => {
            "Allowed: orchestration.* using the existing protocol v2 payloads. Stop, reset, cancel and interrupt operations require confirmation."
        }
        Activity::Settings => {
            "Allowed: runtimeSettings.update, workbenchViewPrefs.update, projectConfig.upsert and projectConfig.remove."
        }
        Activity::Devices => {
            "Allowed: local mobile management calls except cloud account and emulator routes. Revoke, delete and cancel require confirmation."
        }
        Activity::Diagnostics => {
            "Allowed: status.get, cliRegistration.status/install and shellEnvironment.reload."
        }
        _ => "This activity does not expose runtime mutations.",
    }
}

#[cfg(test)]
mod tests {
    use super::{is_destructive_verb, runtime_action_allowed};
    use crate::activity::Activity;

    #[test]
    fn action_allowlist_keeps_excluded_scopes_out() {
        assert!(runtime_action_allowed(
            Activity::Devices,
            "mobile.device.rename"
        ));
        assert!(!runtime_action_allowed(
            Activity::Devices,
            "mobile.cloudEnrollment.create"
        ));
        assert!(!runtime_action_allowed(
            Activity::Diagnostics,
            "browser.open"
        ));
    }

    #[test]
    fn destructive_runtime_actions_require_confirmation() {
        assert!(is_destructive_verb("mobile.device.delete"));
        assert!(is_destructive_verb("orchestration.runStop"));
        assert!(!is_destructive_verb("agentQuota.snapshot"));
    }
}
