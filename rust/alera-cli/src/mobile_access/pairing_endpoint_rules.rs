use anyhow::{bail, Result};
use url::Url;

pub(super) struct ValidPairingEndpoint {
    pub(super) value: String,
    pub(super) port: u16,
    pub(super) requires_listener_port_match: bool,
}

pub(super) fn validate_pairing_endpoint(
    endpoint: String,
    endpoint_network: Option<&str>,
) -> Result<ValidPairingEndpoint> {
    let parsed = Url::parse(&endpoint)
        .map_err(|_| anyhow::anyhow!("mobile pairing endpoint must be a ws:// or wss:// URL"))?;
    match parsed.scheme() {
        "ws" | "wss" => {}
        _ => bail!("mobile pairing endpoint must use ws:// or wss://"),
    }
    let Some(host) = parsed.host_str().filter(|host| !host.trim().is_empty()) else {
        bail!("mobile pairing endpoint host is required");
    };
    let Some(port) = endpoint_port(&endpoint) else {
        bail!("mobile pairing endpoint must include an explicit port");
    };
    if port == 0 {
        bail!("mobile pairing endpoint port must be between 1 and 65535");
    }
    let plaintext_allowed = parsed.scheme() != "ws"
        || is_loopback_endpoint_host(host)
        || is_private_overlay_endpoint_host(host)
        || (endpoint_network == Some("netbird") && is_dns_hostname(host));
    if !plaintext_allowed {
        bail!("mobile pairing endpoints outside loopback or a private overlay must use wss://");
    }
    Ok(ValidPairingEndpoint {
        value: endpoint,
        port,
        requires_listener_port_match: parsed.scheme() == "ws",
    })
}

fn is_dns_hostname(host: &str) -> bool {
    let normalized = normalize_endpoint_host(host);
    !normalized.is_empty()
        && !normalized.contains(':')
        && normalized
            .chars()
            .all(|character| character.is_ascii_alphanumeric() || matches!(character, '-' | '.'))
        && normalized.contains('.')
        && !normalized.starts_with('.')
        && !normalized.ends_with('.')
}

pub(super) fn endpoint_host(bind_host: &str) -> String {
    let host = bind_host.trim();
    if host.starts_with('[') || !host.contains(':') {
        host.to_string()
    } else {
        format!("[{host}]")
    }
}

fn is_loopback_endpoint_host(host: &str) -> bool {
    let normalized = normalize_endpoint_host(host);
    normalized == "localhost"
        || normalized
            .parse::<std::net::IpAddr>()
            .is_ok_and(|address| address.is_loopback())
}

fn is_private_overlay_endpoint_host(host: &str) -> bool {
    normalize_endpoint_host(host)
        .parse::<std::net::IpAddr>()
        .is_ok_and(crate::tailscale::is_tailscale_ip)
}

fn normalize_endpoint_host(host: &str) -> String {
    host.trim()
        .strip_prefix('[')
        .and_then(|value| value.strip_suffix(']'))
        .unwrap_or(host)
        .trim_end_matches('.')
        .to_ascii_lowercase()
}

pub(super) fn endpoint_port(endpoint: &str) -> Option<u16> {
    let authority = endpoint
        .split_once("://")
        .map(|(_, rest)| rest)
        .unwrap_or(endpoint)
        .split(['/', '?', '#'])
        .next()
        .unwrap_or(endpoint)
        .rsplit('@')
        .next()
        .unwrap_or(endpoint);
    let port = if let Some(rest) = authority.strip_prefix('[') {
        let (_, after_host) = rest.split_once(']')?;
        after_host.strip_prefix(':')?
    } else {
        let (_, port) = authority.rsplit_once(':')?;
        port
    };
    port.parse::<u16>().ok()
}
