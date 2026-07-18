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

    assert!(error.contains("outside loopback must use wss://"));
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
