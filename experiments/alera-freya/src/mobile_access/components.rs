use chrono::{DateTime, Utc};
use freya::{clipboard::Clipboard, prelude::*};
use qrcode::{Color as QrColor, QrCode};
use serde_json::json;

use crate::{BORDER, FAINT, MUTED, SURFACE, SURFACE_RAISED, TEXT};

use super::MobileSignals;
use super::actions::run_request;
use super::model::{MobileOverlay, expiry_label};
use alera_desktop_core::RuntimeBridge;

pub(super) fn mode_selector(mut mode: State<String>) -> Element {
    let selected = mode.read().clone();
    mobile_row_shell(
        "Endpoint Mode",
        "Choose how the mobile app reaches this runtime.",
    )
    .child(
        rect().horizontal().spacing(4.).children(
            [
                ("loopback", "This Device"),
                ("tailscale", "Tailscale"),
                ("manual", "Manual"),
            ]
            .into_iter()
            .map(|(value, text)| {
                Button::new()
                    .compact()
                    .maybe(selected == value, Button::filled)
                    .on_press(move |_| mode.set(value.to_string()))
                    .child(text)
            }),
        ),
    )
    .into_element()
}

pub(super) fn mobile_overlay(
    overlay: MobileOverlay,
    bridge: RuntimeBridge,
    signals: MobileSignals,
    rename_value: State<String>,
) -> Element {
    let mut overlay_for_close = signals.overlay;
    let content = match overlay {
        MobileOverlay::PairingGrant(grant) => {
            let raw = grant.raw_payload.to_string();
            let raw_for_copy = raw.clone();
            let pairing_id = grant.pairing_id.clone();
            let bridge_for_cancel = bridge.clone();
            let expired = DateTime::parse_from_rfc3339(&grant.expires_at)
                .map(|value| value.with_timezone(&Utc) <= Utc::now())
                .unwrap_or(false);
            rect()
                .vertical()
                .spacing(10.)
                .child(
                    label()
                        .font_size(15.)
                        .color(TEXT)
                        .text("Link Mobile Device"),
                )
                .child(if expired {
                    mobile_empty("Offer Expired")
                } else {
                    qr_element(&raw)
                })
                .child(
                    label()
                        .font_size(11.)
                        .color(TEXT)
                        .text("Scan With The Alera Mobile App"),
                )
                .child(
                    label()
                        .font_size(10.)
                        .color(MUTED)
                        .text(format!("{} - {}", grant.host_name, grant.endpoint)),
                )
                .child(label().font_size(10.).color(MUTED).text(if expired {
                    "Offer Expired".to_string()
                } else {
                    expiry_label(&grant.expires_at)
                }))
                .child(
                    rect()
                        .horizontal()
                        .spacing(8.)
                        .child(
                            Button::new()
                                .width(Size::flex(1.))
                                .outline()
                                .on_press(move |_| {
                                    run_request(
                                        bridge_for_cancel.clone(),
                                        "mobile.pairing.cancel",
                                        json!({"id": pairing_id}),
                                        signals,
                                        true,
                                    );
                                })
                                .child("Cancel Offer"),
                        )
                        .child(
                            Button::new()
                                .width(Size::flex(1.))
                                .filled()
                                .on_press(move |_| {
                                    let _ = Clipboard::set(raw_for_copy.clone());
                                })
                                .child("Copy Pairing JSON"),
                        ),
                )
                .into_element()
        }
        MobileOverlay::Rename { id, current_name } => {
            let bridge_for_save = bridge.clone();
            rect()
                .vertical()
                .spacing(10.)
                .child(label().font_size(15.).color(TEXT).text("Rename Device"))
                .child(Input::new(rename_value).width(Size::fill()).filled())
                .child(
                    Button::new()
                        .filled()
                        .on_press(move |_| {
                            let name = rename_value.read().trim().to_string();
                            if !name.is_empty() && name != current_name {
                                run_request(
                                    bridge_for_save.clone(),
                                    "mobile.device.rename",
                                    json!({"id": id, "displayName": name}),
                                    signals,
                                    true,
                                );
                            }
                        })
                        .child("Rename"),
                )
                .into_element()
        }
        MobileOverlay::Confirm {
            title,
            message,
            verb,
            payload,
        } => rect()
            .vertical()
            .spacing(10.)
            .child(label().font_size(15.).color(TEXT).text(title))
            .child(
                label()
                    .font_size(11.)
                    .color(MUTED)
                    .max_lines(4)
                    .text(message),
            )
            .child(
                Button::new()
                    .filled()
                    .on_press(move |_| {
                        run_request(bridge.clone(), verb, payload.clone(), signals, true);
                    })
                    .child("Confirm"),
            )
            .into_element(),
    };
    rect()
        .position(
            Position::new_absolute()
                .top(0.)
                .right(0.)
                .bottom(0.)
                .left(0.),
        )
        .layer(Layer::Overlay)
        .background(Color::from_af32rgb(0.72, 0, 0, 0))
        .center()
        .child(
            rect()
                .width(Size::px(430.))
                .padding(Gaps::new_all(20.))
                .vertical()
                .spacing(12.)
                .background(SURFACE)
                .border(Border::new().width(1.).fill(BORDER))
                .corner_radius(8.)
                .child(content)
                .child(
                    Button::new()
                        .flat()
                        .on_press(move |_| overlay_for_close.set(None))
                        .child("Close"),
                ),
        )
        .into_element()
}

