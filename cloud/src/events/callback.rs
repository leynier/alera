//! Outbound webhook egress: HTTPS only, public addresses only, the checked address pinned
//! for the connection, no proxy, no redirects, 10 seconds per attempt, and a 16 KiB
//! response cap.

use std::{net::SocketAddr, sync::Arc, time::Duration};

use async_trait::async_trait;
use reqwest::{redirect::Policy, Client};
use url::{Host, Url};

use crate::{config::CallbackPolicy, mcp_oauth::cimd::is_forbidden_address};

pub const ATTEMPT_TIMEOUT: Duration = Duration::from_secs(10);
pub const MAX_RESPONSE_BYTES: usize = 16 * 1024;
pub const MAX_PAYLOAD_BYTES: usize = 256 * 1024;
pub const MAX_URL_BYTES: usize = 2048;

/// Why a callback could not be reached. `reason()` is the stable code clients see.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum CallbackError {
    InvalidUrl,
    DnsFailed,
    NonPublicDestination,
    Timeout,
    ConnectionFailed,
    ResponseTooLarge,
    PayloadTooLarge,
}

impl CallbackError {
    pub fn reason(self) -> &'static str {
        match self {
            Self::InvalidUrl => "invalid_url",
            Self::DnsFailed => "dns_failed",
            Self::NonPublicDestination => "non_public_destination",
            Self::Timeout => "timeout",
            Self::ConnectionFailed => "connection_failed",
            Self::ResponseTooLarge => "response_too_large",
            Self::PayloadTooLarge => "payload_too_large",
        }
    }

    /// Errors that a retry cannot fix.
    pub fn is_permanent(self) -> bool {
        matches!(
            self,
            Self::InvalidUrl | Self::NonPublicDestination | Self::PayloadTooLarge
        )
    }
}

/// Resolves callback hosts. Tests inject answers so they never depend on real DNS.
#[async_trait]
pub trait CallbackResolver: Send + Sync {
    async fn resolve(&self, host: &str, port: u16) -> std::io::Result<Vec<SocketAddr>>;
}

pub struct SystemResolver;

#[async_trait]
impl CallbackResolver for SystemResolver {
    async fn resolve(&self, host: &str, port: u16) -> std::io::Result<Vec<SocketAddr>> {
        Ok(tokio::net::lookup_host((host, port)).await?.collect())
    }
}

pub struct Reply {
    pub status: u16,
    pub body: Vec<u8>,
}

#[derive(Clone)]
pub struct CallbackClient {
    resolver: Arc<dyn CallbackResolver>,
    policy: CallbackPolicy,
    timeout: Duration,
}

impl CallbackClient {
    pub fn new(policy: CallbackPolicy) -> Self {
        Self {
            resolver: Arc::new(SystemResolver),
            policy,
            timeout: ATTEMPT_TIMEOUT,
        }
    }

    pub fn with_resolver(mut self, resolver: Arc<dyn CallbackResolver>) -> Self {
        self.resolver = resolver;
        self
    }

    pub fn with_timeout(mut self, timeout: Duration) -> Self {
        self.timeout = timeout;
        self
    }

    /// Parses and checks a callback URL without contacting it.
    pub fn validate_url(&self, text: &str) -> Result<Url, CallbackError> {
        validate_url(text, self.policy)
    }

    /// Resolves the host and returns the one address the connection must use.
    pub async fn destination(&self, url: &Url) -> Result<SocketAddr, CallbackError> {
        let port = url
            .port_or_known_default()
            .ok_or(CallbackError::InvalidUrl)?;
        let addresses = match url.host() {
            Some(Host::Ipv4(ip)) => vec![SocketAddr::new(ip.into(), port)],
            Some(Host::Ipv6(ip)) => vec![SocketAddr::new(ip.into(), port)],
            Some(Host::Domain(host)) => self
                .resolver
                .resolve(host, port)
                .await
                .map_err(|_| CallbackError::DnsFailed)?,
            None => return Err(CallbackError::InvalidUrl),
        };
        let first = *addresses.first().ok_or(CallbackError::DnsFailed)?;
        if !self.policy.allow_private_targets
            && addresses
                .iter()
                .any(|address| is_forbidden_address(address.ip()))
        {
            return Err(CallbackError::NonPublicDestination);
        }
        Ok(first)
    }

