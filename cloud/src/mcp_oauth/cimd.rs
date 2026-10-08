use std::{
    net::{IpAddr, Ipv4Addr, Ipv6Addr, SocketAddr},
    time::Duration,
};

use anyhow::{anyhow, bail};
use async_trait::async_trait;
use reqwest::{redirect::Policy, Client, StatusCode};
use url::Url;

pub const MAX_DOCUMENT_BYTES: usize = 16 * 1024;
const FETCH_TIMEOUT: Duration = Duration::from_secs(5);

/// Loads Client ID Metadata Documents. Tests replace it so they never reach the network.
#[async_trait]
pub trait ClientMetadataFetcher: Send + Sync {
    async fn fetch(&self, url: &Url) -> anyhow::Result<Vec<u8>>;
}

pub struct HttpClientMetadataFetcher {
    timeout: Duration,
}

impl Default for HttpClientMetadataFetcher {
    fn default() -> Self {
        Self {
            timeout: FETCH_TIMEOUT,
        }
    }
}

#[async_trait]
impl ClientMetadataFetcher for HttpClientMetadataFetcher {
    async fn fetch(&self, url: &Url) -> anyhow::Result<Vec<u8>> {
        tokio::time::timeout(self.timeout, fetch_document(url, self.timeout))
            .await
            .map_err(|_| anyhow!("client metadata document fetch timed out"))?
    }
}

async fn fetch_document(url: &Url, timeout: Duration) -> anyhow::Result<Vec<u8>> {
    if url.scheme() != "https" {
        bail!("client metadata documents must use https");
    }
    let host = url
        .host_str()
        .ok_or_else(|| anyhow!("client metadata URL has no host"))?;
    let port = url.port_or_known_default().unwrap_or(443);
    let addresses: Vec<SocketAddr> = match url.host() {
        Some(url::Host::Ipv4(ip)) => vec![SocketAddr::new(IpAddr::V4(ip), port)],
        Some(url::Host::Ipv6(ip)) => vec![SocketAddr::new(IpAddr::V6(ip), port)],
        _ => tokio::net::lookup_host((host, port)).await?.collect(),
    };
    let first = *addresses
        .first()
        .ok_or_else(|| anyhow!("client metadata host did not resolve"))?;
    if addresses
        .iter()
        .any(|address| is_forbidden_address(address.ip()))
    {
        bail!("client metadata host resolves to a forbidden address");
    }
    // Pinning the checked address keeps a second DNS answer from reaching a private host.
    let mut builder = Client::builder().timeout(timeout).redirect(Policy::none());
    if matches!(url.host(), Some(url::Host::Domain(_))) {
        builder = builder.resolve(host, first);
    }
    let client = builder.build()?;
    let mut response = client
        .get(url.clone())
        .header("Accept", "application/json")
        .send()
        .await?;
    if response.status() != StatusCode::OK {
        bail!("client metadata document returned {}", response.status());
    }
    if response
        .content_length()
        .is_some_and(|length| length > MAX_DOCUMENT_BYTES as u64)
    {
        bail!("client metadata document is too large");
    }
    let mut body = Vec::new();
    while let Some(chunk) = response.chunk().await? {
        if body.len() + chunk.len() > MAX_DOCUMENT_BYTES {
            bail!("client metadata document is too large");
        }
        body.extend_from_slice(&chunk);
    }
    Ok(body)
}

/// Returns true for addresses a server-side fetch must never reach.
pub fn is_forbidden_address(address: IpAddr) -> bool {
    match address {
        IpAddr::V4(ip) => is_forbidden_v4(ip),
        IpAddr::V6(ip) => is_forbidden_v6(ip),
    }
}

fn is_forbidden_v4(ip: Ipv4Addr) -> bool {
    let [a, b, c, _] = ip.octets();
    ip.is_private()
        || ip.is_loopback()
        || ip.is_link_local()
        || ip.is_unspecified()
        || ip.is_broadcast()
        || ip.is_multicast()
        || ip.is_documentation()
        || a == 0
        || (a == 100 && (64..=127).contains(&b))
        || (a == 192 && b == 0 && c == 0)
        || (a == 198 && (18..=19).contains(&b))
        || a >= 240
}

fn is_forbidden_v6(ip: Ipv6Addr) -> bool {
    if let Some(mapped) = ip.to_ipv4_mapped() {
        return is_forbidden_v4(mapped);
    }
    let segments = ip.segments();
    let nat64 = segments[0] == 0x64 && segments[1] == 0xff9b;
    if nat64 {
        let [_, _, _, _, _, _, high, low] = segments;
        let embedded = Ipv4Addr::new(
            (high >> 8) as u8,
            (high & 0xff) as u8,
            (low >> 8) as u8,
            (low & 0xff) as u8,
        );
        return is_forbidden_v4(embedded);
    }
    ip.is_loopback()
        || ip.is_unspecified()
        || ip.is_multicast()
        || (segments[0] & 0xfe00) == 0xfc00
        || (segments[0] & 0xffc0) == 0xfe80
        || (segments[0] & 0xffc0) == 0xfec0
        || (segments[0] == 0x2001 && segments[1] == 0x0db8)
        || segments[..6].iter().all(|segment| *segment == 0)
}

#[cfg(test)]
mod tests {
    use std::net::IpAddr;

    use super::is_forbidden_address;

    fn forbidden(value: &str) -> bool {
        match value.parse::<IpAddr>() {
            Ok(address) => is_forbidden_address(address),
            Err(error) => panic!("bad test address {value}: {error}"),
        }
    }

    #[test]
    fn blocks_private_loopback_and_link_local_addresses() {
        for value in [
            "127.0.0.1",
            "10.1.2.3",
            "172.16.0.1",
            "192.168.1.1",
            "169.254.169.254",
            "0.0.0.0",
            "100.64.0.1",
            "::1",
            "::",
            "fe80::1",
            "fd00::1",
            "::ffff:127.0.0.1",
            "::ffff:10.0.0.1",
            "64:ff9b::a9fe:a9fe",
            "::127.0.0.1",
        ] {
            assert!(forbidden(value), "{value} must be blocked");
        }
    }

    #[test]
    fn allows_public_addresses() {
        for value in [
            "8.8.8.8",
            "140.82.112.3",
            "2606:4700::1111",
            "64:ff9b::808:808",
        ] {
            assert!(!forbidden(value), "{value} must be allowed");
        }
    }
}
