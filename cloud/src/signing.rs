use std::{sync::Arc, time::Duration};

use anyhow::{anyhow, bail, Context};
use async_trait::async_trait;
use base64::{
    engine::general_purpose::{STANDARD, URL_SAFE_NO_PAD},
    Engine,
};
use ed25519_dalek::{Signer, SigningKey};
use reqwest::Client;
use serde::{Deserialize, Serialize};
use url::Url;

use crate::google_credentials::GoogleAccessTokenProvider;

#[derive(Clone, Debug, Deserialize, Serialize)]
pub struct JsonWebKey {
    pub kty: String,
    pub crv: String,
    pub x: String,
    #[serde(rename = "use")]
    pub key_use: String,
    pub alg: String,
    pub kid: String,
}

#[derive(Debug, Deserialize, Serialize)]
pub struct JsonWebKeySet {
    pub keys: Vec<JsonWebKey>,
}

#[async_trait]
pub trait TokenSigner: Send + Sync {
    fn key_id(&self) -> &str;
    fn public_keys(&self) -> Vec<JsonWebKey>;
    async fn sign(&self, message: &[u8]) -> anyhow::Result<Vec<u8>>;
}

pub struct LocalEd25519Signer {
    key_id: String,
    key: SigningKey,
}

impl LocalEd25519Signer {
    pub fn from_seed_b64url(key_id: String, seed: &str) -> anyhow::Result<Self> {
        let decoded = URL_SAFE_NO_PAD
            .decode(seed)
            .context("decode local signing seed")?;
        let bytes: [u8; 32] = decoded
            .try_into()
            .map_err(|_| anyhow!("local signing seed must contain exactly 32 bytes"))?;
        Ok(Self {
            key_id,
            key: SigningKey::from_bytes(&bytes),
        })
    }
}

#[async_trait]
impl TokenSigner for LocalEd25519Signer {
    fn key_id(&self) -> &str {
        &self.key_id
    }

    fn public_keys(&self) -> Vec<JsonWebKey> {
        vec![JsonWebKey {
            kty: "OKP".to_owned(),
            crv: "Ed25519".to_owned(),
            x: URL_SAFE_NO_PAD.encode(self.key.verifying_key().as_bytes()),
            key_use: "sig".to_owned(),
            alg: "EdDSA".to_owned(),
            kid: self.key_id.clone(),
        }]
    }

    async fn sign(&self, message: &[u8]) -> anyhow::Result<Vec<u8>> {
        Ok(self.key.sign(message).to_bytes().to_vec())
    }
}

pub struct GoogleKmsSigner {
    key_id: String,
    sign_url: Url,
    public_keys: Vec<JsonWebKey>,
    client: Client,
    token_provider: Arc<dyn GoogleAccessTokenProvider>,
}

#[derive(Serialize)]
struct KmsSignRequest {
    data: String,
}

#[derive(Deserialize)]
struct KmsSignResponse {
    signature: String,
}

impl GoogleKmsSigner {
    pub fn new(
        key_id: String,
        sign_url: Url,
        public_key_b64url: String,
        previous_jwks_json: Option<&str>,
        token_provider: Arc<dyn GoogleAccessTokenProvider>,
        timeout: Duration,
    ) -> anyhow::Result<Self> {
        validate_public_key(&public_key_b64url)?;
        let mut public_keys = vec![JsonWebKey {
            kty: "OKP".to_owned(),
            crv: "Ed25519".to_owned(),
            x: public_key_b64url,
            key_use: "sig".to_owned(),
            alg: "EdDSA".to_owned(),
            kid: key_id.clone(),
        }];
        if let Some(json) = previous_jwks_json {
            let previous: JsonWebKeySet =
                serde_json::from_str(json).context("parse ALERA_KMS_PREVIOUS_JWKS_JSON")?;
            for key in &previous.keys {
                validate_jwk(key)?;
            }
            public_keys.extend(previous.keys);
        }

        Ok(Self {
            key_id,
            sign_url,
            public_keys,
            client: Client::builder().timeout(timeout).build()?,
            token_provider,
        })
    }
}

#[async_trait]
impl TokenSigner for GoogleKmsSigner {
    fn key_id(&self) -> &str {
        &self.key_id
    }

    fn public_keys(&self) -> Vec<JsonWebKey> {
        self.public_keys.clone()
    }

    async fn sign(&self, message: &[u8]) -> anyhow::Result<Vec<u8>> {
        let bearer = self.token_provider.access_token().await?;
        let response = self
            .client
            .post(self.sign_url.clone())
            .bearer_auth(bearer)
            .json(&KmsSignRequest {
                data: STANDARD.encode(message),
            })
            .send()
            .await?
            .error_for_status()?
            .json::<KmsSignResponse>()
            .await?;
        STANDARD
            .decode(response.signature)
            .context("decode Cloud KMS signature")
    }
}

fn validate_jwk(key: &JsonWebKey) -> anyhow::Result<()> {
    if key.kty != "OKP" || key.crv != "Ed25519" || key.alg != "EdDSA" {
        bail!("only Ed25519 signing JWKs are supported");
    }
    validate_public_key(&key.x)
}

fn validate_public_key(value: &str) -> anyhow::Result<()> {
    let decoded = URL_SAFE_NO_PAD
        .decode(value)
        .context("decode Ed25519 public key")?;
    if decoded.len() != 32 {
        bail!("Ed25519 public key must contain exactly 32 bytes");
    }
    Ok(())
}

#[cfg(test)]
mod tests {
    use base64::{engine::general_purpose::URL_SAFE_NO_PAD, Engine};

    use super::{LocalEd25519Signer, TokenSigner};

    #[tokio::test]
    async fn local_signer_exposes_matching_public_key() {
        let signer = LocalEd25519Signer::from_seed_b64url(
            "test".to_owned(),
            &URL_SAFE_NO_PAD.encode([7_u8; 32]),
        );
        assert!(signer.is_ok());
        let signer = match signer {
            Ok(value) => value,
            Err(error) => panic!("unexpected signer error: {error}"),
        };
        let signature = signer.sign(b"alera").await;
        assert!(signature.is_ok());
        assert_eq!(signer.public_keys().len(), 1);
    }
}
