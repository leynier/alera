use std::{
    collections::HashMap,
    sync::Arc,
    time::{Duration, Instant, SystemTime, UNIX_EPOCH},
};

use anyhow::{anyhow, bail, Context};
use jsonwebtoken::{decode, decode_header, Algorithm, DecodingKey, Validation};
use reqwest::{header::CACHE_CONTROL, Client};
use serde::{Deserialize, Serialize};
use sha2::{Digest, Sha256};
use subtle::ConstantTimeEq;
use tokio::sync::Mutex;
use url::Url;

const DEFAULT_JWKS_CACHE_TTL: Duration = Duration::from_secs(60 * 60);

#[derive(Clone)]
pub struct GoogleIdTokenVerifier {
    client: Client,
    client_id: String,
    jwks_url: Url,
    cache: Arc<Mutex<GoogleJwksCache>>,
}

#[derive(Default)]
struct GoogleJwksCache {
    keys: HashMap<String, GoogleRsaJwk>,
    expires_at: Option<Instant>,
}

#[derive(Clone, Deserialize)]
struct GoogleRsaJwk {
    kid: String,
    kty: String,
    alg: String,
    #[serde(rename = "use")]
    usage: String,
    n: String,
    e: String,
}

#[derive(Deserialize)]
struct GoogleJwks {
    keys: Vec<GoogleRsaJwk>,
}

#[derive(Clone, Debug, Deserialize, Serialize)]
pub struct VerifiedGoogleClaims {
    iss: String,
    aud: String,
    exp: u64,
    iat: u64,
    pub sub: String,
    pub email: String,
    #[serde(default)]
    pub email_verified: bool,
    nonce: Option<String>,
    azp: Option<String>,
}

impl GoogleIdTokenVerifier {
    pub fn new(client: Client, client_id: String, jwks_url: Url) -> anyhow::Result<Self> {
        if client_id.trim().is_empty() {
            bail!("Google OIDC client id is empty");
        }
        if jwks_url.scheme() != "https" && !jwks_url.host_str().is_some_and(is_loopback_host) {
            bail!("Google JWKS URL must use HTTPS");
        }
        Ok(Self {
            client,
            client_id,
            jwks_url,
            cache: Arc::new(Mutex::new(GoogleJwksCache::default())),
        })
    }

    pub async fn verify(
        &self,
        id_token: &str,
        expected_nonce: Option<&str>,
    ) -> anyhow::Result<VerifiedGoogleClaims> {
        let expected_nonce =
            expected_nonce.ok_or_else(|| anyhow!("Google exchange requires a nonce"))?;
        let header = decode_header(id_token).context("decode Google ID token header")?;
        if header.alg != Algorithm::RS256 {
            bail!("Google ID token did not use RS256");
        }
        let kid = header
            .kid
            .as_deref()
            .ok_or_else(|| anyhow!("Google ID token did not identify a signing key"))?;
        let jwk = self.signing_key(kid).await?;
        let decoding_key =
            DecodingKey::from_rsa_components(&jwk.n, &jwk.e).context("decode Google RSA key")?;
        let mut validation = Validation::new(Algorithm::RS256);
        validation.leeway = 30;
        validation.set_required_spec_claims(&["exp", "iss", "aud", "sub"]);
        validation.set_issuer(&["https://accounts.google.com", "accounts.google.com"]);
        validation.set_audience(&[self.client_id.as_str()]);
        let claims = decode::<VerifiedGoogleClaims>(id_token, &decoding_key, &validation)
            .context("verify Google ID token")?
            .claims;

        if claims
            .azp
            .as_deref()
            .is_some_and(|presenter| presenter != self.client_id)
        {
            bail!("Google ID token authorized presenter did not match the client");
        }
        if !constant_time_text_eq(claims.nonce.as_deref().unwrap_or_default(), expected_nonce) {
            bail!("Google ID token nonce did not match the authorization transaction");
        }
        if claims.sub.is_empty() || claims.sub.len() > 255 {
            bail!("Google ID token subject is invalid");
        }
        if claims.iat > unix_timestamp()?.saturating_add(300) {
            bail!("Google ID token was issued in the future");
        }
        Ok(claims)
    }

