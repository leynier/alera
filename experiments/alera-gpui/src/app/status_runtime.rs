use gpui::{
    div, prelude::FluentBuilder as _, px, AnyElement, Context, CursorStyle,
    InteractiveElement as _, IntoElement, ParentElement as _, Role,
    StatefulInteractiveElement as _, Styled as _,
};
use serde_json::{json, Value};
use std::cmp::Ordering;

use super::AleraApp;
use crate::{
    design_system::{button, dialog_shell, ButtonKind},
    icons::loading_indicator,
    runtime_bridge::RuntimeHostStartConfig,
    theme,
};

impl AleraApp {
    pub(super) fn render_runtime_popover(&self, cx: &mut Context<Self>) -> AnyElement {
        let value = self.status_data.runtime.as_ref();
        let running = runtime_is_running(value, self.status_data.runtime_error.is_some());
        let loading = self.status_data.runtime_loading;
        let version = version_label(string_at(value, "runtimeHostVersion"));
        let bundled_version = version_label(Some(bundled_runtime_version()));
        let host_commit = string_at(value, "runtimeHostCommit");
        let bundled_commit = option_env!("ALERA_BUILD_COMMIT").unwrap_or("unknown");
        // Flutter exposes build metadata only when the host and bundled
        // versions are equal.  An older host is an update candidate, but it
        // must not also render the build rows; a newer host is left alone.
        let build_mismatch = runtime_has_build_mismatch(
            value,
            self.status_data.runtime_error.is_some(),
            &bundled_version,
            bundled_commit,
        );
        let update_available =
            runtime_update_available(value, self.status_data.runtime_error.is_some());
        let sessions = integer_at(value, "activeSessions");
        let agents = integer_at(value, "activeAgents");
        let persistent = value
            .and_then(|item| item.get("persistent"))
            .and_then(Value::as_bool)
            .unwrap_or(false);
        let stop_is_destructive = sessions > 0 || agents > 0;

        div()
            .id("runtime-popover")
            .role(Role::Dialog)
            .aria_label("Runtime Host")
            .absolute()
            .right(px(4.0))
            .bottom(theme::status_bar_height() + px(4.0))
            .w(px(240.0))
            .max_h(px(360.0))
            .occlude()
            .rounded_lg()
            .border_1()
            .border_color(theme::border())
            .bg(theme::surface_raised())
            .shadow_lg()
            .p_3()
            .on_hover(cx.listener(|this, hovered: &bool, _, cx| {
                this.set_status_popover_panel_hovered(*hovered, cx);
            }))
            .on_mouse_down(
                gpui::MouseButton::Left,
                cx.listener(|this, _, _, cx| this.pin_active_status_popover(cx)),
            )
            .child(
                div()
                    .text_size(px(13.0))
                    .font_weight(gpui::FontWeight::SEMIBOLD)
                    .child("Runtime"),
            )
            .child(div().h(px(8.0)))
            .child(runtime_row(
                "Status",
                if loading {
                    "Checking".to_owned()
                } else if running {
                    "Running".to_owned()
                } else {
                    "Stopped".to_owned()
                },
                (!loading && running).then(theme::success),
            ))
            .child(runtime_row("Host Version", version, None))
            .child(runtime_row("Bundled Version", bundled_version, None))
            .when(build_mismatch, |panel| {
                panel
                    .child(runtime_row("Host Build", build_label(host_commit), None))
                    .child(runtime_row(
                        "Bundled Build",
                        build_label(Some(bundled_commit)),
                        None,
                    ))
            })
            .when(persistent, |panel| {
                panel.child(runtime_row("Lifecycle", "Persistent".to_owned(), None))
            })
            .child(runtime_row("Sessions", sessions.to_string(), None))
            .child(runtime_row("Agents", agents.to_string(), None))
            .when_some(self.status_data.runtime_error.clone(), |panel, error| {
                panel.child(
                    div()
                        .mt_2()
                        .text_sm()
                        .text_color(theme::danger())
                        .child(error),
                )
            })
            .child(
                div()
                    .flex()
                    .flex_col()
                    .flex_shrink_0()
                    .gap_2()
                    .mt_3()
                    .child(
                        div()
                            .flex()
                            .justify_end()
                            .gap_2()
                            .child(
                                runtime_button(
                                    "runtime-refresh",
                                    "Refresh",
                                    RuntimeButtonStyle::Outline,
                                )
                                .on_click(cx.listener(
                                    |this, _, _, cx| {
                                        this.refresh_runtime_status(cx);
                                    },
                                )),
                            )
                            .when(!running, |actions| {
                                actions.child(
                                    runtime_button_with_loading(
                                        "runtime-start",
                                        "Start",
                                        RuntimeButtonStyle::Filled,
                                        self.runtime_action_busy,
                                    )
                                    .on_click(cx.listener(
                                        |this, _, _, cx| {
                                            this.request_runtime_start(cx);
                                        },
                                    )),
                                )
                            })
                            .when(running, |actions| {
                                actions.child(
                                    runtime_button_with_loading(
                                        "runtime-stop",
                                        "Stop",
                                        if stop_is_destructive {
                                            RuntimeButtonStyle::Danger
                                        } else {
                                            RuntimeButtonStyle::Outline
                                        },
                                        self.runtime_action_busy,
                                    )
                                    .on_click(cx.listener(
                                        |this, _, _, cx| {
                                            this.request_runtime_stop(false, false, cx);
                                        },
                                    )),
                                )
                            }),
                    )
                    .when(update_available, |actions| {
                        actions.child(
                            div().flex().justify_end().child(
                                runtime_button_with_loading(
                                    "runtime-update",
                                    "Update Runtime",
                                    RuntimeButtonStyle::Filled,
                                    self.runtime_action_busy,
                                )
                                .on_click(cx.listener(
                                    |this, _, _, cx| {
                                        this.request_runtime_stop(false, true, cx);
                                    },
                                )),
                            ),
                        )
                    }),
            )
            .when(
                build_mismatch
                    || persistent
                    || self.status_data.runtime_error.is_some()
                    || update_available,
                |panel| panel.overflow_y_scroll(),
            )
            .into_any_element()
    }

