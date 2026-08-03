use super::*;

#[test]
fn pairing_settings_adopt_plaintext_loopback_endpoint_port_before_persistence() {
    let settings = MobileAccessSettings::default();
    let request = MobilePairingCreateRequest {
        endpoint: Some("ws://127.0.0.1:6123".to_string()),
        device_name: None,
        expires_minutes: None,
    };

    let (next, endpoint) = prepare_mobile_pairing_offer_settings(settings, &request).unwrap();

    assert!(next.enabled);
    assert_eq!(next.port, 6123);
    assert_eq!(endpoint, "ws://127.0.0.1:6123");
}

#[test]
fn pairing_settings_keep_wss_proxy_endpoint_port_separate_when_disabled() {
    let settings = MobileAccessSettings::default();
    let request = MobilePairingCreateRequest {
        endpoint: Some("wss://alera.example.test:443".to_string()),
        device_name: None,
        expires_minutes: None,
    };

    let (next, endpoint) = prepare_mobile_pairing_offer_settings(settings, &request).unwrap();

    assert!(next.enabled);
    assert_eq!(next.port, 6768);
    assert_eq!(endpoint, "wss://alera.example.test:443");
}

#[test]
fn pairing_settings_allow_wss_proxy_endpoint_port_mismatch_when_enabled() {
    let settings = MobileAccessSettings {
        enabled: true,
        port: 6768,
        ..MobileAccessSettings::default()
    };
    let request = MobilePairingCreateRequest {
        endpoint: Some("wss://alera.example.test:443".to_string()),
        device_name: None,
        expires_minutes: None,
    };

    let (next, endpoint) = prepare_mobile_pairing_offer_settings(settings, &request).unwrap();

    assert!(next.enabled);
    assert_eq!(next.port, 6768);
    assert_eq!(endpoint, "wss://alera.example.test:443");
}

#[test]
fn pairing_settings_reject_mismatched_endpoint_port_when_enabled() {
    let settings = MobileAccessSettings {
        enabled: true,
        port: 6123,
        ..MobileAccessSettings::default()
    };
    let request = MobilePairingCreateRequest {
        endpoint: Some("ws://127.0.0.1:7123".to_string()),
        device_name: None,
        expires_minutes: None,
    };

    let error = prepare_mobile_pairing_offer_settings(settings, &request)
        .unwrap_err()
        .to_string();

    assert!(error.contains("does not match enabled mobile gateway port 6123"));
}

#[test]
fn pairing_settings_reject_endpoint_without_explicit_port() {
    let settings = MobileAccessSettings::default();
    let request = MobilePairingCreateRequest {
        endpoint: Some("wss://alera.example.test".to_string()),
        device_name: None,
        expires_minutes: None,
    };

    let error = prepare_mobile_pairing_offer_settings(settings, &request)
        .unwrap_err()
        .to_string();

    assert!(error.contains("must include an explicit port"));
}

#[test]
fn pairing_settings_accept_endpoint_with_query_after_explicit_port() {
    let settings = MobileAccessSettings::default();
    let request = MobilePairingCreateRequest {
        endpoint: Some("wss://alera.example.test:443?token=abc".to_string()),
        device_name: None,
        expires_minutes: None,
    };

    let (next, endpoint) = prepare_mobile_pairing_offer_settings(settings, &request).unwrap();

    assert!(next.enabled);
    assert_eq!(next.port, 6768);
    assert_eq!(endpoint, "wss://alera.example.test:443?token=abc");
}

#[test]
fn pairing_settings_reject_query_that_only_looks_like_port() {
    let settings = MobileAccessSettings::default();
    let request = MobilePairingCreateRequest {
        endpoint: Some("wss://alera.example.test?token=:443".to_string()),
        device_name: None,
        expires_minutes: None,
    };

    let error = prepare_mobile_pairing_offer_settings(settings, &request)
        .unwrap_err()
        .to_string();

    assert!(error.contains("must include an explicit port"));
}

#[test]
fn pairing_settings_reject_endpoint_zero_port() {
    let settings = MobileAccessSettings::default();
    let request = MobilePairingCreateRequest {
        endpoint: Some("ws://127.0.0.1:0".to_string()),
        device_name: None,
        expires_minutes: None,
    };

    let error = prepare_mobile_pairing_offer_settings(settings, &request)
        .unwrap_err()
        .to_string();

    assert!(error.contains("port must be between 1 and 65535"));
}

#[test]
fn pairing_settings_reject_plaintext_external_endpoint() {
    let settings = MobileAccessSettings::default();
    let request = MobilePairingCreateRequest {
        endpoint: Some("ws://192.168.1.50:6768".to_string()),
        device_name: None,
        expires_minutes: None,
    };

    let error = prepare_mobile_pairing_offer_settings(settings, &request)
        .unwrap_err()
        .to_string();

    assert!(error.contains("outside loopback or a private overlay must use wss://"));
}

#[test]
fn pairing_settings_allow_plaintext_tailscale_endpoint_with_port_match() {
    let settings = MobileAccessSettings::default();
    let request = MobilePairingCreateRequest {
        endpoint: Some("ws://100.101.102.103:6123".to_string()),
        device_name: None,
        expires_minutes: None,
    };

    let (next, endpoint) = prepare_mobile_pairing_offer_settings(settings, &request).unwrap();

    assert!(next.enabled);
    assert_eq!(next.port, 6123);
    assert_eq!(endpoint, "ws://100.101.102.103:6123");
}

