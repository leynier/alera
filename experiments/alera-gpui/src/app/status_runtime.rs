use gpui::{
    div, prelude::FluentBuilder as _, px, AnyElement, Context, CursorStyle,
    InteractiveElement as _, IntoElement, ParentElement as _, StatefulInteractiveElement as _,
    Styled as _,
};
use serde_json::{json, Value};

use super::AleraApp;
use crate::{icons::loading_indicator, runtime_bridge::RuntimeHostStartConfig, theme};

impl AleraApp {
    pub(super) fn render_runtime_popover(&self, cx: &mut Context<Self>) -> AnyElement {
        let value = self.status_data.runtime.as_ref();
        let running = value.is_some() && self.status_data.runtime_error.is_none();
        let version = version_label(string_at(value, "runtimeHostVersion"));
        let bundled_version = version_label(Some(env!("CARGO_PKG_VERSION")));
        let host_commit = string_at(value, "runtimeHostCommit");
        let bundled_commit = option_env!("ALERA_BUILD_COMMIT").unwrap_or("unknown");
        let commit_mismatch = match (
            known_commit(host_commit),
            known_commit(Some(bundled_commit)),
        ) {
            (Some(host), Some(bundled)) => host != bundled,
            _ => false,
        };
        let version_mismatch = running && version != bundled_version;
        let build_mismatch = running && !version_mismatch && commit_mismatch;
        let update_available = version_mismatch || build_mismatch;
        let sessions = integer_at(value, "activeSessions");
        let agents = integer_at(value, "activeAgents");
        let persistent = value
            .and_then(|item| item.get("persistent"))
            .and_then(Value::as_bool)
            .unwrap_or(false);
        let stop_is_destructive = sessions > 0 || agents > 0;

        div()
            .id("runtime-popover")
            .absolute()
            .right(px(4.0))
            .bottom(theme::status_bar_height())
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
                    .text_base()
                    .font_weight(gpui::FontWeight::SEMIBOLD)
                    .child("Runtime"),
            )
            .child(div().h(px(8.0)))
            .child(runtime_row(
                "Status",
                if self.status_data.runtime_error.is_some() {
                    "Stopped".to_owned()
                } else if running {
                    "Running".to_owned()
                } else {
                    "Checking".to_owned()
                },
                running.then(theme::success),
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
                    .flex_shrink_0()
                    .justify_end()
                    .gap_2()
                    .mt_3()
                    .child(
                        runtime_button("runtime-refresh", "Refresh", RuntimeButtonStyle::Outline)
                            .on_mouse_down(
                                gpui::MouseButton::Left,
                                cx.listener(|this, _, _, cx| {
                                    this.refresh_runtime_status(cx);
                                }),
                            ),
                    )
                    .when(!running, |actions| {
                        actions.child(
                            runtime_button_with_loading(
                                "runtime-start",
                                "Start",
                                RuntimeButtonStyle::Filled,
                                self.runtime_action_busy,
                            )
                            .on_mouse_down(
                                gpui::MouseButton::Left,
                                cx.listener(|this, _, _, cx| {
                                    this.request_runtime_start(cx);
                                }),
                            ),
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
                            .on_mouse_down(
                                gpui::MouseButton::Left,
                                cx.listener(|this, _, _, cx| {
                                    this.request_runtime_stop(false, false, cx);
                                }),
                            ),
                        )
                    })
                    .when(update_available, |actions| {
                        actions.child(
                            runtime_button_with_loading(
                                "runtime-update",
                                "Update Runtime",
                                RuntimeButtonStyle::Filled,
                                self.runtime_action_busy,
                            )
                            .on_mouse_down(
                                gpui::MouseButton::Left,
                                cx.listener(|this, _, _, cx| {
                                    this.request_runtime_stop(false, true, cx);
                                }),
                            ),
                        )
                    }),
            )
            // Keep the overlay out of the status bar flex flow. The generic
            // scrollbar wrapper forces a relative outer element.
            .overflow_y_scroll()
            .into_any_element()
    }

    pub(super) fn render_runtime_force_dialog(&self, cx: &mut Context<Self>) -> AnyElement {
        let message = self
            .runtime_action_armed
            .as_deref()
            .unwrap_or("The Runtime Still Has Active Work.");
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
                div()
                    .w(px(430.0))
                    .rounded_lg()
                    .border_1()
                    .border_color(theme::border())
                    .bg(theme::surface_raised())
                    .shadow_lg()
                    .p_4()
                    .child(
                        div()
                            .text_lg()
                            .font_weight(gpui::FontWeight::SEMIBOLD)
                            .child("Force Stop Runtime"),
                    )
                    .child(
                        div()
                            .mt_3()
                            .text_sm()
                            .text_color(theme::text_muted())
                            .child(format!("{message} Force Stop Terminates Them.")),
                    )
                    .child(
                        div()
                            .flex()
                            .justify_end()
                            .gap_2()
                            .mt_4()
                            .child(
                                runtime_button(
                                    "cancel-runtime-stop",
                                    "Cancel",
                                    RuntimeButtonStyle::Outline,
                                )
                                .on_mouse_down(
                                    gpui::MouseButton::Left,
                                    cx.listener(|this, _, _, cx| {
                                        if !this.runtime_action_busy {
                                            this.runtime_action_armed = None;
                                            this.runtime_restart_after_stop = false;
                                            cx.notify();
                                        }
                                    }),
                                ),
                            )
                            .child(
                                runtime_button_with_loading(
                                    "confirm-runtime-stop",
                                    "Force Stop",
                                    RuntimeButtonStyle::Danger,
                                    self.runtime_action_busy,
                                )
                                .on_mouse_down(
                                    gpui::MouseButton::Left,
                                    cx.listener(|this, _, _, cx| {
                                        let restart = this.runtime_restart_after_stop;
                                        this.request_runtime_stop(true, restart, cx);
                                    }),
                                ),
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
            let _ = this.update(cx, |this, cx| {
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
                    Err(error) if !force => this.runtime_action_armed = Some(error),
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
            gpui::Timer::after(std::time::Duration::from_millis(500)).await;
            let Some(this) = this.upgrade() else {
                return;
            };
            let _ = this.update(cx, |this, cx| {
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
        .min_h(px(20.0))
        .text_sm()
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

fn string_at<'a>(value: Option<&'a Value>, key: &str) -> Option<&'a str> {
    value.and_then(|item| item.get(key)).and_then(Value::as_str)
}

fn integer_at(value: Option<&Value>, key: &str) -> u64 {
    value
        .and_then(|item| item.get(key))
        .and_then(Value::as_u64)
        .unwrap_or(0)
}
