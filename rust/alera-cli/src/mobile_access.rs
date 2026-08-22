mod pairing_endpoint_rules;

use alera_core::runtime::{
    MobileAccessSettings, MobileDevice, MobileDevicePermission, MobileEndpointMode,
    MobileNetbirdEndpoint, MobilePairingOffer, RuntimeStore,
};
use anyhow::{bail, Result};
use chrono::{Duration, Utc};
use serde::{Deserialize, Serialize};
use sha2::{Digest, Sha256};
use uuid::Uuid;

use pairing_endpoint_rules::{endpoint_host, validate_pairing_endpoint};

pub const MOBILE_PROTOCOL_VERSION: i64 = 1;

#[derive(Debug, Clone, Deserialize, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct MobileSettingsUpdateRequest {
    #[serde(default)]
    pub enabled: Option<bool>,
    #[serde(default)]
    pub remote_access_enabled: Option<bool>,
    #[serde(default)]
    pub bind_host: Option<String>,
    #[serde(default)]
    pub port: Option<i64>,
    #[serde(default)]
    pub endpoint_mode: Option<MobileEndpointMode>,
    #[serde(default)]
    pub netbird_endpoint: Option<MobileNetbirdEndpoint>,
}

#[derive(Debug, Clone, Deserialize, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct MobilePairingCreateRequest {
    #[serde(default)]
    pub endpoint: Option<String>,
    #[serde(default)]
    pub device_name: Option<String>,
    #[serde(default)]
    pub expires_minutes: Option<i64>,
}

