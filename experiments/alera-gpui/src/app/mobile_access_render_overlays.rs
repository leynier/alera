impl AleraApp {
    fn render_mobile_offers(
        &self,
        status: &MobileAccessStatus,
        cx: &mut Context<Self>,
    ) -> AnyElement {
        let rows = if status.active_pairings.is_empty() {
            vec![mobile_qr_empty_state(
                "No Active Offers",
                "Generate A Pairing QR To Link A New Device.",
            )]
        } else {
            status
                .active_pairings
                .iter()
                .enumerate()
                .map(|(index, offer)| {
                    let id = offer.id.clone();
                    let title = offer
                        .expected_device_name
                        .as_ref()
                        .map(|name| format!("{name} · {}", offer.endpoint))
                        .unwrap_or_else(|| offer.endpoint.clone());
                    div()
                        .flex()
                        .items_center()
                        .p_3()
                        .border_b_1()
                        .border_color(theme::border_subtle())
                        .child(qr_icon(16.0))
                        .child(
                            div()
                                .flex_1()
                                .ml_2()
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
                                        .text_color(theme::warning())
                                        .child(mobile_expiry_label(&offer.expires_at)),
                                ),
                        )
                        .child(
                            mobile_icon_button(
                                ("mobile-offer-cancel", index),
                                AleraIcon::Close,
                                theme::text_muted(),
                            )
                            .tooltip(|_, cx| cx.new(|_| Tooltip::new("Cancel Offer")).into())
                            .on_mouse_down(
                                MouseButton::Left,
                                cx.listener(move |this, _, _, cx| {
                                    this.mobile_access.overlay =
                                        Some(MobileOverlay::CancelOffer(id.clone()));
                                    cx.notify();
                                }),
                            ),
                        )
                })
                .collect()
        };
        mobile_settings_group(
            "Active Pairing Offers",
            "Pending offers waiting to be claimed. The QR for an existing offer cannot be shown again - cancel it and generate a new one.",
            rows,
        )
        .id(("settings-group-anchor", 2usize))
        .anchor_scroll(
            self.settings_group_anchors
                .get(&(crate::activity::SettingsPane::MobileDevices, 2))
                .cloned(),
        )
        .into_any_element()
    }

    fn render_mobile_devices(
        &self,
        status: &MobileAccessStatus,
        cx: &mut Context<Self>,
    ) -> AnyElement {
        let rows = if status.devices.is_empty() {
            vec![mobile_empty_state(
                AleraIcon::MobileDevice,
                "No Paired Devices",
                "Link A Device To See It Here.",
            )]
        } else {
            status
                .devices
                .iter()
                .enumerate()
                .map(|(index, device)| {
                    let revoked = device.revoked_at.is_some();
                    let id = device.id.clone();
                    let name = device.display_name.clone();
                    let detail = if let Some(revoked_at) = device.revoked_at.as_deref() {
                        format!("Revoked {}", mobile_timestamp(revoked_at))
                    } else if let Some(last_seen) = device.last_seen_at.as_deref() {
                        format!("Last Seen {}", mobile_timestamp(last_seen))
                    } else {
                        format!("Paired {}", mobile_timestamp(&device.paired_at))
                    };
                    let name_for_action = name.clone();
                    let revoke_id = id.clone();
                    let revoke_name = name_for_action.clone();
                    let delete_id = id.clone();
                    let delete_name = name_for_action.clone();
                    div()
                        .flex()
                        .items_center()
                        .p_3()
                        .border_b_1()
                        .border_color(theme::border_subtle())
                        .child(icon(
                            AleraIcon::MobileDevice,
                            16.0,
                            if revoked {
                                theme::text_faint()
                            } else {
                                theme::text_muted()
                            },
                        ))
                        .child(
                            div()
                                .flex_1()
                                .ml_2()
                                .child(
                                    div()
                                        .flex()
                                        .items_center()
                                        .gap_2()
                                        .child(
                                            div()
                                                .text_size(px(13.0))
                                                .font_weight(gpui::FontWeight::SEMIBOLD)
                                                .text_color(if revoked {
                                                    theme::text_muted()
                                                } else {
                                                    theme::text()
                                                })
                                                .child(name),
                                        )
                                        .when(revoked, |row| {
                                            row.child(mobile_revoked_badge())
                                        }),
                                )
                                .child(
                                    div()
                                        .mt_1()
                                        .text_size(px(12.0))
                                        .text_color(theme::text_muted())
                                        .child(detail),
                                ),
                        )
                        .when(!revoked, |row| {
                            let rename_id = id.clone();
                            let rename_name = name_for_action.clone();
                            row.child(
                                mobile_icon_button(
                                    ("mobile-device-edit", index),
                                    AleraIcon::Edit,
                                    theme::text_muted(),
                                )
                                .tooltip(|_, cx| {
                                    cx.new(|_| Tooltip::new("Rename Device")).into()
                                })
                                .on_mouse_down(
                                    MouseButton::Left,
                                    cx.listener(move |this, _, window, cx| {
                                        this.begin_mobile_rename(
                                            rename_id.clone(),
                                            rename_name.clone(),
                                            window,
                                            cx,
                                        );
                                    }),
                                ),
                            )
                            .child(
                                mobile_icon_button(
                                    ("mobile-device-revoke", index),
                                    AleraIcon::Delete,
                                    theme::danger(),
                                )
                                .tooltip(|_, cx| {
                                    cx.new(|_| Tooltip::new("Revoke Device")).into()
                                })
                                .on_mouse_down(
                                    MouseButton::Left,
                                    cx.listener(move |this, _, _, cx| {
                                        this.mobile_access.overlay =
                                            Some(MobileOverlay::RevokeDevice {
                                                id: revoke_id.clone(),
                                                display_name: revoke_name.clone(),
                                            });
                                        cx.notify();
                                    }),
                                ),
                            )
                        })
                        .when(revoked, |row| {
                            row.child(
                                mobile_icon_button(
                                    ("mobile-device-delete", index),
                                    AleraIcon::Delete,
                                    theme::danger(),
                                )
                                .tooltip(|_, cx| {
                                    cx.new(|_| Tooltip::new("Delete Device")).into()
                                })
                                .on_mouse_down(
                                    MouseButton::Left,
                                    cx.listener(move |this, _, _, cx| {
                                        this.mobile_access.overlay =
                                            Some(MobileOverlay::DeleteDevice {
                                                id: delete_id.clone(),
                                                display_name: delete_name.clone(),
                                            });
                                        cx.notify();
                                    }),
                                ),
                            )
                        })
                })
                .collect()
        };
        mobile_settings_group(
            "Paired Devices",
            "Devices that can connect to this runtime.",
            rows,
        )
        .id(("settings-group-anchor", 3usize))
        .anchor_scroll(
            self.settings_group_anchors
                .get(&(crate::activity::SettingsPane::MobileDevices, 3))
                .cloned(),
        )
        .into_any_element()
    }

    pub(super) fn render_mobile_access_overlay(&self, cx: &mut Context<Self>) -> AnyElement {
        let Some(overlay) = self.mobile_access.overlay.as_ref() else {
            return div().into_any_element();
        };
        let content = match overlay {
            MobileOverlay::PairingGrant(grant) => self.render_pairing_grant(grant, cx),
            MobileOverlay::RenameDevice { .. } => self.render_mobile_rename(cx),
            MobileOverlay::CancelOffer(_) => self.render_mobile_confirmation(
                "Cancel Pairing Offer",
                "The offer becomes unusable immediately.",
                "Cancel Offer",
                cx,
            ),
            MobileOverlay::RevokeDevice { display_name, .. } => self.render_mobile_confirmation(
                format!("Revoke {display_name}"),
                "The device loses access and active sessions disconnect immediately. This cannot be undone.",
                "Revoke",
                cx,
            ),
            MobileOverlay::DeleteDevice { display_name, .. } => self.render_mobile_confirmation(
                format!("Delete {display_name}"),
                "Permanently removes this revoked device record from the list. This cannot be undone.",
                "Delete",
                cx,
            ),
        };
        div()
            .absolute()
            .top_0()
            .right_0()
            .bottom_0()
            .left_0()
            .occlude()
            .flex()
            .items_center()
            .justify_center()
            .bg(theme::overlay_scrim())
            .child(content)
            .into_any_element()
    }

    fn render_pairing_grant(
        &self,
        grant: &MobilePairingGrant,
        cx: &mut Context<Self>,
    ) -> AnyElement {
        let expired = DateTime::parse_from_rfc3339(&grant.expires_at)
            .map(|value| value.with_timezone(&Utc) <= Utc::now())
            .unwrap_or(false);
        mobile_dialog(420.0)
            .child(mobile_dialog_header("Link Mobile Device", cx))
            .child(
                div()
                    .flex()
                    .justify_center()
                    .mt_4()
                    .child(if expired {
                        mobile_empty_state(
                            AleraIcon::MobileDevice,
                            "Offer Expired",
                            "Generate A New One.",
                        )
                    } else {
                        render_qr_code(&grant.raw_payload.to_string())
                    }),
            )
            .child(
                div()
                    .mt_4()
                    .text_center()
                    .font_weight(gpui::FontWeight::SEMIBOLD)
                    .child("Scan With The Alera Mobile App"),
            )
            .child(
                div()
                    .mt_1()
                    .text_center()
                    .text_size(px(12.0))
                    .text_color(theme::text_muted())
                    .child(format!("{} · {}", grant.host_name, grant.endpoint)),
            )
            .child(
                div()
                    .mt_1()
                    .text_center()
                    .text_size(px(12.0))
                    .text_color(if expired {
                        theme::danger()
                    } else {
                        theme::warning()
                    })
                    .child(if expired {
                        "Offer Expired".to_string()
                    } else {
                        mobile_expiry_label(&grant.expires_at)
                    }),
            )
            .child(
                div()
                    .flex()
                    .gap_2()
                    .mt_4()
                    .child(
                        mobile_dialog_button(
                            "mobile-grant-cancel",
                            AleraIcon::Close,
                            "Cancel Offer",
                            false,
                        )
                        .flex_1()
                        .on_mouse_down(
                            MouseButton::Left,
                            cx.listener(|this, _, window, cx| {
                                this.confirm_mobile_overlay(window, cx);
                            }),
                        ),
                    )
                    .child(
                        mobile_dialog_button(
                            "mobile-grant-copy",
                            AleraIcon::Copy,
                            if self.mobile_access.copied_pairing_json {
                                "Copied"
                            } else {
                                "Copy Pairing JSON"
                            },
                            true,
                        )
                        .flex_1()
                        .on_mouse_down(
                            MouseButton::Left,
                            cx.listener(|this, _, _, cx| {
                                this.copy_mobile_pairing_json(cx);
                            }),
                        ),
                    ),
            )
            .into_any_element()
    }

    fn render_mobile_rename(&self, cx: &mut Context<Self>) -> AnyElement {
        mobile_dialog(420.0)
            .child(mobile_dialog_header("Rename Device", cx))
            .child(
                div()
                    .mt_4()
                    .child(design_system::text_field(&self.mobile_access.rename_input)),
            )
            .child(
                div()
                    .flex()
                    .justify_end()
                    .gap_2()
                    .mt_4()
                    .child(
                        mobile_dialog_button("mobile-rename-cancel", AleraIcon::Close, "Cancel", false)
                            .on_mouse_down(
                                MouseButton::Left,
                                cx.listener(|this, _, _, cx| {
                                    this.close_mobile_overlay(cx);
                                }),
                            ),
                    )
                    .child(
                        mobile_dialog_button("mobile-rename-save", AleraIcon::Check, "Rename", true)
                            .on_mouse_down(
                                MouseButton::Left,
                                cx.listener(|this, _, window, cx| {
                                    this.confirm_mobile_overlay(window, cx);
                                }),
                            ),
                    ),
            )
            .into_any_element()
    }

    fn render_mobile_confirmation(
        &self,
        title: impl Into<gpui::SharedString>,
        message: &'static str,
        confirm_label: &'static str,
        cx: &mut Context<Self>,
    ) -> AnyElement {
        mobile_dialog(440.0)
            .child(mobile_dialog_header(title, cx))
            .child(
                div()
                    .mt_4()
                    .text_size(px(13.0))
                    .text_color(theme::text_muted())
                    .child(message),
            )
            .child(
                div()
                    .flex()
                    .justify_end()
                    .gap_2()
                    .mt_5()
                    .child(
                        mobile_dialog_button(
                            "mobile-confirm-cancel",
                            AleraIcon::Close,
                            "Cancel",
                            false,
                        )
                        .on_mouse_down(
                            MouseButton::Left,
                            cx.listener(|this, _, _, cx| {
                                this.close_mobile_overlay(cx);
                            }),
                        ),
                    )
                    .child(
                        mobile_dialog_button(
                            "mobile-confirm-action",
                            AleraIcon::Delete,
                            confirm_label,
                            true,
                        )
                        .on_mouse_down(
                            MouseButton::Left,
                            cx.listener(|this, _, window, cx| {
                                this.confirm_mobile_overlay(window, cx);
                            }),
                        ),
                    ),
            )
            .into_any_element()
    }
}

include!("mobile_access_components.rs");
