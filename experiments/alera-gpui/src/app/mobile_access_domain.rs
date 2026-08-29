fn parse_mobile_status(value: Value) -> Result<MobileAccessStatus, String> {
    serde_json::from_value(value).map_err(|error| format!("Mobile Access Unavailable: {error}"))
}

fn parse_pairing_grant(value: Value) -> Result<MobilePairingGrant, String> {
    let pairing_id = required_string(&value, "pairingId")?;
    let endpoint = required_string(&value, "endpoint")?;
    let host_name = required_string(&value, "hostName")?;
    let expires_at = required_string(&value, "expiresAt")?;
    Ok(MobilePairingGrant {
        pairing_id,
        endpoint,
        host_name,
        expires_at,
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

pub(super) fn mobile_timestamp(value: &str) -> String {
    DateTime::parse_from_rfc3339(value)
        .map(|value| {
            value
                .with_timezone(&Local)
                .format("%Y-%m-%d %H:%M")
                .to_string()
        })
        .unwrap_or_else(|_| value.to_string())
}

pub(super) fn mobile_expiry_label(value: &str) -> String {
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

pub(super) fn is_loopback_host(value: &str) -> bool {
    let value = value
        .trim()
        .trim_start_matches('[')
        .trim_end_matches(']')
        .trim_end_matches('.')
        .to_lowercase();
    value == "localhost" || value == "::1" || value.starts_with("127.")
}

fn validate_pairing_endpoint(
    endpoint: &str,
    enabled: bool,
    gateway_port: u16,
    netbird_dns: bool,
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
    let safe_insecure_host = is_loopback_host(&host)
        || is_private_overlay_host(&host)
        || (netbird_dns && is_dns_hostname(&host));
    if scheme.eq_ignore_ascii_case("ws") && !safe_insecure_host {
        return Some("Endpoints Outside Loopback Or A Private Overlay Must Use wss://".into());
    }
    if scheme.eq_ignore_ascii_case("ws") && enabled && port != gateway_port {
        return Some(format!(
            "ws:// Endpoint Port Must Match The Enabled Gateway Port {gateway_port}"
        ));
    }
    None
}

#[cfg(test)]
mod remote_access_tests {
    use super::parse_mobile_status;
    use serde_json::json;

    #[test]
    fn remote_access_defaults_off_and_parses_when_enabled() {
        let base = json!({
            "settings": {
                "enabled": true,
                "bindHost": "127.0.0.1",
                "port": 6768
            },
            "devices": [],
            "activePairings": []
        });
        assert!(!parse_mobile_status(base.clone())
            .unwrap()
            .settings
            .remote_access_enabled);
        let mut enabled = base;
        enabled["settings"]["remoteAccessEnabled"] = json!(true);
        assert!(parse_mobile_status(enabled)
            .unwrap()
            .settings
            .remote_access_enabled);
    }
}

fn is_dns_hostname(value: &str) -> bool {
    let value = value.trim().trim_matches(['[', ']']);
    !value.is_empty()
        && !value.contains(':')
        && value.contains('.')
        && !value.starts_with('.')
        && !value.ends_with('.')
        && value
            .chars()
            .all(|character| character.is_ascii_alphanumeric() || matches!(character, '-' | '.'))
}

fn is_private_overlay_host(value: &str) -> bool {
    value
        .trim_matches(['[', ']'])
        .parse::<std::net::Ipv4Addr>()
        .map(|ip| ip.octets()[0] == 100 && (64..=127).contains(&ip.octets()[1]))
        .unwrap_or(false)
        || value
            .trim_matches(['[', ']'])
            .to_lowercase()
        .starts_with("fd7a:115c:a1e0:")
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn endpoint_validation_matches_mobile_pairing_rules() {
        assert!(validate_pairing_endpoint("ws://127.0.0.1:6768", true, 6768, false).is_none());
        assert!(validate_pairing_endpoint("wss://example.com:443", true, 6768, false).is_none());
        assert!(validate_pairing_endpoint("https://example.com:443", true, 6768, false).is_some());
        assert!(validate_pairing_endpoint("ws://example.com:6768", true, 6768, false).is_some());
        assert!(validate_pairing_endpoint("ws://127.0.0.1:9999", true, 6768, false).is_some());
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
