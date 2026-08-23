use chrono::Utc;
use serde_json::{json, Value};

use crate::mobile_access::{authenticate_mobile_device, MOBILE_PROTOCOL_VERSION};
use crate::terminal_host::host_error::{HostError, HostResult};
use crate::terminal_host::protocol::event;

use super::mobile_gateway_surface::MOBILE_HELLO_CAPABILITIES;
use super::request_payloads::parse_payload;
use super::ServerActor;

#[derive(Debug, serde::Deserialize)]
#[serde(rename_all = "camelCase")]
pub(super) struct MobileHelloRequest {
    protocol_version: i64,
    device_id: String,
    device_token: String,
    #[serde(default)]
    pub(super) cloud_device_id: Option<String>,
    #[serde(default)]
    relay_client_id: Option<String>,
    #[serde(default)]
    supported_tab_kinds: Vec<String>,
}

impl ServerActor {
    pub(super) async fn handle_mobile_hello(
        &mut self,
        client_id: u64,
        payload: &Value,
    ) -> HostResult<Value> {
        if !self.is_mobile_client(client_id) {
            return Err(HostError::state(
                "mobile authentication is only available on the mobile gateway.",
            ));
        }
        let request: MobileHelloRequest = parse_payload(payload)?;
        if request.protocol_version != MOBILE_PROTOCOL_VERSION {
            return Err(HostError::state(format!(
                "Unsupported mobile protocol version: {}",
                request.protocol_version
            )));
        }
        let (device_id, device_name, device) = if let Some(relay_client_id) = request
            .relay_client_id
            .as_deref()
            .map(str::trim)
            .filter(|id| !id.is_empty())
        {
            let client = self
                .clients
                .get(&client_id)
                .ok_or_else(|| HostError::state("Client disconnected."))?;
            if client.relay_client_id.as_deref() != Some(relay_client_id)
                || !request.device_token.trim().is_empty()
            {
                return Err(HostError::state("The relay mobile identity is invalid."));
            }
            (
                relay_client_id.to_string(),
                client
                    .mobile_device_name
                    .clone()
                    .unwrap_or_else(|| "Remote Mobile".to_string()),
                json!({
                    "id": relay_client_id,
                    "displayName": "Remote Mobile",
                    "permission": "fullControl",
                    "pairedAt": Utc::now(),
                    "lastSeenAt": Utc::now(),
                    "revokedAt": Value::Null,
                }),
            )
        } else {
            let device = authenticate_mobile_device(
                &self.runtime_store,
                &request.device_id,
                &request.device_token,
            )
            .await
            .map_err(|error| HostError::state(error.to_string()))?;
            (
                device.id.clone(),
                device.display_name.clone(),
                json!(device),
            )
        };
        let binary_frames = payload
            .get("binaryFrames")
            .and_then(Value::as_bool)
            .unwrap_or(false);
        if let Some(client) = self.clients.get_mut(&client_id) {
            client.authenticated = true;
            client.binary_frames = binary_frames;
            client.mobile_device_id = Some(device_id);
            client.mobile_device_name = Some(device_name);
            client.cloud_device_id = request
                .cloud_device_id
                .filter(|cloud_device_id| !cloud_device_id.trim().is_empty())
                .or_else(|| client.relay_client_id.clone());
            client.supports_codex_tab_kind = request
                .supported_tab_kinds
                .iter()
                .any(|kind| kind == crate::terminal_host::protocol::CODEX_TAB_KIND);
        }
        self.cancel_shutdown_timer();
        if binary_frames {
            // The response stays ahead of the in-band frame upgrade.
            self.upgrade_client_to_binary(client_id);
        }
        self.broadcast_authenticated(event("mobileDevicesChanged", json!({})));
        Ok(json!({
            "protocolVersion": MOBILE_PROTOCOL_VERSION,
            "runtime": "alera",
            "runtimeCapabilities": MOBILE_HELLO_CAPABILITIES,
            "authenticated": true,
            "binaryFrames": binary_frames,
            "supportedTabKinds": request.supported_tab_kinds,
            "device": device,
        }))
    }
}
