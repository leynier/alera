use std::net::Ipv4Addr;
use std::time::Duration;

use alera_core::child_process::windowless_async_command;
use alera_core::runtime::MobileNetbirdEndpoint;
use anyhow::{bail, Result};
use serde::{Deserialize, Serialize};
use url::Url;

const STATUS_TIMEOUT: Duration = Duration::from_secs(2);

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct NetbirdStatusSummary {
    pub detected: bool,
    pub connected: bool,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub netbird_ip: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub dns_hostname: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub interface_name: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub profile_name: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub management_url: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub management_kind: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub error: Option<String>,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct NetbirdStatus {
    pub connected: bool,
    pub netbird_ipv4: Option<Ipv4Addr>,
    pub dns_hostname: Option<String>,
    pub interface_name: Option<String>,
    pub profile_name: Option<String>,
    pub management_url: Option<String>,
    pub management_kind: Option<String>,
}

pub async fn detect() -> NetbirdStatusSummary {
    match read_status().await {
        Ok(Some(status)) => NetbirdStatusSummary {
            detected: true,
            connected: status.connected,
            netbird_ip: status.netbird_ipv4.map(|ip| ip.to_string()),
            dns_hostname: status.connected.then_some(status.dns_hostname).flatten(),
            interface_name: status.connected.then_some(status.interface_name).flatten(),
            profile_name: status.profile_name,
            management_url: status.management_url,
            management_kind: status.management_kind,
            error: None,
        },
        Ok(None) => NetbirdStatusSummary {
            detected: false,
            connected: false,
            netbird_ip: None,
            dns_hostname: None,
            interface_name: None,
            profile_name: None,
            management_url: None,
            management_kind: None,
            error: None,
        },
        Err(error) => NetbirdStatusSummary {
            detected: true,
            connected: false,
            netbird_ip: None,
            dns_hostname: None,
            interface_name: None,
            profile_name: None,
            management_url: None,
            management_kind: None,
            error: Some(error.to_string()),
        },
    }
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct NetbirdEndpointResolution {
    pub bind_ip: Ipv4Addr,
    pub advertised_host: String,
    pub endpoint_network: Option<String>,
}

pub async fn resolve_netbird_endpoint(
    endpoint: MobileNetbirdEndpoint,
) -> Result<NetbirdEndpointResolution> {
    let Some(status) = read_status().await? else {
        bail!(
            "netbird is not installed; install it from https://netbird.io/download or use a manual wss:// endpoint"
        );
    };
    if !status.connected {
        bail!(
            "netbird is installed but not connected; run `netbird up` and sign in to your network"
        );
    }
    let Some(netbird_ip) = status.netbird_ipv4 else {
        bail!("netbird is connected but reported no NetBird IPv4 address");
    };
    let bind_ip = match endpoint {
        MobileNetbirdEndpoint::Interface => {
            let interface = status.interface_name.as_deref().unwrap_or("wt0");
            resolve_interface_ipv4(interface)?
        }
        MobileNetbirdEndpoint::Ip | MobileNetbirdEndpoint::Dns => netbird_ip,
    };
    let (advertised_host, endpoint_network) = match endpoint {
        MobileNetbirdEndpoint::Dns => {
            let hostname = status.dns_hostname.ok_or_else(|| {
                anyhow::anyhow!("netbird is connected but reported no DNS hostname for this peer")
            })?;
            (hostname, Some("netbird".to_string()))
        }
        MobileNetbirdEndpoint::Ip | MobileNetbirdEndpoint::Interface => (bind_ip.to_string(), None),
    };
    Ok(NetbirdEndpointResolution {
        bind_ip,
        advertised_host,
        endpoint_network,
    })
}

fn resolve_interface_ipv4(interface_name: &str) -> Result<Ipv4Addr> {
    let interface_name = interface_name.trim();
    if interface_name.is_empty() {
        bail!("netbird reported an empty private interface name");
    }
    let addresses = if_addrs::get_if_addrs()
        .map_err(|error| anyhow::anyhow!("failed to inspect network interfaces: {error}"))?;
    addresses
        .into_iter()
        .find_map(|interface| {
            if interface.name != interface_name {
                return None;
            }
            match interface.addr {
                if_addrs::IfAddr::V4(address) => Some(address.ip),
                if_addrs::IfAddr::V6(_) => None,
            }
        })
        .ok_or_else(|| anyhow::anyhow!("NetBird interface {interface_name} has no IPv4 address"))
}

async fn read_status() -> Result<Option<NetbirdStatus>> {
    for candidate in binary_candidates() {
        let command = windowless_async_command(candidate)
            .args(["status", "--json"])
            .kill_on_drop(true)
            .output();
        let output = match tokio::time::timeout(STATUS_TIMEOUT, command).await {
            Ok(Ok(output)) => output,
            Ok(Err(error)) if error.kind() == std::io::ErrorKind::NotFound => continue,
            Ok(Err(error)) => bail!("netbird status failed to launch: {error}"),
            Err(_) => bail!("netbird status timed out"),
        };
        if !output.status.success() {
            let stderr = String::from_utf8_lossy(&output.stderr);
            bail!("netbird status failed: {}", stderr.trim());
        }
        let stdout = String::from_utf8_lossy(&output.stdout);
        return parse_status_json(&stdout).map(Some);
    }
    Ok(None)
}

fn binary_candidates() -> Vec<&'static str> {
    let mut candidates = vec!["netbird"];
    if cfg!(target_os = "macos") {
        candidates.extend([
            "/usr/local/bin/netbird",
            "/opt/homebrew/bin/netbird",
            "/Applications/NetBird.app/Contents/MacOS/netbird",
        ]);
    } else if cfg!(windows) {
        candidates.push("C:\\Program Files\\NetBird\\netbird.exe");
    } else {
        candidates.extend([
            "/usr/local/bin/netbird",
            "/usr/bin/netbird",
            "/usr/sbin/netbird",
        ]);
    }
    candidates
}

fn parse_status_json(raw: &str) -> Result<NetbirdStatus> {
    let status: serde_json::Value = serde_json::from_str(raw)
        .map_err(|error| anyhow::anyhow!("netbird status returned invalid JSON: {error}"))?;
    let local_peer = status.get("localPeerState");
    let netbird_ipv4 = local_peer
        .and_then(|peer| peer.get("IP"))
        .and_then(serde_json::Value::as_str)
        .and_then(parse_ipv4_with_optional_cidr)
        .or_else(|| {
            status
                .get("netbirdIp")
                .and_then(serde_json::Value::as_str)
                .and_then(parse_ipv4_with_optional_cidr)
        });
    let dns_hostname = local_peer
        .and_then(|peer| peer.get("fqdn").or_else(|| peer.get("hostname")))
        .and_then(serde_json::Value::as_str)
        .and_then(non_empty_string);
    let interface_name = local_peer
        .and_then(|peer| {
            ["interfaceName", "interface", "wgIface"]
                .into_iter()
                .find_map(|key| peer.get(key).and_then(serde_json::Value::as_str))
        })
        .or_else(|| {
            ["interfaceName", "interface", "wgIface"]
                .into_iter()
                .find_map(|key| status.get(key).and_then(serde_json::Value::as_str))
        })
        .and_then(non_empty_string)
        .or_else(|| Some("wt0".to_string()));
    let management = status.get("management");
    let management_url = management
        .and_then(|value| value.get("url"))
        .and_then(serde_json::Value::as_str)
        .and_then(sanitize_management_url);
    let management_kind = management_url.as_deref().map(classify_management_url);
    let daemon_status = status
        .get("daemonStatus")
        .or_else(|| status.get("status"))
        .and_then(serde_json::Value::as_str);
    let management_connected = status
        .get("managementState")
        .and_then(|value| value.as_str().map(|state| state == "Connected"))
        .or_else(|| {
            management
                .and_then(|value| value.get("connected"))
                .and_then(serde_json::Value::as_bool)
        })
        .unwrap_or(false);
    let connected =
        daemon_status == Some("Connected") && management_connected && netbird_ipv4.is_some();
    Ok(NetbirdStatus {
        connected,
        netbird_ipv4,
        dns_hostname,
        interface_name,
        profile_name: status
            .get("profileName")
            .and_then(serde_json::Value::as_str)
            .and_then(non_empty_string),
        management_url,
        management_kind,
    })
}

fn non_empty_string(value: &str) -> Option<String> {
    let value = value.trim();
    (!value.is_empty()).then(|| value.to_string())
}

fn parse_ipv4_with_optional_cidr(value: &str) -> Option<Ipv4Addr> {
    value
        .trim()
        .split('/')
        .next()
        .and_then(|address| address.parse().ok())
}

fn sanitize_management_url(value: &str) -> Option<String> {
    let url = Url::parse(value).ok()?;
    let host = url.host_str()?.trim();
    if host.is_empty() {
        return None;
    }
    let host = if host.contains(':') {
        format!("[{host}]")
    } else {
        host.to_string()
    };
    let port = explicit_url_port(value)
        .or_else(|| url.port().map(|port| port.to_string()))
        .map(|port| format!(":{port}"))
        .unwrap_or_default();
    Some(format!("{}://{host}{port}", url.scheme()))
}

fn explicit_url_port(value: &str) -> Option<String> {
    let authority = value
        .split_once("://")
        .map(|(_, rest)| rest)
        .unwrap_or(value)
        .split(['/', '?', '#'])
        .next()?;
    if let Some(rest) = authority.strip_prefix('[') {
        return rest
            .split_once(']')
            .and_then(|(_, after)| after.strip_prefix(':'))
            .filter(|port| !port.is_empty())
            .map(str::to_string);
    }
    authority
        .rsplit_once(':')
        .map(|(_, port)| port)
        .filter(|port| !port.is_empty() && port.chars().all(|character| character.is_ascii_digit()))
        .map(str::to_string)
}

fn classify_management_url(value: &str) -> String {
    Url::parse(value)
        .ok()
        .and_then(|url| url.host_str().map(str::to_ascii_lowercase))
        .map(|host| {
            if host == "api.netbird.io" {
                "cloud".to_string()
            } else {
                "selfHosted".to_string()
            }
        })
        .unwrap_or_else(|| "unknown".to_string())
}

#[cfg(test)]
mod tests {
    use super::{
        classify_management_url, parse_ipv4_with_optional_cidr, parse_status_json,
        resolve_interface_ipv4,
    };
    use std::net::Ipv4Addr;

    #[test]
    fn parses_connected_cloud_status() {
        let status = parse_status_json(
            r#"{
                "status":"Connected",
                "managementState":"Connected",
                "localPeerState":{"IP":"100.121.195.4/16","fqdn":"laptop.netbird.cloud","interfaceName":"wt0"},
                "profileName":"default",
                "management":{"url":"https://api.netbird.io:443/path?token=secret"}
            }"#,
        )
        .unwrap();

        assert!(status.connected);
        assert_eq!(status.netbird_ipv4, Some(Ipv4Addr::new(100, 121, 195, 4)));
        assert_eq!(status.dns_hostname.as_deref(), Some("laptop.netbird.cloud"));
        assert_eq!(status.interface_name.as_deref(), Some("wt0"));
        assert_eq!(status.profile_name.as_deref(), Some("default"));
        assert_eq!(
            status.management_url.as_deref(),
            Some("https://api.netbird.io:443")
        );
        assert_eq!(status.management_kind.as_deref(), Some("cloud"));
    }

    #[test]
    fn parses_disconnected_self_hosted_status() {
        let status = parse_status_json(
            r#"{
                "status":"NeedsLogin",
                "managementState":"Disconnected",
                "localPeerState":{"IP":"","fqdn":""},
                "management":{"url":"https://nb.example.test"}
            }"#,
        )
        .unwrap();

        assert!(!status.connected);
        assert_eq!(status.netbird_ipv4, None);
        assert_eq!(
            status.management_url.as_deref(),
            Some("https://nb.example.test")
        );
        assert_eq!(status.management_kind.as_deref(), Some("selfHosted"));
    }

    #[test]
    fn parses_legacy_status_shape_and_defaults_interface_name() {
        let status = parse_status_json(
            r#"{
                "daemonStatus":"Connected",
                "netbirdIp":"100.121.195.4/16",
                "management":{"connected":true,"url":"https://nb.example.test"}
            }"#,
        )
        .unwrap();

        assert!(status.connected);
        assert_eq!(status.interface_name.as_deref(), Some("wt0"));
    }

    #[test]
    fn interface_resolution_rejects_unknown_interface() {
        assert!(resolve_interface_ipv4("definitely-not-a-netbird-interface").is_err());
    }

    #[test]
    fn accepts_ipv4_without_cidr() {
        assert_eq!(
            parse_ipv4_with_optional_cidr("100.64.1.2"),
            Some(Ipv4Addr::new(100, 64, 1, 2))
        );
    }

    #[test]
    fn rejects_invalid_status_json() {
        assert!(parse_status_json("not json").is_err());
    }

    #[test]
    fn classifies_only_netbird_cloud_as_cloud() {
        assert_eq!(classify_management_url("https://api.netbird.io"), "cloud");
        assert_eq!(
            classify_management_url("https://netbird.example.test"),
            "selfHosted"
        );
    }
}