    /// Posts `body` once. Every status is returned as a reply; only transport failures
    /// are errors. Redirects are never followed.
    pub async fn post(
        &self,
        url_text: &str,
        headers: &[(String, String)],
        body: Vec<u8>,
    ) -> Result<Reply, CallbackError> {
        if body.len() > MAX_PAYLOAD_BYTES {
            return Err(CallbackError::PayloadTooLarge);
        }
        let url = self.validate_url(url_text)?;
        tokio::time::timeout(self.timeout, self.send(url, headers, body))
            .await
            .map_err(|_| CallbackError::Timeout)?
    }

    async fn send(
        &self,
        url: Url,
        headers: &[(String, String)],
        body: Vec<u8>,
    ) -> Result<Reply, CallbackError> {
        let address = self.destination(&url).await?;
        // No proxy: a proxy would resolve the hostname itself (CONNECT host:port) and
        // could reach a private address, bypassing the check and the pinned address.
        let mut builder = Client::builder()
            .no_proxy()
            .timeout(self.timeout)
            .redirect(Policy::none());
        if let Some(Host::Domain(host)) = url.host() {
            // Pinning the checked address keeps a second DNS answer from reaching a private host.
            builder = builder.resolve(host, address);
        }
        let client = builder
            .build()
            .map_err(|_| CallbackError::ConnectionFailed)?;
        let mut request = client.post(url).body(body);
        for (name, value) in headers {
            request = request.header(name.as_str(), value.as_str());
        }
        let mut response = request.send().await.map_err(transport_error)?;
        let status = response.status().as_u16();
        let mut received = Vec::new();
        while let Some(chunk) = response.chunk().await.map_err(transport_error)? {
            if received.len() + chunk.len() > MAX_RESPONSE_BYTES {
                return Err(CallbackError::ResponseTooLarge);
            }
            received.extend_from_slice(&chunk);
        }
        Ok(Reply {
            status,
            body: received,
        })
    }
}

fn transport_error(error: reqwest::Error) -> CallbackError {
    if error.is_timeout() {
        CallbackError::Timeout
    } else {
        CallbackError::ConnectionFailed
    }
}

/// HTTPS on port 443 without credentials or fragments. The policy can admit other ports
/// (development) or plain HTTP (tests only).
pub fn validate_url(text: &str, policy: CallbackPolicy) -> Result<Url, CallbackError> {
    if text.is_empty()
        || text.len() > MAX_URL_BYTES
        || text.bytes().any(|byte| !(0x21..=0x7e).contains(&byte))
        || text.contains('\\')
    {
        return Err(CallbackError::InvalidUrl);
    }
    let url = Url::parse(text).map_err(|_| CallbackError::InvalidUrl)?;
    let scheme_allowed =
        url.scheme() == "https" || (policy.allow_private_targets && url.scheme() == "http");
    let port_allowed = url.port().is_none()
        || url.port() == Some(443)
        || policy.allow_any_port
        || policy.allow_private_targets;
    if !scheme_allowed
        || !port_allowed
        || url.host().is_none()
        || !url.username().is_empty()
        || url.password().is_some()
        || url.fragment().is_some()
    {
        return Err(CallbackError::InvalidUrl);
    }
    Ok(url)
}

#[cfg(test)]
mod tests {
    use std::net::IpAddr;

    use super::*;

