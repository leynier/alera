use std::time::Duration;

use alera_desktop_core::RuntimeBridge;
use freya::prelude::*;
use serde_json::json;

use crate::MUTED;

mod actions;
mod components;
mod model;

use actions::{create_pairing, run_request};
use components::{
    mobile_card, mobile_empty, mobile_item_row, mobile_message, mobile_overlay, mobile_row_shell,
    mode_selector, overlay_button, toggle_control,
};
use model::{MobileAccessStatus, MobileOverlay, expiry_label, timestamp};

#[derive(Clone, Copy)]
struct MobileSignals {
    busy: State<bool>,
    message: State<Option<String>>,
    revision: State<u64>,
    overlay: State<Option<MobileOverlay>>,
}

pub fn settings_content(active: bool, bridge: RuntimeBridge) -> Element {
    let status = use_state(|| None::<Result<MobileAccessStatus, String>>);
    let revision = use_state(|| 0_u64);
    let busy = use_state(|| false);
    let message = use_state(|| None::<String>);
    let overlay = use_state(|| None::<MobileOverlay>);
    let bind_host = use_state(|| "127.0.0.1".to_string());
    let port = use_state(|| "6768".to_string());
    let endpoint = use_state(String::new);
    let device_name = use_state(String::new);
    let expires_minutes = use_state(|| "10".to_string());
    let rename_value = use_state(String::new);
    let mode = use_state(|| "loopback".to_string());
    let signals = MobileSignals {
        busy,
        message,
        revision,
        overlay,
    };

    let deps = (active, *revision.read());
    let status_bridge = bridge.clone();
    let mut status_for_load = status;
    use_side_effect_with_deps(&deps, move |(active, _)| {
        if !*active {
            return;
        }
        let bridge = status_bridge.clone();
        spawn(async move {
            let result = bridge
                .request_with_timeout("mobile.status.get", json!({}), Duration::from_secs(10))
                .await
                .and_then(|value| {
                    serde_json::from_value(value)
                        .map_err(|error| format!("Mobile Access Unavailable: {error}"))
                });
            status_for_load.set(Some(result));
        });
    });
    let seed = status
        .read()
        .as_ref()
        .and_then(|result| result.as_ref().ok())
        .map(|status| {
            (
                status.settings.bind_host.clone(),
                status.settings.port,
                status.settings.endpoint_mode.clone(),
            )
        });
    let mut bind_for_seed = bind_host;
    let mut port_for_seed = port;
    let mut mode_for_seed = mode;
    use_side_effect_with_deps(&seed, move |seed| {
        let Some((bind, gateway_port, endpoint_mode)) = seed else {
            return;
        };
        bind_for_seed.set(bind.clone());
        port_for_seed.set(gateway_port.to_string());
        mode_for_seed.set(if endpoint_mode.is_empty() {
            "loopback".to_string()
        } else {
            endpoint_mode.clone()
        });
    });

    let content = match status.read().as_ref() {
        None => mobile_message("Loading Mobile Access", true),
        Some(Err(error)) => mobile_message(error, false),
        Some(Ok(snapshot)) => mobile_status_view(
            snapshot.clone(),
            bridge.clone(),
            signals,
            bind_host,
            port,
            endpoint,
            device_name,
            expires_minutes,
            rename_value,
            mode,
        ),
    };
    rect()
        .width(Size::fill())
        .vertical()
        .spacing(10.)
        .child(content)
        .maybe_child(message.read().clone().map(|message| {
            label()
                .font_size(10.)
                .color(MUTED)
                .max_lines(4)
                .text(message)
        }))
        .maybe_child(
            overlay
                .read()
                .clone()
                .map(|overlay| mobile_overlay(overlay, bridge, signals, rename_value)),
        )
        .into_element()
}

