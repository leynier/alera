fn application_workspace_panel(
    input: &Entity<InputState>,
    cx: &mut Context<AleraApp>,
) -> gpui::Div {
    settings_panel(vec![
        div()
            .px_4()
            .py(px(16.0))
            .child(
                div()
                    .text_size(px(13.0))
                    .font_weight(gpui::FontWeight::MEDIUM)
                    .child("Workspace Directory"),
            )
            .child(
                div()
                    .mt_1()
                    .text_size(px(12.0))
                    .text_color(theme::text_muted())
                    .child(
                        "Where new linked workspaces are created on disk. Existing workspaces are not moved. Leave empty to use the default (~/.alera/workspaces).",
                    ),
            )
            .child(
                div()
                    .flex()
                    .items_center()
                    .gap_2()
                    .mt_3()
                    // The directory row is the compact Flutter workspace
                    // control. Keep its field at the same 40 px rhythm as
                    // the adjacent Browse button without changing the
                    // regular text-field height used by other settings.
                    .child(
                        div()
                            .flex_1()
                            .child(design_system::text_field(input).height(px(40.0))),
                    )
                    .child(
                        div()
                            .id("browse-workspace-directory")
                            .focusable()
                            .tab_stop(true)
                            .role(Role::Button)
                            .aria_label("Browse Workspace Directory")
                            .flex()
                            .items_center()
                            .justify_center()
                            .h(px(34.0))
                            .px_3()
                            .gap_2()
                            .rounded_lg()
                            .border_1()
                            .border_color(theme::border())
                            .cursor(CursorStyle::PointingHand)
                            .hover(|style| style.bg(theme::surface_raised()))
                            .on_click(
                                cx.listener(|this, _, window, cx| {
                                    this.browse_workspace_directory(window, cx);
                                    cx.stop_propagation();
                                }),
                            )
                            .child(icon(AleraIcon::FolderOpen, 16.0, theme::text_muted()))
                            .child("Browse"),
                    ),
            ),
    ])
}

