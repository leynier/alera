use gpui::{
    div, prelude::FluentBuilder as _, px, AnyElement, CursorStyle, ElementId,
    InteractiveElement as _, ParentElement as _, Role, SharedString,
    StatefulInteractiveElement as _, Styled as _,
};

use crate::icons::{icon, loading_indicator, AleraIcon};
use crate::theme;

pub fn dropdown_trigger(
    id: impl Into<ElementId>,
    value: impl Into<SharedString>,
    expanded: bool,
    enabled: bool,
) -> gpui::Stateful<gpui::Div> {
    let value = value.into();
    dropdown_field(value.clone(), expanded, enabled)
        .id(id)
        .focusable()
        .tab_stop(enabled)
        .role(Role::ComboBox)
        .aria_label(value)
        .aria_expanded(expanded)
}

pub fn dropdown_trigger_with_loading(
    id: impl Into<ElementId>,
    value: impl Into<SharedString>,
    expanded: bool,
    enabled: bool,
    loading: bool,
) -> gpui::Stateful<gpui::Div> {
    let value = value.into();
    dropdown_field_with_loading(value.clone(), expanded, enabled, loading)
        .id(id)
        .focusable()
        .tab_stop(enabled)
        .role(Role::ComboBox)
        .aria_label(value)
        .aria_expanded(expanded)
}

pub fn dropdown_field(value: impl Into<SharedString>, expanded: bool, enabled: bool) -> gpui::Div {
    dropdown_field_with_loading(value, expanded, enabled, false)
}

pub fn dropdown_field_with_loading(
    value: impl Into<SharedString>,
    expanded: bool,
    enabled: bool,
    loading: bool,
) -> gpui::Div {
    let value = value.into();
    div()
        .flex()
        .items_center()
        .min_w(px(0.0))
        .h(px(34.0))
        .px(px(12.0))
        .gap(px(8.0))
        .rounded_md()
        .border_1()
        .border_color(theme::border())
        .bg(theme::surface_selected())
        .text_size(px(13.0))
        .text_color(if enabled {
            theme::text()
        } else {
            theme::text_faint()
        })
        .when(enabled, |trigger| {
            trigger
                .cursor(CursorStyle::PointingHand)
                .hover(|style| style.bg(theme::surface_raised()))
        })
        .child(
            div()
                .min_w(px(0.0))
                .flex_1()
                .overflow_hidden()
                .whitespace_nowrap()
                .child(value),
        )
        .when(loading, |trigger| {
            trigger.child(loading_indicator(14.0, theme::text_faint()))
        })
        .child(icon(
            if expanded {
                AleraIcon::ChevronUp
            } else {
                AleraIcon::ChevronDown
            },
            16.0,
            if enabled {
                theme::text_muted()
            } else {
                theme::text_faint()
            },
        ))
}

pub fn checkbox(value: bool, enabled: bool, label: Option<SharedString>) -> gpui::Div {
    div()
        .flex()
        .items_center()
        .gap(px(8.0))
        .p(px(4.0))
        .when(enabled, |control| control.cursor(CursorStyle::PointingHand))
        .child(
            div()
                .flex()
                .items_center()
                .justify_center()
                .w(px(18.0))
                .h(px(18.0))
                .rounded_sm()
                .border_1()
                .border_color(if value {
                    theme::transparent()
                } else {
                    theme::border()
                })
                .bg(if value {
                    if enabled {
                        theme::accent()
                    } else {
                        theme::text_faint()
                    }
                } else {
                    theme::surface_selected()
                })
                .when(value, |box_| {
                    box_.child(icon(AleraIcon::Check, 14.0, theme::on_accent()))
                }),
        )
        .when_some(label, |control, label| {
            control.child(
                div()
                    .text_size(px(13.0))
                    .text_color(if enabled {
                        theme::text()
                    } else {
                        theme::text_faint()
                    })
                    .child(label),
            )
        })
}