#[test]
fn pairing_settings_reject_plaintext_tailscale_endpoint_on_port_mismatch_when_enabled() {
    let settings = MobileAccessSettings {
        enabled: true,
        ..MobileAccessSettings::default()
    };
    let request = MobilePairingCreateRequest {
        endpoint: Some("ws://100.101.102.103:7000".to_string()),
        device_name: None,
        expires_minutes: None,
    };

    let error = prepare_mobile_pairing_offer_settings(settings, &request)
        .unwrap_err()
        .to_string();

    assert!(error.contains("does not match enabled mobile gateway port"));
}

#[test]
fn pairing_settings_reject_plaintext_cgnat_endpoint_outside_tailscale_range() {
    let settings = MobileAccessSettings::default();
    let request = MobilePairingCreateRequest {
        endpoint: Some("ws://100.63.0.1:6768".to_string()),
        device_name: None,
        expires_minutes: None,
    };

    let error = prepare_mobile_pairing_offer_settings(settings, &request)
        .unwrap_err()
        .to_string();

    assert!(error.contains("outside loopback or a private overlay must use wss://"));
}

#[test]
fn pairing_settings_accept_plaintext_netbird_endpoint_with_port_match() {
    let settings = MobileAccessSettings::default();
    let request = MobilePairingCreateRequest {
        endpoint: Some("ws://100.121.195.4:6123".to_string()),
        device_name: None,
        expires_minutes: None,
    };

    let (next, endpoint) = prepare_mobile_pairing_offer_settings(settings, &request).unwrap();

    assert!(next.enabled);
    assert_eq!(next.port, 6123);
    assert_eq!(endpoint, "ws://100.121.195.4:6123");
}

#[test]
fn pairing_settings_accept_netbird_dns_endpoint_only_for_netbird_payloads() {
    let endpoint = validate_pairing_endpoint(
        "ws://laptop.netbird.example:6123".to_string(),
        Some("netbird"),
    )
    .unwrap();
    assert_eq!(endpoint.value, "ws://laptop.netbird.example:6123");
    assert!(
        validate_pairing_endpoint("ws://laptop.netbird.example:6123".to_string(), None,).is_err()
    );
}

#[test]
fn pairing_settings_allow_plaintext_tailscale_ipv6_endpoint() {
    let settings = MobileAccessSettings::default();
    let request = MobilePairingCreateRequest {
        endpoint: Some("ws://[fd7a:115c:a1e0:ab12::4]:6768".to_string()),
        device_name: None,
        expires_minutes: None,
    };

    let (next, endpoint) = prepare_mobile_pairing_offer_settings(settings, &request).unwrap();

    assert!(next.enabled);
    assert_eq!(endpoint, "ws://[fd7a:115c:a1e0:ab12::4]:6768");
}

#[test]
fn settings_update_applies_endpoint_mode() {
    let settings = apply_mobile_settings_update(
        MobileAccessSettings::default(),
        MobileSettingsUpdateRequest {
            enabled: Some(true),
            remote_access_enabled: None,
            bind_host: None,
            port: None,
            endpoint_mode: Some(MobileEndpointMode::Tailscale),
            netbird_endpoint: None,
        },
    )
    .unwrap();

    assert_eq!(settings.endpoint_mode, MobileEndpointMode::Tailscale);
    assert_eq!(settings.bind_host, "127.0.0.1");
}

#[test]
fn settings_update_applies_netbird_endpoint_source() {
    let settings = apply_mobile_settings_update(
        MobileAccessSettings::default(),
        MobileSettingsUpdateRequest {
            enabled: None,
            bind_host: None,
            port: None,
            endpoint_mode: Some(MobileEndpointMode::Netbird),
            netbird_endpoint: Some(MobileNetbirdEndpoint::Dns),
        },
    )
    .unwrap();

    assert_eq!(settings.endpoint_mode, MobileEndpointMode::Netbird);
    assert_eq!(settings.netbird_endpoint, MobileNetbirdEndpoint::Dns);
}

#[test]
fn pairing_settings_allow_plaintext_loopback_endpoint() {
    let settings = MobileAccessSettings::default();
    let request = MobilePairingCreateRequest {
        endpoint: Some("ws://127.0.0.1:6768".to_string()),
        device_name: None,
        expires_minutes: None,
    };

    let (next, endpoint) = prepare_mobile_pairing_offer_settings(settings, &request).unwrap();

    assert!(next.enabled);
    assert_eq!(endpoint, "ws://127.0.0.1:6768");
}

#[test]
fn pairing_settings_bracket_ipv6_default_endpoint() {
    let settings = MobileAccessSettings {
        bind_host: "::1".to_string(),
        ..MobileAccessSettings::default()
    };
    let request = MobilePairingCreateRequest {
        endpoint: None,
        device_name: None,
        expires_minutes: None,
    };

    let (next, endpoint) = prepare_mobile_pairing_offer_settings(settings, &request).unwrap();

    assert!(next.enabled);
    assert_eq!(endpoint, "ws://[::1]:6768");
}
