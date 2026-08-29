use gpui::{
    div, prelude::FluentBuilder as _, px, AnyElement, Context, CursorStyle,
    InteractiveElement as _, IntoElement, ParentElement as _, Role, SharedString,
    StatefulInteractiveElement as _, Styled as _, Toggled, Window,
};
use gpui_component::input::Input;
use gpui_component::scroll::ScrollableElement as _;
use serde_json::{json, Value};

use super::AleraApp;
use crate::design_system;
use crate::icons::{icon, AleraIcon};
use crate::theme;

const TERMINAL_PULSE_CAPABILITY: &str = "terminalPulseV1";
const DEFAULT_COMMAND: &str = "r";
const DEFAULT_DELAY_MS: u64 = 2_000;
const MIN_DELAY_MS: u64 = 100;
const MAX_DELAY_MS: u64 = 3_600_000;

#[derive(Clone, Copy)]
struct PulseConfiguration {
    append_enter: bool,
    delay_ms: u64,
}

impl AleraApp {
    pub(super) fn terminal_pulse_supported(&self) -> bool {
        self.settings_state
            .runtime_capabilities
            .iter()
            .any(|capability| capability == TERMINAL_PULSE_CAPABILITY)
    }

    pub(super) fn open_terminal_pulse_dialog(
        &mut self,
        session_id: String,
        window: &mut Window,
        cx: &mut Context<Self>,
    ) {
        if !self.terminal_pulse_supported() || session_id.trim().is_empty() {
            return;
        }
        let configuration = self.terminal_pulse_configuration(&session_id);
        self.terminal_pulse_command_input.update(cx, |input, cx| {
            input.set_value(configuration.0, window, cx);
        });
        self.terminal_pulse_delay_input.update(cx, |input, cx| {
            input.set_value(format_delay_seconds(configuration.1.delay_ms), window, cx);
        });
        self.terminal_pulse_append_enter = configuration.1.append_enter;
        self.terminal_pulse_armed = false;
        self.terminal_pulse_error = None;
        self.terminal_pulse_dialog_session = Some(session_id.clone());
        self.terminal_pulse_busy = true;
        self.terminal_pulse_generation = self.terminal_pulse_generation.wrapping_add(1);
        let generation = self.terminal_pulse_generation;
        let bridge = self.bridge.clone();
        cx.spawn(async move |this, cx| {
            let result = bridge
                .request_with_timeout(
                    "terminal.pulse.status",
                    json!({"sessionId": session_id}),
                    std::time::Duration::from_secs(30),
                )
                .await;
            let Some(this) = this.upgrade() else {
                return;
            };
            this.update(cx, |this, cx| {
                if generation != this.terminal_pulse_generation {
                    return;
                }
                this.terminal_pulse_busy = false;
                match result {
                    Ok(value) => {
                        this.terminal_pulse_armed = value
                            .get("armed")
                            .and_then(Value::as_bool)
                            .unwrap_or(false);
                        this.terminal_pulse_error = value
                            .get("error")
                            .and_then(Value::as_str)
                            .map(SharedString::from);
                    }
                    Err(error) => this.terminal_pulse_error = Some(error.into()),
                }
                cx.notify();
            });
        })
        .detach();
        cx.notify();
    }

    pub(super) fn close_terminal_pulse_dialog(&mut self, cx: &mut Context<Self>) {
        self.terminal_pulse_dialog_session = None;
        self.terminal_pulse_busy = false;
        self.terminal_pulse_error = None;
        self.terminal_pulse_generation = self.terminal_pulse_generation.wrapping_add(1);
        cx.notify();
    }

    pub(super) fn save_terminal_pulse(&mut self, cx: &mut Context<Self>) {
        if self.terminal_pulse_busy {
            return;
        }
        let Some(session_id) = self.terminal_pulse_dialog_session.clone() else {
            return;
        };
        let command = self
            .terminal_pulse_command_input
            .read(cx)
            .value()
            .trim()
            .to_owned();
        if command.is_empty() {
            self.terminal_pulse_error = Some("Terminal Input Is Required.".into());
            cx.notify();
            return;
        }
        let delay_seconds = self
            .terminal_pulse_delay_input
            .read(cx)
            .value()
            .trim()
            .parse::<f64>();
        let Ok(delay_seconds) = delay_seconds else {
            self.terminal_pulse_error = Some("Wait Must Be A Valid Number Of Seconds.".into());
            cx.notify();
            return;
        };
        if !delay_seconds.is_finite() {
            self.terminal_pulse_error = Some("Wait Must Be A Valid Number Of Seconds.".into());
            cx.notify();
            return;
        }
        let delay_ms = (delay_seconds.clamp(0.1, 3_600.0) * 1_000.0).round() as u64;
        let delay_ms = delay_ms.clamp(MIN_DELAY_MS, MAX_DELAY_MS);
        let append_enter = self.terminal_pulse_append_enter;
        let armed = self.terminal_pulse_armed;
        self.terminal_pulse_busy = true;
        self.terminal_pulse_error = None;
        self.terminal_pulse_generation = self.terminal_pulse_generation.wrapping_add(1);
        let generation = self.terminal_pulse_generation;
        let bridge = self.bridge.clone();
        cx.spawn(async move |this, cx| {
            let result = bridge
                .request_with_timeout(
                    "terminal.pulse.configure",
                    json!({
                        "sessionId": session_id,
                        "configuration": {
                            "command": command,
                            "appendEnter": append_enter,
                            "delayMs": delay_ms,
                        },
                        "armed": armed,
                    }),
                    std::time::Duration::from_secs(30),
                )
                .await;
            let Some(this) = this.upgrade() else {
                return;
            };
            this.update(cx, |this, cx| {
                if generation != this.terminal_pulse_generation {
                    return;
                }
                this.terminal_pulse_busy = false;
                match result {
                    Ok(_) => this.close_terminal_pulse_dialog(cx),
                    Err(error) => this.terminal_pulse_error = Some(error.into()),
                }
                cx.notify();
            });
        })
        .detach();
        cx.notify();
    }

