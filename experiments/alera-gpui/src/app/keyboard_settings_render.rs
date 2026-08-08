use gpui::{
    div, prelude::FluentBuilder as _, px, svg, AnyElement, AppContext as _, Context, CursorStyle,
    InteractiveElement as _, IntoElement as _, ParentElement as _, SharedString,
    StatefulInteractiveElement as _, Styled as _,
};
use gpui_component::tooltip::Tooltip;

use super::keyboard_settings::{
    definition, effective_bindings, KeyboardActionGroup, KeyboardBindingDefinition,
    KEYBOARD_BINDINGS,
};
use super::AleraApp;
use crate::{
    icons::{icon, AleraIcon},
    theme,
};

impl AleraApp {
    pub(super) fn render_keyboard_settings_pane(&self, cx: &mut Context<Self>) -> AnyElement {
        div()
            .relative()
            .track_focus(&self.keyboard_settings.focus)
            .on_key_down(cx.listener(Self::handle_keyboard_record_key))
            .child(self.render_keyboard_behavior(cx))
            .children(KeyboardActionGroup::ALL.into_iter().map(|group| {
                keyboard_group(
                    group.label(),
                    None,
                    KEYBOARD_BINDINGS
                        .iter()
                        .filter(|definition| definition.group == group)
                        .map(|definition| self.render_keyboard_binding_row(definition, cx))
                        .collect(),
                )
                .mt_4()
            }))
            .into_any_element()
    }

    fn render_keyboard_behavior(&self, cx: &mut Context<Self>) -> gpui::Div {
        let app_first = self.settings_state.keyboard_terminal_policy != "terminalFirst";
        keyboard_group(
            "Behavior",
            Some("How Shortcuts Behave While A Terminal Is Focused."),
            vec![keyboard_setting_row(
                "When A Terminal Is Focused",
                "App First Lets Alera Capture Combinations The Shell Would Otherwise Receive. Terminal First Defers To The Shell.",
                220.0,
                div()
                    .flex()
                    .h(px(34.0))
                    .rounded_md()
                    .border_1()
                    .border_color(theme::border_subtle())
                    .overflow_hidden()
                    .child(
                        keyboard_segment("keyboard-app-first", "App First", app_first).on_mouse_down(gpui::MouseButton::Left,
                            cx.listener(|this, _, _, cx| {
                                this.set_keyboard_terminal_policy("appFirst", cx);
                            }),
                        ),
                    )
                    .child(
                        keyboard_segment(
                            "keyboard-terminal-first",
                            "Terminal First",
                            !app_first,
                        )
                        .on_mouse_down(gpui::MouseButton::Left, cx.listener(|this, _, _, cx| {
                            this.set_keyboard_terminal_policy("terminalFirst", cx);
                        })),
                    )
                    .into_any_element(),
            )],
        )
    }

    fn render_keyboard_binding_row(
        &self,
        definition: &'static KeyboardBindingDefinition,
        cx: &mut Context<Self>,
    ) -> gpui::Div {
        let bindings = effective_bindings(&self.settings_state, definition);
        let modified = self
            .settings_state
            .keyboard_overrides
            .contains_key(definition.id);
        let disabled = bindings.is_empty();
        let recording = self.keyboard_settings.recording_id == Some(definition.id);
        let error = self
            .keyboard_settings
            .error
            .as_ref()
            .filter(|(id, _)| *id == definition.id)
            .map(|(_, message)| message.as_str());
        let id = definition.id;
        let binding_display = if recording {
            div()
                .flex_1()
                .text_right()
                .text_size(px(12.0))
                .text_color(theme::accent())
                .child("Press Keys... (Esc To Cancel)")
        } else if let Some(error) = error {
            div()
                .flex_1()
                .text_right()
                .text_size(px(12.0))
                .text_color(theme::danger())
                .child(error.to_string())
        } else if disabled {
            div()
                .flex_1()
                .text_right()
                .text_size(px(12.0))
                .text_color(theme::text_muted())
                .child("Disabled")
        } else {
            div()
                .flex_1()
                .flex()
                .items_center()
                .justify_end()
                .gap_1()
                .children(bindings.into_iter().map(keyboard_binding_chip))
        };
        keyboard_setting_row(
            definition.label,
            definition.description,
            280.0,
            div()
                .flex()
                .items_center()
                .justify_end()
                .gap_1()
                .child(binding_display)
                .child(
                    keyboard_icon_button(
                        SharedString::from(format!("keyboard-record-{id}")),
                        if recording {
                            AleraIcon::Close
                        } else {
                            AleraIcon::Keyboard
                        },
                        if recording {
                            "Stop Recording"
                        } else {
                            "Change Shortcut"
                        },
                    )
                    .on_mouse_down(
                        gpui::MouseButton::Left,
                        cx.listener(move |this, _, window, cx| {
                            this.start_keyboard_recording(id, window, cx);
                        }),
                    ),
                )
                .when(modified, |row| {
                    row.child(
                        keyboard_icon_button(
                            SharedString::from(format!("keyboard-reset-{id}")),
                            AleraIcon::Refresh,
                            "Reset To Default",
                        )
                        .on_mouse_down(
                            gpui::MouseButton::Left,
                            cx.listener(move |this, _, _, cx| {
                                this.reset_keyboard_binding(id, cx);
                            }),
                        ),
                    )
                })
                .when(!disabled, |row| {
                    row.child(
                        keyboard_block_button(SharedString::from(format!("keyboard-disable-{id}")))
                            .on_mouse_down(
                                gpui::MouseButton::Left,
                                cx.listener(move |this, _, _, cx| {
                                    this.disable_keyboard_binding(id, cx);
                                }),
                            ),
                    )
                })
                .into_any_element(),
        )
    }

