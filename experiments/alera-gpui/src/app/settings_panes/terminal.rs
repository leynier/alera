fn terminal_pane(
    settings: &SettingsState,
    inputs: &SettingsInputs,
    font_select: &SettingsSelect,
    theme_search_input: &Entity<InputState>,
    anchors: &SettingsGroupAnchors,
    cx: &mut Context<AleraApp>,
) -> AnyElement {
    div()
        .child(
            exact_settings_group(
                "Typography",
                "Default terminal typography for new sessions.",
                vec![
                exact_settings_row(
                    "Font Family",
                    "Typeface used in new terminal sessions.",
                    settings_font_select_control(font_select, cx),
                ),
                exact_settings_row(
                    "Font Size",
                    "Text size used in new terminal sessions.",
                    number_input_control(
                        "terminal-font-size",
                        "Font Size",
                        settings_input(inputs, "terminal-font-size"),
                        "px",
                        1.0,
                        8.0,
                        32.0,
                        cx,
                    ),
                ),
                exact_settings_row(
                    "Font Weight",
                    "Weight used for terminal text.",
                    number_input_control(
                        "terminal-font-weight",
                        "Font Weight",
                        settings_input(inputs, "terminal-font-weight"),
                        "",
                        100.0,
                        100.0,
                        900.0,
                        cx,
                    ),
                ),
                exact_settings_row(
                    "Line Height",
                    "Vertical spacing for terminal rows.",
                    number_input_control(
                        "terminal-line-height",
                        "Line Height",
                        settings_input(inputs, "terminal-line-height"),
                        "",
                        0.1,
                        0.8,
                        2.4,
                        cx,
                    ),
                ),
                ],
            )
            .id(("settings-group-anchor", 0usize))
            .anchor_scroll(settings_group_anchor(
                anchors,
                SettingsPane::Terminal,
                0,
            )),
        )
        .child(
            div().mt_4().child(
                exact_settings_group(
                    "Cursor",
                    "Default cursor appearance for terminal sessions.",
                    vec![
                exact_settings_row(
                    "Cursor Shape",
                    "Cursor style for new terminal sessions.",
                    terminal_cursor_shape_control(settings, cx),
                ),
                exact_settings_row(
                    "Blinking Cursor",
                    "Blink the cursor while the terminal has focus.",
                    settings_switch(
                        "terminal-cursor-blink",
                        "Blinking Cursor",
                        settings.terminal_cursor_blink,
                    )
                        .on_click(
                            cx.listener(|this, _, _, cx| {
                                this.update_terminal_settings(
                                    |settings| {
                                        settings.terminal_cursor_blink =
                                            !settings.terminal_cursor_blink;
                                    },
                                    cx,
                                );
                                cx.stop_propagation();
                            }),
                        ),
                ),
                exact_settings_row(
                    "Cursor Opacity",
                    "Opacity of the terminal cursor.",
                    number_input_control(
                        "terminal-cursor-opacity",
                        "Cursor Opacity",
                        settings_input(inputs, "terminal-cursor-opacity"),
                        "",
                        0.05,
                        0.0,
                        1.0,
                        cx,
                    ),
                ),
                    ],
                )
                .id(("settings-group-anchor", 1usize))
                .anchor_scroll(settings_group_anchor(
                    anchors,
                    SettingsPane::Terminal,
                    1,
                )),
            ),
        )
        .child(
            div().mt_4().child(
                exact_settings_group(
                    "Appearance",
                    "Terminal colors, theme and spacing.",
                    vec![
                terminal_theme_picker(theme_search_input, settings, cx),
                exact_settings_row(
                    "Background Opacity",
                    "Opacity of the terminal background.",
                    number_input_control(
                        "terminal-background-opacity",
                        "Background Opacity",
                        settings_input(inputs, "terminal-background-opacity"),
                        "",
                        0.05,
                        0.0,
                        1.0,
                        cx,
                    ),
                ),
                exact_settings_row(
                    "Horizontal Padding",
                    "Horizontal spacing around the terminal grid.",
                    number_input_control(
                        "terminal-padding-x",
                        "Horizontal Padding",
                        settings_input(inputs, "terminal-padding-x"),
                        "px",
                        1.0,
                        0.0,
                        64.0,
                        cx,
                    ),
                ),
                exact_settings_row(
                    "Vertical Padding",
                    "Vertical spacing around the terminal grid.",
                    number_input_control(
                        "terminal-padding-y",
                        "Vertical Padding",
                        settings_input(inputs, "terminal-padding-y"),
                        "px",
                        1.0,
                        0.0,
                        64.0,
                        cx,
                    ),
                ),
                terminal_color_row(
                    "Foreground Color",
                    "Override the terminal text color.",
                    "#f5f5f5",
                    settings_input(inputs, "terminal-color-foreground"),
                ),
                terminal_color_row(
                    "Background Color",
                    "Override the terminal background color.",
                    "#101010",
                    settings_input(inputs, "terminal-color-background"),
                ),
                terminal_color_row(
                    "Cursor Color",
                    "Override the terminal cursor color.",
                    "#e0e0e0",
                    settings_input(inputs, "terminal-color-cursor"),
                ),
                terminal_color_row(
                    "Selection Color",
                    "Override the terminal selection color.",
                    "#3e4451",
                    settings_input(inputs, "terminal-color-selection"),
                ),
                    ],
                )
                .id(("settings-group-anchor", 2usize))
                .anchor_scroll(settings_group_anchor(
                    anchors,
                    SettingsPane::Terminal,
                    2,
                )),
            ),
        )
        .child(
            div().mt_4().child(
                exact_settings_group(
                    "Interaction",
                    "Mouse, scrolling and clipboard behavior for TUIs.",
                    vec![
                exact_settings_row(
                    "TUI Scroll Speed",
                    "Mouse reports sent per wheel step while a TUI owns scrolling.",
                    number_input_control(
                        "terminal-tui-scroll",
                        "TUI Scroll Speed",
                        settings_input(inputs, "terminal-tui-scroll"),
                        "",
                        1.0,
                        1.0,
                        10.0,
                        cx,
                    ),
                ),
                exact_settings_row(
                    "Copy On Select",
                    "Copy local terminal selections to the system clipboard.",
                    settings_switch(
                        "terminal-copy-on-select",
                        "Copy On Select",
                        settings.terminal_clipboard_on_select,
                    )
                    .on_click(
                        cx.listener(|this, _, _, cx| {
                            this.update_terminal_settings(
                                |settings| {
                                    settings.terminal_clipboard_on_select =
                                        !settings.terminal_clipboard_on_select;
                                },
                                cx,
                            );
                            cx.stop_propagation();
                        }),
                    ),
                ),
                exact_settings_row(
                    "Allow OSC 52 Clipboard Writes",
                    "Let terminal applications replace the system clipboard.",
                    settings_switch(
                        "terminal-osc52",
                        "Allow OSC 52 Clipboard Writes",
                        settings.terminal_allow_osc52_clipboard,
                    )
                    .on_click(
                        cx.listener(|this, _, _, cx| {
                            this.update_terminal_settings(
                                |settings| {
                                    settings.terminal_allow_osc52_clipboard =
                                        !settings.terminal_allow_osc52_clipboard;
                                },
                                cx,
                            );
                            cx.stop_propagation();
                        }),
                    ),
                ),
                exact_settings_row(
                    "Show Terminal Composer By Default",
                    "Open the prompt composer when a new terminal session starts.",
                    settings_switch(
                        "terminal-show-composer",
                        "Show Terminal Composer By Default",
                        settings.terminal_show_composer_by_default,
                    )
                    .on_click(cx.listener(|this, _, _, cx| {
                        this.update_terminal_settings(
                            |settings| {
                                settings.terminal_show_composer_by_default =
                                    !settings.terminal_show_composer_by_default;
                            },
                            cx,
                        );
                        cx.stop_propagation();
                    })),
                ),
                    ],
                )
                .id(("settings-group-anchor", 3usize))
                .anchor_scroll(settings_group_anchor(
                    anchors,
                    SettingsPane::Terminal,
                    3,
                )),
            ),
        )
        .child(
            div().mt_4().child(
                exact_settings_group(
                    "Advanced",
                    "History, shell startup and double-click selection behavior.",
                    vec![
                exact_settings_row(
                    "Use Login Shell",
                    "Start shells as login shells so profile files such as ~/.zprofile and ~/.profile are loaded.",
                    settings_switch(
                        "terminal-login-shell",
                        "Use Login Shell",
                        settings.terminal_login_shell,
                    )
                        .on_click(
                            cx.listener(|this, _, _, cx| {
                                this.update_terminal_settings(
                                    |settings| {
                                        settings.terminal_login_shell =
                                            !settings.terminal_login_shell;
                                    },
                                    cx,
                                );
                                cx.stop_propagation();
                            }),
                        ),
                ),
                exact_settings_row(
                    "Reload Shell Environment",
                    "Re-read the login shell PATH so tools installed since the runtime started resolve in new terminals.",
                    settings_button("terminal-reload-shell", "Reload").on_click(
                        cx.listener(|this, _, _, cx| {
                            this.reload_shell_environment(cx);
                            cx.stop_propagation();
                        }),
                    ),
                ),
                exact_settings_row(
                    "Scrollback Lines",
                    "Maximum terminal history retained per session.",
                    number_input_control(
                        "terminal-scrollback-lines",
                        "Scrollback Lines",
                        settings_input(inputs, "terminal-scrollback-lines"),
                        "",
                        100.0,
                        100.0,
                        200_000.0,
                        cx,
                    ),
                ),
                exact_settings_row(
                    "Host Scrollback Size",
                    "Maximum host-side terminal output retained per session.",
                    number_input_control(
                        "terminal-host-scrollback-mb",
                        "Host Scrollback Size",
                        settings_input(inputs, "terminal-host-scrollback-mb"),
                        "MB",
                        1.0,
                        1.0,
                        256.0,
                        cx,
                    ),
                ),
                exact_settings_row(
                    "Terminal Memory Budget",
                    "Ceiling for terminal scrollback held in the app. Over it, terminals you have not looked at recently are unloaded and restored when you return. Their agents keep running. Use 0 for no limit.",
                    number_input_control(
                        "terminal-buffer-budget-mb",
                        "Terminal Memory Budget",
                        settings_input(inputs, "terminal-buffer-budget-mb"),
                        "MB",
                        64.0,
                        0.0,
                        4096.0,
                        cx,
                    ),
                ),
                exact_settings_row(
                    "Word Separators",
                    "Characters that break double-click word selection.",
                    settings_text_input(
                        "Word Separators",
                        settings_input(inputs, "terminal-word-separators"),
                        220.0,
                        48.0,
                    ),
                ),
                    ],
                )
                .id(("settings-group-anchor", 4usize))
                .anchor_scroll(settings_group_anchor(
                    anchors,
                    SettingsPane::Terminal,
                    4,
                )),
            ),
        )
        .into_any_element()
}