#[derive(Debug, Clone, Deserialize, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct MobileDevicePairRequest {
    pub pairing_id: String,
    pub pairing_secret: String,
    #[serde(default)]
    pub device_name: Option<String>,
    #[serde(default)]
    pub public_key_b64: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct MobileStatusPayload {
    pub protocol_version: i64,
    pub settings: MobileAccessSettings,
    pub devices: Vec<MobileDeviceSummary>,
    pub active_pairings: Vec<MobilePairingOfferSummary>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub runtime_host_active: Option<bool>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub tailscale: Option<crate::tailscale::TailscaleStatusSummary>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub netbird: Option<crate::netbird::NetbirdStatusSummary>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct MobileDeviceSummary {
    pub id: String,
    pub display_name: String,
    pub public_key_b64: Option<String>,
    pub permission: String,
    pub paired_at: chrono::DateTime<Utc>,
    pub last_seen_at: Option<chrono::DateTime<Utc>>,
    pub revoked_at: Option<chrono::DateTime<Utc>>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct MobilePairingOfferSummary {
    pub id: String,
    pub endpoint: String,
    pub expected_device_name: Option<String>,
    pub server_public_key_b64: Option<String>,
    pub created_at: chrono::DateTime<Utc>,
    pub expires_at: chrono::DateTime<Utc>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct MobilePairingOfferPayload {
    pub v: i64,
    pub pairing_id: String,
    pub endpoint: String,
    pub runtime_id: String,
    pub host_name: String,
    pub pairing_secret: String,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub endpoint_network: Option<String>,
    pub server_public_key_b64: Option<String>,
    pub expires_at: chrono::DateTime<Utc>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct MobileDevicePairPayload {
    pub device_id: String,
    pub display_name: String,
    pub runtime_id: String,
    pub device_token: String,
}

pub async fn mobile_status(
    store: &RuntimeStore,
    runtime_host_active: Option<bool>,
) -> Result<MobileStatusPayload> {
    let settings = store.mobile_access_settings().await?;
    let devices = store
        .list_mobile_devices(true)
        .await?
        .into_iter()
        .map(MobileDeviceSummary::from)
        .collect();
    let active_pairings = store
        .list_mobile_pairing_offers()
        .await?
        .into_iter()
        .map(MobilePairingOfferSummary::from)
        .collect();
    Ok(MobileStatusPayload {
        protocol_version: MOBILE_PROTOCOL_VERSION,
        settings,
        devices,
        active_pairings,
        runtime_host_active,
        tailscale: Some(crate::tailscale::detect().await),
        netbird: Some(crate::netbird::detect().await),
    })
}

pub async fn update_mobile_settings(
    store: &RuntimeStore,
    request: MobileSettingsUpdateRequest,
) -> Result<MobileAccessSettings> {
    let settings = apply_mobile_settings_update(store.mobile_access_settings().await?, request)?;
    store.set_mobile_access_settings(settings).await
}

pub fn apply_mobile_settings_update(
    mut settings: MobileAccessSettings,
    request: MobileSettingsUpdateRequest,
) -> Result<MobileAccessSettings> {
    if let Some(enabled) = request.enabled {
        settings.enabled = enabled;
    }
    if let Some(remote_access_enabled) = request.remote_access_enabled {
        settings.remote_access_enabled = remote_access_enabled;
    }
    if let Some(bind_host) = request
        .bind_host
        .as_deref()
        .map(str::trim)
        .filter(|value| !value.is_empty())
    {
        settings.bind_host = bind_host.to_string();
    }
    if let Some(port) = request.port {
        if !(1..=65535).contains(&port) {
            bail!("mobile port must be between 1 and 65535");
        }
        settings.port = port;
    }
    if let Some(endpoint_mode) = request.endpoint_mode {
        settings.endpoint_mode = endpoint_mode;
    }
    if let Some(netbird_endpoint) = request.netbird_endpoint {
        settings.netbird_endpoint = netbird_endpoint;
    }
    Ok(settings)
}

pub async fn apply_mobile_settings_update_resolved(
    current: MobileAccessSettings,
    request: MobileSettingsUpdateRequest,
) -> Result<MobileAccessSettings> {
    let previous_mode = current.endpoint_mode;
    let request_has_bind_host = request
        .bind_host
        .as_deref()
        .map(str::trim)
        .filter(|value| !value.is_empty())
        .is_some();
    let mut settings = apply_mobile_settings_update(current, request)?;
    let switched_mode = settings.endpoint_mode != previous_mode;
    match settings.endpoint_mode {
        MobileEndpointMode::Tailscale if settings.enabled || switched_mode => {
            settings.bind_host = crate::tailscale::resolve_tailnet_bind_ip()
                .await?
                .to_string();
        }
        MobileEndpointMode::Netbird if settings.enabled || switched_mode => {
            settings.bind_host =
                crate::netbird::resolve_netbird_endpoint(settings.netbird_endpoint)
                    .await?
                    .bind_ip
                    .to_string();
        }
        MobileEndpointMode::Loopback if switched_mode && !request_has_bind_host => {
            settings.bind_host = MobileAccessSettings::default().bind_host;
        }
        _ => {}
    }
    Ok(settings)
}

pub async fn prepare_mobile_pairing_offer_settings_resolved(
    mut settings: MobileAccessSettings,
    request: &MobilePairingCreateRequest,
) -> Result<(MobileAccessSettings, String)> {
    let has_explicit_endpoint = request
        .endpoint
        .as_deref()
        .map(str::trim)
        .filter(|value| !value.is_empty())
        .is_some();
    if settings.endpoint_mode == MobileEndpointMode::Tailscale && !has_explicit_endpoint {
        settings.bind_host = crate::tailscale::resolve_tailnet_bind_ip()
            .await?
            .to_string();
    }
    let mut generated_endpoint_network = None;
    if settings.endpoint_mode == MobileEndpointMode::Netbird && !has_explicit_endpoint {
        let resolved = crate::netbird::resolve_netbird_endpoint(settings.netbird_endpoint).await?;
        settings.bind_host = resolved.bind_ip.to_string();
        if settings.netbird_endpoint == MobileNetbirdEndpoint::Dns {
            let endpoint = format!("ws://{}:{}", resolved.advertised_host, settings.port);
            return prepare_mobile_pairing_offer_settings_with_network(
                settings,
                request,
                Some(endpoint),
                resolved.endpoint_network,
            );
        }
        generated_endpoint_network = resolved.endpoint_network;
    }
    prepare_mobile_pairing_offer_settings_with_network(
        settings,
        request,
        None,
        generated_endpoint_network,
    )
}

#[cfg(test)]
fn prepare_mobile_pairing_offer_settings(
    settings: MobileAccessSettings,
    request: &MobilePairingCreateRequest,
) -> Result<(MobileAccessSettings, String)> {
    prepare_mobile_pairing_offer_settings_with_network(settings, request, None, None)
}

fn prepare_mobile_pairing_offer_settings_with_network(
    mut settings: MobileAccessSettings,
    request: &MobilePairingCreateRequest,
    generated_endpoint: Option<String>,
    endpoint_network: Option<String>,
) -> Result<(MobileAccessSettings, String)> {
    let explicit_endpoint = request
        .endpoint
        .as_deref()
        .map(str::trim)
        .filter(|value| !value.is_empty())
        .map(ToString::to_string);
    let endpoint = generated_endpoint
        .or(explicit_endpoint)
        .map(Ok)
        .unwrap_or_else(|| {
            if is_wildcard_bind_host(&settings.bind_host) {
                bail!(
                    "mobile pairing endpoint is required when bind host is {}; pass --endpoint wss://<host-or-vpn-name>:{}",
                    settings.bind_host,
                    settings.port
                );
            }
            Ok(format!(
                "ws://{}:{}",
                endpoint_host(&settings.bind_host),
                settings.port
            ))
        })?;
    let endpoint = validate_pairing_endpoint(endpoint, endpoint_network.as_deref())?;
    let endpoint_port = i64::from(endpoint.port);
    if !settings.enabled {
        settings.enabled = true;
        if endpoint.requires_listener_port_match {
            settings.port = endpoint_port;
        }
    } else if endpoint.requires_listener_port_match && endpoint_port != settings.port {
        bail!(
            "mobile pairing ws:// endpoint port {endpoint_port} does not match enabled mobile gateway port {}; run alera mobile --json enable --port {endpoint_port} before creating the pairing offer",
            settings.port
        );
    }
    Ok((settings, endpoint.value))
}

pub async fn create_mobile_pairing_offer_for_settings(
    store: &RuntimeStore,
    settings: &MobileAccessSettings,
    request: &MobilePairingCreateRequest,
    endpoint: String,
) -> Result<MobilePairingOfferPayload> {
    let expires_minutes = request.expires_minutes.unwrap_or(10).clamp(1, 60);
    let now = Utc::now();
    let pairing_secret = new_secret();
    let offer = MobilePairingOffer {
        id: Uuid::new_v4().to_string(),
        endpoint: endpoint.clone(),
        secret_hash: sha256_hex(&pairing_secret),
        expected_device_name: request
            .device_name
            .as_deref()
            .map(str::trim)
            .filter(|value| !value.is_empty())
            .map(ToString::to_string),
        server_public_key_b64: settings.server_public_key_b64.clone(),
        created_at: now,
        expires_at: now + Duration::minutes(expires_minutes),
        claimed_device_id: None,
    };
    let offer = store.upsert_mobile_pairing_offer(offer).await?;
    let endpoint_network = if request
        .endpoint
        .as_deref()
        .map(str::trim)
        .filter(|value| !value.is_empty())
        .is_none()
        && settings.endpoint_mode == MobileEndpointMode::Netbird
        && settings.netbird_endpoint == MobileNetbirdEndpoint::Dns
    {
        Some("netbird".to_string())
    } else {
        None
    };
    Ok(MobilePairingOfferPayload {
        v: MOBILE_PROTOCOL_VERSION,
        pairing_id: offer.id,
        endpoint,
        runtime_id: runtime_id(store).await?,
        host_name: host_name(),
        pairing_secret,
        endpoint_network,
        server_public_key_b64: offer.server_public_key_b64,
        expires_at: offer.expires_at,
    })
}

pub async fn list_mobile_devices(
    store: &RuntimeStore,
    include_revoked: bool,
) -> Result<Vec<MobileDeviceSummary>> {
    Ok(store
        .list_mobile_devices(include_revoked)
        .await?
        .into_iter()
        .map(MobileDeviceSummary::from)
        .collect())
}

pub async fn pair_mobile_device(
    store: &RuntimeStore,
    request: MobileDevicePairRequest,
) -> Result<MobileDevicePairPayload> {
    let offer = store
        .find_mobile_pairing_offer(request.pairing_id.trim())
        .await?
        .ok_or_else(|| anyhow::anyhow!("pairing offer not found"))?;
    if Utc::now() > offer.expires_at {
        bail!("pairing offer expired");
    }
    let secret_hash = sha256_hex(request.pairing_secret.trim());
    if offer.secret_hash != secret_hash {
        bail!("pairing secret is invalid");
    }
    let display_name = request
        .device_name
        .as_deref()
        .map(str::trim)
        .filter(|value| !value.is_empty())
        .or(offer.expected_device_name.as_deref())
        .unwrap_or("Mobile Device")
        .to_string();
    let device_token = new_secret();
    let now = Utc::now();
    let device = MobileDevice {
        id: Uuid::new_v4().to_string(),
        display_name: display_name.clone(),
        token_hash: sha256_hex(&device_token),
        public_key_b64: request
            .public_key_b64
            .as_deref()
            .map(str::trim)
            .filter(|value| !value.is_empty())
            .map(ToString::to_string),
        permission: MobileDevicePermission::FullControl,
        paired_at: now,
        last_seen_at: Some(now),
        revoked_at: None,
    };
    let device = store
        .claim_mobile_pairing_offer(&offer.id, &secret_hash, device)
        .await?;
    Ok(MobileDevicePairPayload {
        device_id: device.id,
        display_name,
        runtime_id: runtime_id(store).await?,
        device_token,
    })
}

pub async fn authenticate_mobile_device(
    store: &RuntimeStore,
    device_id: &str,
    device_token: &str,
) -> Result<MobileDeviceSummary> {
    let device_id = device_id.trim();
    let device_token = device_token.trim();
    if device_id.is_empty() || device_token.is_empty() {
        bail!("mobile device credentials are required");
    }
    let device = store
        .find_mobile_device(device_id)
        .await?
        .ok_or_else(|| anyhow::anyhow!("mobile device is not paired"))?;
    if device.revoked_at.is_some() {
        bail!("mobile device has been revoked");
    }
    if device.token_hash != sha256_hex(device_token) {
        bail!("mobile device token is invalid");
    }
    let device = store
        .mark_mobile_device_seen_if_active(&device.id, Utc::now())
        .await?
        .ok_or_else(|| anyhow::anyhow!("mobile device has been revoked"))?;
    Ok(MobileDeviceSummary::from(device))
}

pub async fn revoke_mobile_device(store: &RuntimeStore, id: &str) -> Result<()> {
    store.revoke_mobile_device(id).await
}

pub async fn delete_mobile_device(store: &RuntimeStore, id: &str) -> Result<()> {
    let id = id.trim();
    if id.is_empty() {
        bail!("mobile device id is required");
    }
    if !store.delete_mobile_device(id).await? {
        bail!("mobile device not found or still active; revoke it first");
    }
    Ok(())
}

pub async fn cancel_mobile_pairing_offer(store: &RuntimeStore, id: &str) -> Result<()> {
    let id = id.trim();
    if id.is_empty() {
        bail!("pairing offer id is required");
    }
    if !store.delete_mobile_pairing_offer(id).await? {
        bail!("pairing offer not found");
    }
    Ok(())
}

pub async fn rename_mobile_device(
    store: &RuntimeStore,
    id: &str,
    display_name: &str,
) -> Result<MobileDeviceSummary> {
    let id = id.trim();
    if id.is_empty() {
        bail!("mobile device id is required");
    }
    let display_name = display_name.trim();
    if display_name.is_empty() {
        bail!("mobile device name is required");
    }
    let device = store
        .rename_mobile_device(id, display_name)
        .await?
        .ok_or_else(|| anyhow::anyhow!("mobile device not found or revoked"))?;
    Ok(MobileDeviceSummary::from(device))
}

impl From<MobileDevice> for MobileDeviceSummary {
    fn from(device: MobileDevice) -> Self {
        Self {
            id: device.id,
            display_name: device.display_name,
            public_key_b64: device.public_key_b64,
            permission: device.permission.as_str().to_string(),
            paired_at: device.paired_at,
            last_seen_at: device.last_seen_at,
            revoked_at: device.revoked_at,
        }
    }
}

impl From<MobilePairingOffer> for MobilePairingOfferSummary {
    fn from(offer: MobilePairingOffer) -> Self {
        Self {
            id: offer.id,
            endpoint: offer.endpoint,
            expected_device_name: offer.expected_device_name,
            server_public_key_b64: offer.server_public_key_b64,
            created_at: offer.created_at,
            expires_at: offer.expires_at,
        }
    }
}

pub(crate) async fn runtime_id(store: &RuntimeStore) -> Result<String> {
    if let Some(id) = store.get_metadata("runtime.identity.id").await? {
        return Ok(id);
    }
    let id = Uuid::new_v4().to_string();
    store.set_metadata("runtime.identity.id", &id).await?;
    Ok(id)
}

pub(crate) fn host_name() -> String {
    std::env::var("HOSTNAME")
        .or_else(|_| std::env::var("COMPUTERNAME"))
        .ok()
        .map(|value| value.trim().to_string())
        .filter(|value| !value.is_empty())
        .unwrap_or_else(|| "Alera Runtime".to_string())
}

fn is_wildcard_bind_host(value: &str) -> bool {
    matches!(value.trim(), "0.0.0.0" | "::" | "[::]")
}

fn new_secret() -> String {
    format!("{}{}", Uuid::new_v4().simple(), Uuid::new_v4().simple())
}

fn sha256_hex(value: &str) -> String {
    let mut hasher = Sha256::new();
    hasher.update(value.as_bytes());
    hex::encode(hasher.finalize())
}

#[cfg(test)]
mod tests;