    pub(super) fn render_runtime_force_dialog(&self, cx: &mut Context<Self>) -> AnyElement {
        let message = self
            .runtime_action_armed
            .as_deref()
            .unwrap_or("The runtime still has active work.");
        div()
            .absolute()
            .top_0()
            .right_0()
            .bottom_0()
            .left_0()
            .occlude()
            .flex()
            .items_center()
            .justify_center()
            .bg(theme::overlay_scrim())
            .child(
                // Flutter's intrinsic confirm dialog resolves to roughly 350
                // GPUI logical pixels on the macOS desktop scale; keeping the
                // shell compact also preserves the same message wrapping.
                dialog_shell("force-stop-runtime-dialog", "Force Stop Runtime", 350.0)
                    .child(
                        div()
                            .text_size(px(14.0))
                            .font_weight(gpui::FontWeight::MEDIUM)
                            .child("Force Stop Runtime"),
                    )
                    .child(
                        div()
                            .mt(px(12.0))
                            .text_sm()
                            .text_color(theme::text_muted())
                            .child(format!("{message} Force stop terminates them.")),
                    )
                    .child(
                        div()
                            .flex()
                            .gap(px(8.0))
                            .mt(px(20.0))
                            .child(
                                button("cancel-runtime-stop", "Cancel", ButtonKind::Text, false)
                                    .flex_1()
                                    .on_click(cx.listener(|this, _, _, cx| {
                                        if !this.runtime_action_busy {
                                            this.runtime_action_armed = None;
                                            this.runtime_restart_after_stop = false;
                                            cx.notify();
                                        }
                                    })),
                            )
                            .child(
                                button(
                                    "confirm-runtime-stop",
                                    "Force Stop",
                                    ButtonKind::Destructive,
                                    self.runtime_action_busy,
                                )
                                .flex_1()
                                .on_click(cx.listener(
                                    |this, _, _, cx| {
                                        let restart = this.runtime_restart_after_stop;
                                        this.request_runtime_stop(true, restart, cx);
                                    },
                                )),
                            ),
                    ),
            )
            .into_any_element()
    }