fn terminal_theme_picker(
    search_input: &Entity<InputState>,
    settings: &SettingsState,
    cx: &mut Context<AleraApp>,
) -> gpui::Div {
    let query = search_input.read(cx).value().trim().to_lowercase();
    let themes = TERMINAL_THEME_NAMES
        .into_iter()
        .filter(|name| query.is_empty() || name.to_lowercase().contains(&query))
        .collect::<Vec<_>>();
    div()
        .p_4()
        .child(
            div()
                .text_size(px(13.0))
                .font_weight(gpui::FontWeight::MEDIUM)
                .child("Theme Preset"),
        )
        .child(
            div()
                .mt_1()
                .text_size(px(12.0))
                .text_color(theme::text_muted())
                .child("Search and select a built-in terminal color theme."),
        )
        .child(
            div()
                .flex()
                .items_start()
                .gap_4()
                .mt_3()
                .child(
                    div()
                        .flex()
                        .flex_col()
                        .flex_1()
                        .child(
                            design_system::search_field(search_input, false)
                                .aria_label("Search Built-In Themes"),
                        )
                        .child(
                            div()
                                .mt_2()
                                .overflow_hidden()
                                .rounded_md()
                                .border_1()
                                .border_color(theme::border_subtle())
                                .bg(theme::surface())
                                .child(
                                    div()
                                        .flex()
                                        .items_center()
                                        .h(px(34.0))
                                        .px_3()
                                        .border_b_1()
                                        .border_color(theme::border_subtle())
                                        .text_size(px(12.0))
                                        .text_color(theme::text_muted())
                                        .child(format!(
                                            "Selected: {}",
                                            settings.terminal_theme_name
                                        ))
                                        .child(div().flex_1())
                                        .child(format!(
                                            "Showing {} of {}",
                                            themes.len(),
                                            TERMINAL_THEME_NAMES.len()
                                        )),
                                )
                                .child(
                                    div()
                                        .max_h(px(220.0))
                                        .overflow_y_scrollbar()
                                        .py_1()
                                        .when(themes.is_empty(), |list| {
                                            list.child(
                                                div()
                                                    .h(px(52.0))
                                                    .flex()
                                                    .items_center()
                                                    .justify_center()
                                                    .text_color(theme::text_muted())
                                                    .child("No themes found."),
                                            )
                                        })
                                        .children(themes.iter().enumerate().map(|(index, name)| {
                                            let selected = *name == settings.terminal_theme_name;
                                            let name_for_click = (*name).to_string();
                                            div()
                                                .id(("terminal-theme", index))
                                                .focusable()
                                                .tab_stop(true)
                                                .role(Role::ListBoxOption)
                                                .aria_label(*name)
                                                .aria_selected(selected)
                                                .flex()
                                                .items_center()
                                                .h(px(28.0))
                                                .px_2()
                                                .gap_2()
                                                .cursor(CursorStyle::PointingHand)
                                                .when(selected, |row| {
                                                    row.bg(theme::surface_raised())
                                                })
                                                .hover(|style| {
                                                    style.bg(theme::surface_selected())
                                                })
                                                .on_click(
                                                    cx.listener(move |this, _, _, cx| {
                                                        this.set_terminal_theme(
                                                            name_for_click.clone(),
                                                            cx,
                                                        );
                                                        cx.stop_propagation();
                                                    }),
                                                )
                                                .child(terminal_theme_color_dots(name))
                                                .child(*name)
                                        })),
                                ),
                        ),
                )
                .child(terminal_theme_preview(&settings.terminal_theme_name)),
        )
}

