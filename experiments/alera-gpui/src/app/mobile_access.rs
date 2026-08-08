#![allow(clippy::items_after_test_module)]

use std::time::Duration;

use chrono::{DateTime, Local, Utc};
use gpui::{
    AppContext as _, ClipboardItem, Context, Entity, SharedString, StatefulInteractiveElement as _,
    Window,
};
use gpui_component::input::InputState;
use serde::Deserialize;
use serde_json::{json, Value};

use super::AleraApp;

#[derive(Clone, Copy, Debug, Default, Eq, PartialEq)]
pub(super) enum MobileEndpointMode {
    #[default]
    Loopback,
    Tailscale,
    Manual,
}

impl MobileEndpointMode {
    fn from_wire(value: &str) -> Self {
        match value {
            "tailscale" => Self::Tailscale,
            "manual" => Self::Manual,
            _ => Self::Loopback,
        }
    }

    fn wire_name(self) -> &'static str {
        match self {
            Self::Loopback => "loopback",
            Self::Tailscale => "tailscale",
            Self::Manual => "manual",
        }
    }
}

#[derive(Clone, Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
pub(super) struct MobileGatewaySettings {
    pub enabled: bool,
    pub bind_host: String,
    pub port: u16,
    #[serde(default)]
    endpoint_mode: String,
}

impl MobileGatewaySettings {
    pub(super) fn displayed_mode(&self) -> MobileEndpointMode {
        let mode = MobileEndpointMode::from_wire(&self.endpoint_mode);
        if mode == MobileEndpointMode::Loopback && !is_loopback_host(&self.bind_host) {
            MobileEndpointMode::Manual
        } else {
            mode
        }
    }
}

#[derive(Clone, Debug, Default, Deserialize)]
#[serde(default, rename_all = "camelCase")]
pub(super) struct MobileTailscaleStatus {
    pub detected: bool,
    pub running: bool,
    pub tailnet_ip: Option<String>,
    pub error: Option<String>,
}

#[derive(Clone, Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
pub(super) struct MobilePairingOffer {
    pub id: String,
    pub endpoint: String,
    pub expected_device_name: Option<String>,
    pub expires_at: String,
}

#[derive(Clone, Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
pub(super) struct MobileDevice {
    pub id: String,
    pub display_name: String,
    pub paired_at: String,
    pub last_seen_at: Option<String>,
    pub revoked_at: Option<String>,
}

#[derive(Clone, Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
pub(super) struct MobileAccessStatus {
    pub settings: MobileGatewaySettings,
    #[serde(default)]
    pub devices: Vec<MobileDevice>,
    #[serde(default)]
    pub active_pairings: Vec<MobilePairingOffer>,
    pub tailscale: Option<MobileTailscaleStatus>,
}

#[derive(Clone, Debug)]
pub(super) struct MobilePairingGrant {
    pub pairing_id: String,
    pub endpoint: String,
    pub host_name: String,
    pub expires_at: String,
    pub raw_payload: Value,
}

#[derive(Clone, Debug)]
pub(super) enum MobileOverlay {
    PairingGrant(MobilePairingGrant),
    CancelOffer(String),
    RenameDevice { id: String, current_name: String },
    RevokeDevice { id: String, display_name: String },
    DeleteDevice { id: String, display_name: String },
}

pub(super) struct MobileAccessState {
    pub bind_host_input: Entity<InputState>,
    pub endpoint_input: Entity<InputState>,
    pub device_name_input: Entity<InputState>,
    pub rename_input: Entity<InputState>,
    pub gateway_port_input: Entity<InputState>,
    pub expires_minutes_input: Entity<InputState>,
    pub status: Option<MobileAccessStatus>,
    pub loading: bool,
    pub busy: bool,
    pub error: Option<SharedString>,
    pub gateway_port: u16,
    pub expires_minutes: u8,
    pub seeded_signature: Option<String>,
    pub overlay: Option<MobileOverlay>,
    pub copied_pairing_json: bool,
    generation: u64,
}

impl MobileAccessState {
    pub fn new(window: &mut Window, cx: &mut Context<AleraApp>) -> Self {
        Self {
            bind_host_input: cx.new(|cx| InputState::new(window, cx).placeholder("127.0.0.1")),
            endpoint_input: cx
                .new(|cx| InputState::new(window, cx).placeholder("wss://host-or-vpn-name:6768")),
            device_name_input: cx.new(|cx| InputState::new(window, cx).placeholder("My Phone")),
            rename_input: cx.new(|cx| InputState::new(window, cx).placeholder("Device Name")),
            gateway_port_input: cx.new(|cx| InputState::new(window, cx).default_value("6768")),
            expires_minutes_input: cx.new(|cx| InputState::new(window, cx).default_value("10")),
            status: None,
            loading: false,
            busy: false,
            error: None,
            gateway_port: 6768,
            expires_minutes: 10,
            seeded_signature: None,
            overlay: None,
            copied_pairing_json: false,
            generation: 0,
        }
    }

