use gpui::{
    div, prelude::FluentBuilder as _, px, AnyElement, CursorStyle, InteractiveElement as _,
    IntoElement as _, MouseButton, MouseDownEvent, ParentElement as _, Styled as _,
};
use gpui_component::tooltip::Tooltip;
use qrcode::{Color, QrCode};

use crate::{
    activity::SettingsPane,
    design_system,
    icons::{icon, loading_indicator, AleraIcon},
    theme,
};

impl AleraApp {
    pub(super) fn render_mobile_devices_settings_pane(
        &self,
        cx: &mut Context<Self>,
    ) -> AnyElement {
        if self.mobile_access.loading && self.mobile_access.status.is_none() {
            return mobile_empty_state(
                AleraIcon::Loading,
                "Loading Mobile Access",
                "Reading Live Gateway And Device State.",
            )
            .into_any_element();
        }
        let Some(status) = self.mobile_access.status.as_ref() else {
            return mobile_empty_state(
                AleraIcon::MobileDevice,
                "Mobile Access Unavailable",
                self.mobile_access
                    .error
                    .clone()
                    .unwrap_or_else(|| "The Runtime Did Not Return Mobile Access State.".into()),
            )
            .into_any_element();
        };
        let settings = &status.settings;
        let mode = settings.displayed_mode();
        let mut gateway_rows = vec![
            mobile_settings_row(
                "Enable Mobile Access",
                "Accept connections from paired mobile devices.",
                self.mobile_switch(settings.enabled, cx),
            ),
            mobile_settings_row_width(
                "Connection Mode",
                match mode {
                    MobileEndpointMode::Loopback => "Only This Machine Can Reach The Gateway.",
                    MobileEndpointMode::Tailscale => {
                        "Devices On Your Tailnet Reach The Gateway Over Tailscale."
                    }
                    MobileEndpointMode::Manual => {
                        "Configure The Bind Host And Endpoint Yourself."
                    }
                },
                320.0,
                self.mobile_mode_control(mode, cx),
            ),
        ];
        if mode == MobileEndpointMode::Tailscale {
            gateway_rows.push(self.mobile_tailscale_row(status));
        }
        if mode == MobileEndpointMode::Manual {
            gateway_rows.push(mobile_settings_row(
                "Bind Host",
                "Interface the gateway listens on.",
                mobile_text_input(&self.mobile_access.bind_host_input, 220.0),
            ));
            if let Some(hint) = mobile_bind_host_hint(
                self.mobile_access.bind_host_input.read(cx).value().trim(),
                self.mobile_access.gateway_port,
            ) {
                gateway_rows.push(mobile_settings_row(
                    "Network Hint",
                    hint,
                    div().into_any_element(),
                ));
            }
        }
        gateway_rows.push(mobile_settings_row(
            "Port",
            "Gateway listener port.",
            self.mobile_number_control(true, &self.mobile_access.gateway_port_input, "", cx),
        ));
        gateway_rows.push(mobile_settings_row(
            "Apply Gateway Settings",
            "Persist gateway changes.",
            self.mobile_button(
                "mobile-apply-gateway",
                None,
                if self.mobile_access.busy {
                    "Applying…"
                } else {
                    "Apply"
                },
                true,
                cx.listener(|this, _, window, cx| {
                    this.update_mobile_settings(None, None, window, cx);
                }),
            ),
        ));

        let mut pairing_rows = Vec::new();
        if mode != MobileEndpointMode::Tailscale {
            pairing_rows.push(mobile_settings_row(
                "Endpoint",
                "Optional wss://host:port the phone connects to. Leave empty to use the bind host.",
                mobile_text_input(&self.mobile_access.endpoint_input, 320.0),
            ));
        }
        pairing_rows.push(mobile_settings_row(
            "Device Name",
            "Optional expected name for the new device.",
            mobile_text_input(&self.mobile_access.device_name_input, 220.0),
        ));
        pairing_rows.push(mobile_settings_row(
            "Expires In",
            "Minutes before the offer expires.",
            self.mobile_number_control(
                false,
                &self.mobile_access.expires_minutes_input,
                "min",
                cx,
            ),
        ));
        pairing_rows.push(mobile_settings_row(
            "Generate Pairing QR",
            "Enables the gateway if it is disabled.",
            self.mobile_button(
                "mobile-generate-pairing",
                Some(AleraIcon::MobileDevice),
                if self.mobile_access.busy {
                    "Generating…"
                } else {
                    "Generate"
                },
                true,
                cx.listener(|this, _, window, cx| {
                    this.generate_mobile_pairing(window, cx);
                }),
            ),
        ));

        div()
            .flex()
            .flex_col()
            .gap_4()
            .child(
                mobile_settings_group(
                    "Mobile Gateway",
                    "WebSocket listener the mobile companion app connects to. Applying changes restarts the gateway and disconnects connected devices.",
                    gateway_rows,
                )
                .id(("settings-group-anchor", 0usize))
                .anchor_scroll(
                    self.settings_group_anchors
                        .get(&(SettingsPane::MobileDevices, 0))
                        .cloned(),
                ),
            )
            .child(
                mobile_settings_group(
                    "Link A Device",
                    "Generates a one-time QR offer for the Alera mobile app. The QR is only shown at creation time.",
                    pairing_rows,
                )
                .id(("settings-group-anchor", 1usize))
                .anchor_scroll(
                    self.settings_group_anchors
                        .get(&(SettingsPane::MobileDevices, 1))
                        .cloned(),
                ),
            )
            .child(self.render_mobile_offers(status, cx))
            .child(self.render_mobile_devices(status, cx))
            .when_some(self.mobile_access.error.clone(), |pane, error| {
                pane.child(
                    div()
                        .text_size(px(12.0))
                        .text_color(theme::danger())
                        .child(error),
                )
            })
            .into_any_element()
    }

