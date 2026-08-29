use gpui::{
    div, prelude::FluentBuilder as _, px, AnyElement, ClickEvent, CursorStyle,
    InteractiveElement as _, IntoElement as _, ParentElement as _, Role,
    Styled as _, Toggled,
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
            mobile_settings_row(
                "Enable Remote Access",
                "Allow signed-in Alera mobile devices to discover this runtime and use the encrypted relay.",
                self.mobile_remote_switch(settings.remote_access_enabled, cx),
            ),
            mobile_settings_row_width(
                "Connection Mode",
                match mode {
                    MobileEndpointMode::Loopback => "Only This Machine Can Reach The Gateway.",
                    MobileEndpointMode::Tailscale => {
                        "Devices On Your Tailnet Reach The Gateway Over Tailscale."
                    }
                    MobileEndpointMode::Netbird => {
                        "Devices On Your NetBird Network Reach The Gateway Over NetBird."
                    }
                    MobileEndpointMode::Manual => {
                        "Configure The Bind Host And Endpoint Yourself."
                    }
                },
                320.0,
                        self.mobile_mode_control(mode, status.netbird.is_some(), cx),
            ),
        ];
        if mode == MobileEndpointMode::Tailscale {
            gateway_rows.push(self.mobile_tailscale_row(status));
        }
        if mode == MobileEndpointMode::Netbird {
            gateway_rows.push(self.mobile_netbird_row(status));
            gateway_rows.push(self.mobile_netbird_endpoint_row(status, cx));
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
                    this.update_mobile_settings(None, None, None, window, cx);
                }),
            ),
        ));

        let mut pairing_rows = Vec::new();
        if !matches!(mode, MobileEndpointMode::Tailscale | MobileEndpointMode::Netbird) {
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
                Some(AleraIcon::QrCode),
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
            .focusable()
            .tab_stop(true)
            .role(Role::Switch)
            .aria_label("Enable Mobile Access")
            .aria_toggled(if enabled {
                Toggled::True
            } else {
                Toggled::False
            })
            .on_click(
                cx.listener(move |this, _, window, cx| {
                    this.update_mobile_settings(Some(!enabled), None, None, window, cx);
                    cx.stop_propagation();
                }),
            )
            .into_any_element()
    }

    fn mobile_remote_switch(&self, enabled: bool, cx: &mut Context<Self>) -> AnyElement {
        design_system::switch(enabled, true)
            .id("mobile-remote-enabled-switch")
            .focusable()
            .tab_stop(true)
            .role(Role::Switch)
            .aria_label("Enable Remote Access")
            .aria_toggled(if enabled {
                Toggled::True
            } else {
                Toggled::False
            })
            .on_click(cx.listener(move |this, _, window, cx| {
                this.update_mobile_remote_access(!enabled, window, cx);
                cx.stop_propagation();
            }))
            .into_any_element()
    }

    fn mobile_mode_control(
        &self,
        selected: MobileEndpointMode,
        netbird_available: bool,
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
                {
                    let mut modes = vec![
                        (MobileEndpointMode::Loopback, "This Device"),
                        (MobileEndpointMode::Tailscale, "Tailscale"),
                    ];
                    if netbird_available {
                        modes.push((MobileEndpointMode::Netbird, "NetBird"));
                    }
                    modes.push((MobileEndpointMode::Manual, "Manual"));
                    modes
                }
                .into_iter()
                .enumerate()
                .map(|(index, (mode, label))| {
                    div()
                        .id(("mobile-mode", index))
                        .focusable()
                        .tab_stop(true)
                        .role(Role::RadioButton)
                        .aria_label(label)
                        .aria_selected(mode == selected)
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
                        .on_click(
                            cx.listener(move |this, _, window, cx| {
                                this.update_mobile_settings(None, Some(mode), None, window, cx);
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

    fn mobile_netbird_endpoint_row(
        &self,
        status: &MobileAccessStatus,
        cx: &mut Context<Self>,
    ) -> gpui::Div {
        let selected = status.settings.netbird_endpoint;
        let netbird = status.netbird.as_ref();
        let mut modes = vec![(MobileNetbirdEndpoint::Ip, "IP Address".to_string())];
        if netbird.and_then(|value| value.dns_hostname.as_ref()).is_some()
            || selected == MobileNetbirdEndpoint::Dns
        {
            modes.push((MobileNetbirdEndpoint::Dns, "DNS Hostname".to_string()));
        }
        if let Some(interface) = netbird.and_then(|value| value.interface_name.clone()) {
            modes.push((
                MobileNetbirdEndpoint::Interface,
                format!("Interface ({interface})"),
            ));
        } else if selected == MobileNetbirdEndpoint::Interface {
            modes.push((
                MobileNetbirdEndpoint::Interface,
                "Private Interface".to_string(),
            ));
        }
        mobile_settings_row_width(
            "NetBird Endpoint",
            "Address included in new pairing offers.",
            360.0,
            div()
                .flex()
                .h(px(34.0))
                .rounded_lg()
                .border_1()
                .border_color(theme::border())
                .overflow_hidden()
                .children(modes.into_iter().enumerate().map(|(index, (mode, label))| {
                    div()
                        .id(("mobile-netbird-endpoint", index))
                        .focusable()
                        .tab_stop(!self.mobile_access.busy)
                        .role(Role::RadioButton)
                        .aria_label(label.clone())
                        .aria_selected(mode == selected)
                        .flex()
                        .items_center()
                        .justify_center()
                        .flex_1()
                        .px_2()
                        .when(mode == selected, |item| {
                            item.bg(theme::surface_raised()).text_color(theme::text())
                        })
                        .when(mode != selected, |item| item.text_color(theme::text_muted()))
                        .cursor(CursorStyle::PointingHand)
                        .on_click(cx.listener(move |this, _, window, cx| {
                            this.update_mobile_settings(
                                None,
                                None,
                                Some(mode),
                                window,
                                cx,
                            );
                        }))
                        .child(label)
                })),
        )
    }

    fn mobile_netbird_row(&self, status: &MobileAccessStatus) -> gpui::Div {
        let (active, label, description) = match status.netbird.as_ref() {
            None => (
                false,
                "Unknown".to_string(),
                "The Runtime Does Not Report NetBird - Update The Alera CLI.".to_string(),
            ),
            Some(netbird) if !netbird.detected => (
                false,
                "Not Detected".to_string(),
                "Install NetBird On This Machine To Use This Mode.".to_string(),
            ),
            Some(netbird) if !netbird.connected => (
                false,
                "Not Connected".to_string(),
                netbird.error.clone().unwrap_or_else(|| {
                    "Run \"netbird up\" And Sign In To Your Network.".to_string()
                }),
            ),
            Some(netbird) if netbird.netbird_ip.is_some() => (
                true,
                format!(
                    "Connected · {}",
                    netbird.netbird_ip.as_deref().unwrap_or_default()
                ),
                "Devices Connected To The Same NetBird Network Can Pair And Connect."
                    .to_string(),
            ),
            Some(_) => (
                false,
                "No NetBird IP".to_string(),
                "NetBird Is Connected But Reported No NetBird IPv4 Address.".to_string(),
            ),
        };
        mobile_settings_row(
            "NetBird Status",
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
                            .focusable()
                            .tab_stop(true)
                            .role(Role::Button)
                            .aria_label(if port {
                                "Increase Port"
                            } else {
                                "Increase Expires In"
                            })
                            .flex()
                            .items_center()
                            .justify_center()
                            .flex_1()
                            .border_1()
                            .border_color(theme::border())
                            .cursor(CursorStyle::PointingHand)
                            .on_click(
                                cx.listener(move |this, _, window, cx| {
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
                            .focusable()
                            .tab_stop(true)
                            .role(Role::Button)
                            .aria_label(if port {
                                "Decrease Port"
                            } else {
                                "Decrease Expires In"
                            })
                            .flex()
                            .items_center()
                            .justify_center()
                            .flex_1()
                            .border_1()
                            .border_color(theme::border())
                            .cursor(CursorStyle::PointingHand)
                            .on_click(
                                cx.listener(move |this, _, window, cx| {
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
        listener: impl Fn(&ClickEvent, &mut Window, &mut gpui::App) + 'static,
    ) -> AnyElement {
        div()
            .id(id)
            .focusable()
            .tab_stop(!self.mobile_access.busy)
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
                    button.child(icon(
                        icon_kind,
                        16.0,
                        if filled {
                            theme::on_accent()
                        } else {
                            theme::text()
                        },
                    ))
                })
            })
            .text_color(if filled {
                theme::on_accent()
            } else {
                theme::text()
            })
            .child(label)
            .on_click(listener)
            .into_any_element()
    }
}

include!("mobile_access_render_overlays.rs");
