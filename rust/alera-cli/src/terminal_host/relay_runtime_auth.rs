use std::time::Duration;

use base64::{engine::general_purpose::URL_SAFE_NO_PAD, Engine as _};
use ed25519_dalek::{Signature, Verifier, VerifyingKey};
use serde::Deserialize;

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

pub(super) async fn verify_grant(token: &str) -> anyhow::Result<GrantClaims> {
    let segments = token.split('.').collect::<Vec<_>>();
    if segments.len() != 3 {
        anyhow::bail!("relay grant is malformed");
    }
    let header: GrantHeader = decode_json_part(segments[0])?;
    if header.alg != "EdDSA" || header.typ != "relay+jwt" {
        anyhow::bail!("relay grant header is invalid");
    }
    let claims: GrantClaims = decode_json_part(segments[1])?;
    let now = chrono::Utc::now().timestamp();
    let expected_issuer = std::env::var("ALERA_CLOUD_ISSUER").unwrap_or_else(|_| {
        std::env::var("ALERA_CLOUD_URL").unwrap_or_else(|_| "https://api.alera.build".to_owned())
    });
    if claims.aud != "alera-relay"
        || claims.iss != expected_issuer
        || claims.exp <= now
        || claims.nbf > now + 30
        || claims.iat > now + 30
        || claims.jti.is_empty()
    {
        anyhow::bail!("relay grant is expired or invalid");
    }
    let cloud_url =
        std::env::var("ALERA_CLOUD_URL").unwrap_or_else(|_| "https://api.alera.build".to_owned());
    let jwks_url = format!("{}/.well-known/jwks.json", cloud_url.trim_end_matches('/'));
    let jwks: JsonWebKeySet = reqwest::Client::builder()
        .timeout(Duration::from_secs(10))
        .build()?
        .get(jwks_url)
        .send()
        .await?
        .error_for_status()?
        .json()
        .await?;
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
