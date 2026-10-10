use std::{
    collections::HashMap,
    sync::Arc,
    time::{Duration, Instant},
};

use jsonwebtoken::jwk::{AlgorithmParameters, Jwk, JwkSet, PublicKeyUse};
use tokio::sync::Mutex;
use url::Url;

use super::cimd::ClientMetadataFetcher;

const CACHE_TTL: Duration = Duration::from_secs(10 * 60);
/// An unknown `kid` may mean the client rotated keys, but refetching on every miss would
/// let any caller make Alera fetch the client's JWKS once per request.
const MIN_REFETCH_INTERVAL: Duration = Duration::from_secs(60);
const MAX_CACHED_CLIENTS: usize = 1024;

const UNKNOWN_KEY: &str = "The client assertion signing key is unknown.";
const UNAVAILABLE_KEYS: &str = "The client signing keys could not be loaded.";

/// Per-instance cache of the JWKS published by `private_key_jwt` clients. Key lookup
/// precedes signature verification, so unauthenticated callers reach it: every URI is
/// fetched by one request at a time and at most once per `MIN_REFETCH_INTERVAL`,
/// failed attempts included, and requests that miss during a fetch wait for its result.
pub struct ClientJwksCache {
    entries: Mutex<HashMap<String, CachedJwks>>,
    capacity: usize,
}

impl Default for ClientJwksCache {
    fn default() -> Self {
        Self::with_capacity(MAX_CACHED_CLIENTS)
    }
}

#[derive(Default)]
struct CachedJwks {
    keys: Arc<Vec<Jwk>>,
    fetched_at: Option<Instant>,
    attempted_at: Option<Instant>,
    fetch_lock: Arc<Mutex<()>>,
}

impl CachedJwks {
    /// True while the entry still rate-limits its URI: a fetch is running or queued, or
    /// one was attempted within `MIN_REFETCH_INTERVAL`.
    fn guarded(&self) -> bool {
        Arc::strong_count(&self.fetch_lock) > 1 || self.attempted_recently()
    }

    fn attempted_recently(&self) -> bool {
        self.attempted_at
            .is_some_and(|attempted| attempted.elapsed() < MIN_REFETCH_INTERVAL)
    }

    fn fresh_key(&self, kid: Option<&str>) -> Option<Jwk> {
        self.fetched_at
            .filter(|fetched| fetched.elapsed() < CACHE_TTL)
            .and_then(|_| select_key(&self.keys, kid))
    }

    fn cached_answer(&self, kid: Option<&str>) -> Result<Jwk, &'static str> {
        match self.fresh_key(kid) {
            Some(key) => Ok(key),
            None if self.fetched_at.is_some() => Err(UNKNOWN_KEY),
            None => Err(UNAVAILABLE_KEYS),
        }
    }
}

impl ClientJwksCache {
    fn with_capacity(capacity: usize) -> Self {
        Self {
            entries: Mutex::default(),
            capacity,
        }
    }

    /// Returns the client's signing key named by `kid`, or its only key when `kid` is
    /// absent. Errors are user-safe messages.
    pub async fn signing_key(
        &self,
        fetcher: &dyn ClientMetadataFetcher,
        jwks_uri: &Url,
        kid: Option<&str>,
    ) -> Result<Jwk, &'static str> {
        let fetch_lock = {
            let mut entries = self.entries.lock().await;
            let entry = self.entry(&mut entries, jwks_uri)?;
            if let Some(key) = entry.fresh_key(kid) {
                return Ok(key);
            }
            entry.fetch_lock.clone()
        };
        // Every miss queues on the URI's lock, so a request that arrives during a fetch
        // answers from that fetch instead of failing or starting another one.
        let _fetching = fetch_lock.lock().await;
        {
            let mut entries = self.entries.lock().await;
            let entry = self.entry(&mut entries, jwks_uri)?;
            if entry.attempted_recently() {
                return entry.cached_answer(kid);
            }
            entry.attempted_at = Some(Instant::now());
        }
        let fetched = fetch_keys(fetcher, jwks_uri).await;
        let mut entries = self.entries.lock().await;
        let entry = self.entry(&mut entries, jwks_uri)?;
        if let Ok(keys) = fetched {
            entry.keys = Arc::new(keys);
            entry.fetched_at = Some(Instant::now());
        }
        entry.cached_answer(kid)
    }

    /// Finds or admits the entry for a URI. A full cache drops only entries that hold no
    /// rate guard; when every entry still does, the new URI is refused rather than
    /// letting it erase another URI's guard.
    fn entry<'a>(
        &self,
        entries: &'a mut HashMap<String, CachedJwks>,
        jwks_uri: &Url,
    ) -> Result<&'a mut CachedJwks, &'static str> {
        if entries.len() >= self.capacity && !entries.contains_key(jwks_uri.as_str()) {
            entries.retain(|_, entry| entry.guarded());
            if entries.len() >= self.capacity {
                return Err(UNAVAILABLE_KEYS);
            }
        }
        Ok(entries.entry(jwks_uri.as_str().to_owned()).or_default())
    }
}

async fn fetch_keys(
    fetcher: &dyn ClientMetadataFetcher,
    jwks_uri: &Url,
) -> Result<Vec<Jwk>, &'static str> {
    let body = fetcher.fetch(jwks_uri).await.map_err(|error| {
        tracing::warn!(error = %error, "client JWKS fetch failed");
        UNAVAILABLE_KEYS
    })?;
    let set: JwkSet = serde_json::from_slice(&body)
        .map_err(|_| "The client signing keys are not a valid JWKS.")?;
    Ok(set.keys.into_iter().filter(usable_signing_key).collect())
}

