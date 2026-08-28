fn editor_pane(
    search_input: &Entity<InputState>,
    inputs: &SettingsInputs,
    settings: &SettingsState,
    cx: &mut Context<AleraApp>,
) -> AnyElement {
    let query = search_input.read(cx).value().trim().to_lowercase();
    let themes = [
        "Alera",
        "GitHub Dark",
        "GitHub Dark Dimmed",
        "VS2015",
        "Atom One Dark",
        "Night Owl",
        "Nord",
        "Monokai",
        "Tokyo Night Dark",
        "Dracula",
    ];
    let filtered = themes
        .into_iter()
        .filter(|name| query.is_empty() || name.to_lowercase().contains(&query))
        .collect::<Vec<_>>();
    div()
        .child(exact_settings_group(
            "Appearance",
            "Syntax highlighting defaults for editor tabs.",
            vec![div()
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
                        .child("Search and select a syntax highlighting theme."),
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
                                .child(design_system::search_field(search_input, false))
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
                                                    settings.editor_theme
                                                ))
                                                .child(div().flex_1())
                                                .child(format!(
                                                    "Showing {} of {}",
                                                    filtered.len(),
                                                    themes.len()
                                                )),
                                        )
                                        .child(
                                            div()
                                                .max_h(px(220.0))
                                                .overflow_y_scrollbar()
                                                .py_1()
                                                .when(filtered.is_empty(), |list| {
                                                    list.child(
                                                        div()
                                                            .p_3()
                                                            .text_size(px(12.0))
                                                            .text_color(theme::text_muted())
                                                            .child("No themes found."),
                                                    )
                                                })
                                                .children(filtered.iter().enumerate().map(
                                                    |(index, name)| {
                                                        let selected =
                                                            *name == settings.editor_theme;
                                                        let name_for_click = (*name).to_string();
                                                        div()
                                                            .id(("editor-theme", index))
                                                            .focusable()
                                                            .tab_stop(true)
                                                            .role(Role::RadioButton)
                                                            .aria_label(*name)
                                                            .aria_selected(selected)
                                                            .aria_toggled(if selected {
                                                                Toggled::True
                                                            } else {
                                                                Toggled::False
                                                            })
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
                                                                cx.listener(
                                                                move |this, _, _, cx| {
                                                                    this.set_editor_theme(
                                                                        name_for_click.clone(),
                                                                        cx,
                                                                    );
                                                                    cx.stop_propagation();
                                                                },
                                                            ))
                                                            .child(theme_color_dots(name))
                                                            .child(*name)
                                                    },
                                                )),
                                        ),
                                ),
                        )
                        .child(editor_theme_preview(&settings.editor_theme)),
                )],
        ))
        .child(div().mt_4().child(exact_settings_group(
            "Indentation",
            "Defaults used by editor tabs.",
            vec![exact_settings_row(
                "Tab Size",
                "Spaces inserted when pressing Tab.",
                number_input_control(
                    "editor-tab-size",
                    "Tab Size",
                    settings_input(inputs, "editor-tab-size"),
                    "spaces",
                    1.0,
                    1.0,
                    8.0,
                    cx,
                ),
            )],
        )))
        .into_any_element()
}