    pub(super) fn render_terminal_pulse_button(
        &self,
        session_id: &str,
        cx: &mut Context<Self>,
    ) -> AnyElement {
        let session_id = session_id.to_owned();
        design_system::icon_button(
            SharedString::from(format!("terminal-pulse-{session_id}")),
            "Configure Terminal Pulse",
            AleraIcon::Activity,
            true,
            28.0,
            Some(theme::surface_raised()),
            Some(theme::border_subtle()),
        )
        .absolute()
        .top(px(4.0))
        .right(px(68.0))
        .on_click(cx.listener(move |this, _, window, cx| {
            this.open_terminal_pulse_dialog(session_id.clone(), window, cx);
            cx.stop_propagation();
        }))
        .into_any_element()
    }

    pub(super) fn render_terminal_pulse_dialog(&self, cx: &mut Context<Self>) -> AnyElement {
        let Some(session_id) = self.terminal_pulse_dialog_session.as_deref() else {
            return div().into_any_element();
        };
        let command = self.terminal_pulse_command_input.clone();
        let delay = self.terminal_pulse_delay_input.clone();
        div()
            .id("terminal-pulse-overlay")
            .absolute()
            .inset_0()
            .occlude()
            .flex()
            .items_center()
            .justify_center()
            .bg(theme::overlay_scrim())
            .child(
                div()
                    .id("terminal-pulse-dialog")
                    .role(Role::Dialog)
                    .aria_label("Terminal Pulse")
                    .w(px(620.0))
                    .max_h(px(700.0))
                    .rounded_lg()
                    .border_1()
                    .border_color(theme::border())
                    .bg(theme::surface_raised())
                    .shadow_lg()
                    .flex()
                    .flex_col()
                    .child(
                        div()
                            .flex()
                            .items_center()
                            .px_5()
                            .py_4()
                            .border_b_1()
                            .border_color(theme::border_subtle())
                            .child(
                                div()
                                    .text_lg()
                                    .font_weight(gpui::FontWeight::SEMIBOLD)
                                    .child("Terminal Pulse"),
                            )
                            .child(div().flex_1())
                            .child(
                                div()
                                    .id("terminal-pulse-close")
                                    .role(Role::Button)
                                    .aria_label("Close Terminal Pulse")
                                    .p_2()
                                    .cursor(CursorStyle::PointingHand)
                                    .hover(|style| style.bg(theme::surface_selected()))
                                    .on_click(cx.listener(|this, _, _, cx| {
                                        this.close_terminal_pulse_dialog(cx);
                                    }))
                                    .child(icon(AleraIcon::Close, 14.0, theme::text_muted())),
                            ),
                    )
                    .child(
                        div()
                            .id(SharedString::from(format!("terminal-pulse-body-{session_id}")))
                            .flex_1()
                            .min_h_0()
                            .overflow_y_scrollbar()
                            .p_5()
                            .child(
                                div()
                                    .text_size(px(11.0))
                                    .text_color(theme::text_muted())
                                    .child("Watch Git tracked and new untracked files in this workspace. The first change starts a fixed wait, then the configured input is sent once."),
                            )
                            .child(
                                div()
                                    .mt_4()
                                    .rounded_lg()
                                    .border_1()
                                    .border_color(theme::border_subtle())
                                    .bg(theme::surface())
                                    .child(
                                        div()
                                            .id("terminal-pulse-armed")
                                            .role(Role::CheckBox)
                                            .aria_label("Armed")
                                            .aria_toggled(if self.terminal_pulse_armed {
                                                Toggled::True
                                            } else {
                                                Toggled::False
                                            })
                                            .flex()
                                            .items_center()
                                            .gap_2()
                                            .p_3()
                                            .cursor(if self.terminal_pulse_busy {
                                                CursorStyle::Arrow
                                            } else {
                                                CursorStyle::PointingHand
                                            })
                                            .on_click(cx.listener(|this, _, _, cx| {
                                                if !this.terminal_pulse_busy {
                                                    this.terminal_pulse_armed =
                                                        !this.terminal_pulse_armed;
                                                    cx.notify();
                                                }
                                            }))
                                            .child(design_system::checkbox(
                                                self.terminal_pulse_armed,
                                                !self.terminal_pulse_busy,
                                                None,
                                            ))
                                            .child(
                                                div()
                                                    .flex()
                                                    .flex_col()
                                                    .child("Armed")
                                                    .child(
                                                        div()
                                                            .text_size(px(10.0))
                                                            .text_color(theme::text_faint())
                                                            .child("Disarms Automatically When This Terminal Process Restarts."),
                                                    ),
                                            ),
                                    )
                                    .child(pulse_input("Terminal Input", &command))
                                    .child(
                                        div()
                                            .id("terminal-pulse-send-enter")
                                            .role(Role::CheckBox)
                                            .aria_label("Send Enter")
                                            .aria_toggled(if self.terminal_pulse_append_enter {
                                                Toggled::True
                                            } else {
                                                Toggled::False
                                            })
                                            .flex()
                                            .items_center()
                                            .gap_2()
                                            .p_3()
                                            .cursor(if self.terminal_pulse_busy {
                                                CursorStyle::Arrow
                                            } else {
                                                CursorStyle::PointingHand
                                            })
                                            .on_click(cx.listener(|this, _, _, cx| {
                                                if !this.terminal_pulse_busy {
                                                    this.terminal_pulse_append_enter =
                                                        !this.terminal_pulse_append_enter;
                                                    cx.notify();
                                                }
                                            }))
                                            .child(design_system::checkbox(
                                                self.terminal_pulse_append_enter,
                                                !self.terminal_pulse_busy,
                                                None,
                                            ))
                                            .child("Send Enter"),
                                    )
                                    .child(pulse_input("Wait (Seconds)", &delay)),
                            )
                            .when_some(self.terminal_pulse_error.clone(), |body, error| {
                                body.child(
                                    div()
                                        .mt_3()
                                        .text_size(px(11.0))
                                        .text_color(theme::danger())
                                        .child(error),
                                )
                            }),
                    )
                    .child(
                        div()
                            .flex()
                            .justify_end()
                            .px_5()
                            .py_4()
                            .border_t_1()
                            .border_color(theme::border_subtle())
                            .child(
                                pulse_dialog_button(
                                    "terminal-pulse-save",
                                    if self.terminal_pulse_busy {
                                        "Saving Changes"
                                    } else {
                                        "Save Changes"
                                    },
                                    true,
                                    self.terminal_pulse_busy,
                                )
                                .on_click(cx.listener(|this, _, _, cx| {
                                    this.save_terminal_pulse(cx);
                                })),
                            ),
                    ),
            )
            .into_any_element()
    }