    fn request_runtime_stop(
        &mut self,
        force: bool,
        restart_after_stop: bool,
        cx: &mut Context<Self>,
    ) {
        if self.runtime_action_busy {
            return;
        }
        self.runtime_restart_after_stop = restart_after_stop;
        self.runtime_action_busy = true;
        let bridge = self.bridge.clone();
        cx.spawn(async move |this, cx| {
            let result = bridge
                .request("host.shutdown", json!({"force": force}))
                .await;
            let Some(this) = this.upgrade() else {
                return;
            };
            this.update(cx, |this, cx| {
                this.runtime_action_busy = false;
                match result {
                    Ok(_) => {
                        this.runtime_action_armed = None;
                        this.dismiss_status_popover(cx);
                        this.status_data.runtime = None;
                        this.connection_label = "Runtime Unavailable".into();
                        if this.runtime_restart_after_stop {
                            this.runtime_restart_after_stop = false;
                            this.request_runtime_start(cx);
                        }
                    }
                    Err(error) if !force => {
                        if let Some(message) = runtime_busy_message(&error) {
                            this.runtime_action_armed = Some(message);
                        } else {
                            this.local_message = Some(error.into());
                        }
                    }
                    Err(error) => {
                        this.runtime_action_armed = None;
                        this.runtime_restart_after_stop = false;
                        this.local_message = Some(error.into());
                    }
                }
                cx.notify();
            });
        })
        .detach();
    }

    fn request_runtime_start(&mut self, cx: &mut Context<Self>) {
        if self.runtime_action_busy {
            return;
        }
        self.runtime_action_busy = true;
        let bridge = self.bridge.clone();
        let config = RuntimeHostStartConfig {
            empty_shutdown_delay_seconds: positive_u64(
                self.settings_state.host_empty_shutdown_delay_seconds,
                30,
            ),
            detached_session_shutdown_delay_seconds: positive_u64(
                self.settings_state.host_detached_shutdown_delay_seconds,
                3600,
            ),
            scrollback_bytes: positive_u64(
                self.settings_state.terminal_host_scrollback_bytes,
                10_000_000,
            ),
            login_shell: self.settings_state.terminal_login_shell,
            crash_reporting: self.settings_state.crash_reporting_enabled,
        };
        cx.spawn(async move |this, cx| {
            let result = bridge.start_host(config).await;
            cx.background_executor()
                .timer(std::time::Duration::from_millis(500))
                .await;
            let Some(this) = this.upgrade() else {
                return;
            };
            this.update(cx, |this, cx| {
                this.runtime_action_busy = false;
                match result {
                    Ok(()) => {
                        this.status_data.runtime_error = None;
                        this.refresh_runtime_status(cx);
                    }
                    Err(error) => this.local_message = Some(error.into()),
                }
                cx.notify();
            });
        })
        .detach();
    }
}

fn runtime_row(label: &'static str, value: String, value_color: Option<gpui::Rgba>) -> gpui::Div {
    div()
        .flex()
        .items_center()
        // Flutter's status rows keep a four-pixel bottom gap under the
        // twelve-pixel label line. A 21px minimum preserves that rhythm
        // without making the values themselves taller, so the anchored card
        // grows upward to the same top edge as the reference panel.
        .min_h(px(21.0))
        .text_size(px(12.0))
        .child(
            div()
                .w(px(116.0))
                .text_color(theme::text_muted())
                .child(label),
        )
        .child(
            div()
                .flex_1()
                .overflow_hidden()
                .text_ellipsis()
                .font_family("JetBrains Mono")
                .text_size(px(11.0))
                .when_some(value_color, |item, color| item.text_color(color))
                .child(value),
        )
}

#[derive(Clone, Copy)]
enum RuntimeButtonStyle {
    Outline,
    Filled,
    Danger,
}