fn qr_element(payload: &str) -> Element {
    let Ok(code) = QrCode::new(payload.as_bytes()) else {
        return mobile_message("Could Not Render Pairing QR", false);
    };
    let width = code.width();
    let colors = code.to_colors();
    rect()
        .padding(Gaps::new_all(10.))
        .background((255, 255, 255))
        .vertical()
        .children((0..width).map(|row| {
            rect().horizontal().children((0..width).map(|column| {
                rect().width(Size::px(3.)).height(Size::px(3.)).background(
                    if colors[row * width + column] == QrColor::Dark {
                        (0, 0, 0)
                    } else {
                        (255, 255, 255)
                    },
                )
            }))
        }))
        .into_element()
}

pub(super) fn mobile_card(title: &'static str) -> Rect {
    rect()
        .width(Size::fill())
        .vertical()
        .spacing(1.)
        .background(SURFACE_RAISED)
        .border(Border::new().width(1.).fill(BORDER))
        .corner_radius(7.)
        .child(
            label()
                .padding(Gaps::new(12., 8., 12., 8.))
                .font_size(12.)
                .color(TEXT)
                .text(title),
        )
}

pub(super) fn mobile_row_shell(title: &'static str, description: &'static str) -> Rect {
    rect()
        .width(Size::fill())
        .min_height(Size::px(58.))
        .horizontal()
        .content(Content::Flex)
        .cross_align(Alignment::Center)
        .spacing(8.)
        .padding(Gaps::new_all(10.))
        .child(
            rect()
                .width(Size::flex(1.))
                .vertical()
                .spacing(3.)
                .child(label().font_size(11.).color(TEXT).text(title))
                .child(label().font_size(9.).color(MUTED).text(description)),
        )
}

pub(super) fn mobile_item_row(title: String, subtitle: String) -> Rect {
    rect()
        .width(Size::fill())
        .min_height(Size::px(54.))
        .horizontal()
        .content(Content::Flex)
        .cross_align(Alignment::Center)
        .spacing(6.)
        .padding(Gaps::new_all(10.))
        .background(SURFACE_RAISED)
        .child(
            rect()
                .width(Size::flex(1.))
                .vertical()
                .spacing(3.)
                .child(label().font_size(11.).color(TEXT).text(title))
                .child(label().font_size(9.).color(MUTED).text(subtitle)),
        )
}

pub(super) fn toggle_control(enabled: bool, mut action: impl FnMut() + 'static) -> Element {
    crate::settings_switch::control(enabled, true, move |event| {
        event.stop_propagation();
        action();
    })
}

pub(super) fn overlay_button(
    label_text: &'static str,
    overlay: MobileOverlay,
    mut overlay_state: State<Option<MobileOverlay>>,
) -> Element {
    Button::new()
        .compact()
        .flat()
        .on_press(move |_| overlay_state.set(Some(overlay.clone())))
        .child(label_text)
        .into_element()
}

pub(super) fn mobile_message(text: impl Into<String>, loading: bool) -> Element {
    rect()
        .height(Size::px(100.))
        .center()
        .horizontal()
        .spacing(8.)
        .maybe_child(loading.then(|| CircularLoader::new().size(14.)))
        .child(label().font_size(11.).color(MUTED).text(text.into()))
        .into_element()
}

pub(super) fn mobile_empty(text: &'static str) -> Element {
    rect()
        .height(Size::px(54.))
        .center()
        .background(SURFACE_RAISED)
        .child(label().font_size(10.).color(FAINT).text(text))
        .into_element()
}
