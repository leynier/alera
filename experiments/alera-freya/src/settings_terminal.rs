use alera_desktop_core::RuntimeBridge;
use freya::{icons, prelude::*};
use serde_json::json;

use crate::{
    BORDER, MUTED, SURFACE, TEXT, settings_group_described, settings_switch,
    settings_terminal_color, settings_terminal_font,
    settings_terminal_state::{TerminalSignals, compact_number, load_draft, persist_draft},
    settings_terminal_theme,
};

pub fn content(
    active: bool,
    bridge: RuntimeBridge,
    terminal_settings_revision: State<u64>,
) -> Element {
    let signals = TerminalSignals {
        font_family: use_state(|| "JetBrains Mono".to_string()),
        font_size: use_state(|| "13".to_string()),
        font_weight: use_state(|| "400".to_string()),
        line_height: use_state(|| "1.3".to_string()),
        padding_x: use_state(|| "12".to_string()),
        padding_y: use_state(|| "12".to_string()),
        cursor_shape: use_state(|| "block".to_string()),
        cursor_blink: use_state(|| false),
        cursor_opacity: use_state(|| "1".to_string()),
        theme_name: use_state(|| "Alera Dark".to_string()),
        background_opacity: use_state(|| "1".to_string()),
        foreground: use_state(String::new),
        background: use_state(String::new),
        cursor: use_state(String::new),
        selection: use_state(String::new),
        tui_scroll: use_state(|| "1".to_string()),
        clipboard_on_select: use_state(|| false),
        allow_osc52: use_state(|| false),
        login_shell: use_state(|| cfg!(target_os = "macos")),
        scrollback_lines: use_state(|| "10000".to_string()),
        host_scrollback_mb: use_state(|| "10".to_string()),
        buffer_budget_mb: use_state(|| "256".to_string()),
        word_separators: use_state(String::new),
    };
    let loaded = use_state(|| false);
    let open_menu = use_state(|| None::<String>);
    let just_opened = use_state(|| false);
    let font_highlight = use_state(|| 0_usize);
    let font_committed = use_state(|| "JetBrains Mono".to_string());
    let font_families = use_state(|| {
        [
            "Fira Code",
            "JetBrains Mono",
            "SF Mono",
            "Menlo",
            "Monaco",
            "monospace",
        ]
        .into_iter()
        .map(str::to_string)
        .collect::<Vec<_>>()
    });
    let theme_search = use_state(String::new);
    let message = use_state(|| None::<String>);
    let mut loaded_for_start = loaded;
    let mut font_committed_for_load = font_committed;
    use_side_effect(move || {
        spawn(async move {
            let draft = blocking::unblock(load_draft).await;
            font_committed_for_load.set(draft.font_family.clone());
            signals.apply(draft);
            loaded_for_start.set(true);
        });
    });
    let mut font_families_for_load = font_families;
    use_side_effect(move || {
        spawn(async move {
            let families = blocking::unblock(alera_desktop_core::list_system_font_families).await;
            if !families.is_empty() {
                font_families_for_load.set(families);
            }
        });
    });
    let draft = signals.draft();
    let mut revision_for_persist = terminal_settings_revision;
    use_side_effect_with_deps(&(loaded(), draft.clone()), move |(loaded, draft)| {
        if !*loaded {
            return;
        }
        let draft = draft.clone();
        spawn(async move {
            if blocking::unblock(move || persist_draft(&draft))
                .await
                .is_ok()
            {
                let next = revision_for_persist.peek().saturating_add(1);
                revision_for_persist.set(next);
            }
        });
    });
    if !active {
        return rect().into_element();
    }

    rect()
        .width(Size::fill())
        .vertical()
        .spacing(22.)
        .child(settings_group_described(
            "Typography",
            "Default terminal typography for new sessions.",
            vec![
                settings_terminal_font::autocomplete_row(
                    signals.font_family,
                    open_menu,
                    just_opened,
                    font_highlight,
                    font_families,
                    font_committed,
                ),
                input_row(
                    "Font Size",
                    "Text size used in new terminal sessions.",
                    signals.font_size,
                    "px",
                ),
                input_row(
                    "Font Weight",
                    "Weight used for terminal text.",
                    signals.font_weight,
                    "",
                ),
                input_row(
                    "Line Height",
                    "Vertical spacing for terminal rows.",
                    signals.line_height,
                    "",
                ),
            ],
        ))
        .child(settings_group_described(
            "Cursor",
            "Default cursor appearance for terminal sessions.",
            vec![
                cursor_shape_row(signals.cursor_shape),
                toggle_row(
                    "Blinking Cursor",
                    "Blink the cursor while the terminal has focus.",
                    signals.cursor_blink,
                ),
                input_row(
                    "Cursor Opacity",
                    "Opacity of the terminal cursor.",
                    signals.cursor_opacity,
                    "",
                ),
            ],
        ))
        .child(settings_group_described(
            "Appearance",
            "Terminal colors, theme and spacing.",
            vec![
                settings_terminal_theme::picker(signals.theme_name, theme_search),
                input_row(
                    "Background Opacity",
                    "Opacity of the terminal background.",
                    signals.background_opacity,
                    "",
                ),
                input_row(
                    "Horizontal Padding",
                    "Horizontal spacing around the terminal grid.",
                    signals.padding_x,
                    "px",
                ),
                input_row(
                    "Vertical Padding",
                    "Vertical spacing around the terminal grid.",
                    signals.padding_y,
                    "px",
                ),
                settings_terminal_color::input_row(
                    "Foreground Color",
                    "Override the terminal text color.",
                    signals.foreground,
                    "#f5f5f5",
                ),
                settings_terminal_color::input_row(
                    "Background Color",
                    "Override the terminal background color.",
                    signals.background,
                    "#101010",
                ),
                settings_terminal_color::input_row(
                    "Cursor Color",
                    "Override the terminal cursor color.",
                    signals.cursor,
                    "#e0e0e0",
                ),
                settings_terminal_color::input_row(
                    "Selection Color",
                    "Override the terminal selection color.",
                    signals.selection,
                    "#3e4451",
                ),
            ],
        ))
        .child(settings_group_described(
            "Interaction",
            "Mouse, scrolling and clipboard behavior for TUIs.",
            vec![
                input_row(
                    "TUI Scroll Speed",
                    "Mouse reports sent per wheel step while a TUI owns scrolling.",
                    signals.tui_scroll,
                    "",
                ),
                toggle_row(
                    "Copy On Select",
                    "Copy local terminal selections to the system clipboard.",
                    signals.clipboard_on_select,
                ),
                toggle_row(
                    "Allow OSC 52 Clipboard Writes",
                    "Let terminal applications replace the system clipboard.",
                    signals.allow_osc52,
                ),
            ],
        ))
        .child(settings_group_described(
            "Advanced",
            "History, shell startup and double-click selection behavior.",
            vec![
                toggle_row(
                    "Use Login Shell",
                    "Start shells as login shells so profile files such as ~/.zprofile and ~/.profile are loaded.",
                    signals.login_shell,
                ),
                reload_row(bridge, message),
                input_row(
                    "Scrollback Lines",
                    "Maximum terminal history retained per session.",
                    signals.scrollback_lines,
                    "",
                ),
                input_row(
                    "Host Scrollback Size",
                    "Maximum host-side terminal output retained per session.",
                    signals.host_scrollback_mb,
                    "MB",
                ),
                input_row(
                    "Terminal Memory Budget",
                    "Ceiling for terminal scrollback held in the app. Over it, terminals you have not looked at recently are unloaded and restored when you return. Their agents keep running. Use 0 for no limit.",
                    signals.buffer_budget_mb,
                    "MB",
                ),
                text_input_row(
                    "Word Separators",
                    "Characters that break double-click word selection.",
                    signals.word_separators,
                ),
            ],
        ))
        .maybe_child(
            message
                .read()
                .clone()
                .map(|value| label().font_size(11.).color(MUTED).text(value)),
        )
        .into_element()
}