#[allow(clippy::too_many_arguments)]
fn mobile_status_view(
    status: MobileAccessStatus,
    bridge: RuntimeBridge,
    signals: MobileSignals,
    bind_host: State<String>,
    port: State<String>,
    endpoint: State<String>,
    device_name: State<String>,
    expires_minutes: State<String>,
    rename_value: State<String>,
    mode: State<String>,
) -> Element {
    let enabled = status.settings.enabled;
    let bridge_for_toggle = bridge.clone();
    let signals_for_toggle = signals;
    let mut rows = rect()
        .width(Size::fill())
        .vertical()
        .spacing(10.)
        .child(
            mobile_card("Mobile Gateway")
                .child(
                    mobile_row_shell(
                        "Enable Mobile Access",
                        "Accept connections from paired mobile devices.",
                    )
                    .child(toggle_control(enabled, move || {
                        run_request(
                            bridge_for_toggle.clone(),
                            "mobile.settings.update",
                            json!({"enabled": !enabled}),
                            signals_for_toggle,
                            true,
                        );
                    })),
                )
                .child(mode_selector(mode))
                .child(
                    mobile_row_shell(
                        "Bind Host And Port",
                        "Applying changes restarts the gateway and disconnects connected devices.",
                    )
                    .child(
                        Input::new(bind_host)
                            .width(Size::px(180.))
                            .compact()
                            .filled(),
                    )
                    .child(Input::new(port).width(Size::px(90.)).compact().filled())
                    .child(
                        Button::new()
                            .compact()
                            .outline()
                            .on_press({
                                let bridge = bridge.clone();
                                move |_| {
                                    let Ok(port) = port.read().trim().parse::<u16>() else {
                                        let mut message = signals.message;
                                        message.set(Some(
                                            "Port Must Be Between 1 And 65535".to_string(),
                                        ));
                                        return;
                                    };
                                    run_request(
                                        bridge.clone(),
                                        "mobile.settings.update",
                                        json!({
                                            "bindHost": bind_host.read().trim(),
                                            "port": port,
                                            "endpointMode": mode.read().as_str(),
                                        }),
                                        signals,
                                        true,
                                    );
                                }
                            })
                            .child("Apply"),
                    ),
                ),
        )
        .child(
            mobile_card("Link A Device").child(
                rect()
                    .width(Size::fill())
                    .horizontal()
                    .cross_align(Alignment::Center)
                    .spacing(8.)
                    .padding(Gaps::new_all(10.))
                    .child(
                        Input::new(endpoint)
                            .width(Size::flex(2.))
                            .placeholder("wss://host-or-vpn-name:6768")
                            .compact()
                            .filled(),
                    )
                    .child(
                        Input::new(device_name)
                            .width(Size::flex(1.))
                            .placeholder("My Phone")
                            .compact()
                            .filled(),
                    )
                    .child(
                        Input::new(expires_minutes)
                            .width(Size::px(60.))
                            .compact()
                            .filled(),
                    )
                    .child(
                        Button::new()
                            .filled()
                            .on_press({
                                let bridge = bridge.clone();
                                let settings = status.settings.clone();
                                move |_| {
                                    create_pairing(
                                        bridge.clone(),
                                        endpoint.read().clone(),
                                        device_name.read().clone(),
                                        expires_minutes.read().clone(),
                                        settings.clone(),
                                        signals,
                                    );
                                }
                            })
                            .child(if *signals.busy.read() {
                                CircularLoader::new().size(13.).into_element()
                            } else {
                                label().text("Link Device").into_element()
                            }),
                    ),
            ),
        );

    let mut offers = mobile_card("Active Pairing Offers");
    if status.active_pairings.is_empty() {
        offers = offers.child(mobile_empty("No Active Pairing Offers"));
    } else {
        for offer in status.active_pairings {
            offers = offers.child(
                mobile_item_row(
                    offer
                        .expected_device_name
                        .unwrap_or_else(|| "Any Device".to_string()),
                    format!("{} - {}", offer.endpoint, expiry_label(&offer.expires_at)),
                )
                .child(overlay_button(
                    "Cancel",
                    MobileOverlay::Confirm {
                        title: "Cancel Pairing Offer".to_string(),
                        message: "The offer becomes unusable immediately.".to_string(),
                        verb: "mobile.pairing.cancel",
                        payload: json!({"id": offer.id}),
                    },
                    signals.overlay,
                )),
            );
        }
    }
    rows = rows.child(offers);

    let mut devices = mobile_card("Paired Devices");
    if status.devices.is_empty() {
        devices = devices.child(mobile_empty("No Paired Devices"));
    } else {
        for device in status.devices {
            let revoked = device.revoked_at.is_some();
            let detail = if let Some(revoked_at) = device.revoked_at.as_deref() {
                format!("Revoked {}", timestamp(revoked_at))
            } else if let Some(last_seen) = device.last_seen_at.as_deref() {
                format!("Last Seen {}", timestamp(last_seen))
            } else {
                format!("Paired {}", timestamp(&device.paired_at))
            };
            let id = device.id.clone();
            let name = device.display_name.clone();
            let mut row = mobile_item_row(device.display_name.clone(), detail);
            if revoked {
                row = row.child(overlay_button(
                    "Delete",
                    MobileOverlay::Confirm {
                        title: format!("Delete {}", device.display_name),
                        message:
                            "Permanently removes this revoked device record. This cannot be undone."
                                .to_string(),
                        verb: "mobile.device.delete",
                        payload: json!({"id": device.id}),
                    },
                    signals.overlay,
                ));
            } else {
                let mut rename_input = rename_value;
                let mut overlay_for_rename = signals.overlay;
                row = row
                    .child(
                        Button::new()
                            .compact()
                            .flat()
                            .on_press(move |_| {
                                rename_input.set(name.clone());
                                overlay_for_rename.set(Some(MobileOverlay::Rename {
                                    id: id.clone(),
                                    current_name: name.clone(),
                                }));
                            })
                            .child("Rename"),
                    )
                    .child(overlay_button(
                        "Revoke",
                        MobileOverlay::Confirm {
                            title: format!("Revoke {}", device.display_name),
                            message: "The device loses access and active sessions disconnect immediately. This cannot be undone."
                                .to_string(),
                            verb: "mobile.device.revoke",
                            payload: json!({"id": device.id}),
                        },
                        signals.overlay,
                    ));
            }
            devices = devices.child(row);
        }
    }
    rows.child(devices).into_element()
}
