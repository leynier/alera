use std::sync::{Arc, Mutex};

use async_trait::async_trait;
use base64::{engine::general_purpose::URL_SAFE_NO_PAD, Engine};
use ed25519_dalek::{Signer, SigningKey};
use url::Url;

use crate::{
    api_models::ProviderKind,
    fcm::{FcmError, FcmMessage, FcmReceipt, FcmSender},
    oauth::{AuthorizationInput, ExchangeInput, OAuthProvider, ProviderIdentity},
    signing::{JsonWebKey, TokenSigner},
};

pub struct FakeOAuthProvider {
    kind: ProviderKind,
    identity: ProviderIdentity,
}

impl FakeOAuthProvider {
    pub fn new(kind: ProviderKind, identity: ProviderIdentity) -> Self {
        Self { kind, identity }
    }
}

#[async_trait]
impl OAuthProvider for FakeOAuthProvider {
    fn kind(&self) -> ProviderKind {
        self.kind
    }

    fn authorization_url(&self, input: AuthorizationInput<'_>) -> anyhow::Result<Url> {
        let mut url = Url::parse("https://identity.test/authorize")?;
        url.query_pairs_mut()
            .append_pair("state", input.state)
            .append_pair("redirect_uri", input.redirect_uri)
            .append_pair("code_challenge", input.code_challenge);
        Ok(url)
    }

    async fn exchange(&self, _input: ExchangeInput<'_>) -> anyhow::Result<ProviderIdentity> {
        Ok(self.identity.clone())
    }
}

#[derive(Clone, Copy)]
pub enum FakeFcmOutcome {
    Delivered,
    Unregistered,
    Transient,
}

pub struct FakeFcmSender {
    outcome: FakeFcmOutcome,
    messages: Arc<Mutex<Vec<FcmMessage>>>,
}

impl FakeFcmSender {
    pub fn new(outcome: FakeFcmOutcome) -> Self {
        Self {
            outcome,
            messages: Arc::new(Mutex::new(Vec::new())),
        }
    }

    pub fn message_count(&self) -> usize {
        match self.messages.lock() {
            Ok(messages) => messages.len(),
            Err(_) => 0,
        }
    }
}

#[async_trait]
impl FcmSender for FakeFcmSender {
    async fn send(&self, message: FcmMessage) -> Result<FcmReceipt, FcmError> {
        if let Ok(mut messages) = self.messages.lock() {
            messages.push(message);
        }
        match self.outcome {
            FakeFcmOutcome::Delivered => Ok(FcmReceipt {
                message_id: "fake-message".to_owned(),
            }),
            FakeFcmOutcome::Unregistered => Err(FcmError::Unregistered),
            FakeFcmOutcome::Transient => Err(FcmError::Transient("fake failure".to_owned())),
        }
    }
}

pub struct FakeTokenSigner {
    key: SigningKey,
}

impl FakeTokenSigner {
    pub fn new() -> Self {
        Self {
            key: SigningKey::from_bytes(&[11_u8; 32]),
        }
    }
}

impl Default for FakeTokenSigner {
    fn default() -> Self {
        Self::new()
    }
}

#[async_trait]
impl TokenSigner for FakeTokenSigner {
    fn key_id(&self) -> &str {
        "fake-signing-key"
    }

    fn public_keys(&self) -> Vec<JsonWebKey> {
        vec![JsonWebKey {
            kty: "OKP".to_owned(),
            crv: "Ed25519".to_owned(),
            x: URL_SAFE_NO_PAD.encode(self.key.verifying_key().as_bytes()),
            key_use: "sig".to_owned(),
            alg: "EdDSA".to_owned(),
            kid: self.key_id().to_owned(),
        }]
    }

    async fn sign(&self, message: &[u8]) -> anyhow::Result<Vec<u8>> {
        Ok(self.key.sign(message).to_bytes().to_vec())
    }
}
