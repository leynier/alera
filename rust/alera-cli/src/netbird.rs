use std::net::Ipv4Addr;
use std::time::Duration;

use alera_core::child_process::windowless_async_command;
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
            profile_name: status.profile_name,
            management_url: status.management_url,
            management_kind: status.management_kind,
            error: None,
        },
        Ok(None) => NetbirdStatusSummary {
            detected: false,
            connected: false,
            netbird_ip: None,
            profile_name: None,
            management_url: None,
            management_kind: None,
            error: None,
        },
        Err(error) => NetbirdStatusSummary {
            detected: true,
            connected: false,
            netbird_ip: None,
            profile_name: None,
            management_url: None,
            management_kind: None,
            error: Some(error.to_string()),
        },
    }
}

pub async fn resolve_netbird_bind_ip() -> Result<Ipv4Addr> {
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
    let Some(ip) = status.netbird_ipv4 else {
        bail!("netbird is connected but reported no NetBird IPv4 address");
    };
    Ok(ip)
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
    #[derive(Deserialize)]
    struct StatusJson {
        #[serde(rename = "daemonStatus")]
        daemon_status: Option<String>,
        #[serde(rename = "netbirdIp")]
        netbird_ip: Option<String>,
        #[serde(rename = "profileName")]
        profile_name: Option<String>,
        management: Option<ConnectionState>,
    }

    #[derive(Deserialize)]
    struct ConnectionState {
        connected: bool,
        url: Option<String>,
    }

    let status: StatusJson = serde_json::from_str(raw)
        .map_err(|error| anyhow::anyhow!("netbird status returned invalid JSON: {error}"))?;
    let netbird_ipv4 = status
        .netbird_ip
        .as_deref()
        .and_then(parse_ipv4_with_optional_cidr);
    let management_url = status
        .management
        .as_ref()
        .and_then(|management| management.url.as_deref())
        .and_then(sanitize_management_url);
    let management_kind = management_url.as_deref().map(classify_management_url);
    let connected = status.daemon_status.as_deref() == Some("Connected")
        && status
            .management
            .as_ref()
            .is_some_and(|management| management.connected)
        && netbird_ipv4.is_some();
    Ok(NetbirdStatus {
        connected,
        netbird_ipv4,
        profile_name: status.profile_name.filter(|value| !value.trim().is_empty()),
        management_url,
        management_kind,
    })
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
    let port = url
        .port()
        .map(|port| format!(":{port}"))
        .unwrap_or_default();
    Some(format!("{}://{host}{port}", url.scheme()))
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
    use super::{classify_management_url, parse_ipv4_with_optional_cidr, parse_status_json};
    use std::net::Ipv4Addr;

    #[test]
    fn parses_connected_cloud_status() {
        let status = parse_status_json(
            r#"{
                "daemonStatus":"Connected",
                "netbirdIp":"100.121.195.4/16",
                "profileName":"default",
                "management":{"connected":true,"url":"https://api.netbird.io:443/path?token=secret"}
            }"#,
        )
        .unwrap();

        assert!(status.connected);
        assert_eq!(status.netbird_ipv4, Some(Ipv4Addr::new(100, 121, 195, 4)));
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
                "daemonStatus":"NeedsLogin",
                "netbirdIp":"",
                "management":{"connected":false,"url":"https://nb.example.test"}
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
