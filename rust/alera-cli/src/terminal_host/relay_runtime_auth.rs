use std::sync::Arc;
use std::time::{Duration, Instant};
use tokio::sync::Mutex;

use base64::{engine::general_purpose::URL_SAFE_NO_PAD, Engine as _};
use ed25519_dalek::{Signature, Verifier, VerifyingKey};
use serde::Deserialize;

use crate::terminal_host::alera_account::validate_cloud_base_url;

#[derive(Debug, Clone, Deserialize)]
#[serde(rename_all = "camelCase")]
struct GrantHeader {
    alg: String,
    kid: String,
    typ: String,
}

#[derive(Debug, Clone, Deserialize)]
#[serde(rename_all = "camelCase")]
pub(super) struct GrantClaims {
    pub(super) iss: String,
    pub(super) aud: String,
    pub(super) exp: i64,
    pub(super) iat: i64,
    pub(super) nbf: i64,
    pub(super) jti: String,
    pub(super) account_id: String,
    pub(super) runtime_id: String,
    pub(super) client_id: String,
    pub(super) role: String,
    pub(super) key_version: i32,
    pub(super) client_public_key: String,
    pub(super) runtime_public_key: String,
}

#[derive(Debug, Clone, Deserialize)]
struct JsonWebKeySet {
    keys: Vec<JsonWebKey>,
}

#[derive(Debug, Clone, Deserialize)]
struct JsonWebKey {
    kty: String,
    crv: String,
    x: String,
    alg: String,
    kid: String,
}

#[derive(Debug, thiserror::Error)]
#[error("relay signing keys are temporarily unavailable")]
pub(super) struct GrantKeysUnavailable;

type KeyCache = Option<(Instant, Option<JsonWebKeySet>)>;

#[derive(Clone)]
pub(super) struct GrantVerifier {
    client: reqwest::Client,
    issuer: String,
    url: String,
    cache: Arc<Mutex<KeyCache>>,
    unknown_refresh: Arc<std::sync::Mutex<Option<Instant>>>,
}

impl GrantVerifier {
    pub(super) fn new() -> anyhow::Result<Self> {
        let cloud_url =
            std::env::var("ALERA_CLOUD_URL").unwrap_or_else(|_| "https://api.alera.build".into());
        let issuer = std::env::var("ALERA_CLOUD_ISSUER").unwrap_or_else(|_| cloud_url.clone());
        Self::with_url(
            issuer,
            format!("{}/.well-known/jwks.json", cloud_url.trim_end_matches('/')),
        )
    }

    pub(super) fn with_url(issuer: String, url: String) -> anyhow::Result<Self> {
        validate_cloud_base_url(&url)?;
        Ok(Self {
            client: reqwest::Client::builder()
                .timeout(Duration::from_secs(10))
                .build()?,
            issuer,
            url,
            cache: Arc::new(Mutex::new(None)),
            unknown_refresh: Arc::new(std::sync::Mutex::new(None)),
        })
    }

    pub(super) async fn verify(&self, token: &str) -> anyhow::Result<GrantClaims> {
        verify_grant(self, token).await
    }

    async fn keys(&self, kid: &str) -> anyhow::Result<JsonWebKeySet> {
        let mut cached = self.cache.lock().await;
        if let Some((fetched, None)) = cached.as_ref() {
            if fetched.elapsed() < Duration::from_secs(1) {
                return Err(GrantKeysUnavailable.into());
            }
        }
        if let Some((fetched, Some(keys))) = cached.as_ref() {
            if fetched.elapsed() < Duration::from_secs(60) {
                if keys.keys.iter().any(|key| key.kid == kid) {
                    return Ok(keys.clone());
                }
                let mut refreshed = self.unknown_refresh.lock().unwrap();
                if refreshed.is_some_and(|at| at.elapsed() < Duration::from_secs(5)) {
                    return Ok(keys.clone());
                }
                *refreshed = Some(Instant::now());
            }
        }
        let result = self.fetch_keys().await;
        match result {
            Ok(keys) => {
                *cached = Some((Instant::now(), Some(keys.clone())));
                Ok(keys)
            }
            Err(_) => {
                *cached = Some((Instant::now(), None));
                Err(GrantKeysUnavailable.into())
            }
        }
    }