fn runtime_button(
    id: &'static str,
    label: &'static str,
    button_style: RuntimeButtonStyle,
) -> gpui::Stateful<gpui::Div> {
    let filled = matches!(button_style, RuntimeButtonStyle::Filled);
    let danger = matches!(button_style, RuntimeButtonStyle::Danger);
    div()
        .id(id)
        .focusable()
        .tab_stop(true)
        .role(Role::Button)
        .aria_label(label)
        .h(px(28.0))
        .px_3()
        .flex()
        .items_center()
        .justify_center()
        .rounded_md()
        .border_1()
        .border_color(if danger {
            theme::danger()
        } else if filled {
            theme::accent()
        } else {
            theme::border()
        })
        .bg(if filled {
            theme::accent()
        } else {
            theme::transparent()
        })
        .text_color(if danger {
            theme::danger()
        } else if filled {
            theme::on_accent()
        } else {
            theme::text()
        })
        .cursor(CursorStyle::PointingHand)
        .hover(move |style| {
            style.bg(if filled {
                theme::accent_hover()
            } else {
                theme::surface_selected()
            })
        })
        .child(label)
}

fn runtime_button_with_loading(
    id: &'static str,
    label: &'static str,
    button_style: RuntimeButtonStyle,
    loading: bool,
) -> gpui::Stateful<gpui::Div> {
    runtime_button(id, label, button_style).when(loading, |button| {
        button.child(loading_indicator(13.0, theme::text_faint()))
    })
}

fn known_commit(value: Option<&str>) -> Option<&str> {
    value.filter(|value| {
        let value = value.trim();
        !value.is_empty() && !value.eq_ignore_ascii_case("unknown")
    })
}

fn build_label(value: Option<&str>) -> String {
    known_commit(value)
        .map(|value| value.chars().take(7).collect())
        .unwrap_or_else(|| "-".to_owned())
}

/// Converts the host's shutdown-busy protocol error into the same concise
/// explanation Flutter presents before asking whether to force-stop it.
/// Non-busy errors return `None` so they remain ordinary error toasts.
fn runtime_busy_message(error: &str) -> Option<String> {
    let captures = regex::Regex::new(
        r"Runtime host has (\d+) active agent\(s\), (\d+) active terminal session\(s\), (\d+) active background job\(s\), and (\d+) active push subscription\(s\)",
    )
    .ok()
    .and_then(|pattern| pattern.captures(error));
    let (agents, sessions, jobs, pushes) = if let Some(captures) = captures {
        (
            captures.get(1)?.as_str().parse::<u64>().ok()?,
            captures.get(2)?.as_str().parse::<u64>().ok()?,
            captures.get(3)?.as_str().parse::<u64>().ok()?,
            captures.get(4)?.as_str().parse::<u64>().ok()?,
        )
    } else {
        let legacy = regex::Regex::new(
            r"Runtime host has (\d+) active terminal session\(s\) and (\d+) active background job\(s\)",
        )
        .ok()
        .and_then(|pattern| pattern.captures(error));
        let captures = legacy?;
        (
            0,
            captures.get(1)?.as_str().parse::<u64>().ok()?,
            captures.get(2)?.as_str().parse::<u64>().ok()?,
            0,
        )
    };

    let mut parts = Vec::new();
    if agents > 0 {
        parts.push(format!("{agents} open agent(s)"));
    }
    if sessions > 0 {
        parts.push(format!("{sessions} active terminal session(s)"));
    }
    if jobs > 0 {
        parts.push(format!("{jobs} active background job(s)"));
    }
    if pushes > 0 {
        parts.push(format!("{pushes} active push subscription(s)"));
    }
    if parts.is_empty() {
        return Some("The runtime still has active work.".to_owned());
    }

    let message = match parts.as_slice() {
        [part] => format!("The runtime has {part}."),
        [first, second] => format!("The runtime has {first} and {second}."),
        [first, second, third] => {
            format!("The runtime has {first}, {second}, and {third}.")
        }
        [first, second, third, fourth] => {
            format!("The runtime has {first}, {second}, {third}, and {fourth}.")
        }
        _ => unreachable!("runtime busy message has at most four counters"),
    };
    Some(message)
}

fn positive_u64(value: i64, fallback: u64) -> u64 {
    u64::try_from(value)
        .ok()
        .filter(|value| *value > 0)
        .unwrap_or(fallback)
}

