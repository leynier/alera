fn mobile_settings_group(
    title: &'static str,
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
                .overflow_hidden()
                .rounded_lg()
                .border_1()
                .border_color(theme::border_subtle())
                .bg(theme::surface_selected())
                .children(rows),
        )
}

fn mobile_settings_row(
    title: &'static str,
    description: impl Into<gpui::SharedString>,
    control: impl gpui::IntoElement,
) -> gpui::Div {
    mobile_settings_row_width(title, description, 220.0, control)
}

fn mobile_settings_row_width(
    title: &'static str,
    description: impl Into<gpui::SharedString>,
    control_width: f32,
    control: impl gpui::IntoElement,
) -> gpui::Div {
    div()
        .flex()
        .items_center()
        // Match Flutter's AleraSettingRow: two body lines plus 16 px vertical
        // padding settle at the same 66 px floor as the shared settings rows.
        .min_h(px(66.0))
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

fn mobile_text_input(input: &Entity<InputState>, width: f32) -> AnyElement {
    div()
        .w(px(width))
        .h(px(34.0))
        .child(design_system::text_field(input).height(px(34.0)))
        .into_any_element()
}

fn mobile_empty_state(
    icon_kind: AleraIcon,
    title: impl Into<gpui::SharedString>,
    message: impl Into<gpui::SharedString>,
) -> gpui::Div {
    div()
        .flex()
        .flex_col()
        .items_center()
        .justify_center()
        .min_h(px(132.0))
        .p_6()
        .child(icon(icon_kind, 28.0, theme::text_faint()))
        .child(
            div()
                .mt_3()
                .text_size(px(14.0))
                .font_weight(gpui::FontWeight::SEMIBOLD)
                .child(title.into()),
        )
        .child(
            div()
                .mt_2()
                .text_size(px(13.0))
                .text_color(theme::text_muted())
                .child(message.into()),
        )
}

fn mobile_badge(label: impl Into<gpui::SharedString>) -> gpui::Div {
    div()
        .px_2()
        .py(px(2.0))
        .rounded_full()
        .bg(theme::surface_raised())
        .text_size(px(11.0))
        .text_color(theme::text_muted())
        .child(label.into())
}

fn mobile_revoked_badge() -> gpui::Div {
    div()
        .px_2()
        .py(px(2.0))
        .rounded_full()
        .bg(theme::danger())
        .text_size(px(11.0))
        .font_weight(gpui::FontWeight::MEDIUM)
        .text_color(theme::on_danger())
        .child("Revoked")
}

fn mobile_qr_empty_state(
    title: impl Into<gpui::SharedString>,
    message: impl Into<gpui::SharedString>,
) -> gpui::Div {
    div()
        .flex()
        .flex_col()
        .items_center()
        .justify_center()
        .min_h(px(132.0))
        .p_6()
        .child(icon(AleraIcon::QrCode, 28.0, theme::text_faint()))
        .child(
            div()
                .mt_3()
                .text_size(px(14.0))
                .font_weight(gpui::FontWeight::SEMIBOLD)
                .child(title.into()),
        )
        .child(
            div()
                .mt_2()
                .text_size(px(13.0))
                .text_color(theme::text_muted())
                .child(message.into()),
        )
}

fn mobile_icon_button(
    id: impl Into<gpui::ElementId>,
    icon_kind: AleraIcon,
    color: gpui::Rgba,
) -> gpui::Stateful<gpui::Div> {
    div()
        .id(id)
        .focusable()
        .tab_stop(true)
        .role(Role::Button)
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

fn mobile_dialog(width: f32) -> gpui::Div {
    div()
        .w(px(width))
        .rounded_xl()
        .border_1()
        .border_color(theme::border())
        .bg(theme::surface_raised())
        .shadow_lg()
        .p_5()
}

fn mobile_dialog_header(
    title: impl Into<gpui::SharedString>,
    cx: &mut Context<AleraApp>,
) -> gpui::Div {
    div()
        .flex()
        .items_center()
        .child(
            div()
                .flex_1()
                .text_size(px(16.0))
                .font_weight(gpui::FontWeight::SEMIBOLD)
                .child(title.into()),
        )
        .child(
            mobile_icon_button(
                "mobile-dialog-close",
                AleraIcon::Close,
                theme::text_muted(),
            )
            .aria_label("Close")
            .on_click(
                cx.listener(|this, _, _, cx| {
                    this.close_mobile_overlay(cx);
                    cx.stop_propagation();
                }),
            ),
        )
}

fn mobile_dialog_button(
    id: &'static str,
    icon_kind: AleraIcon,
    label: &'static str,
    filled: bool,
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
        .child(icon(
            icon_kind,
            16.0,
            if filled {
                theme::on_accent()
            } else {
                theme::text()
            },
        ))
        .child(label)
}

fn render_qr_code(payload: &str) -> gpui::Div {
    let Ok(code) = QrCode::new(payload.as_bytes()) else {
        return mobile_empty_state(
            AleraIcon::Error,
            "QR Unavailable",
            "Copy The Pairing JSON Instead.",
        );
    };
    let width = code.width();
    let module = 240.0 / (width + 8) as f32;
    div()
        .flex()
        .flex_col()
        .p(px(module * 4.0))
        .bg(gpui::white())
        .children((0..width).map(|y| {
            div().flex().children((0..width).map(|x| {
                div()
                    .w(px(module))
                    .h(px(module))
                    .bg(if code[(x, y)] == Color::Dark {
                        gpui::black()
                    } else {
                        gpui::white()
                    })
            }))
        }))
}

fn mobile_bind_host_hint(bind_host: &str, port: u16) -> Option<String> {
    if is_wildcard_host(bind_host) {
        Some(format!(
            "Wildcard Bind Hosts Require An Explicit wss:// Endpoint When Linking (For Example wss://<host-or-vpn-name>:{port})"
        ))
    } else if !is_loopback_host(bind_host) {
        Some(
            "Devices Outside This Machine Must Connect Through wss:// - Use A TLS Proxy Or A VPN Address And Provide A Custom Endpoint".into(),
        )
    } else {
        None
    }
}