/// Only asymmetric signature keys can verify an assertion against a published JWKS.
fn usable_signing_key(key: &Jwk) -> bool {
    let signing_use = !matches!(
        key.common.public_key_use,
        Some(PublicKeyUse::Encryption | PublicKeyUse::Other(_))
    );
    let asymmetric = matches!(
        key.algorithm,
        AlgorithmParameters::RSA(_) | AlgorithmParameters::EllipticCurve(_)
    );
    signing_use && asymmetric
}

fn select_key(keys: &[Jwk], kid: Option<&str>) -> Option<Jwk> {
    match kid {
        Some(kid) => keys
            .iter()
            .find(|key| key.common.key_id.as_deref() == Some(kid))
            .cloned(),
        None => match keys {
            [only] => Some(only.clone()),
            _ => None,
        },
    }
}

#[cfg(test)]
mod tests {
    use std::{
        sync::{
            atomic::{AtomicBool, AtomicUsize, Ordering},
            Arc,
        },
        time::Duration,
    };

    use async_trait::async_trait;
    use serde_json::json;
    use tokio::task::JoinSet;
    use url::Url;

    use super::ClientJwksCache;
    use crate::mcp_oauth::cimd::ClientMetadataFetcher;

    #[derive(Default)]
    struct CountingFetcher {
        hits: AtomicUsize,
        failing: AtomicBool,
    }

    #[async_trait]
    impl ClientMetadataFetcher for CountingFetcher {
        async fn fetch(&self, _url: &Url) -> anyhow::Result<Vec<u8>> {
            self.hits.fetch_add(1, Ordering::SeqCst);
            tokio::time::sleep(Duration::from_millis(20)).await;
            if self.failing.load(Ordering::SeqCst) {
                anyhow::bail!("JWKS host is down");
            }
            Ok(serde_json::to_vec(&json!({"keys": [
                {"kty": "RSA", "kid": "rsa", "use": "sig", "n": "sXch", "e": "AQAB"},
                {"kty": "RSA", "kid": "encryption", "use": "enc", "n": "sXch", "e": "AQAB"},
                {"kty": "oct", "kid": "secret", "k": "c2VjcmV0"}
            ]}))?)
        }
    }

    fn jwks_url() -> Url {
        Url::parse("https://client.example/jwks.json")
            .unwrap_or_else(|error| panic!("parse test JWKS URL: {error}"))
    }

    #[tokio::test]
    async fn caches_keys_and_limits_refetches_for_unknown_kids() {
        let fetcher = CountingFetcher::default();
        let cache = ClientJwksCache::default();
        let url = jwks_url();
        assert!(cache.signing_key(&fetcher, &url, Some("rsa")).await.is_ok());
        assert!(cache.signing_key(&fetcher, &url, Some("rsa")).await.is_ok());
        assert!(cache.signing_key(&fetcher, &url, None).await.is_ok());
        assert!(cache
            .signing_key(&fetcher, &url, Some("missing"))
            .await
            .is_err());
        assert_eq!(fetcher.hits.load(Ordering::SeqCst), 1);
        for kid in ["encryption", "secret"] {
            assert!(cache.signing_key(&fetcher, &url, Some(kid)).await.is_err());
        }
    }

    #[tokio::test]
    async fn concurrent_misses_wait_for_one_fetch() {
        let fetcher = Arc::new(CountingFetcher::default());
        let cache = Arc::new(ClientJwksCache::default());
        let mut requests = JoinSet::new();
        for _ in 0..20 {
            let fetcher = fetcher.clone();
            let cache = cache.clone();
            requests.spawn(async move {
                cache
                    .signing_key(fetcher.as_ref(), &jwks_url(), Some("rsa"))
                    .await
                    .is_ok()
            });
        }
        while let Some(found) = requests.join_next().await {
            assert!(matches!(found, Ok(true)));
        }
        assert_eq!(fetcher.hits.load(Ordering::SeqCst), 1);
    }

    #[tokio::test]
    async fn failed_fetches_are_not_retried_immediately() {
        let fetcher = CountingFetcher::default();
        fetcher.failing.store(true, Ordering::SeqCst);
        let cache = ClientJwksCache::default();
        let url = jwks_url();
        for _ in 0..3 {
            assert!(cache
                .signing_key(&fetcher, &url, Some("rsa"))
                .await
                .is_err());
        }
        assert_eq!(fetcher.hits.load(Ordering::SeqCst), 1);
    }

    #[tokio::test]
    async fn a_full_cache_keeps_the_rate_guards_of_recent_uris() {
        let fetcher = CountingFetcher::default();
        let cache = ClientJwksCache::with_capacity(1);
        let url = jwks_url();
        let other = Url::parse("https://other.example/jwks.json")
            .unwrap_or_else(|error| panic!("parse test JWKS URL: {error}"));
        assert!(cache
            .signing_key(&fetcher, &url, Some("missing"))
            .await
            .is_err());
        assert!(cache
            .signing_key(&fetcher, &other, Some("rsa"))
            .await
            .is_err());
        assert!(cache
            .signing_key(&fetcher, &url, Some("missing"))
            .await
            .is_err());
        assert_eq!(fetcher.hits.load(Ordering::SeqCst), 1);
    }
}