    pub(super) fn render_keyboard_conflict(
        &self,
        conflict: &super::keyboard_settings::KeyboardBindingConflict,
        cx: &mut Context<Self>,
    ) -> gpui::Div {
        let owner = definition(conflict.owner_id)
            .map(|definition| definition.label)
            .unwrap_or("Another Action");
        let target = definition(conflict.target_id)
            .map(|definition| definition.label)
            .unwrap_or("This Action");
        div()
            .absolute()
            .inset_0()
            .flex()
            .items_center()
            .justify_center()
            .bg(gpui::rgba(0x00000099))
            .child(
                div()
                    .w(px(440.0))
                    .rounded_xl()
                    .border_1()
                    .border_color(theme::border())
                    .bg(theme::surface())
                    .p_5()
                    .child(
                        div()
                            .text_size(px(16.0))
                            .font_weight(gpui::FontWeight::SEMIBOLD)
                            .child("Shortcut Already In Use"),
                    )
                    .child(
                        div()
                            .mt_3()
                            .text_size(px(13.0))
                            .text_color(theme::text_muted())
                            .child(format!(
                                "{} Is Assigned To \"{}\". Reassign It To \"{}\"?",
                                format_binding(&conflict.chord),
                                owner,
                                target
                            )),
                    )
                    .child(
                        div()
                            .flex()
                            .justify_end()
                            .gap_2()
                            .mt_5()
                            .child(
                                keyboard_dialog_button("keyboard-conflict-cancel", "Cancel", false)
                                    .on_mouse_down(
                                        gpui::MouseButton::Left,
                                        cx.listener(|this, _, _, cx| {
                                            this.cancel_keyboard_conflict(cx);
                                        }),
                                    ),
                            )
                            .child(
                                keyboard_dialog_button(
                                    "keyboard-conflict-confirm",
                                    "Reassign",
                                    true,
                                )
                                .on_mouse_down(
                                    gpui::MouseButton::Left,
                                    cx.listener(|this, _, _, cx| {
                                        this.confirm_keyboard_conflict(cx);
                                    }),
                                ),
                            ),
                    ),
            )
    }
}

fn keyboard_group(
    title: &'static str,
    description: Option<&'static str>,
    rows: Vec<gpui::Div>,
) -> gpui::Div {
    div()
        .child(
            div()
                .ml_1()
                .mb_2()
                .child(
                    div()
                        .text_size(px(13.0))
                        .font_weight(gpui::FontWeight::SEMIBOLD)
                        .child(title),
                )
                .when_some(description, |heading, description| {
                    heading.child(
                        div()
                            .mt_1()
                            .text_size(px(12.0))
                            .text_color(theme::text_muted())
                            .child(description),
                    )
                }),
        )
        .child(
            div()
                .overflow_hidden()
                .rounded_lg()
                .border_1()
                .border_color(theme::border_subtle())
                .bg(theme::surface_selected())
                .children(rows),
        )
}

fn keyboard_setting_row(
    title: &'static str,
    description: &'static str,
    control_width: f32,
    control: AnyElement,
) -> gpui::Div {
    div()
        .flex()
        .items_center()
        .min_h(px(72.0))
        .px_3()
        .py_2()
        .border_b_1()
        .border_color(theme::border_subtle())
        .child(
            div()
                .flex_1()
                .min_w_0()
                .child(
                    div()
                        .text_size(px(14.0))
                        .font_weight(gpui::FontWeight::MEDIUM)
                        .child(title),
                )
                .child(
                    div()
                        .mt_1()
                        .text_size(px(12.0))
                        .text_color(theme::text_muted())
                        .child(description),
                ),
        )
        .child(div().w(px(control_width)).flex_none().child(control))
}

