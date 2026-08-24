use std::net::Ipv4Addr;

use chrono::{DateTime, Local, Utc};
use serde::Deserialize;
use serde_json::Value;

#[derive(Clone, Debug, Default, Deserialize, PartialEq)]
#[serde(default, rename_all = "camelCase")]
pub(super) struct MobileGatewaySettings {
    pub(super) enabled: bool,
    pub(super) bind_host: String,
    pub(super) port: u16,
    pub(super) endpoint_mode: String,
}

#[derive(Clone, Debug, Deserialize, PartialEq)]
#[serde(rename_all = "camelCase")]
pub(super) struct MobilePairingOffer {
    pub(super) id: String,
    pub(super) endpoint: String,
    pub(super) expected_device_name: Option<String>,
    pub(super) expires_at: String,
}

#[derive(Clone, Debug, Deserialize, PartialEq)]
#[serde(rename_all = "camelCase")]
pub(super) struct MobileDevice {
    pub(super) id: String,
    pub(super) display_name: String,
    pub(super) paired_at: String,
    pub(super) last_seen_at: Option<String>,
    pub(super) revoked_at: Option<String>,
}

#[derive(Clone, Debug, Default, Deserialize, PartialEq)]
#[serde(default, rename_all = "camelCase")]
pub(super) struct MobileAccessStatus {
    pub(super) settings: MobileGatewaySettings,
    pub(super) devices: Vec<MobileDevice>,
    pub(super) active_pairings: Vec<MobilePairingOffer>,
}

#[derive(Clone, Debug, PartialEq)]
pub(super) struct MobilePairingGrant {
    pub(super) pairing_id: String,
    pub(super) endpoint: String,
    pub(super) host_name: String,
    pub(super) expires_at: String,
    pub(super) raw_payload: Value,
}

#[derive(Clone, Debug, PartialEq)]
pub(super) enum MobileOverlay {
    PairingGrant(MobilePairingGrant),
    Rename {
        id: String,
        current_name: String,
    },
    Confirm {
        title: String,
        message: String,
        verb: &'static str,
        payload: Value,
    },
}

pub(super) fn parse_pairing_grant(value: Value) -> Result<MobilePairingGrant, String> {
    Ok(MobilePairingGrant {
        pairing_id: required_string(&value, "pairingId")?,
        endpoint: required_string(&value, "endpoint")?,
        host_name: required_string(&value, "hostName")?,
        expires_at: required_string(&value, "expiresAt")?,
        raw_payload: value,
    })
}

fn required_string(value: &Value, key: &str) -> Result<String, String> {
    value
        .get(key)
        .and_then(Value::as_str)
        .filter(|value| !value.trim().is_empty())
        .map(str::to_string)
        .ok_or_else(|| format!("Mobile Pairing Response Is Missing {key}"))
}

pub(super) fn timestamp(value: &str) -> String {
    DateTime::parse_from_rfc3339(value)
        .map(|value| {
            value
                .with_timezone(&Local)
                .format("%Y-%m-%d %H:%M")
                .to_string()
        })
        .unwrap_or_else(|_| value.to_string())
}

pub(super) fn expiry_label(value: &str) -> String {
    let Ok(expires_at) = DateTime::parse_from_rfc3339(value) else {
        return "Expires Soon".to_string();
    };
    let seconds = expires_at
        .with_timezone(&Utc)
        .signed_duration_since(Utc::now())
        .num_seconds();
    if seconds <= 0 {
        "Expired".to_string()
    } else if seconds >= 60 {
        format!("Expires In {}m", seconds / 60)
    } else {
        format!("Expires In {seconds}s")
    }
}

pub(super) fn is_wildcard_host(value: &str) -> bool {
    matches!(value.trim(), "0.0.0.0" | "::" | "[::]")
}

fn is_loopback_host(value: &str) -> bool {
    let value = value
        .trim()
        .trim_start_matches('[')
        .trim_end_matches(']')
        .trim_end_matches('.')
        .to_lowercase();
    value == "localhost" || value == "::1" || value.starts_with("127.")
}

