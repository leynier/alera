fn settings_switch(
    id: impl Into<gpui::ElementId>,
    label: impl Into<SharedString>,
    enabled: bool,
) -> gpui::Stateful<gpui::Div> {
    design_system::switch(enabled, true)
        .id(id)
        .focusable()
        .tab_stop(true)
        .role(Role::Switch)
        .aria_label(label.into())
        .aria_toggled(if enabled { Toggled::True } else { Toggled::False })
}

fn settings_button(
    id: impl Into<gpui::ElementId>,
    label: impl Into<SharedString>,
) -> gpui::Stateful<gpui::Div> {
    settings_button_with_loading(id, label, false)
}

fn settings_button_with_loading(
    id: impl Into<gpui::ElementId>,
    label: impl Into<SharedString>,
    loading: bool,
) -> gpui::Stateful<gpui::Div> {
    let label = label.into();
    div()
        .id(id)
        .focusable()
        .tab_stop(!loading)
        .role(Role::Button)
        .aria_label(label.clone())
        .flex()
        .items_center()
        .justify_center()
        .h(px(34.0))
        .px_3()
        .rounded_md()
        .border_1()
        .border_color(theme::border())
        .bg(theme::surface_selected())
        .cursor(if loading {
            CursorStyle::Arrow
        } else {
            CursorStyle::PointingHand
        })
        .when(!loading, |button| {
            button.hover(|style| style.bg(theme::surface_raised()))
        })
        .when(loading, |button| {
            button.child(loading_indicator(16.0, theme::text_muted()))
        })
        .when(!loading, |button| button.child(label))
}

fn settings_select_control(
    label: &'static str,
    select: &SettingsSelect,
    wide: bool,
    _compact: bool,
) -> gpui::Div {
    div()
        .relative()
        .w(px(if wide { 260.0 } else { 220.0 }))
        // Flutter's AleraDropdownField uses a fixed 34 px trigger for both
        // compact and regular settings rows. The previous 40/48 px variants
        // made every select row grow the pane and shifted the scrollbar.
        .h(px(34.0))
        .rounded_md()
        .border_1()
        .border_color(theme::border())
        .bg(theme::surface_selected())
        .cursor(CursorStyle::PointingHand)
        .child(
            div()
                .id(("settings-select", select.entity_id()))
                .role(Role::ComboBox)
                .aria_label(label)
                .size_full()
                .child(Select::new(select).w_full().h_full()),
        )
        .child(
            div()
                .absolute()
                .top_0()
                .right(px(10.0))
                .bottom_0()
                .flex()
                .items_center()
                .child(icon(AleraIcon::ChevronDown, 14.0, theme::text_muted())),
        )
}

fn settings_font_select_control(
    select: &SettingsSelect,
    cx: &mut Context<AleraApp>,
) -> gpui::Div {
    let has_value = select.read(cx).selected_value().is_some();
    let select_for_clear = select.clone();
    div()
        .relative()
        .w(px(260.0))
        .h(px(40.0))
        .rounded_md()
        .border_1()
        .border_color(theme::border())
        .bg(theme::surface_selected())
        .cursor(CursorStyle::PointingHand)
        .child(
            div()
                .id(("settings-font-select", select.entity_id()))
                .role(Role::ComboBox)
                .aria_label("Font Family")
                .size_full()
                .child(
                    Select::new(select)
                        .w_full()
                        .h_full()
                        .placeholder("SF Mono")
                        .appearance(false),
                ),
        )
        .when(has_value, |this| {
            this.child(
                div()
                    .id("settings-terminal-font-clear")
                    .focusable()
                    .tab_stop(true)
                    .role(Role::Button)
                    .aria_label("Clear Font Family")
                    .absolute()
                    .top_0()
                    .right(px(30.0))
                    .bottom_0()
                    .w(px(24.0))
                    .flex()
                    .items_center()
                    .justify_center()
                    .cursor(CursorStyle::PointingHand)
                    .tooltip(|_, cx| cx.new(|_| Tooltip::new("Clear")).into())
                    .child(icon(AleraIcon::Cancel, 14.0, theme::text_muted()))
                    .on_click(
                        cx.listener(move |_, _, window, cx| {
                            select_for_clear.update(cx, |select, cx| {
                                select.set_selected_index(None, window, cx);
                                cx.emit(SelectEvent::Confirm(None));
                            });
                        }),
                    ),
            )
        })
        .child(
            div()
                .id("settings-terminal-font-menu")
                .absolute()
                .top_0()
                .right(px(8.0))
                .bottom_0()
                .w(px(18.0))
                .flex()
                .items_center()
                .justify_center()
                .tooltip(|_, cx| cx.new(|_| Tooltip::new("Fonts")).into())
                .child(icon(AleraIcon::ChevronDown, 14.0, theme::text_muted())),
        )
}