pub(super) fn terminal_row_shell(title: &'static str, description: &'static str) -> Rect {
    rect()
        .width(Size::fill())
        .min_height(Size::px(80.))
        .horizontal()
        .content(Content::Flex)
        .cross_align(Alignment::Center)
        .padding(Gaps::new_all(17.))
        .child(
            rect()
                .width(Size::flex(1.))
                .vertical()
                .spacing(3.)
                .child(label().font_size(14.).color(TEXT).text(title))
                .child(label().font_size(12.).color(MUTED).text(description)),
        )
        .child(rect().width(Size::px(16.)).child(""))
}

fn input_row(
    title: &'static str,
    description: &'static str,
    value: State<String>,
    suffix: &'static str,
) -> Element {
    let (min, max, step) = match title {
        "Font Size" => (8., 32., 1.),
        "Font Weight" => (100., 900., 100.),
        "Line Height" => (0.8, 2.4, 0.1),
        "Cursor Opacity" | "Background Opacity" => (0., 1., 0.05),
        "Horizontal Padding" | "Vertical Padding" => (0., 64., 1.),
        "TUI Scroll Speed" => (1., 10., 1.),
        "Scrollback Lines" => (100., 200_000., 100.),
        "Host Scrollback Size" => (1., 256., 1.),
        "Terminal Memory Budget" => (0., 4096., 64.),
        _ => (f64::MIN, f64::MAX, 1.),
    };
    terminal_row_shell(title, description)
        .child(
            rect()
                .width(Size::px(220.))
                .height(Size::px(40.))
                .horizontal()
                .content(Content::Flex)
                .cross_align(Alignment::Center)
                .spacing(8.)
                .child(
                    rect()
                        .width(Size::flex(1.))
                        .height(Size::px(40.))
                        .padding(Gaps::new(
                            0.,
                            if suffix.is_empty() { 0. } else { 28. },
                            0.,
                            0.,
                        ))
                        .background(SURFACE)
                        .border(Border::new().width(1.).fill(BORDER))
                        .corner_radius(5.)
                        .child(Input::new(value).width(Size::fill()).compact().flat())
                        .maybe_child((!suffix.is_empty()).then(|| {
                            rect()
                                .position(Position::new_absolute().top(12.).right(9.))
                                .child(label().font_size(11.).color(MUTED).text(suffix))
                        })),
                )
                .child(
                    rect()
                        .width(Size::px(26.))
                        .height(Size::px(36.))
                        .vertical()
                        .content(Content::Flex)
                        .child(stepper_button(value, step, min, max, true))
                        .child(stepper_button(value, -step, min, max, false)),
                ),
        )
        .into_element()
}