    async fn signing_key(&self, kid: &str) -> anyhow::Result<GoogleRsaJwk> {
        let mut cache = self.cache.lock().await;
        if cache
            .expires_at
            .is_some_and(|expires_at| expires_at > Instant::now())
        {
            if let Some(key) = cache.keys.get(kid) {
                return Ok(key.clone());
            }
        }

        let response = self
            .client
            .get(self.jwks_url.clone())
            .send()
            .await
            .context("fetch Google JWKS")?
            .error_for_status()
            .context("Google JWKS endpoint rejected the request")?;
        let cache_ttl = cache_ttl(response.headers().get(CACHE_CONTROL));
        let document = response
            .json::<GoogleJwks>()
            .await
            .context("parse Google JWKS")?;
        let keys: HashMap<_, _> = document
            .keys
            .into_iter()
            .filter(|key| key.kty == "RSA" && key.alg == "RS256" && key.usage == "sig")
            .map(|key| (key.kid.clone(), key))
            .collect();
        if keys.is_empty() {
            bail!("Google JWKS did not contain an RS256 signing key");
        }
        cache.keys = keys;
        cache.expires_at = Some(Instant::now() + cache_ttl);
        cache
            .keys
            .get(kid)
            .cloned()
            .ok_or_else(|| anyhow!("Google JWKS did not contain the requested signing key"))
    }
}

fn cache_ttl(value: Option<&reqwest::header::HeaderValue>) -> Duration {
    value
        .and_then(|value| value.to_str().ok())
        .and_then(|value| {
            value.split(',').find_map(|directive| {
                directive
                    .trim()
                    .strip_prefix("max-age=")
                    .and_then(|seconds| seconds.parse::<u64>().ok())
            })
        })
        .map(Duration::from_secs)
        .unwrap_or(DEFAULT_JWKS_CACHE_TTL)
}

fn constant_time_text_eq(left: &str, right: &str) -> bool {
    let left_hash = Sha256::digest(left.as_bytes());
    let right_hash = Sha256::digest(right.as_bytes());
    bool::from(left_hash.ct_eq(&right_hash))
}

fn unix_timestamp() -> anyhow::Result<u64> {
    Ok(SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .context("system clock is before Unix epoch")?
        .as_secs())
}

fn is_loopback_host(host: &str) -> bool {
    matches!(host, "127.0.0.1" | "localhost" | "::1")
}

#[cfg(test)]
mod tests {
    use std::sync::{
        atomic::{AtomicUsize, Ordering},
        Arc,
    };

    use axum::{routing::get, Json, Router};
    use base64::{engine::general_purpose::URL_SAFE_NO_PAD, Engine};
    use jsonwebtoken::{encode, Algorithm, EncodingKey, Header};
    use rand::rngs::OsRng;
    use rsa::{pkcs1::EncodeRsaPrivateKey, traits::PublicKeyParts, RsaPrivateKey};
    use serde_json::json;
    use tokio::net::TcpListener;
    use url::Url;

    use super::{unix_timestamp, GoogleIdTokenVerifier, VerifiedGoogleClaims};

    struct TestRsaKey {
        encoding: EncodingKey,
        modulus: String,
        exponent: String,
    }

