use std::net::IpAddr;

use super::{is_tailscale_ip, parse_status_json};

fn ip(value: &str) -> IpAddr {
    value.parse().unwrap()
}

#[test]
fn tailscale_ipv4_range_boundaries() {
    assert!(!is_tailscale_ip(ip("100.63.255.255")));
    assert!(is_tailscale_ip(ip("100.64.0.0")));
    assert!(is_tailscale_ip(ip("100.101.102.103")));
    assert!(is_tailscale_ip(ip("100.127.255.255")));
    assert!(!is_tailscale_ip(ip("100.128.0.0")));
    assert!(!is_tailscale_ip(ip("192.168.1.10")));
    assert!(!is_tailscale_ip(ip("127.0.0.1")));
}

#[test]
fn tailscale_ipv6_prefix_boundaries() {
    assert!(is_tailscale_ip(ip("fd7a:115c:a1e0::1")));
    assert!(is_tailscale_ip(ip("fd7a:115c:a1e0:ab12::4")));
    assert!(!is_tailscale_ip(ip("fd7a:115c:a1e1::1")));
    assert!(!is_tailscale_ip(ip("fd7b:115c:a1e0::1")));
    assert!(!is_tailscale_ip(ip("::1")));
}

#[test]
fn parses_running_status_with_self_ips() {
    let status = parse_status_json(
        r#"{
            "BackendState": "Running",
            "Self": {
                "TailscaleIPs": ["100.101.102.103", "fd7a:115c:a1e0:ab12::4"]
            }
        }"#,
    )
    .unwrap();
    assert!(status.running);
    assert_eq!(
        status.tailnet_ipv4,
        Some("100.101.102.103".parse().unwrap())
    );
}

#[test]
fn parses_stopped_status_without_self() {
    let status = parse_status_json(r#"{"BackendState": "Stopped"}"#).unwrap();
    assert!(!status.running);
    assert_eq!(status.tailnet_ipv4, None);
}

#[test]
fn ignores_non_tailnet_addresses_in_self_ips() {
    let status = parse_status_json(
        r#"{
            "BackendState": "Running",
            "Self": {"TailscaleIPs": ["192.168.1.5"]}
        }"#,
    )
    .unwrap();
    assert!(status.running);
    assert_eq!(status.tailnet_ipv4, None);
}

#[test]
fn rejects_invalid_json() {
    assert!(parse_status_json("not json").is_err());
}
