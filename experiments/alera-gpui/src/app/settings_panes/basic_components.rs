fn settings_switch(
    id: impl Into<gpui::ElementId>,
    enabled: bool,
) -> gpui::Stateful<gpui::Div> {
    design_system::switch(enabled, true).id(id)
}

fn settings_button(
    id: impl Into<gpui::ElementId>,
    label: impl Into<SharedString>,
) -> gpui::Stateful<gpui::Div> {
    div()
        .id(id)
        .flex()
        .items_center()
        .justify_center()
        .h(px(34.0))
        .px_3()
        .rounded_md()
        .border_1()
        .border_color(theme::border())
        .bg(theme::surface_selected())
        .cursor(CursorStyle::PointingHand)
        .hover(|style| style.bg(theme::surface_raised()))
        .child(label.into())
}

fn settings_select_control(
    select: &SettingsSelect,
    wide: bool,
    compact: bool,
) -> gpui::Div {
    div()
        .relative()
        .w(px(if wide { 260.0 } else { 220.0 }))
        .h(px(if compact { 40.0 } else { 48.0 }))
        .rounded_md()
        .border_1()
        .border_color(theme::border())
        .bg(theme::surface_selected())
        .cursor(CursorStyle::PointingHand)
        .child(Select::new(select).w_full().h_full())
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
                .flex()
                .items_center()
                .justify_center()
                .w(px(28.0))
                .h(px(28.0))
                .rounded_md()
                .when(index > 0, |button| {
                    button
                        .cursor(CursorStyle::PointingHand)
                        .hover(|style| style.bg(theme::surface_raised()))
                        .on_mouse_down(
                            MouseButton::Left,
                            cx.listener(move |this, _: &MouseDownEvent, _, cx| {
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
                .flex()
                .items_center()
                .justify_center()
                .w(px(28.0))
                .h(px(28.0))
                .rounded_md()
                .when(index + 1 < count, |button| {
                    button
                        .cursor(CursorStyle::PointingHand)
                        .hover(|style| style.bg(theme::surface_raised()))
                        .on_mouse_down(
                            MouseButton::Left,
                            cx.listener(move |this, _: &MouseDownEvent, _, cx| {
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