    async fn fetch_keys(&self) -> anyhow::Result<JsonWebKeySet> {
        let mut response = self
            .client
            .get(&self.url)
            .send()
            .await?
            .error_for_status()?;
        let mut bytes = Vec::new();
        while let Some(chunk) = response.chunk().await? {
            if bytes.len() + chunk.len() > 64 * 1024 {
                anyhow::bail!("relay signing key response is too large");
            }
            bytes.extend_from_slice(&chunk);
        }
        let keys: JsonWebKeySet = serde_json::from_slice(&bytes)?;
        if keys.keys.len() > 32 {
            anyhow::bail!("too many relay signing keys");
        }
        Ok(keys)
    }
}

impl GrantClaims {
    pub(super) fn same_identity(&self, other: &Self) -> bool {
        self.iss == other.iss
            && self.aud == other.aud
            && self.account_id == other.account_id
            && self.runtime_id == other.runtime_id
            && self.client_id == other.client_id
            && self.role == other.role
            && self.key_version == other.key_version
            && self.client_public_key == other.client_public_key
            && self.runtime_public_key == other.runtime_public_key
    }
}

async fn verify_grant(verifier: &GrantVerifier, token: &str) -> anyhow::Result<GrantClaims> {
    let segments = token.split('.').collect::<Vec<_>>();
    if token.len() > 16 * 1024 || segments.len() != 3 {
        anyhow::bail!("relay grant is malformed");
    }
    let header: GrantHeader = decode_json_part(segments[0])?;
    if header.alg != "EdDSA" || header.typ != "relay+jwt" {
        anyhow::bail!("relay grant header is invalid");
    }
    let claims: GrantClaims = decode_json_part(segments[1])?;
    let now = chrono::Utc::now().timestamp();
    if claims.aud != "alera-relay"
        || claims.iss != verifier.issuer
        || claims.exp <= now
        || claims.exp <= claims.iat
        || claims.exp.saturating_sub(claims.iat) > 120
        || claims.nbf > claims.exp
        || claims.nbf > now + 30
        || claims.iat > now + 30
        || ![
            &claims.jti,
            &claims.account_id,
            &claims.runtime_id,
            &claims.client_id,
        ]
        .iter()
        .all(|value| !value.is_empty() && value.len() <= 128)
        || claims.key_version <= 0
        || !matches!(claims.role.as_str(), "mobile" | "runtime")
        || decode_fixed(&claims.client_public_key).is_err()
        || decode_fixed(&claims.runtime_public_key).is_err()
    {
        anyhow::bail!("relay grant is expired or invalid");
    }
    let jwks = verifier.keys(&header.kid).await?;
    let key = jwks
        .keys
        .into_iter()
        .find(|key| key.kid == header.kid)
        .ok_or_else(|| anyhow::anyhow!("relay grant signing key is unavailable"))?;
    if key.kty != "OKP" || key.crv != "Ed25519" || key.alg != "EdDSA" {
        anyhow::bail!("relay grant signing key is invalid");
    }
    let public_key: [u8; 32] = URL_SAFE_NO_PAD
        .decode(key.x)?
        .try_into()
        .map_err(|_| anyhow::anyhow!("relay grant key length is invalid"))?;
    let signature: [u8; 64] = URL_SAFE_NO_PAD
        .decode(segments[2])?
        .try_into()
        .map_err(|_| anyhow::anyhow!("relay grant signature length is invalid"))?;
    VerifyingKey::from_bytes(&public_key)?.verify(
        format!("{}.{}", segments[0], segments[1]).as_bytes(),
        &Signature::from_bytes(&signature),
    )?;
    if claims.exp <= chrono::Utc::now().timestamp() {
        anyhow::bail!("relay grant expired during verification");
    }
    Ok(claims)
}

fn decode_json_part<T: for<'de> Deserialize<'de>>(value: &str) -> anyhow::Result<T> {
    Ok(serde_json::from_slice(&URL_SAFE_NO_PAD.decode(value)?)?)
}

pub(super) fn decode_fixed(value: &str) -> anyhow::Result<[u8; 32]> {
    URL_SAFE_NO_PAD
        .decode(value)?
        .try_into()
        .map_err(|_| anyhow::anyhow!("relay key length is invalid"))
}

pub(super) fn decode_nonce(value: &str) -> anyhow::Result<[u8; 16]> {
    URL_SAFE_NO_PAD
        .decode(value)?
        .try_into()
        .map_err(|_| anyhow::anyhow!("relay nonce length is invalid"))
}

pub(super) fn encode(bytes: impl AsRef<[u8]>) -> String {
    URL_SAFE_NO_PAD.encode(bytes)
}

#[cfg(test)]
#[path = "relay_runtime_auth_tests.rs"]
mod tests;