fn terminal_theme_color_dots(name: &str) -> gpui::Div {
    let palette = terminal_theme_palette(name);
    div()
        .flex()
        .items_center()
        .gap(px(1.0))
        .w(px(18.0))
        .h(px(12.0))
        .children(
            [palette.normal[1], palette.normal[2], palette.normal[4]]
                .into_iter()
                .map(|color| {
                    div()
                        .w(px(3.0))
                        .h(px(10.0))
                        .rounded_full()
                        .bg(rgb(color))
                }),
        )
}

fn terminal_theme_preview(name: &str) -> gpui::Div {
    let palette = terminal_theme_palette(name);
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
                .child(
                    div()
                        .w(px(8.0))
                        .h(px(8.0))
                        .rounded_full()
                        .bg(rgb(palette.normal[2])),
                )
                .child(name.to_string()),
        )
        .child(div().mt_3().child("$ git status --short"))
        .child(
            div()
                .mt_1()
                .text_color(rgb(palette.normal[1]))
                .child("M  lib/src/features/settings/presentation/settings_dialog.dart"),
        )
        .child(
            div()
                .text_color(rgb(palette.normal[2]))
                .child("A  lib/src/features/settings/domain/terminal_theme_catalog.dart"),
        )
        .child(
            div()
                .mt_2()
                .px(px(2.0))
                .bg(rgb(palette.selection))
                .child("theme preview selected text"),
        )
        .child(
            div()
                .flex()
                .items_center()
                .mt_2()
                .child("$ echo \"cursor\" ")
                .child(div().w(px(7.0)).h(px(16.0)).bg(rgb(palette.cursor))),
        )
}