    fn mobile_switch(&self, enabled: bool, cx: &mut Context<Self>) -> AnyElement {
        design_system::switch(enabled, true)
            .id("mobile-enabled-switch")
            .on_mouse_down(
                MouseButton::Left,
                cx.listener(move |this, _: &MouseDownEvent, window, cx| {
                    this.update_mobile_settings(Some(!enabled), None, window, cx);
                    cx.stop_propagation();
                }),
            )
            .into_any_element()
    }

    fn mobile_mode_control(
        &self,
        selected: MobileEndpointMode,
        cx: &mut Context<Self>,
    ) -> AnyElement {
        div()
            .flex()
            .w(px(300.0))
            .h(px(34.0))
            .rounded_lg()
            .border_1()
            .border_color(theme::border())
            .overflow_hidden()
            .children(
                [
                    (MobileEndpointMode::Loopback, "This Device"),
                    (MobileEndpointMode::Tailscale, "Tailscale"),
                    (MobileEndpointMode::Manual, "Manual"),
                ]
                .into_iter()
                .enumerate()
                .map(|(index, (mode, label))| {
                    div()
                        .id(("mobile-mode", index))
                        .flex()
                        .items_center()
                        .justify_center()
                        .flex_1()
                        .h_full()
                        .border_r_1()
                        .border_color(theme::border_subtle())
                        .when(mode == selected, |item| {
                            item.bg(theme::surface_raised()).text_color(theme::text())
                        })
                        .when(mode != selected, |item| item.text_color(theme::text_muted()))
                        .cursor(CursorStyle::PointingHand)
                        .on_mouse_down(
                            MouseButton::Left,
                            cx.listener(move |this, _: &MouseDownEvent, window, cx| {
                                this.update_mobile_settings(None, Some(mode), window, cx);
                                cx.stop_propagation();
                            }),
                        )
                        .child(label)
                }),
            )
            .into_any_element()
    }

    fn mobile_tailscale_row(&self, status: &MobileAccessStatus) -> gpui::Div {
        let (active, label, description) = match status.tailscale.as_ref() {
            None => (
                false,
                "Unknown".to_string(),
                "The Runtime Does Not Report Tailscale - Update The Alera CLI.".to_string(),
            ),
            Some(tailscale) if !tailscale.detected => (
                false,
                "Not Detected".to_string(),
                "Install Tailscale On This Machine To Use This Mode.".to_string(),
            ),
            Some(tailscale) if !tailscale.running => (
                false,
                "Not Running".to_string(),
                tailscale
                    .error
                    .clone()
                    .unwrap_or_else(|| "Run \"tailscale up\" And Sign In To Your Tailnet.".into()),
            ),
            Some(tailscale) if tailscale.tailnet_ip.is_some() => (
                true,
                format!(
                    "Running · {}",
                    tailscale.tailnet_ip.as_deref().unwrap_or_default()
                ),
                "Devices Signed In To The Same Tailnet Can Pair And Connect.".to_string(),
            ),
            Some(_) => (
                false,
                "No Tailnet IP".to_string(),
                "Tailscale Is Running But Reported No Tailnet IPv4 Address.".to_string(),
            ),
        };
        mobile_settings_row(
            "Tailscale Status",
            description,
            div()
                .flex()
                .items_center()
                .gap_2()
                .child(
                    div()
                        .w(px(8.0))
                        .h(px(8.0))
                        .rounded_full()
                        .bg(if active {
                            theme::success()
                        } else {
                            theme::text_faint()
                        }),
                )
                .child(mobile_badge(label))
                .into_any_element(),
        )
    }

