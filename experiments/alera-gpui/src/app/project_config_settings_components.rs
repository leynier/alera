fn project_config_group(
    title: impl Into<gpui::SharedString>,
    description: &'static str,
    rows: Vec<gpui::Div>,
) -> gpui::Div {
    div()
        .child(
            div()
                .ml_1()
                .mb_2()
                .child(
                    div()
                        .text_size(px(13.0))
                        .font_weight(gpui::FontWeight::SEMIBOLD)
                        .child(title.into()),
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
                .overflow_hidden()
                .rounded_lg()
                .border_1()
                .border_color(theme::border_subtle())
                .bg(theme::surface_selected())
                .children(rows),
        )
}

fn project_config_row(
    title: &'static str,
    description: impl Into<gpui::SharedString>,
    control: impl gpui::IntoElement,
) -> gpui::Div {
    project_config_row_width(title, description, 220.0, control)
}

fn project_config_row_width(
    title: &'static str,
    description: impl Into<gpui::SharedString>,
    control_width: f32,
    control: impl gpui::IntoElement,
) -> gpui::Div {
    div()
        .flex()
        .items_center()
        .min_h(px(72.0))
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
                        .child(description.into()),
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

fn project_config_source_badge(label: &'static str) -> gpui::Div {
    div()
        .px_2()
        .py(px(4.0))
        .rounded_sm()
        .border_1()
        .border_color(theme::border_subtle())
        .bg(theme::accent_subtle())
        .text_size(px(10.0))
        .font_weight(gpui::FontWeight::SEMIBOLD)
        .text_color(theme::accent())
        .child(label)
}

fn project_labeled_input(label: &'static str, input: &Entity<InputState>) -> gpui::Div {
    div()
        .flex_1()
        .min_w_0()
        .child(
            div()
                .mb_1()
                .text_size(px(10.0))
                .text_color(theme::text_muted())
                .child(label),
        )
        .child(
            div()
                .h(px(36.0))
                .child(design_system::text_field(input).height(px(36.0))),
        )
}

fn project_prompt_append_input(input: &Entity<InputState>) -> gpui::Div {
    div()
        .relative()
        .h(px(84.0))
        .child(design_system::text_field(input).height(px(76.0)))
        .child(
            div()
                .absolute()
                .top(px(-6.0))
                .left(px(10.0))
                .px_1()
                .bg(theme::surface_selected())
                .text_size(px(10.0))
                .text_color(theme::text_muted())
                .child("Prompt Append"),
        )
}

fn project_checkbox(
    id: impl Into<gpui::ElementId>,
    checked: bool,
) -> gpui::Stateful<gpui::Div> {
    design_system::checkbox(checked, true, None).id(id)
}

fn project_icon_button(
    id: impl Into<gpui::ElementId>,
    icon_kind: AleraIcon,
    color: gpui::Rgba,
) -> gpui::Stateful<gpui::Div> {
    div()
        .id(id)
        .flex()
        .items_center()
        .justify_center()
        .w(px(32.0))
        .h(px(32.0))
        .rounded_md()
        .cursor(CursorStyle::PointingHand)
        .hover(|style| style.bg(theme::surface_raised()))
        .child(icon(icon_kind, 16.0, color))
}

fn project_outline_button(
    id: &'static str,
    icon_kind: AleraIcon,
    label: &'static str,
) -> gpui::Stateful<gpui::Div> {
    div()
        .id(id)
        .flex()
        .items_center()
        .h(px(34.0))
        .px_6()
        .gap_2()
        .rounded_lg()
        .border_1()
        .border_color(theme::border())
        .cursor(CursorStyle::PointingHand)
        .hover(|style| style.bg(theme::surface_raised()))
        .child(icon(icon_kind, 16.0, theme::text_muted()))
        .child(label)
}

fn project_action_button(
    id: &'static str,
    icon_kind: Option<AleraIcon>,
    label: &'static str,
    filled: bool,
) -> gpui::Stateful<gpui::Div> {
    div()
        .id(id)
        .flex()
        .items_center()
        .h(px(36.0))
        .px_3()
        .gap_2()
        .rounded_lg()
        .border_1()
        .border_color(if filled {
            theme::accent()
        } else {
            theme::border()
        })
        .bg(if filled {
            theme::accent()
        } else {
            theme::surface_selected()
        })
        .text_color(if filled {
            theme::on_accent()
        } else {
            theme::text()
        })
        .cursor(CursorStyle::PointingHand)
        .when_some(icon_kind, |button, icon_kind| {
            button.child(icon(
                icon_kind,
                16.0,
                if filled {
                    theme::on_accent()
                } else {
                    theme::text_muted()
                },
            ))
        })
        .child(label)
}

fn project_empty_row(message: &'static str) -> gpui::Div {
    div()
        .p_4()
        .text_size(px(12.0))
        .text_color(theme::text_muted())
        .border_b_1()
        .border_color(theme::border_subtle())
        .child(message)
}

fn project_config_empty_state(
    icon_kind: AleraIcon,
    title: &'static str,
    message: &'static str,
) -> gpui::Div {
    div()
        .flex()
        .flex_col()
        .flex_1()
        .items_center()
        .justify_center()
        .child(icon(icon_kind, 28.0, theme::text_faint()))
        .child(
            div()
                .mt_3()
                .font_weight(gpui::FontWeight::SEMIBOLD)
                .child(title),
        )
        .child(
            div()
                .mt_1()
                .text_size(px(12.0))
                .text_color(theme::text_muted())
                .child(message),
        )
}

fn provider_label(provider: Option<&str>) -> &'static str {
    match provider {
        Some("github") => "GitHub",
        Some("azureDevops") => "Azure DevOps",
        Some("gitlab") => "GitLab",
        _ => "Auto-Detect",
    }
}
