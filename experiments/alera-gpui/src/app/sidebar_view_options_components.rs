use gpui::{
    div, prelude::FluentBuilder as _, px, CursorStyle, InteractiveElement as _, IntoElement as _,
    ParentElement as _, Role, SharedString, StatefulInteractiveElement as _, Styled as _, Toggled,
};

use super::SidebarSortBy;
use crate::{
    icons::{icon, AleraIcon},
    theme,
};

pub(super) fn sidebar_sort_label(sort: SidebarSortBy) -> &'static str {
    match sort {
        SidebarSortBy::Name => "Name",
        SidebarSortBy::Recent => "Recent",
        SidebarSortBy::Activity => "Agent Activity",
    }
}

pub(super) fn section_label(label: &'static str) -> gpui::Div {
    div()
        .text_xs()
        .font_weight(gpui::FontWeight::SEMIBOLD)
        .text_color(theme::text_faint())
        .child(label)
}

pub(super) fn segment_button(
    id: &'static str,
    label: &'static str,
    selected: bool,
) -> gpui::Stateful<gpui::Div> {
    div()
        .id(id)
        .focusable()
        .tab_stop(true)
        .role(Role::RadioButton)
        .aria_label(label)
        .aria_selected(selected)
        .flex()
        .flex_1()
        .items_center()
        .justify_center()
        .h_full()
        .rounded_md()
        .text_xs()
        .text_color(if selected {
            theme::text()
        } else {
            theme::text_muted()
        })
        .when(selected, |button| button.bg(theme::accent_subtle()))
        .cursor(CursorStyle::PointingHand)
        .child(label)
}

pub(super) fn sort_row(
    label: &'static str,
    value: &'static str,
    id: &'static str,
) -> gpui::Stateful<gpui::Div> {
    div()
        .id(id)
        .focusable()
        .tab_stop(true)
        .role(Role::Button)
        .aria_label(format!("{label}: {value}"))
        .flex()
        .items_center()
        .h(px(32.0))
        .cursor(CursorStyle::PointingHand)
        .child(
            div()
                .flex_1()
                .text_sm()
                .text_color(theme::text_muted())
                .child(label),
        )
        .child(
            div()
                .flex()
                .items_center()
                .gap_1()
                .px_2()
                .py_1()
                .rounded_md()
                .hover(|style| style.bg(theme::surface()))
                .text_xs()
                .text_color(theme::text_muted())
                .child(value)
                .child(icon(AleraIcon::ChevronDown, 14.0, theme::text_faint())),
        )
}

pub(super) fn check_row(
    id: impl Into<SharedString>,
    label: impl Into<SharedString>,
    checked: bool,
) -> gpui::Stateful<gpui::Div> {
    let label = label.into();
    div()
        .id(id.into())
        .focusable()
        .tab_stop(true)
        .role(Role::CheckBox)
        .aria_label(label.clone())
        .aria_toggled(if checked {
            Toggled::True
        } else {
            Toggled::False
        })
        .flex()
        .items_center()
        .gap_2()
        .min_h(px(30.0))
        .px_1()
        .rounded_md()
        .cursor(CursorStyle::PointingHand)
        .hover(|style| style.bg(theme::surface()))
        .child(
            div()
                .flex()
                .items_center()
                .justify_center()
                .w(px(16.0))
                .h(px(16.0))
                .rounded(px(4.0))
                .border_1()
                .border_color(if checked {
                    theme::accent()
                } else {
                    theme::border()
                })
                .when(checked, |box_| {
                    box_.bg(theme::accent())
                        .child(icon(AleraIcon::Check, 11.0, theme::on_accent()))
                }),
        )
        .child(div().text_sm().child(label))
}

pub(super) fn filter_header(label: &'static str, count: usize) -> gpui::Div {
    div()
        .flex()
        .items_center()
        .h(px(28.0))
        .child(section_label(label))
        .when(count > 0, |row| {
            row.child(
                div()
                    .ml_2()
                    .min_w(px(18.0))
                    .h(px(18.0))
                    .px_1()
                    .rounded_full()
                    .bg(theme::surface())
                    .text_xs()
                    .text_color(theme::text_muted())
                    .child(count.to_string()),
            )
        })
        .child(div().flex_1())
}

pub(super) fn clear_button(id: &'static str, enabled: bool) -> gpui::Stateful<gpui::Div> {
    div()
        .id(id)
        .focusable()
        .tab_stop(enabled)
        .role(Role::Button)
        .aria_label("Clear")
        .px_2()
        .py_1()
        .rounded_md()
        .text_xs()
        .text_color(if enabled {
            theme::text_muted()
        } else {
            theme::text_faint()
        })
        .when(enabled, |button| {
            button
                .cursor(CursorStyle::PointingHand)
                .hover(|style| style.bg(theme::surface()))
        })
        .child("Clear")
}

pub(super) fn selected_filter_chip(
    id: impl Into<SharedString>,
    label: impl Into<SharedString>,
) -> gpui::Stateful<gpui::Div> {
    let label = label.into();
    div()
        .id(id.into())
        .focusable()
        .tab_stop(true)
        .role(Role::Button)
        .aria_label(SharedString::from(format!("Remove {label}")))
        .flex()
        .items_center()
        .gap_1()
        .h(px(26.0))
        .px_2()
        .rounded_full()
        .border_1()
        .border_color(theme::border())
        .bg(theme::surface())
        .text_xs()
        .cursor(CursorStyle::PointingHand)
        .hover(|style| style.bg(theme::surface_selected()))
        .child(label)
        .child(icon(AleraIcon::Close, 11.0, theme::text_faint()))
}

pub(super) fn available_filter_row(
    id: impl Into<SharedString>,
    label: impl Into<SharedString>,
    leading: Option<AleraIcon>,
) -> gpui::Stateful<gpui::Div> {
    let label = label.into();
    div()
        .id(id.into())
        .focusable()
        .tab_stop(true)
        .role(Role::Button)
        .aria_label(label.clone())
        .flex()
        .items_center()
        .gap_2()
        .min_h(px(30.0))
        .px_2()
        .rounded_md()
        .cursor(CursorStyle::PointingHand)
        .hover(|style| style.bg(theme::surface()))
        .child(if let Some(leading) = leading {
            icon(leading, 12.0, theme::text_faint())
        } else {
            div()
                .w(px(6.0))
                .h(px(6.0))
                .rounded_full()
                .bg(theme::text_faint())
                .into_any_element()
        })
        .child(
            div()
                .flex_1()
                .overflow_hidden()
                .text_ellipsis()
                .text_sm()
                .child(label),
        )
}

pub(super) fn empty_filter_message(message: impl Into<SharedString>) -> gpui::Div {
    div()
        .py_2()
        .text_sm()
        .text_color(theme::text_faint())
        .text_center()
        .child(message.into())
}