    fn terminal_pulse_configuration(&self, session_id: &str) -> (String, PulseConfiguration) {
        let payload = self
            .snapshot
            .tabs
            .iter()
            .find(|tab| tab.kind == "terminal" && super::terminal_surface::terminal_session_id(tab) == session_id)
            .and_then(|tab| tab.payload.get("terminalPulse"));
        let command = payload
            .and_then(|value| value.get("command"))
            .and_then(Value::as_str)
            .filter(|value| !value.is_empty())
            .unwrap_or(DEFAULT_COMMAND)
            .to_owned();
        let append_enter = payload
            .and_then(|value| value.get("appendEnter"))
            .and_then(Value::as_bool)
            .unwrap_or(true);
        let delay_ms = payload
            .and_then(|value| value.get("delayMs"))
            .and_then(Value::as_u64)
            .unwrap_or(DEFAULT_DELAY_MS)
            .clamp(MIN_DELAY_MS, MAX_DELAY_MS);
        (command, PulseConfiguration { append_enter, delay_ms })
    }
}

fn pulse_input(label: &'static str, input: &gpui::Entity<gpui_component::input::InputState>) -> gpui::Div {
    div()
        .p_3()
        .child(
            div()
                .mb_1()
                .text_size(px(12.0))
                .text_color(theme::text_muted())
                .child(label),
        )
        .child(Input::new(input).h(px(32.0)))
}

fn pulse_dialog_button(
    id: &'static str,
    label: &'static str,
    primary: bool,
    loading: bool,
) -> gpui::Stateful<gpui::Div> {
    div()
        .id(id)
        .role(Role::Button)
        .aria_label(label)
        .focusable()
        .tab_stop(!loading)
        .h(px(32.0))
        .px_3()
        .flex()
        .items_center()
        .gap_2()
        .rounded_md()
        .cursor(if loading {
            CursorStyle::Arrow
        } else {
            CursorStyle::PointingHand
        })
        .when(primary, |button| {
            button.bg(theme::accent()).text_color(theme::on_accent())
        })
        .when(!primary, |button| button.bg(theme::surface_selected()))
        .when(loading, |button| {
            button.child(crate::icons::loading_indicator(13.0, theme::on_accent()))
        })
        .child(label)
}

fn format_delay_seconds(delay_ms: u64) -> String {
    let seconds = delay_ms / 1_000;
    let remainder = delay_ms % 1_000;
    if remainder == 0 {
        seconds.to_string()
    } else {
        format!("{seconds}.{:03}", remainder).trim_end_matches('0').to_owned()
    }
}