    fn seed_status(
        &mut self,
        status: MobileAccessStatus,
        window: &mut Window,
        cx: &mut Context<AleraApp>,
    ) {
        let signature = format!(
            "{}|{}|{}|{}",
            status.settings.enabled,
            status.settings.bind_host,
            status.settings.port,
            status.settings.endpoint_mode
        );
        if self.seeded_signature.as_deref() != Some(&signature) {
            let bind_host = status.settings.bind_host.clone();
            self.bind_host_input.update(cx, |input, cx| {
                input.set_value(bind_host, window, cx);
            });
            self.gateway_port = status.settings.port;
            self.gateway_port_input.update(cx, |input, cx| {
                input.set_value(status.settings.port.to_string(), window, cx);
            });
            self.seeded_signature = Some(signature);
        }
        self.status = Some(status);
    }
}

impl AleraApp {
    pub(super) fn refresh_mobile_access(&mut self, window: &mut Window, cx: &mut Context<Self>) {
        self.mobile_access.generation += 1;
        let generation = self.mobile_access.generation;
        self.mobile_access.loading = true;
        self.mobile_access.error = None;
        let bridge = self.bridge.clone();
        cx.spawn_in(window, async move |this, cx| {
            let result = bridge.request("mobile.status.get", json!({})).await;
            let Some(this) = this.upgrade() else {
                return;
            };
            let _ = this.update_in(cx, |this, window, cx| {
                if generation != this.mobile_access.generation {
                    return;
                }
                this.mobile_access.loading = false;
                match result.and_then(parse_mobile_status) {
                    Ok(status) => this.mobile_access.seed_status(status, window, cx),
                    Err(error) => this.mobile_access.error = Some(error.into()),
                }
                cx.notify();
            });
        })
        .detach();
    }

    pub(super) fn update_mobile_settings(
        &mut self,
        enabled: Option<bool>,
        mode: Option<MobileEndpointMode>,
        window: &mut Window,
        cx: &mut Context<Self>,
    ) {
        if self.mobile_access.busy {
            return;
        }
        let mut payload = serde_json::Map::new();
        if let Some(enabled) = enabled {
            payload.insert("enabled".into(), enabled.into());
        }
        if let Some(mode) = mode {
            payload.insert("endpointMode".into(), mode.wire_name().into());
        }
        if enabled.is_none() && mode.is_none() {
            let port = match self
                .mobile_access
                .gateway_port_input
                .read(cx)
                .value()
                .trim()
                .parse::<u16>()
            {
                Ok(port) if port > 0 => port,
                _ => {
                    self.mobile_access.error =
                        Some("Port Must Be A Number Between 1 And 65535".into());
                    cx.notify();
                    return;
                }
            };
            let bind_host = self
                .mobile_access
                .bind_host_input
                .read(cx)
                .value()
                .trim()
                .to_string();
            if !bind_host.is_empty() {
                payload.insert("bindHost".into(), bind_host.into());
            }
            self.mobile_access.gateway_port = port;
            payload.insert("port".into(), port.into());
        }
        self.run_mobile_request(
            "mobile.settings.update",
            Value::Object(payload),
            true,
            window,
            cx,
        );
    }

    pub(super) fn adjust_mobile_number(
        &mut self,
        port: bool,
        delta: i32,
        window: &mut Window,
        cx: &mut Context<Self>,
    ) {
        if port {
            let current = self
                .mobile_access
                .gateway_port_input
                .read(cx)
                .value()
                .trim()
                .parse::<i32>()
                .unwrap_or(i32::from(self.mobile_access.gateway_port));
            self.mobile_access.gateway_port = (current + delta).clamp(1, 65_535) as u16;
            let value = self.mobile_access.gateway_port.to_string();
            self.mobile_access
                .gateway_port_input
                .update(cx, |input, cx| input.set_value(value, window, cx));
        } else {
            let current = self
                .mobile_access
                .expires_minutes_input
                .read(cx)
                .value()
                .trim()
                .parse::<i32>()
                .unwrap_or(i32::from(self.mobile_access.expires_minutes));
            self.mobile_access.expires_minutes = (current + delta).clamp(1, 60) as u8;
            let value = self.mobile_access.expires_minutes.to_string();
            self.mobile_access
                .expires_minutes_input
                .update(cx, |input, cx| input.set_value(value, window, cx));
        }
        cx.notify();
    }