    struct FakeResolver(Vec<&'static str>);

    #[async_trait]
    impl CallbackResolver for FakeResolver {
        async fn resolve(&self, _host: &str, port: u16) -> std::io::Result<Vec<SocketAddr>> {
            self.0
                .iter()
                .map(|value| {
                    value
                        .parse::<IpAddr>()
                        .map(|ip| SocketAddr::new(ip, port))
                        .map_err(|_| std::io::Error::other("bad test address"))
                })
                .collect()
        }
    }

    fn client(answers: Vec<&'static str>, policy: CallbackPolicy) -> CallbackClient {
        CallbackClient::new(policy).with_resolver(Arc::new(FakeResolver(answers)))
    }

    async fn destination(client: &CallbackClient, text: &str) -> Result<SocketAddr, CallbackError> {
        let url = client.validate_url(text)?;
        client.destination(&url).await
    }

    #[test]
    fn accepts_only_https_on_port_443_by_default() {
        let policy = CallbackPolicy::default();
        assert!(validate_url("https://hooks.example.com/alera?x=1", policy).is_ok());
        assert!(validate_url("https://hooks.example.com:443/alera", policy).is_ok());
        for bad in [
            "http://hooks.example.com/alera",
            "https://hooks.example.com:8443/alera",
            "https://user:pass@hooks.example.com/",
            "https://hooks.example.com/#fragment",
            "https://hooks.example.com/a b",
            "ftp://hooks.example.com/",
            "https://",
            "",
        ] {
            assert_eq!(
                validate_url(bad, policy).err(),
                Some(CallbackError::InvalidUrl),
                "{bad}"
            );
        }
        let long = format!("https://hooks.example.com/{}", "a".repeat(MAX_URL_BYTES));
        assert!(validate_url(&long, policy).is_err());
        let dev = CallbackPolicy {
            allow_any_port: true,
            allow_private_targets: false,
        };
        assert!(validate_url("https://hooks.example.com:8443/alera", dev).is_ok());
        assert!(validate_url("http://hooks.example.com/alera", dev).is_err());
    }

    #[tokio::test]
    async fn blocks_private_answers_and_pins_the_public_one() {
        let policy = CallbackPolicy::default();
        for answers in [
            vec!["127.0.0.1"],
            vec!["10.0.0.8"],
            vec!["169.254.169.254"],
            vec!["::1"],
            vec!["fe80::1"],
            vec!["224.0.0.1"],
            vec!["0.0.0.0"],
            vec!["93.184.216.34", "192.168.1.1"],
        ] {
            let result = destination(
                &client(answers.clone(), policy),
                "https://hooks.example.com/",
            )
            .await;
            assert_eq!(
                result.err(),
                Some(CallbackError::NonPublicDestination),
                "{answers:?}"
            );
        }
        let empty = destination(&client(Vec::new(), policy), "https://hooks.example.com/").await;
        assert_eq!(empty.err(), Some(CallbackError::DnsFailed));
        let public = destination(
            &client(vec!["93.184.216.34", "93.184.216.35"], policy),
            "https://hooks.example.com/",
        )
        .await;
        assert_eq!(public.ok(), "93.184.216.34:443".parse().ok());
        for literal in ["https://127.0.0.1/", "https://[::1]/", "https://10.1.2.3/"] {
            let result = destination(&client(Vec::new(), policy), literal).await;
            assert_eq!(
                result.err(),
                Some(CallbackError::NonPublicDestination),
                "{literal}"
            );
        }
    }

    #[tokio::test]
    async fn the_test_policy_admits_loopback_http() {
        let policy = CallbackPolicy {
            allow_any_port: false,
            allow_private_targets: true,
        };
        let result = destination(&client(Vec::new(), policy), "http://127.0.0.1:9/hook").await;
        assert_eq!(result.ok(), "127.0.0.1:9".parse().ok());
    }

    #[tokio::test]
    async fn refuses_oversized_payloads_before_connecting() {
        let client = client(vec!["93.184.216.34"], CallbackPolicy::default());
        let result = client
            .post(
                "https://hooks.example.com/",
                &[],
                vec![0_u8; MAX_PAYLOAD_BYTES + 1],
            )
            .await;
        assert_eq!(result.err(), Some(CallbackError::PayloadTooLarge));
    }
}