fn toggle_quota_provider(settings: &mut SettingsState, provider: &str) {
    if let Some(index) = settings
        .quota_enabled_providers
        .iter()
        .position(|candidate| candidate == provider)
    {
        settings.quota_enabled_providers.remove(index);
    } else {
        settings.quota_enabled_providers.push(provider.to_owned());
    }
}

fn toggle_quota_pin(settings: &mut SettingsState, key: &str) {
    if !settings.quota_unpinned_keys.insert(key.to_owned()) {
        settings.quota_unpinned_keys.remove(key);
    }
}

fn provider_order_item(
    provider: String,
    index: usize,
    count: usize,
    cx: &mut Context<AleraApp>,
) -> gpui::Div {
    let provider_up = provider.clone();
    let provider_down = provider.clone();
    let provider_label = quota_provider_label(&provider);
    let earlier_tooltip: SharedString = format!("Move {provider_label} Earlier").into();
    let later_tooltip: SharedString = format!("Move {provider_label} Later").into();
    div()
        .flex()
        .items_center()
        .h(px(36.0))
        .px_2()
        .rounded_md()
        .border_1()
        .border_color(theme::border_subtle())
        .bg(theme::surface_selected())
        .child(
            div()
                .flex_1()
                .font_weight(gpui::FontWeight::MEDIUM)
                .flex()
                .items_center()
                .gap_2()
                .child(agent_icon(
                    super::status_quota::provider_agent_icon(&provider),
                    16.0,
                    theme::text_muted(),
                ))
                .child(quota_provider_label(&provider)),
        )
        .child(
            div()
                .id(SharedString::from(format!("quota-order-up-{provider}")))
                .focusable()
                .tab_stop(index > 0)
                .role(Role::Button)
                .aria_label(earlier_tooltip.clone())
                .flex()
                .items_center()
                .justify_center()
                .w(px(28.0))
                .h(px(28.0))
                .rounded_md()
                .tooltip(move |_, cx| {
                    let label = earlier_tooltip.clone();
                    cx.new(move |_| Tooltip::new(label)).into()
                })
                .when(index > 0, |button| {
                    button
                        .cursor(CursorStyle::PointingHand)
                        .hover(|style| style.bg(theme::surface_raised()))
                        .on_click(
                            cx.listener(move |this, _, _, cx| {
                                this.update_quota_settings(
                                    |settings| {
                                        let Some(current) = settings
                                            .quota_enabled_providers
                                            .iter()
                                            .position(|item| item == &provider_up)
                                        else {
                                            return;
                                        };
                                        if current > 0 {
                                            settings
                                                .quota_enabled_providers
                                                .swap(current, current - 1);
                                        }
                                    },
                                    cx,
                                );
                            }),
                        )
                })
                .child(icon(AleraIcon::ChevronUp, 14.0, theme::text_muted())),
        )
        .child(
            div()
                .id(SharedString::from(format!("quota-order-down-{provider}")))
                .focusable()
                .tab_stop(index + 1 < count)
                .role(Role::Button)
                .aria_label(later_tooltip.clone())
                .flex()
                .items_center()
                .justify_center()
                .w(px(28.0))
                .h(px(28.0))
                .rounded_md()
                .tooltip(move |_, cx| {
                    let label = later_tooltip.clone();
                    cx.new(move |_| Tooltip::new(label)).into()
                })
                .when(index + 1 < count, |button| {
                    button
                        .cursor(CursorStyle::PointingHand)
                        .hover(|style| style.bg(theme::surface_raised()))
                        .on_click(
                            cx.listener(move |this, _, _, cx| {
                                this.update_quota_settings(
                                    |settings| {
                                        let Some(current) = settings
                                            .quota_enabled_providers
                                            .iter()
                                            .position(|item| item == &provider_down)
                                        else {
                                            return;
                                        };
                                        if current + 1 < settings.quota_enabled_providers.len() {
                                            settings
                                                .quota_enabled_providers
                                                .swap(current, current + 1);
                                        }
                                    },
                                    cx,
                                );
                            }),
                        )
                })
                .child(icon(
                    AleraIcon::ChevronDown,
                    14.0,
                    theme::text_muted(),
                )),
        )
}

fn quota_provider_label(provider: &str) -> SharedString {
    match provider {
        "claude" => "Claude Code".into(),
        "codex" => "Codex".into(),
        "copilot" => "GitHub Copilot".into(),
        "cursor" => "Cursor".into(),
        "kimi" => "Kimi".into(),
        "agy" => "AGY".into(),
        "opencode" => "OpenCode".into(),
        "pi" => "Pi".into(),
        "amp" => "Amp".into(),
        "grok" => "Grok".into(),
        _ => provider.to_owned().into(),
    }
}