fn text_input_row(title: &'static str, description: &'static str, value: State<String>) -> Element {
    terminal_row_shell(title, description)
        .child(
            rect()
                .width(Size::px(220.))
                .height(Size::px(40.))
                .background(SURFACE)
                .border(Border::new().width(1.).fill(BORDER))
                .corner_radius(5.)
                .child(Input::new(value).width(Size::fill()).compact().flat()),
        )
        .into_element()
}

fn stepper_button(mut value: State<String>, delta: f64, min: f64, max: f64, top: bool) -> Element {
    rect()
        .width(Size::fill())
        .height(Size::flex(1.))
        .center()
        .border(Border::new().width(1.).fill(BORDER))
        .corner_radius(4.)
        .a11y_role(AccessibilityRole::Button)
        .a11y_alt(if top { "Increment" } else { "Decrement" })
        .on_pointer_enter(|_| Cursor::set(CursorIcon::Pointer))
        .on_pointer_leave(|_| Cursor::set(CursorIcon::default()))
        .on_pointer_down(move |event: Event<PointerEventData>| {
            event.stop_propagation();
            let current = value.read().trim().parse::<f64>().unwrap_or(min);
            value.set(compact_number((current + delta).clamp(min, max)));
        })
        .child(
            SvgViewer::new(if top {
                icons::lucide::chevron_up()
            } else {
                icons::lucide::chevron_down()
            })
            .width(Size::px(13.))
            .height(Size::px(13.))
            .color(MUTED),
        )
        .into_element()
}

fn toggle_row(title: &'static str, description: &'static str, value: State<bool>) -> Element {
    let mut value_for_click = value;
    terminal_row_shell(title, description)
        .child(settings_switch::control(value(), true, move |event| {
            event.stop_propagation();
            value_for_click.toggle();
        }))
        .into_element()
}

fn cursor_shape_row(value: State<String>) -> Element {
    let mut group = rect()
        .width(Size::px(220.))
        .height(Size::px(34.))
        .horizontal()
        .content(Content::Flex)
        .border(Border::new().width(1.).fill(BORDER))
        .corner_radius(5.);
    for (shape, width, height) in [("block", 8., 12.), ("bar", 2., 12.), ("underline", 10., 2.)] {
        let selected = value.read().as_str() == shape;
        let mut value = value;
        group = group.child(
            rect()
                .width(Size::flex(1.))
                .height(Size::fill())
                .center()
                .background(if selected { (52, 52, 52) } else { SURFACE })
                .a11y_role(AccessibilityRole::Button)
                .a11y_alt(shape)
                .on_pointer_enter(|_| Cursor::set(CursorIcon::Pointer))
                .on_pointer_leave(|_| Cursor::set(CursorIcon::default()))
                .on_pointer_down(move |event: Event<PointerEventData>| {
                    event.stop_propagation();
                    value.set(shape.to_string());
                })
                .child(
                    rect()
                        .width(Size::px(width))
                        .height(Size::px(height))
                        .background(TEXT),
                ),
        );
    }
    terminal_row_shell("Cursor Shape", "Cursor style for new terminal sessions.")
        .child(group)
        .into_element()
}

fn reload_row(bridge: RuntimeBridge, message: State<Option<String>>) -> Element {
    let mut message_for_action = message;
    terminal_row_shell(
        "Reload Shell Environment",
        "Re-read the login shell PATH so tools installed since the runtime started resolve in new terminals.",
    )
    .child(
        Button::new()
            .width(Size::px(68.))
            .height(Size::px(36.))
            .compact()
            .outline()
            .on_press(move |_| {
                let bridge = bridge.clone();
                spawn(async move {
                    let result = bridge.request("shellEnvironment.reload", json!({})).await;
                    message_for_action.set(Some(if result.is_ok() {
                        "Shell Environment Reloaded".to_string()
                    } else {
                        "Could Not Reload Shell Environment".to_string()
                    }));
                });
            })
            .child("Reload"),
    )
    .into_element()
}