fn version_label(value: Option<&str>) -> String {
    match value {
        Some(value) if value.starts_with(['v', 'V']) => value.to_owned(),
        Some(value) => format!("v{value}"),
        None => "Unknown".to_owned(),
    }
}

fn bundled_runtime_version() -> &'static str {
    option_env!("ALERA_RUNTIME_BUNDLED_VERSION").unwrap_or("0.1.0")
}

pub(super) fn runtime_is_running(value: Option<&Value>, has_error: bool) -> bool {
    value.is_some() && !has_error
}

pub(super) fn runtime_update_available(value: Option<&Value>, has_error: bool) -> bool {
    let running = runtime_is_running(value, has_error);
    if !running {
        return false;
    }
    let Some(raw_host_version) =
        string_at(value, "runtimeHostVersion").filter(|version| !version.trim().is_empty())
    else {
        return false;
    };
    let host_version = version_label(Some(raw_host_version));
    let bundled_version = version_label(Some(bundled_runtime_version()));
    let version_order = compare_runtime_versions(&bundled_version, &host_version);
    if version_order == Ordering::Greater {
        return true;
    }
    if version_order != Ordering::Equal {
        return false;
    }
    let host_commit = string_at(value, "runtimeHostCommit");
    let bundled_commit = option_env!("ALERA_BUILD_COMMIT").unwrap_or("unknown");
    matches!(
        (known_commit(host_commit), known_commit(Some(bundled_commit))),
        (Some(host), Some(bundled)) if host != bundled
    )
}

fn runtime_has_build_mismatch(
    value: Option<&Value>,
    has_error: bool,
    bundled_version: &str,
    bundled_commit: &str,
) -> bool {
    if !runtime_is_running(value, has_error) {
        return false;
    }
    let Some(host_version) =
        string_at(value, "runtimeHostVersion").filter(|version| !version.trim().is_empty())
    else {
        return false;
    };
    if compare_runtime_versions(bundled_version, &version_label(Some(host_version)))
        != Ordering::Equal
    {
        return false;
    }
    matches!(
        (
            known_commit(string_at(value, "runtimeHostCommit")),
            known_commit(Some(bundled_commit)),
        ),
        (Some(host), Some(bundled)) if host != bundled
    )
}

fn compare_runtime_versions(left: &str, right: &str) -> Ordering {
    match (parse_runtime_version(left), parse_runtime_version(right)) {
        (None, None) => left.cmp(right),
        (None, Some(_)) => Ordering::Less,
        (Some(_), None) => Ordering::Greater,
        (Some(left), Some(right)) => left.cmp(&right),
    }
}

fn parse_runtime_version(value: &str) -> Option<[u64; 3]> {
    let core = value
        .trim()
        .trim_start_matches(['v', 'V'])
        .split(['-', '+'])
        .next()?
        .trim();
    if core.is_empty() {
        return None;
    }
    let mut numbers = core.split('.').map(str::parse::<u64>);
    let first = numbers.next()?.ok()?;
    let second = numbers.next().and_then(Result::ok).unwrap_or(0);
    let third = numbers.next().and_then(Result::ok).unwrap_or(0);
    if numbers.next().is_some() {
        return None;
    }
    Some([first, second, third])
}

pub(super) fn runtime_chip_label(value: Option<&Value>, has_error: bool, loading: bool) -> String {
    if loading && value.is_none() {
        return "Runtime".to_owned();
    }
    if has_error && !runtime_is_running(value, has_error) {
        return "Runtime Error".to_owned();
    }
    if runtime_update_available(value, has_error) {
        return "Update Available".to_owned();
    }
    if runtime_is_running(value, has_error) {
        let version = string_at(value, "runtimeHostVersion");
        if version.is_some_and(|version| !version.trim().is_empty()) {
            return format!("Runtime {}", version_label(version));
        }
        return "Runtime Running".to_owned();
    }
    "Runtime Stopped".to_owned()
}