    #[tokio::test]
    async fn verifies_signature_claims_nonce_and_caches_jwks() {
        let key = test_rsa_key();
        let modulus = key.modulus.clone();
        let exponent = key.exponent.clone();
        let hits = Arc::new(AtomicUsize::new(0));
        let server_hits = hits.clone();
        let app = Router::new().route(
            "/certs",
            get(move || {
                server_hits.fetch_add(1, Ordering::SeqCst);
                let modulus = modulus.clone();
                let exponent = exponent.clone();
                async move {
                    (
                        [("cache-control", "public, max-age=3600")],
                        Json(json!({
                            "keys": [{
                                "kid": "test-key",
                                "kty": "RSA",
                                "alg": "RS256",
                                "use": "sig",
                                "n": modulus,
                                "e": exponent
                            }]
                        })),
                    )
                }
            }),
        );
        let listener = match TcpListener::bind("127.0.0.1:0").await {
            Ok(value) => value,
            Err(error) => panic!("bind test JWKS server: {error}"),
        };
        let address = match listener.local_addr() {
            Ok(value) => value,
            Err(error) => panic!("read test JWKS address: {error}"),
        };
        tokio::spawn(async move {
            if let Err(error) = axum::serve(listener, app).await {
                panic!("serve test JWKS: {error}");
            }
        });
        let verifier = match GoogleIdTokenVerifier::new(
            reqwest::Client::new(),
            "alera-client".to_owned(),
            Url::parse(&format!("http://{address}/certs"))
                .unwrap_or_else(|error| panic!("parse test JWKS URL: {error}")),
        ) {
            Ok(value) => value,
            Err(error) => panic!("create verifier: {error}"),
        };

        let nonce = uuid::Uuid::new_v4().to_string();
        let other_nonce = uuid::Uuid::new_v4().to_string();
        let valid = token(
            claims("https://accounts.google.com", "alera-client", 3600, &nonce),
            &key.encoding,
        );
        assert!(verifier.verify(&valid, Some(nonce.as_str())).await.is_ok());
        assert!(verifier.verify(&valid, Some(nonce.as_str())).await.is_ok());
        assert_eq!(hits.load(Ordering::SeqCst), 1);

        assert!(verifier
            .verify(&tamper_signature(&valid), Some(nonce.as_str()))
            .await
            .is_err());
        assert!(verifier
            .verify(
                &token(
                    claims("https://attacker.example", "alera-client", 3600, &nonce),
                    &key.encoding,
                ),
                Some(nonce.as_str()),
            )
            .await
            .is_err());
        assert!(verifier
            .verify(
                &token(
                    claims("https://accounts.google.com", "other-client", 3600, &nonce),
                    &key.encoding,
                ),
                Some(nonce.as_str()),
            )
            .await
            .is_err());
        assert!(verifier
            .verify(
                &token(
                    claims("https://accounts.google.com", "alera-client", -120, &nonce),
                    &key.encoding,
                ),
                Some(nonce.as_str()),
            )
            .await
            .is_err());
        assert!(verifier
            .verify(&valid, Some(other_nonce.as_str()))
            .await
            .is_err());
    }

    fn claims(issuer: &str, audience: &str, expires_in: i64, nonce: &str) -> VerifiedGoogleClaims {
        let now = unix_timestamp().unwrap_or_else(|error| panic!("read timestamp: {error}"));
        VerifiedGoogleClaims {
            iss: issuer.to_owned(),
            aud: audience.to_owned(),
            exp: now.saturating_add_signed(expires_in),
            iat: now,
            sub: "google-user-1".to_owned(),
            email: "user@example.com".to_owned(),
            email_verified: true,
            nonce: Some(nonce.to_owned()),
            azp: Some(audience.to_owned()),
        }
    }

    fn test_rsa_key() -> TestRsaKey {
        let private = RsaPrivateKey::new(&mut OsRng, 2048)
            .unwrap_or_else(|error| panic!("generate ephemeral test RSA key: {error}"));
        let der = private
            .to_pkcs1_der()
            .unwrap_or_else(|error| panic!("encode ephemeral test RSA key: {error}"));
        TestRsaKey {
            encoding: EncodingKey::from_rsa_der(der.as_bytes()),
            modulus: URL_SAFE_NO_PAD.encode(private.n().to_bytes_be()),
            exponent: URL_SAFE_NO_PAD.encode(private.e().to_bytes_be()),
        }
    }

    fn token(claims: VerifiedGoogleClaims, key: &EncodingKey) -> String {
        let mut header = Header::new(Algorithm::RS256);
        header.kid = Some("test-key".to_owned());
        encode(&header, &claims, key)
            .unwrap_or_else(|error| panic!("sign test Google ID token: {error}"))
    }

    fn tamper_signature(token: &str) -> String {
        let mut parts: Vec<String> = token.split('.').map(ToOwned::to_owned).collect();
        if let Some(signature) = parts.get_mut(2) {
            let mut bytes = URL_SAFE_NO_PAD
                .decode(signature.as_bytes())
                .unwrap_or_else(|error| panic!("decode test signature: {error}"));
            if let Some(first) = bytes.first_mut() {
                *first ^= 1;
            }
            *signature = URL_SAFE_NO_PAD.encode(bytes);
        }
        parts.join(".")
    }
}