fn keyboard_segment(
    id: &'static str,
    label: &'static str,
    selected: bool,
) -> gpui::Stateful<gpui::Div> {
    div()
        .id(id)
        .flex_1()
        .flex()
        .items_center()
        .justify_center()
        .px_3()
        .text_size(px(12.0))
        .font_weight(if selected {
            gpui::FontWeight::SEMIBOLD
        } else {
            gpui::FontWeight::NORMAL
        })
        .bg(if selected {
            theme::surface_raised()
        } else {
            theme::transparent()
        })
        .cursor(CursorStyle::PointingHand)
        .hover(|style| style.bg(theme::surface_raised()))
        .child(label)
}

fn keyboard_binding_chip(binding: String) -> gpui::Div {
    div()
        .h(px(22.0))
        .px_2()
        .flex()
        .items_center()
        .rounded_md()
        .bg(theme::surface_raised())
        .text_size(px(11.0))
        .font_family("JetBrains Mono")
        .child(format_binding(&binding))
}

fn keyboard_icon_button(
    id: SharedString,
    icon_kind: AleraIcon,
    tooltip: &'static str,
) -> gpui::Stateful<gpui::Div> {
    div()
        .id(id)
        .flex()
        .items_center()
        .justify_center()
        .w(px(28.0))
        .h(px(28.0))
        .rounded_md()
        .cursor(CursorStyle::PointingHand)
        .hover(|style| style.bg(theme::surface_raised()))
        .tooltip(move |_, cx| cx.new(|_| Tooltip::new(tooltip)).into())
        .child(icon(icon_kind, 17.0, theme::text_muted()))
}

fn keyboard_block_button(id: SharedString) -> gpui::Stateful<gpui::Div> {
    div()
        .id(id)
        .flex()
        .items_center()
        .justify_center()
        .w(px(28.0))
        .h(px(28.0))
        .rounded_md()
        .cursor(CursorStyle::PointingHand)
        .hover(|style| style.bg(theme::surface_raised()))
        .tooltip(|_, cx| cx.new(|_| Tooltip::new("Disable Shortcut")).into())
        .child(
            svg()
                .path("icons/ban.svg")
                .w(px(14.0))
                .h(px(14.0))
                .text_color(theme::text_muted()),
        )
}

fn keyboard_dialog_button(
    id: &'static str,
    label: &'static str,
    filled: bool,
) -> gpui::Stateful<gpui::Div> {
    div()
        .id(id)
        .flex()
        .items_center()
        .justify_center()
        .h(px(34.0))
        .px_4()
        .rounded_lg()
        .border_1()
        .border_color(if filled {
            theme::accent()
        } else {
            theme::border_subtle()
        })
        .bg(if filled {
            theme::accent()
        } else {
            theme::surface_selected()
        })
        .text_color(if filled {
            theme::on_accent()
        } else {
            theme::text()
        })
        .cursor(CursorStyle::PointingHand)
        .hover(|style| style.bg(theme::surface_raised()))
        .child(label)
}

fn format_binding(binding: &str) -> String {
    let mut parts = binding.split('+').collect::<Vec<_>>();
    let trigger = parts.pop().unwrap_or_default();
    let trigger = match trigger {
        "Comma" => ",",
        "Period" => ".",
        "Slash" => "/",
        "Backslash" => "\\",
        "BracketLeft" => "[",
        "BracketRight" => "]",
        "Minus" => "-",
        "Equal" => "=",
        "Semicolon" => ";",
        "Quote" => "'",
        "Backquote" => "`",
        other => other,
    };
    if cfg!(target_os = "macos") {
        let mut label = String::new();
        for modifier in ["Ctrl", "Alt", "Shift", "Cmd", "Mod"] {
            if parts.contains(&modifier) {
                label.push_str(match modifier {
                    "Ctrl" => "⌃",
                    "Alt" => "⌥",
                    "Shift" => "⇧",
                    "Cmd" | "Mod" => "⌘",
                    _ => "",
                });
            }
        }
        label.push_str(trigger);
        label
    } else {
        parts.push(trigger);
        parts
            .into_iter()
            .map(|part| if part == "Mod" { "Ctrl" } else { part })
            .collect::<Vec<_>>()
            .join("+")
    }
}