pub(super) fn runtime_chip_color(
    value: Option<&Value>,
    has_error: bool,
    loading: bool,
) -> gpui::Rgba {
    if has_error && !runtime_is_running(value, has_error) {
        return theme::danger();
    }
    if runtime_update_available(value, has_error) {
        return theme::warning();
    }
    if runtime_is_running(value, has_error) {
        return theme::success();
    }
    if loading {
        return theme::text_muted();
    }
    theme::text_faint()
}

fn string_at<'a>(value: Option<&'a Value>, key: &str) -> Option<&'a str> {
    value.and_then(|item| item.get(key)).and_then(Value::as_str)
}

fn integer_at(value: Option<&Value>, key: &str) -> u64 {
    value
        .and_then(|item| item.get(key))
        .and_then(Value::as_u64)
        .unwrap_or(0)
}

#[cfg(test)]
mod tests {
    use serde_json::json;

    use super::{
        bundled_runtime_version, compare_runtime_versions, runtime_busy_message,
        runtime_chip_label, runtime_has_build_mismatch, runtime_is_running,
        runtime_update_available,
    };

    #[test]
    fn runtime_chip_distinguishes_error_from_stopped() {
        assert_eq!(runtime_chip_label(None, true, false), "Runtime Error");
        assert_eq!(runtime_chip_label(None, false, false), "Runtime Stopped");
        assert_eq!(runtime_chip_label(None, false, true), "Runtime");
    }

    #[test]
    fn runtime_chip_uses_version_and_build_updates() {
        let current = json!({
            "runtimeHostVersion": bundled_runtime_version(),
            "runtimeHostCommit": option_env!("ALERA_BUILD_COMMIT").unwrap_or("unknown")
        });
        assert!(runtime_is_running(Some(&current), false));
        assert!(!runtime_update_available(Some(&current), false));

        let newer = json!({"runtimeHostVersion": "999.0.0"});
        assert!(!runtime_update_available(Some(&newer), false));
        assert_eq!(
            runtime_chip_label(Some(&newer), false, false),
            "Runtime v999.0.0"
        );
        assert!(!runtime_update_available(
            Some(&json!({"runtimeHostVersion": "999.0.0"})),
            false
        ));
        assert!(runtime_update_available(
            Some(&json!({"runtimeHostVersion": "0.0.1"})),
            false
        ));
        assert!(compare_runtime_versions("v1.2.10", "v1.2.9").is_gt());
    }

    #[test]
    fn runtime_update_and_build_rows_follow_flutter_version_direction() {
        let bundled_version = format!("v{}", bundled_runtime_version());
        let bundled_commit = option_env!("ALERA_BUILD_COMMIT").unwrap_or("unknown");
        let older = json!({
            "runtimeHostVersion": "0.0.1",
            "runtimeHostCommit": "older"
        });
        assert!(runtime_update_available(Some(&older), false));
        assert!(!runtime_has_build_mismatch(
            Some(&older),
            false,
            &bundled_version,
            bundled_commit
        ));

        let newer = json!({
            "runtimeHostVersion": "999.0.0",
            "runtimeHostCommit": "newer"
        });
        assert!(!runtime_update_available(Some(&newer), false));
        assert!(!runtime_has_build_mismatch(
            Some(&newer),
            false,
            &bundled_version,
            bundled_commit
        ));
    }

    #[test]
    fn runtime_busy_message_matches_flutter_wording_and_ignores_zero_counts() {
        assert_eq!(
            runtime_busy_message(
                "Runtime host has 2 active agent(s), 3 active terminal session(s), 0 active background job(s), and 1 active push subscription(s). Retry with --force to stop it."
            ),
            Some(
                "The runtime has 2 open agent(s), 3 active terminal session(s), and 1 active push subscription(s)."
                    .to_owned()
            )
        );
        assert_eq!(
            runtime_busy_message(
                "Runtime host has 0 active agent(s), 2 active terminal session(s), 1 active background job(s), and 0 active push subscription(s). Retry with --force to stop it."
            ),
            Some(
                "The runtime has 2 active terminal session(s) and 1 active background job(s)."
                    .to_owned()
            )
        );
        assert_eq!(runtime_busy_message("connection refused"), None);
    }
}
