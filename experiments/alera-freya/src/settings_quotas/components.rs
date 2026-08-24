use freya::{icons, prelude::*};
use std::time::Duration;

use crate::{ACCENT, BORDER, MUTED, SURFACE, TEXT, provider_icon_for_name};

pub(super) fn loading_row(message: impl Into<String>) -> Element {
    rect()
        .horizontal()
        .cross_align(Alignment::Center)
        .spacing(8.)
        .padding(Gaps::new_all(12.))
        .child(CircularLoader::new().size(14.))
        .child(label().font_size(11.).color(MUTED).text(message.into()))
        .into_element()
}

pub(super) fn toggle_control(
    value: bool,
    enabled: bool,
    on_toggle: impl FnMut(Event<PointerEventData>) + 'static,
) -> Element {
    crate::settings_switch::control(value, enabled, on_toggle)
}

pub(super) fn icon_action(
    icon: Bytes,
    tooltip: impl Into<String>,
    enabled: bool,
    on_press: impl FnMut(Event<PressEventData>) + 'static,
) -> Element {
    let tooltip = tooltip.into();
    TooltipContainer::new(Tooltip::new_text(tooltip))
        .position(AttachedPosition::Top)
        .delay(Duration::from_millis(350))
        .child(
            Button::new()
                .compact()
                .flat()
                .enabled(enabled)
                .on_press(on_press)
                .child(
                    SvgViewer::new(icon)
                        .width(Size::px(14.))
                        .height(Size::px(14.))
                        .color(if enabled { MUTED } else { (72, 72, 72) }),
                ),
        )
        .into_element()
}

pub(super) fn pin_action(
    pinned: bool,
    enabled: bool,
    on_press: impl FnMut(Event<PressEventData>) + 'static,
) -> Element {
    icon_action(
        if pinned {
            icons::lucide::pin()
        } else {
            icons::lucide::pin_off()
        },
        if pinned {
            "Shown In Status Bar"
        } else {
            "Hidden From Status Bar - Available In The Quota Panel"
        },
        enabled,
        on_press,
    )
}

pub(super) fn provider_label(provider: &str) -> &'static str {
    match provider {
        "claude" => "Claude Code",
        "codex" => "Codex",
        "kimi" => "Kimi",
        "grok" => "Grok Build",
        "cursor" => "Cursor",
        "antigravity" => "Antigravity",
        "minimax" => "MiniMax",
        "zai" => "Z.ai",
        _ => "Provider",
    }
}

pub(super) fn provider_mark(provider: &str) -> Element {
    provider_icon_for_name(provider_label(provider)).unwrap_or_else(|| {
        SvgViewer::new(icons::lucide::gauge())
            .width(Size::px(16.))
            .height(Size::px(16.))
            .color(MUTED)
            .into_element()
    })
}

pub(super) fn settings_input(value: State<String>, width: f32) -> Input {
    Input::new(value)
        .width(Size::px(width))
        .compact()
        .filled()
        .theme_colors(
            InputColorsThemePartial::new()
                .background(SURFACE)
                .focus_background(SURFACE)
                .border_fill(BORDER)
                .focus_border_fill(ACCENT)
                .color(TEXT)
                .placeholder_color(MUTED),
        )
}
