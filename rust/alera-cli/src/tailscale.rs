use std::net::{IpAddr, Ipv4Addr};
use std::time::Duration;

use alera_core::child_process::windowless_async_command;
use anyhow::{bail, Result};
use serde::{Deserialize, Serialize};

const STATUS_TIMEOUT: Duration = Duration::from_secs(2);

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct TailscaleStatusSummary {
    pub detected: bool,
    pub running: bool,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub tailnet_ip: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub error: Option<String>,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct TailscaleStatus {
    pub running: bool,
    pub tailnet_ipv4: Option<Ipv4Addr>,
}

pub fn is_tailscale_ip(address: IpAddr) -> bool {
    match address {
        IpAddr::V4(v4) => {
            let octets = v4.octets();
            octets[0] == 100 && (64..=127).contains(&octets[1])
        }
        IpAddr::V6(v6) => {
            let segments = v6.segments();
            segments[0] == 0xfd7a && segments[1] == 0x115c && segments[2] == 0xa1e0
        }
    }
}

pub async fn detect() -> TailscaleStatusSummary {
    match read_status().await {
        Ok(Some(status)) => TailscaleStatusSummary {
            detected: true,
            running: status.running,
            tailnet_ip: status.tailnet_ipv4.map(|ip| ip.to_string()),
            error: None,
        },
        Ok(None) => TailscaleStatusSummary {
            detected: false,
            running: false,
            tailnet_ip: None,
            error: None,
        },
        Err(error) => TailscaleStatusSummary {
            detected: true,
            running: false,
            tailnet_ip: None,
            error: Some(error.to_string()),
        },
    }
}

pub async fn resolve_tailnet_bind_ip() -> Result<Ipv4Addr> {
    let Some(status) = read_status().await? else {
        bail!(
            "tailscale is not installed; install it from https://tailscale.com/download or use a manual wss:// endpoint"
        );
    };
    if !status.running {
        bail!("tailscale is installed but not running; run `tailscale up` and retry");
    }
    let Some(ip) = status.tailnet_ipv4 else {
        bail!("tailscale is running but reported no tailnet IPv4 address for this machine");
    };
    Ok(ip)
}

async fn read_status() -> Result<Option<TailscaleStatus>> {
    for candidate in binary_candidates() {
        let command = windowless_async_command(candidate)
            .args(["status", "--json"])
            .kill_on_drop(true)
            .output();
        let output = match tokio::time::timeout(STATUS_TIMEOUT, command).await {
            Ok(Ok(output)) => output,
            Ok(Err(error)) if error.kind() == std::io::ErrorKind::NotFound => continue,
            Ok(Err(error)) => bail!("tailscale status failed to launch: {error}"),
            Err(_) => bail!("tailscale status timed out"),
        };
        if !output.status.success() {
            let stderr = String::from_utf8_lossy(&output.stderr);
            bail!("tailscale status failed: {}", stderr.trim());
        }
        let stdout = String::from_utf8_lossy(&output.stdout);
        return parse_status_json(&stdout).map(Some);
    }
    Ok(None)
}

fn binary_candidates() -> Vec<&'static str> {
    let mut candidates = vec!["tailscale"];
    if cfg!(target_os = "macos") {
        candidates.extend([
            "/usr/local/bin/tailscale",
            "/opt/homebrew/bin/tailscale",
            "/Applications/Tailscale.app/Contents/MacOS/Tailscale",
        ]);
    } else if cfg!(windows) {
        candidates.push("C:\\Program Files\\Tailscale\\tailscale.exe");
    } else {
        candidates.extend(["/usr/bin/tailscale", "/usr/sbin/tailscale"]);
    }
    candidates
}

fn parse_status_json(raw: &str) -> Result<TailscaleStatus> {
    #[derive(Deserialize)]
    struct StatusJson {
        #[serde(rename = "BackendState")]
        backend_state: Option<String>,
        #[serde(rename = "Self")]
        self_status: Option<SelfJson>,
    }

    #[derive(Deserialize)]
    struct SelfJson {
        #[serde(rename = "TailscaleIPs")]
        tailscale_ips: Option<Vec<String>>,
    }

    let status: StatusJson = serde_json::from_str(raw)
        .map_err(|error| anyhow::anyhow!("tailscale status returned invalid JSON: {error}"))?;
    let running = status.backend_state.as_deref() == Some("Running");
    let tailnet_ipv4 = status
        .self_status
        .and_then(|self_status| self_status.tailscale_ips)
        .unwrap_or_default()
        .iter()
        .filter_map(|value| value.trim().parse::<Ipv4Addr>().ok())
        .find(|ip| is_tailscale_ip(IpAddr::V4(*ip)));
    Ok(TailscaleStatus {
        running,
        tailnet_ipv4,
    })
}

#[cfg(test)]
mod tests;