pub fn radio(selected: bool, enabled: bool) -> gpui::Div {
    div().size(px(16.0)).flex_shrink_0().child(icon(
        if selected {AleraIcon::CircleDot} else {AleraIcon::Circle},
        16.0,
        if selected && enabled {theme::accent()} else {theme::text_faint()},
    ))
}

pub fn switch(enabled: bool, interactive: bool) -> gpui::Div {
    div()
        .flex()
        .items_center()
        .w(px(52.0))
        .h(px(32.0))
        .px(px(if enabled { 2.0 } else { 6.0 }))
        .rounded_full()
        .border_2()
        .border_color(if enabled {
            theme::accent()
        } else {
            theme::border()
        })
        .bg(if enabled {
            theme::accent()
        } else {
            theme::surface_selected()
        })
        .when(interactive, |control| {
            control.cursor(CursorStyle::PointingHand)
        })
        .child(
            div()
                .w(px(if enabled { 24.0 } else { 16.0 }))
                .h(px(if enabled { 24.0 } else { 16.0 }))
                .rounded_full()
                .bg(if enabled {
                    theme::on_accent()
                } else {
                    theme::text_muted()
                })
                .when(enabled, |thumb| thumb.ml_auto()),
        )
}

pub fn icon_button(
    id: impl Into<ElementId>,
    label: impl Into<SharedString>,
    icon_kind: AleraIcon,
    enabled: bool,
    size: f32,
    background: Option<gpui::Rgba>,
    border: Option<gpui::Rgba>,
) -> gpui::Stateful<gpui::Div> {
    div()
        .id(id)
        .focusable()
        .tab_stop(enabled)
        .role(Role::Button)
        .aria_label(label.into())
        .flex()
        .items_center()
        .justify_center()
        .w(px(size))
        .h(px(size))
        .rounded_md()
        .when_some(background, |button, color| button.bg(color))
        .when_some(border, |button, color| {
            button.border_1().border_color(color)
        })
        .when(enabled, |button| {
            button
                .cursor(CursorStyle::PointingHand)
                .hover(|style| style.bg(theme::surface_selected()))
        })
        .child(icon(
            icon_kind,
            16.0,
            if enabled {
                theme::text_muted()
            } else {
                theme::text_faint()
            },
        ))
}

pub fn menu_item(
    label: impl Into<SharedString>,
    subtitle: Option<SharedString>,
    selected: bool,
    active: bool,
    enabled: bool,
    leading: Option<AnyElement>,
) -> gpui::Div {
    let label = label.into();
    let has_subtitle = subtitle.is_some();
    let has_leading = leading.is_some();
    div()
        .flex()
        .items_center()
        .min_h(if has_subtitle { px(42.0) } else { px(30.0) })
        .px(px(8.0))
        .py(px(6.0))
        .gap(px(6.0))
        .bg(if active && enabled {
            theme::surface_raised()
        } else if selected {
            theme::accent_subtle()
        } else {
            theme::transparent()
        })
        .when(enabled, |item| item.cursor(CursorStyle::PointingHand))
        .child(
            div()
                .flex()
                .items_center()
                .justify_center()
                .w(px(18.0))
                .when_some(leading, |slot, leading| slot.child(leading))
                .when(!has_leading && selected, |slot| {
                    slot.child(icon(AleraIcon::Check, 14.0, theme::text()))
                }),
        )
        .child(
            div()
                .min_w(px(0.0))
                .flex_1()
                .child(
                    div()
                        .overflow_hidden()
                        .whitespace_nowrap()
                        .text_size(px(12.0))
                        .font_weight(if selected {
                            gpui::FontWeight::SEMIBOLD
                        } else {
                            gpui::FontWeight::NORMAL
                        })
                        .text_color(if !enabled {
                            theme::text_faint()
                        } else if selected {
                            theme::text()
                        } else {
                            theme::text_muted()
                        })
                        .child(label),
                )
                .when_some(subtitle, |content, subtitle| {
                    content.child(
                        div()
                            .mt(px(2.0))
                            .overflow_hidden()
                            .whitespace_nowrap()
                            .text_size(px(11.0))
                            .text_color(theme::text_faint())
                            .child(subtitle),
                    )
                }),
        )
}