fn terminal_cursor_shape_control(
    settings: &SettingsState,
    cx: &mut Context<AleraApp>,
) -> gpui::Div {
    div()
        .flex()
        .h(px(34.0))
        .w(px(170.0))
        .rounded_lg()
        .border_1()
        .border_color(theme::border())
        .overflow_hidden()
        .children(
            [
                ("block", "▮", "Block"),
                ("bar", "│", "Bar"),
                ("underline", "_", "Underline"),
            ]
            .into_iter()
            .map(|(shape, glyph, tooltip)| {
                let selected = settings.terminal_cursor_shape == shape;
                div()
                    .id(SharedString::from(format!("terminal-cursor-{shape}")))
                    .focusable()
                    .tab_stop(true)
                    .role(Role::RadioButton)
                    .aria_label(tooltip)
                    .aria_selected(selected)
                    .flex()
                    .flex_1()
                    .items_center()
                    .justify_center()
                    .border_l_1()
                    .border_color(theme::border_subtle())
                    .cursor(CursorStyle::PointingHand)
                    .text_size(px(14.0))
                    .text_color(if selected {
                        theme::text()
                    } else {
                        theme::text_muted()
                    })
                    .when(selected, |item| item.bg(theme::surface_raised()))
                    .hover(|style| style.bg(theme::surface_raised()))
                    .tooltip(move |_, cx| cx.new(|_| Tooltip::new(tooltip)).into())
                    .child(glyph)
                    .on_click(
                        cx.listener(move |this, _, _, cx| {
                            this.update_terminal_settings(
                                |settings| settings.terminal_cursor_shape = shape.to_string(),
                                cx,
                            );
                            cx.stop_propagation();
                        }),
                    )
            }),
        )
}