fn is_tailscale_host(value: &str) -> bool {
    let value = value.trim_matches(['[', ']']);
    value
        .parse::<Ipv4Addr>()
        .map(|ip| ip.octets()[0] == 100 && (64..=127).contains(&ip.octets()[1]))
        .unwrap_or(false)
        || value.to_lowercase().starts_with("fd7a:115c:a1e0:")
}

pub(super) fn validate_pairing_endpoint(
    endpoint: &str,
    enabled: bool,
    gateway_port: u16,
) -> Option<String> {
    let Some((scheme, authority)) = endpoint.trim().split_once("://") else {
        return Some("Endpoint Must Be A ws:// Or wss:// URL With An Explicit Port".into());
    };
    if !matches!(scheme.to_lowercase().as_str(), "ws" | "wss") {
        return Some("Endpoint Must Be A ws:// Or wss:// URL With An Explicit Port".into());
    }
    let authority = authority
        .split(['/', '?', '#'])
        .next()
        .unwrap_or_default()
        .rsplit('@')
        .next()
        .unwrap_or_default();
    let (host, port) = if let Some(rest) = authority.strip_prefix('[') {
        let Some((host, port)) = rest.split_once("]:") else {
            return Some("Endpoint Must Be A ws:// Or wss:// URL With An Explicit Port".into());
        };
        (format!("[{host}]"), port)
    } else {
        let Some((host, port)) = authority.rsplit_once(':') else {
            return Some("Endpoint Must Be A ws:// Or wss:// URL With An Explicit Port".into());
        };
        (host.to_string(), port)
    };
    let Ok(port) = port.parse::<u16>() else {
        return Some("Endpoint Port Must Be Between 1 And 65535".into());
    };
    if port == 0 || host.trim().is_empty() {
        return Some("Endpoint Port Must Be Between 1 And 65535".into());
    }
    if scheme.eq_ignore_ascii_case("ws") && !is_loopback_host(&host) && !is_tailscale_host(&host) {
        return Some("Endpoints Outside Loopback Or A Tailscale Tailnet Must Use wss://".into());
    }
    if scheme.eq_ignore_ascii_case("ws") && enabled && port != gateway_port {
        return Some(format!(
            "ws:// Endpoint Port Must Match The Enabled Gateway Port {gateway_port}"
        ));
    }
    None
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;

    #[test]
    fn endpoint_validation_matches_mobile_pairing_rules() {
        assert!(validate_pairing_endpoint("ws://127.0.0.1:6768", true, 6768).is_none());
        assert!(validate_pairing_endpoint("wss://example.com:443", true, 6768).is_none());
        assert!(validate_pairing_endpoint("ws://100.80.1.2:6768", true, 6768).is_none());
        assert!(validate_pairing_endpoint("ws://[fd7a:115c:a1e0::1]:6768", true, 6768).is_none());
        assert!(validate_pairing_endpoint("ws://example.com:6768", true, 6768).is_some());
        assert!(validate_pairing_endpoint("ws://127.0.0.1:9999", true, 6768).is_some());
        assert!(validate_pairing_endpoint("ws://user@127.0.0.1:6768/path", true, 6768).is_none());
    }

    #[test]
    fn pairing_grant_requires_every_displayed_field() {
        assert!(parse_pairing_grant(json!({"pairingId": "pairing"})).is_err());
        assert!(
            parse_pairing_grant(json!({
                "pairingId": "pairing",
                "endpoint": "wss://example.com:443",
                "hostName": "Alera",
                "expiresAt": "2026-08-08T12:00:00Z"
            }))
            .is_ok()
        );
    }

    #[test]
    fn wildcard_and_loopback_hosts_match_flutter_rules() {
        assert!(is_wildcard_host("0.0.0.0"));
        assert!(is_wildcard_host("[::]"));
        assert!(is_loopback_host("localhost."));
        assert!(is_loopback_host("127.0.0.9"));
        assert!(is_loopback_host("[::1]"));
    }
}