    pub(super) fn generate_mobile_pairing(&mut self, window: &mut Window, cx: &mut Context<Self>) {
        if self.mobile_access.busy {
            return;
        }
        let Some(status) = self.mobile_access.status.as_ref() else {
            return;
        };
        let endpoint = self
            .mobile_access
            .endpoint_input
            .read(cx)
            .value()
            .trim()
            .to_string();
        if !endpoint.is_empty() {
            if let Some(error) =
                validate_pairing_endpoint(&endpoint, status.settings.enabled, status.settings.port)
            {
                self.mobile_access.error = Some(error.into());
                cx.notify();
                return;
            }
        } else if is_wildcard_host(&status.settings.bind_host) {
            self.mobile_access.error = Some(
                "Wildcard Bind Hosts Require An Explicit wss:// Endpoint To Create An Offer".into(),
            );
            cx.notify();
            return;
        }
        let device_name = self
            .mobile_access
            .device_name_input
            .read(cx)
            .value()
            .trim()
            .to_string();
        let expires_minutes = match self
            .mobile_access
            .expires_minutes_input
            .read(cx)
            .value()
            .trim()
            .parse::<u8>()
        {
            Ok(minutes @ 1..=60) => minutes,
            _ => {
                self.mobile_access.error =
                    Some("Expires In Must Be A Number Between 1 And 60".into());
                cx.notify();
                return;
            }
        };
        self.mobile_access.expires_minutes = expires_minutes;
        let payload = json!({
            "endpoint": (!endpoint.is_empty()).then_some(endpoint),
            "deviceName": (!device_name.is_empty()).then_some(device_name),
            "expiresMinutes": expires_minutes,
        });
        self.mobile_access.busy = true;
        self.mobile_access.error = None;
        let bridge = self.bridge.clone();
        cx.spawn_in(window, async move |this, cx| {
            let result = bridge
                .request_with_timeout("mobile.pairing.create", payload, Duration::from_secs(10))
                .await
                .and_then(parse_pairing_grant);
            let Some(this) = this.upgrade() else {
                return;
            };
            let _ = this.update_in(cx, |this, window, cx| {
                this.mobile_access.busy = false;
                match result {
                    Ok(grant) => {
                        this.mobile_access.copied_pairing_json = false;
                        this.mobile_access.overlay = Some(MobileOverlay::PairingGrant(grant));
                        this.refresh_mobile_access(window, cx);
                    }
                    Err(error) => this.mobile_access.error = Some(error.into()),
                }
                cx.notify();
            });
        })
        .detach();
    }

    fn run_mobile_request(
        &mut self,
        verb: &'static str,
        payload: Value,
        refresh: bool,
        window: &mut Window,
        cx: &mut Context<Self>,
    ) {
        self.mobile_access.busy = true;
        self.mobile_access.error = None;
        let bridge = self.bridge.clone();
        cx.spawn_in(window, async move |this, cx| {
            let result = bridge
                .request_with_timeout(verb, payload, Duration::from_secs(10))
                .await;
            let Some(this) = this.upgrade() else {
                return;
            };
            let _ = this.update_in(cx, |this, window, cx| {
                this.mobile_access.busy = false;
                match result {
                    Ok(_) => {
                        if refresh {
                            this.mobile_access.seeded_signature = None;
                            this.refresh_mobile_access(window, cx);
                        }
                    }
                    Err(error) => this.mobile_access.error = Some(error.into()),
                }
                cx.notify();
            });
        })
        .detach();
    }

    pub(super) fn begin_mobile_rename(
        &mut self,
        id: String,
        current_name: String,
        window: &mut Window,
        cx: &mut Context<Self>,
    ) {
        let value = current_name.clone();
        self.mobile_access.rename_input.update(cx, |input, cx| {
            input.set_value(value, window, cx);
        });
        self.mobile_access.overlay = Some(MobileOverlay::RenameDevice { id, current_name });
        cx.notify();
    }

    pub(super) fn confirm_mobile_overlay(&mut self, window: &mut Window, cx: &mut Context<Self>) {
        let Some(overlay) = self.mobile_access.overlay.clone() else {
            return;
        };
        let (verb, payload) = match overlay {
            MobileOverlay::CancelOffer(id) => ("mobile.pairing.cancel", json!({"id": id})),
            MobileOverlay::RenameDevice { id, current_name } => {
                let name = self
                    .mobile_access
                    .rename_input
                    .read(cx)
                    .value()
                    .trim()
                    .to_string();
                if name.is_empty() || name == current_name {
                    self.mobile_access.overlay = None;
                    cx.notify();
                    return;
                }
                (
                    "mobile.device.rename",
                    json!({"id": id, "displayName": name}),
                )
            }
            MobileOverlay::RevokeDevice { id, .. } => ("mobile.device.revoke", json!({"id": id})),
            MobileOverlay::DeleteDevice { id, .. } => ("mobile.device.delete", json!({"id": id})),
            MobileOverlay::PairingGrant(grant) => {
                ("mobile.pairing.cancel", json!({"id": grant.pairing_id}))
            }
        };
        self.mobile_access.overlay = None;
        self.run_mobile_request(verb, payload, true, window, cx);
    }

    pub(super) fn copy_mobile_pairing_json(&mut self, cx: &mut Context<Self>) {
        let Some(MobileOverlay::PairingGrant(grant)) = self.mobile_access.overlay.as_ref() else {
            return;
        };
        cx.write_to_clipboard(ClipboardItem::new_string(grant.raw_payload.to_string()));
        self.mobile_access.copied_pairing_json = true;
        cx.notify();
    }

    pub(super) fn close_mobile_overlay(&mut self, cx: &mut Context<Self>) {
        self.mobile_access.overlay = None;
        cx.notify();
    }
}

include!("mobile_access_domain.rs");
include!("mobile_access_render.rs");
