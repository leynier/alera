use std::collections::BTreeMap;
use std::time::Duration;

use alera_desktop_core::RuntimeBridge;
use freya::prelude::*;
use serde_json::{Value, json};

use super::QuotaSignals;
use super::model::{QuotaSettings, parse_environment_presence};

pub(crate) async fn load_snapshot(bridge: RuntimeBridge) -> Result<QuotaSettings, String> {
    let settings = bridge
        .request_with_timeout("runtimeSettings.get", json!({}), Duration::from_secs(10))
        .await?;
    Ok(QuotaSettings::from_runtime(&settings))
}

pub(super) fn persist_settings(
    bridge: RuntimeBridge,
    settings: QuotaSettings,
    signals: QuotaSignals,
) {
    run_request(
        bridge,
        "runtimeSettings.update",
        settings.payload(),
        "Quota Settings Updated",
        signals,
    );
}

pub(super) fn check_environment(
    bridge: RuntimeBridge,
    mut presence: State<BTreeMap<String, bool>>,
    mut signals: QuotaSignals,
) {
    if *signals.busy.read() {
        return;
    }
    signals.busy.set(true);
    signals.message.set(None);
    spawn(async move {
        match bridge
            .request_with_timeout(
                "agentQuota.snapshot",
                json!({"forceRefresh": true}),
                Duration::from_secs(90),
            )
            .await
        {
            Ok(value) => {
                presence.set(parse_environment_presence(&value));
                signals
                    .message
                    .set(Some("Credential Availability Refreshed".to_string()));
            }
            Err(error) => signals.message.set(Some(error)),
        }
        signals.busy.set(false);
    });
}

fn run_request(
    bridge: RuntimeBridge,
    verb: &'static str,
    payload: Value,
    success: &'static str,
    mut signals: QuotaSignals,
) {
    if *signals.busy.read() {
        return;
    }
    signals.busy.set(true);
    signals.message.set(None);
    spawn(async move {
        match bridge
            .request_with_timeout(verb, payload, Duration::from_secs(30))
            .await
        {
            Ok(_) => {
                signals.message.set(Some(success.to_string()));
                let next_revision = signals.revision.read().saturating_add(1);
                signals.revision.set(next_revision);
            }
            Err(error) => signals.message.set(Some(error)),
        }
        signals.busy.set(false);
    });
}