fn exact_settings_group(
    title: &'static str,
    description: &'static str,
    rows: Vec<gpui::Div>,
) -> gpui::Div {
    div()
        .child(
            div()
                .ml_1()
                .mb_4()
                .child(
                    div()
                        .text_size(px(13.0))
                        .font_weight(gpui::FontWeight::SEMIBOLD)
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
        .child(settings_panel(rows))
}

fn agent_settings_group(
    title: &'static str,
    description: &'static str,
    rows: Vec<gpui::Div>,
) -> gpui::Div {
    // Flutter's Agents pane uses the regular SettingsGroup header inset. The
    // wider GPUI settings groups keep an extra 8 px bottom margin for other
    // panes, which made this first card start visibly too low.
    div()
        .child(
            div()
                .ml_1()
                .mb(px(10.0))
                .child(
                    div()
                        .text_size(px(13.0))
                        .font_weight(gpui::FontWeight::SEMIBOLD)
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
        .child(settings_panel(rows))
}

fn settings_title_only_group(title: &'static str, rows: Vec<gpui::Div>) -> gpui::Div {
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
                ),
        )
        .child(settings_panel(rows))
}

fn settings_group_anchor(
    anchors: &SettingsGroupAnchors,
    pane: SettingsPane,
    index: usize,
) -> Option<gpui::ScrollAnchor> {
    anchors.get(&(pane, index)).cloned()
}

fn settings_panel(rows: Vec<gpui::Div>) -> gpui::Div {
    div()
        .overflow_hidden()
        .rounded_lg()
        .border_1()
        .border_color(theme::border_subtle())
        .bg(theme::surface_selected())
        .children(rows)
}

fn exact_settings_row(
    title: &'static str,
    description: impl Into<SharedString>,
    control: impl IntoElement,
) -> gpui::Div {
    exact_settings_row_width(title, description, 220.0, control)
}

fn exact_settings_row_width(
    title: &'static str,
    description: impl Into<SharedString>,
    control_width: f32,
    control: impl IntoElement,
) -> gpui::Div {
    exact_settings_row_width_with_min_height(title, description, control_width, control, 69.0)
}

fn agent_registration_row_width(
    title: &'static str,
    description: impl Into<SharedString>,
    control_width: f32,
    control: impl IntoElement,
) -> gpui::Div {
    // The registration control has a button row plus status/detail copy. Its
    // Flutter AleraSettingRow is 16 px taller than the regular skill rows.
    exact_settings_row_width_with_min_height(title, description, control_width, control, 85.0)
}

fn exact_settings_row_width_with_min_height(
    title: &'static str,
    description: impl Into<SharedString>,
    control_width: f32,
    control: impl IntoElement,
    min_height: f32,
) -> gpui::Div {
    let description = description.into();
    div()
        .flex()
        .items_center()
        // AleraSettingRow is content-sized: two single-line labels plus
        // 16 px vertical padding plus the Flutter body text metrics settle at
        // roughly 69 px. Keeping the same floor prevents long settings groups
        // from drifting vertically after several rows.
        .min_h(px(min_height))
        .p_4()
        .border_b_1()
        .border_color(theme::border_subtle())
        .child(
            div()
                .flex_1()
                .child(
                    div()
                        .text_size(px(13.0))
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
        .child(
            div()
                .w(px(control_width))
                .flex()
                .justify_end()
                .child(control),
        )
}

fn settings_title_only_row(
    title: &'static str,
    control: impl IntoElement,
) -> gpui::Div {
    div()
        .flex()
        .items_center()
        .min_h(px(52.0))
        .p_4()
        .child(
            div()
                .flex_1()
                .text_size(px(13.0))
                .font_weight(gpui::FontWeight::MEDIUM)
                .child(title),
        )
        .child(
            div()
                .w(px(220.0))
                .flex()
                .justify_end()
                .child(control),
        )
}

fn update_settings_row(settings: &SettingsState, cx: &mut Context<AleraApp>) -> gpui::Div {
    let (status_icon, status_color) = match settings.update_status.as_str() {
        "Update Failed" => (AleraIcon::Error, theme::danger()),
        "No Update Available" => (AleraIcon::Check, theme::success()),
        "Checking for Updates" => (AleraIcon::Loading, theme::text_muted()),
        "Update Available" => (AleraIcon::Download, theme::info()),
        _ => (AleraIcon::Info, theme::text_muted()),
    };
    let message = settings
        .update_message
        .clone()
        .unwrap_or_else(|| "Check the Alera release channel for a newer desktop build.".into());
    let button_label = if settings.update_busy {
        "Checking"
    } else {
        "Check for Updates"
    };
    let button_icon = if settings.update_busy {
        loading_indicator(14.0, theme::text_muted())
    } else {
        icon(AleraIcon::Refresh, 14.0, theme::text_muted())
    };
    div()
        .flex()
        .flex_col()
        .p_4()
        .border_b_1()
        .border_color(theme::border_subtle())
        // Flutter's update panel keeps the status copy in its own row and
        // places the action Wrap below it. Keeping that vertical rhythm is
        // important because this is the last tall group in Application
        // Settings and determines the scroll range.
        .child(
            div()
                .flex()
                .items_start()
                .child(icon(status_icon, 18.0, status_color))
                .child(
                    div()
                        .ml_3()
                        .flex_1()
                        .child(
                            div()
                                .text_size(px(13.0))
                                .font_weight(gpui::FontWeight::MEDIUM)
                                .child(settings.update_status.clone()),
                        )
                        .child(
                            div()
                                .mt_1()
                                .text_size(px(12.0))
                                .text_color(theme::text_muted())
                                .child(message),
                        ),
                ),
        )
        .child(
            div()
                .mt_4()
                .flex()
                .justify_end()
                .child(
                    div()
                        .id("check-for-updates")
                        .focusable()
                        .tab_stop(!settings.update_busy)
                        .role(Role::Button)
                        .aria_label(if settings.update_busy {
                            "Checking For Updates"
                        } else {
                            "Check For Updates"
                        })
                        .flex()
                        .items_center()
                        .justify_center()
                        .h(px(34.0))
                        .px_3()
                        .gap_2()
                        .rounded_md()
                        .border_1()
                        .border_color(theme::border())
                        .bg(theme::surface_selected())
                        .cursor(if settings.update_busy {
                            CursorStyle::Arrow
                        } else {
                            CursorStyle::PointingHand
                        })
                        .when(!settings.update_busy, |button| {
                            button
                                .hover(|style| style.bg(theme::surface_raised()))
                                .on_click(
                                    cx.listener(|this, _, _, cx| {
                                        this.check_for_updates(cx);
                                        cx.stop_propagation();
                                    }),
                                )
                        })
                        .child(button_icon)
                        .child(button_label),
                ),
        )
}

fn settings_icon_button(
    id: &'static str,
    icon_kind: AleraIcon,
    label: &'static str,
) -> gpui::Stateful<gpui::Div> {
    div()
        .id(id)
        .focusable()
        .tab_stop(true)
        .role(Role::Button)
        .aria_label(label)
        .flex()
        .items_center()
        .justify_center()
        .h(px(34.0))
        .px_3()
        .gap_2()
        .rounded_lg()
        .border_1()
        .border_color(theme::border())
        .cursor(CursorStyle::PointingHand)
        .hover(|style| style.bg(theme::surface_raised()))
        .child(icon(icon_kind, 16.0, theme::text_muted()))
        .child(label)
}

fn skill_install_control(
    id: &'static str,
    skill: &'static str,
    runner_select: &SettingsSelect,
    runner: &str,
    show_copy: bool,
    install_label: &'static str,
    cx: &mut Context<AleraApp>,
) -> gpui::Div {
    let runner_for_install = runner.to_ascii_lowercase();
    let runner_for_copy = runner_for_install.clone();
    let runner_label = match skill {
        "all" => "All Alera Skills Runner",
        "cli" => "Alera CLI Skill Runner",
        "orchestration" => "Alera Orchestration Skill Runner",
        "computer-use" => "Alera Computer Use Skill Runner",
        "emulator" => "Alera Emulator Skill Runner",
        _ => "Agent Skill Runner",
    };
    div()
        .flex()
        .justify_end()
        .gap_2()
        .child(
            div()
                .id(SharedString::from(format!("{id}-runner")))
                .role(Role::ComboBox)
                .aria_label(runner_label)
                .relative()
                .w(px(82.0))
                .h(px(34.0))
                .cursor(CursorStyle::PointingHand)
                .child(Select::new(runner_select).w_full().h_full())
                .child(
                    div()
                        .absolute()
                        .top_0()
                        .right(px(8.0))
                        .bottom_0()
                        .flex()
                        .items_center()
                        .child(icon(AleraIcon::ChevronDown, 14.0, theme::text_muted())),
                ),
        )
        .when(show_copy, |control| {
            control.child(
                div()
                    .id(SharedString::from(format!("{id}-copy")))
                    .focusable()
                    .tab_stop(true)
                    .role(Role::Button)
                    .aria_label("Copy")
                    .flex()
                    .items_center()
                    .h(px(34.0))
                    .px_3()
                    .gap_2()
                    .rounded_lg()
                    .border_1()
                    .border_color(theme::border())
                    .cursor(CursorStyle::PointingHand)
                    .hover(|style| style.bg(theme::surface_raised()))
                    .on_click(
                        cx.listener(move |this, _, _, cx| {
                            this.copy_agent_skill_command(skill, &runner_for_copy, cx);
                            cx.stop_propagation();
                        }),
                    )
                    .child(icon(AleraIcon::Copy, 16.0, theme::text_muted()))
                    .child("Copy"),
            )
        })
        .child(
            div()
                .id(SharedString::from(format!("{id}-install")))
                .focusable()
                .tab_stop(true)
                .role(Role::Button)
                .aria_label(install_label)
                .flex()
                .items_center()
                .h(px(34.0))
                .px_3()
                .gap_2()
                .rounded_lg()
                .border_1()
                .border_color(theme::border())
                .cursor(CursorStyle::PointingHand)
                .hover(|style| style.bg(theme::surface_raised()))
                .on_click(
                    cx.listener(move |this, _, _, cx| {
                        if skill == "all" {
                            this.install_all_agent_skills(&runner_for_install, cx);
                        } else {
                            this.install_agent_skill(skill, &runner_for_install, cx);
                        }
                        cx.stop_propagation();
                    }),
                )
                .child(icon(AleraIcon::Terminal, 16.0, theme::text_muted()))
                .child(install_label),
        )
}

fn agent_hook_row(
    agent: &'static str,
    title: &'static str,
    description: &'static str,
    settings: &SettingsState,
    cx: &mut Context<AleraApp>,
) -> gpui::Div {
    let enabled = settings
        .agent_status_hooks
        .get(agent)
        .copied()
        .unwrap_or(false);
    exact_settings_row(
        title,
        description,
        settings_switch(
            SharedString::from(format!("agent-hook-{agent}")),
            title,
            enabled,
        )
        .on_click(
            cx.listener(move |this, _, _, cx| {
                this.update_agent_settings(
                    |settings| {
                        let enabled = settings
                            .agent_status_hooks
                            .get(agent)
                            .copied()
                            .unwrap_or(false);
                        settings
                            .agent_status_hooks
                            .insert(agent.to_string(), !enabled);
                    },
                    cx,
                );
                cx.stop_propagation();
            }),
        ),
    )
}

fn quota_provider_row(
    provider: &'static str,
    title: &'static str,
    description: &'static str,
    settings: &SettingsState,
    cx: &mut Context<AleraApp>,
) -> gpui::Div {
    let enabled = settings
        .quota_enabled_providers
        .iter()
        .any(|candidate| candidate == provider);
    let pinned = !settings.quota_unpinned_keys.contains(provider);
    let pin_tooltip = if pinned {
        "Shown In Status Bar"
    } else {
        "Hidden From Status Bar - Available In The Quota Panel"
    };
    let pin_label: SharedString = if pinned {
        format!("Unpin {title}").into()
    } else {
        format!("Pin {title}").into()
    };
    exact_settings_row(
        title,
        description,
        div()
            .flex()
            .items_center()
            .gap_3()
            .child(
                div()
                    .id(SharedString::from(format!("quota-pin-{provider}")))
                    .flex()
                    .items_center()
                    .justify_center()
                    .w(px(32.0))
                    .h(px(32.0))
                    .rounded_md()
                    .focusable()
                    .tab_stop(true)
                    .role(Role::Button)
                    .aria_label(pin_label)
                    .tooltip(move |_, cx| {
                        cx.new(move |_| Tooltip::new(pin_tooltip)).into()
                    })
                    .cursor(CursorStyle::PointingHand)
                    .hover(|style| style.bg(theme::surface_raised()))
                    .on_click(
                        cx.listener(move |this, _, _, cx| {
                            this.update_quota_settings(
                                |settings| toggle_quota_pin(settings, provider),
                                cx,
                            );
                            cx.stop_propagation();
                        }),
                    )
                    .child(icon(
                        if pinned {
                            AleraIcon::Pin
                        } else {
                            AleraIcon::PinOff
                        },
                        14.0,
                        if pinned {
                            theme::accent()
                        } else {
                            theme::text_muted()
                        },
                    )),
            )
            .child(
                settings_switch(
                    SharedString::from(format!("quota-provider-{provider}")),
                    title,
                    enabled,
                )
                .on_click(
                    cx.listener(move |this, _, _, cx| {
                        this.update_quota_settings(
                            |settings| toggle_quota_provider(settings, provider),
                            cx,
                        );
                        cx.stop_propagation();
                    }),
                ),
            ),
    )
}

fn provider_order_control(settings: &SettingsState, cx: &mut Context<AleraApp>) -> gpui::Div {
    let providers = settings.quota_enabled_providers.clone();
    let count = providers.len();
    div().flex().flex_col().gap_1().children(
        providers
            .into_iter()
            .enumerate()
            .map(|(index, provider)| provider_order_item(provider, index, count, cx)),
    )
}

fn credential_environment_row(title: &'static str, input: &Entity<InputState>) -> gpui::Div {
    exact_settings_row(
        title,
        "Environment Variable Read On The Active Host. The Secret Value Is Never Stored By Alera.",
        settings_text_input(title, input, 220.0, 48.0),
    )
}