    fn mobile_number_control(
        &self,
        port: bool,
        input: &Entity<InputState>,
        suffix: &'static str,
        cx: &mut Context<Self>,
    ) -> AnyElement {
        div()
            .flex()
            .items_center()
            .w(px(220.0))
            .h(px(48.0))
            .gap_2()
            .child(
                div()
                    .flex_1()
                    .h_full()
                    .child(
                        design_system::text_field(input)
                            .height(px(48.0))
                            .suffix(
                            div()
                                .mr_1()
                                .text_size(px(11.0))
                                .text_color(theme::text_muted())
                                .child(suffix),
                            ),
                    ),
            )
            .child(
                div()
                    .flex()
                    .flex_col()
                    .w(px(26.0))
                    .h(px(36.0))
                    .child(
                        div()
                            .id(if port {
                                "mobile-port-up"
                            } else {
                                "mobile-expiry-up"
                            })
                            .flex()
                            .items_center()
                            .justify_center()
                            .flex_1()
                            .border_1()
                            .border_color(theme::border())
                            .cursor(CursorStyle::PointingHand)
                            .on_mouse_down(
                                MouseButton::Left,
                                cx.listener(move |this, _: &MouseDownEvent, window, cx| {
                                    this.adjust_mobile_number(port, 1, window, cx);
                                    cx.stop_propagation();
                                }),
                            )
                            .child(icon(AleraIcon::ChevronUp, 14.0, theme::text_muted())),
                    )
                    .child(
                        div()
                            .id(if port {
                                "mobile-port-down"
                            } else {
                                "mobile-expiry-down"
                            })
                            .flex()
                            .items_center()
                            .justify_center()
                            .flex_1()
                            .border_1()
                            .border_color(theme::border())
                            .cursor(CursorStyle::PointingHand)
                            .on_mouse_down(
                                MouseButton::Left,
                                cx.listener(move |this, _: &MouseDownEvent, window, cx| {
                                    this.adjust_mobile_number(port, -1, window, cx);
                                    cx.stop_propagation();
                                }),
                            )
                            .child(icon(AleraIcon::ChevronDown, 14.0, theme::text_muted())),
                    ),
            )
            .into_any_element()
    }

    fn mobile_button(
        &self,
        id: &'static str,
        icon_kind: Option<AleraIcon>,
        label: &'static str,
        filled: bool,
        listener: impl Fn(&MouseDownEvent, &mut Window, &mut gpui::App) + 'static,
    ) -> AnyElement {
        div()
            .id(id)
            .flex()
            .items_center()
            .justify_center()
            .h(px(34.0))
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
            .cursor(CursorStyle::PointingHand)
            .hover(|style| style.bg(theme::surface_raised()))
            .when(self.mobile_access.busy, |button| {
                button.child(loading_indicator(
                    16.0,
                    if filled {
                        theme::on_accent()
                    } else {
                        theme::text()
                    },
                ))
            })
            .when(!self.mobile_access.busy, |button| {
                button.when_some(icon_kind, |button, icon_kind| {
                    button.child(if icon_kind == AleraIcon::MobileDevice {
                        qr_icon(16.0).into_any_element()
                    } else {
                        icon(
                            icon_kind,
                            16.0,
                            if filled {
                                theme::on_accent()
                            } else {
                                theme::text()
                            },
                        )
                    })
                })
            })
            .text_color(if filled {
                theme::on_accent()
            } else {
                theme::text()
            })
            .child(label)
            .on_mouse_down(MouseButton::Left, listener)
            .into_any_element()
    }
}

include!("mobile_access_render_overlays.rs");
