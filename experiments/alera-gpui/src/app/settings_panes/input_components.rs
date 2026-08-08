
fn terminal_color_row(
    title: &'static str,
    fallback: &'static str,
    input: &Entity<InputState>,
) -> gpui::Div {
    let color = match fallback {
        "#f5f5f5" => rgb(0xf5f5f5),
        "#101010" => rgb(0x101010),
        "#e0e0e0" => rgb(0xe0e0e0),
        _ => rgb(0x3e4451),
    };
    exact_settings_row(
        title,
        "Override The Terminal Color. Leave Empty To Use The Theme.",
        div().w(px(220.0)).h(px(48.0)).child(
            design_system::text_field(input)
                .height(px(48.0))
                .prefix(div().w(px(18.0)).h(px(18.0)).rounded_sm().bg(color)),
        ),
    )
}


fn instruction_row(title: &'static str, input: &Entity<InputState>) -> gpui::Div {
    exact_settings_row(
        title,
        "Extra guidance appended to this generation prompt.",
        settings_text_input(input, 320.0, 76.0),
    )
}

#[derive(Clone, Copy)]
struct EditorThemePalette {
    background: u32,
    foreground: u32,
    keyword: u32,
    string: u32,
    title: u32,
    variable: u32,
    comment: u32,
}

fn editor_theme_palette(name: &str) -> EditorThemePalette {
    match name {
        "GitHub Dark" => EditorThemePalette {
            background: 0x0d1117,
            foreground: 0xc9d1d9,
            keyword: 0xff7b72,
            string: 0xa5d6ff,
            title: 0xd2a8ff,
            variable: 0x79c0ff,
            comment: 0x8b949e,
        },
        "GitHub Dark Dimmed" => EditorThemePalette {
            background: 0x22272e,
            foreground: 0xadbac7,
            keyword: 0xf47067,
            string: 0x96d0ff,
            title: 0xdcbdfb,
            variable: 0x6cb6ff,
            comment: 0x768390,
        },
        "VS2015" => EditorThemePalette {
            background: 0x1e1e1e,
            foreground: 0xdcdcdc,
            keyword: 0x569cd6,
            string: 0xd69d85,
            title: 0xdcdcdc,
            variable: 0xdcdcdc,
            comment: 0x57a64a,
        },
        "Atom One Dark" => EditorThemePalette {
            background: 0x282c34,
            foreground: 0xabb2bf,
            keyword: 0xc678dd,
            string: 0x98c379,
            title: 0x61afef,
            variable: 0xd19a66,
            comment: 0x5c6370,
        },
        "Night Owl" => EditorThemePalette {
            background: 0x011627,
            foreground: 0xd6deeb,
            keyword: 0xc792ea,
            string: 0xecc48d,
            title: 0xdcdcaa,
            variable: 0x7fdbca,
            comment: 0x637777,
        },
        "Nord" => EditorThemePalette {
            background: 0x2e3440,
            foreground: 0xd8dee9,
            keyword: 0x81a1c1,
            string: 0xa3be8c,
            title: 0x8fbcbb,
            variable: 0xd8dee9,
            comment: 0x616e88,
        },
        "Monokai" => EditorThemePalette {
            background: 0x272822,
            foreground: 0xdddddd,
            keyword: 0xf92672,
            string: 0xa6e22e,
            title: 0xa6e22e,
            variable: 0xa6e22e,
            comment: 0x75715e,
        },
        "Tokyo Night Dark" => EditorThemePalette {
            background: 0x1a1b26,
            foreground: 0xc0caf5,
            keyword: 0xbb9af7,
            string: 0x9ece6a,
            title: 0x7dcfff,
            variable: 0xff9e64,
            comment: 0x565f89,
        },
        "Dracula" => EditorThemePalette {
            background: 0x282936,
            foreground: 0xe9e9f4,
            keyword: 0xa1efe4,
            string: 0xebff87,
            title: 0x00f769,
            variable: 0xea51b2,
            comment: 0x626483,
        },
        _ => EditorThemePalette {
            background: 0x101010,
            foreground: 0xf5f5f5,
            keyword: 0xc792ea,
            string: 0x22c55e,
            title: 0x82aaff,
            variable: 0xffcc80,
            comment: 0x606060,
        },
    }
}

fn theme_color_dots(name: &str) -> gpui::Div {
    let palette = editor_theme_palette(name);
    div()
        .flex()
        .items_center()
        .gap(px(1.0))
        .w(px(18.0))
        .h(px(12.0))
        .child(
            div()
                .w(px(3.0))
                .h(px(10.0))
                .rounded_full()
                .bg(rgb(palette.keyword)),
        )
        .child(
            div()
                .w(px(3.0))
                .h(px(10.0))
                .rounded_full()
                .bg(rgb(palette.string)),
        )
        .child(
            div()
                .w(px(3.0))
                .h(px(10.0))
                .rounded_full()
                .bg(rgb(palette.title)),
        )
}

