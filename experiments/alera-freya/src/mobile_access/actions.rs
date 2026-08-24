use std::time::Duration;

use alera_desktop_core::RuntimeBridge;
use freya::prelude::*;
use serde_json::{Value, json};

use super::MobileSignals;
use super::model::{
    MobileGatewaySettings, MobileOverlay, is_wildcard_host, parse_pairing_grant,
    validate_pairing_endpoint,
};

pub(super) fn create_pairing(
    bridge: RuntimeBridge,
    endpoint: String,
    device_name: String,
    expires: String,
    settings: MobileGatewaySettings,
    mut signals: MobileSignals,
) {
    if *signals.busy.read() {
        return;
    }
    let endpoint = endpoint.trim().to_string();
    if !endpoint.is_empty() {
        if let Some(error) = validate_pairing_endpoint(&endpoint, settings.enabled, settings.port) {
            signals.message.set(Some(error));
            return;
        }
    } else if is_wildcard_host(&settings.bind_host) {
        signals.message.set(Some(
            "Wildcard Bind Hosts Require An Explicit wss:// Endpoint".to_string(),
        ));
        return;
    }
    let Ok(expires_minutes @ 1..=60) = expires.trim().parse::<u8>() else {
        signals
            .message
            .set(Some("Expires In Must Be Between 1 And 60".to_string()));
        return;
    };
    signals.busy.set(true);
    signals.message.set(None);
    spawn(async move {
        match bridge
            .request_with_timeout(
                "mobile.pairing.create",
                json!({
                    "endpoint": (!endpoint.is_empty()).then_some(endpoint),
                    "deviceName": (!device_name.trim().is_empty()).then_some(device_name.trim()),
                    "expiresMinutes": expires_minutes,
                }),
                Duration::from_secs(10),
            )
            .await
            .and_then(parse_pairing_grant)
        {
            Ok(grant) => {
                signals
                    .overlay
                    .set(Some(MobileOverlay::PairingGrant(grant)));
                let next_revision = signals.revision.read().saturating_add(1);
                signals.revision.set(next_revision);
            }
            Err(error) => signals.message.set(Some(error)),
        }
        signals.busy.set(false);
    });
}

pub(super) fn run_request(
    bridge: RuntimeBridge,
    verb: &'static str,
    payload: Value,
    mut signals: MobileSignals,
    refresh: bool,
) {
    if *signals.busy.read() {
        return;
    }
    signals.busy.set(true);
    signals.message.set(None);
    spawn(async move {
        match bridge
            .request_with_timeout(verb, payload, Duration::from_secs(10))
            .await
        {
            Ok(_) => {
                signals.overlay.set(None);
                if refresh {
                    let next_revision = signals.revision.read().saturating_add(1);
                    signals.revision.set(next_revision);
                }
            }
            Err(error) => signals.message.set(Some(error)),
        }
        signals.busy.set(false);
    });
}
