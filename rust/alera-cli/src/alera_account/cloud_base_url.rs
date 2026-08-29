use anyhow::{anyhow, Result};
use url::{Host, Url};

/// Cleartext HTTP is accepted only for a literal loopback origin. A prefix match is
/// not enough: `http://localhost.example.com` starts with `http://localhost` while
/// resolving to a remote host, which would put bearer tokens on the wire in the clear.
pub(crate) fn validate_cloud_base_url(base_url: &str) -> Result<()> {
    let parsed =
        Url::parse(base_url).map_err(|_| anyhow!("ALERA_CLOUD_URL must be an absolute URL"))?;
    let loopback = match parsed.host() {
        Some(Host::Domain(domain)) => domain.eq_ignore_ascii_case("localhost"),
        Some(Host::Ipv4(address)) => address.is_loopback(),
        Some(Host::Ipv6(address)) => address.is_loopback(),
        None => false,
    };
    match parsed.scheme() {
        "https" => Ok(()),
        "http" if loopback => Ok(()),
        _ => Err(anyhow!(
            "ALERA_CLOUD_URL must use HTTPS or a loopback HTTP origin"
        )),
    }
}

#[cfg(test)]
mod tests {
    use super::validate_cloud_base_url;

    #[test]
    fn loopback_lookalike_hosts_are_rejected() {
        for base_url in [
            "http://localhost.example.com",
            "http://127.0.0.1.example.com",
            "http://api.alera.build",
            "ftp://localhost",
            "not a url",
        ] {
            assert!(
                validate_cloud_base_url(base_url).is_err(),
                "{base_url} must be rejected"
            );
        }
    }

    #[test]
    fn https_and_real_loopback_origins_are_accepted() {
        for base_url in [
            "https://api.alera.build",
            "http://localhost:8787",
            "http://127.0.0.1:8787",
            "http://[::1]:8787",
        ] {
            assert!(
                validate_cloud_base_url(base_url).is_ok(),
                "{base_url} must be accepted"
            );
        }
    }
}