fn editor_theme_preview(name: &str) -> gpui::Div {
    let palette = editor_theme_palette(name);
    div()
        .w(px(280.0))
        .rounded_md()
        .border_1()
        .border_color(theme::border())
        .bg(rgb(palette.background))
        .p_3()
        .font_family("JetBrains Mono")
        .text_size(px(12.0))
        .text_color(rgb(palette.foreground))
        .child(
            div()
                .flex()
                .items_center()
                .gap_2()
                .text_color(rgb(palette.foreground))
                .child(
                    div()
                        .w(px(6.0))
                        .h(px(6.0))
                        .rounded_full()
                        .bg(rgb(palette.string)),
                )
                .child(name.to_string()),
        )
        .child(
            div()
                .flex()
                .mt_3()
                .child(div().text_color(rgb(palette.keyword)).child("class "))
                .child(
                    div()
                        .text_color(rgb(palette.title))
                        .child("ThemePreview"),
                )
                .child(div().child(" {")),
        )
        .child(
            div()
                .flex()
                .pl_3()
                .child(div().text_color(rgb(palette.keyword)).child("final "))
                .child(div().text_color(rgb(palette.variable)).child("name"))
                .child(div().child(" = "))
                .child(div().text_color(rgb(palette.string)).child("'Alera'"))
                .child(div().child(";")),
        )
        .child(
            div()
                .pl_3()
                .text_color(rgb(palette.comment))
                .child("// Syntax colors"),
        )
        .child(div().child("}"))
}

fn settings_input<'a>(inputs: &'a SettingsInputs, key: &str) -> &'a Entity<InputState> {
    inputs.get(key).expect("settings input should exist")
}

fn settings_text_input(input: &Entity<InputState>, width: f32, height: f32) -> gpui::Div {
    div()
        .w(px(width))
        .h(px(height))
        .child(design_system::text_field(input).height(px(height)))
}

fn number_input_control(
    key: &'static str,
    input: &Entity<InputState>,
    suffix: &'static str,
    step: f64,
    min: f64,
    max: f64,
    cx: &mut Context<AleraApp>,
) -> gpui::Div {
    let decrement_input = input.clone();
    let increment_input = input.clone();
    let suffix = (!suffix.is_empty()).then(|| {
        div()
            .pr_2()
            .text_size(px(11.0))
            .text_color(theme::text_muted())
            .child(suffix)
    });
    div()
        .flex()
        .items_center()
        .w(px(220.0))
        .h(px(48.0))
        .gap_2()
        .child(
            div()
                .flex_1()
                .h_full()
                .child(
                    design_system::text_field(input)
                        .height(px(48.0))
                        .when_some(suffix, |field, suffix| field.suffix(suffix)),
                ),
        )
        .child(
            div()
                .flex()
                .flex_col()
                .w(px(26.0))
                .h(px(36.0))
                .child(
                    div()
                        .id((key, 0usize))
                        .flex()
                        .items_center()
                        .justify_center()
                        .flex_1()
                        .border_1()
                        .border_color(theme::border_subtle())
                        .cursor(CursorStyle::PointingHand)
                        .hover(|style| style.bg(theme::surface_raised()))
                        .on_mouse_down(
                            MouseButton::Left,
                            cx.listener(move |this, _: &MouseDownEvent, window, cx| {
                                adjust_settings_number(
                                    this,
                                    key,
                                    &increment_input,
                                    step,
                                    min,
                                    max,
                                    window,
                                    cx,
                                );
                                cx.stop_propagation();
                            }),
                        )
                        .child(icon(AleraIcon::ChevronUp, 14.0, theme::text_muted())),
                )
                .child(
                    div()
                        .id((key, 1usize))
                        .flex()
                        .items_center()
                        .justify_center()
                        .flex_1()
                        .border_1()
                        .border_color(theme::border_subtle())
                        .cursor(CursorStyle::PointingHand)
                        .hover(|style| style.bg(theme::surface_raised()))
                        .on_mouse_down(
                            MouseButton::Left,
                            cx.listener(move |this, _: &MouseDownEvent, window, cx| {
                                adjust_settings_number(
                                    this,
                                    key,
                                    &decrement_input,
                                    -step,
                                    min,
                                    max,
                                    window,
                                    cx,
                                );
                                cx.stop_propagation();
                            }),
                        )
                        .child(icon(AleraIcon::ChevronDown, 14.0, theme::text_muted())),
                ),
        )
}

#[allow(clippy::too_many_arguments)]
fn adjust_settings_number(
    app: &mut AleraApp,
    key: &'static str,
    input: &Entity<InputState>,
    delta: f64,
    min: f64,
    max: f64,
    window: &mut gpui::Window,
    cx: &mut Context<AleraApp>,
) {
    let current = input.read(cx).value().trim().parse::<f64>().unwrap_or(min);
    let next = (current + delta).clamp(min, max);
    let formatted = format_settings_number(next);
    input.update(cx, |input, cx| {
        input.set_value(formatted.clone(), window, cx);
    });
    app.apply_settings_input(key, formatted, true, cx);
}

fn format_settings_number(value: f64) -> String {
    if value.fract().abs() < f64::EPSILON {
        format!("{value:.0}")
    } else {
        format!("{value:.2}")
            .trim_end_matches('0')
            .trim_end_matches('.')
            .to_string()
    }
}
