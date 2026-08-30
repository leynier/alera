mod configuration;

use std::path::PathBuf;
use std::sync::Arc;

use alera_core::runtime::{LocalAleraAccount, RuntimeStore};
use anyhow::{anyhow, Result};
use base64::{engine::general_purpose::URL_SAFE_NO_PAD, Engine as _};
use chrono::{Duration, Utc};
use tokio::sync::Mutex;

use crate::mobile_access::runtime_id;

use super::cloud_client::{
    AuthEnvelope, AuthProvider, AuthTransaction, CloudAccountClient, CloudRequestError,
    MobileEnrollment, PushEventRequest, DEFAULT_CLOUD_BASE_URL,
};
use super::credential_store::{AccountCredentialStore, StoredAccountCredential};
use crate::terminal_host::relay_crypto::IdentityKeyPair;

const MAX_RELAY_IDENTITY_ROTATIONS: usize = 8;
const MAX_RELAY_KEY_VERSION: i32 = 1_000_000;

#[derive(Debug, Clone)]
struct AccessSession {
    token: String,
    expires_at: chrono::DateTime<Utc>,
}

struct RelayIdentityRegistration {
    account_id: String,
    public_key: String,
    key_version: i32,
    at: std::time::Instant,
}

#[derive(Clone)]
pub(crate) struct AleraAccountService {
    runtime_id: String,
    store: RuntimeStore,
    cloud: CloudAccountClient,
    credentials: AccountCredentialStore,
    session: Arc<Mutex<Option<AccessSession>>>,
    relay_identity_registration: Arc<Mutex<Option<RelayIdentityRegistration>>>,
}

impl AleraAccountService {
    pub(crate) async fn new(runtime_dir: PathBuf, store: RuntimeStore) -> Result<Self> {
        let runtime_id = runtime_id(&store).await?;
        let base_url =
            std::env::var("ALERA_CLOUD_URL").unwrap_or_else(|_| DEFAULT_CLOUD_BASE_URL.to_string());
        Ok(Self {
            credentials: AccountCredentialStore::new(runtime_dir, runtime_id.clone()),
            runtime_id,
            store,
            cloud: CloudAccountClient::new(base_url)?,
            session: Arc::new(Mutex::new(None)),
            relay_identity_registration: Arc::new(Mutex::new(None)),
        })
    }

    pub(crate) fn runtime_id(&self) -> &str {
        &self.runtime_id
    }

    pub(crate) async fn create_auth_transaction(
        &self,
        provider: AuthProvider,
        redirect_uri: &str,
        code_challenge: &str,
        device_name: &str,
    ) -> Result<AuthTransaction> {
        self.cloud
            .create_transaction(
                provider,
                redirect_uri,
                code_challenge,
                &self.runtime_id,
                device_name,
            )
            .await
    }

    pub(crate) async fn create_link_transaction(
        &self,
        provider: AuthProvider,
        redirect_uri: &str,
        code_challenge: &str,
    ) -> Result<AuthTransaction> {
        let token = self.access_token().await?;
        self.cloud
            .create_link_transaction(&token, provider, redirect_uri, code_challenge)
            .await
    }

    pub(crate) async fn exchange_auth(
        &self,
        transaction_id: &str,
        state: &str,
        code: &str,
        verifier: &str,
    ) -> Result<LocalAleraAccount> {
        let envelope = self
            .cloud
            .exchange(transaction_id, state, code, verifier)
            .await?;
        self.complete_auth(envelope).await
    }

    pub(crate) async fn local_account(&self) -> Result<Option<LocalAleraAccount>> {
        self.store.alera_account().await
    }

    pub(crate) async fn complete_auth(&self, envelope: AuthEnvelope) -> Result<LocalAleraAccount> {
        if envelope.token_type != "Bearer"
            || envelope.client.kind != "runtime"
            || envelope.client.id != self.runtime_id
        {
            return Err(anyhow!(
                "cloud returned a credential for a different runtime"
            ));
        }
        let now = Utc::now();
        let expires_at = now + Duration::seconds(envelope.expires_in);
        let existing = self
            .store
            .alera_account()
            .await?
            .filter(|account| account.account_id == envelope.account.id);
        let previous_credential = self.credentials.load().await?;
        self.credentials
            .save(&StoredAccountCredential {
                refresh_token: envelope.refresh_token,
                relay_private_key_b64: previous_credential
                    .as_ref()
                    .and_then(|credential| credential.relay_private_key_b64.clone()),
                relay_key_version: previous_credential
                    .as_ref()
                    .map(|credential| credential.relay_key_version)
                    .unwrap_or(1),
            })
            .await?;
        *self.session.lock().await = Some(AccessSession {
            token: envelope.access_token,
            expires_at,
        });
        let account = LocalAleraAccount {
            account_id: envelope.account.id,
            email: envelope.account.email,
            providers: envelope
                .account
                .identities
                .into_iter()
                .map(|identity| identity.provider)
                .collect(),
            runtime_id: self.runtime_id.clone(),
            cloud_base_url: std::env::var("ALERA_CLOUD_URL")
                .unwrap_or_else(|_| DEFAULT_CLOUD_BASE_URL.to_string()),
            signed_in_at: existing
                .as_ref()
                .map(|account| account.signed_in_at)
                .unwrap_or(now),
            access_token_expires_at: expires_at,
            push_subscription_count: existing
                .as_ref()
                .map(|account| account.push_subscription_count)
                .unwrap_or_default(),
        };
        self.store.set_alera_account(&account).await
    }

    pub(crate) async fn access_token(&self) -> Result<String> {
        let mut session = self.session.lock().await;
        if let Some(current) = session.as_ref() {
            if current.expires_at > Utc::now() + Duration::minutes(2) {
                return Ok(current.token.clone());
            }
        }
        let credential = self
            .credentials
            .load()
            .await?
            .ok_or_else(|| anyhow!("Alera account is signed out"))?;
        let envelope = self.cloud.refresh(&credential.refresh_token).await?;
        if envelope.client.kind != "runtime" || envelope.client.id != self.runtime_id {
            return Err(anyhow!(
                "cloud refreshed a credential for a different runtime"
            ));
        }
        let expires_at = Utc::now() + Duration::seconds(envelope.expires_in);
        self.credentials
            .save(&StoredAccountCredential {
                refresh_token: envelope.refresh_token.clone(),
                relay_private_key_b64: credential.relay_private_key_b64,
                relay_key_version: credential.relay_key_version,
            })
            .await?;
        let local = LocalAleraAccount {
            account_id: envelope.account.id,
            email: envelope.account.email,
            providers: envelope
                .account
                .identities
                .into_iter()
                .map(|identity| identity.provider)
                .collect(),
            runtime_id: self.runtime_id.clone(),
            cloud_base_url: std::env::var("ALERA_CLOUD_URL")
                .unwrap_or_else(|_| DEFAULT_CLOUD_BASE_URL.to_string()),
            signed_in_at: self
                .store
                .alera_account()
                .await?
                .map(|account| account.signed_in_at)
                .unwrap_or_else(Utc::now),
            access_token_expires_at: expires_at,
            push_subscription_count: self
                .store
                .alera_account()
                .await?
                .map(|account| account.push_subscription_count)
                .unwrap_or_default(),
        };
        self.store.set_alera_account(&local).await?;
        *session = Some(AccessSession {
            token: envelope.access_token.clone(),
            expires_at,
        });
        Ok(envelope.access_token)
    }

    pub(crate) async fn create_mobile_enrollment(
        &self,
        device_id: &str,
        device_name: &str,
    ) -> Result<MobileEnrollment> {
        let token = self.access_token().await?;
        self.cloud
            .create_mobile_enrollment(&token, &self.runtime_id, device_id, device_name)
            .await
    }

    pub(crate) async fn send_event(&self, event: &PushEventRequest) -> Result<usize> {
        let token = self.access_token().await?;
        let response = self.cloud.send_event(&token, event).await?;
        self.persist_subscription_count(response.active_subscriptions)
            .await
    }

    pub(crate) async fn refresh_push_subscriptions(&self) -> Result<usize> {
        let token = self.access_token().await?;
        let response = self.cloud.runtime_subscriptions(&token).await?;
        self.persist_subscription_count(response.active_subscriptions)
            .await
    }

    pub(crate) async fn relay_identity(&self) -> Result<IdentityKeyPair> {
        let mut registration = self.relay_identity_registration.lock().await;
        let account_id = self
            .store
            .alera_account()
            .await?
            .ok_or_else(|| anyhow!("Alera account is signed out"))?
            .account_id;
        let mut credential = self
            .credentials
            .load()
            .await?
            .ok_or_else(|| anyhow!("Alera account is signed out"))?;
        let mut key_version = credential.relay_key_version.max(1);
        let (mut identity, encoded) = match credential.relay_private_key_b64.as_deref() {
            Some(encoded) => match URL_SAFE_NO_PAD.decode(encoded) {
                Ok(bytes) if bytes.len() == 32 => {
                    let mut private = [0_u8; 32];
                    private.copy_from_slice(&bytes);
                    let identity = IdentityKeyPair::from_private(private);
                    (identity, encoded.to_owned())
                }
                _ => {
                    let identity = IdentityKeyPair::generate();
                    let encoded = URL_SAFE_NO_PAD.encode(identity.private_bytes());
                    (identity, encoded)
                }
            },
            None => {
                let identity = IdentityKeyPair::generate();
                let encoded = URL_SAFE_NO_PAD.encode(identity.private_bytes());
                (identity, encoded)
            }
        };
        if credential.relay_private_key_b64.as_deref() != Some(encoded.as_str())
            || credential.relay_key_version != key_version
        {
            credential.relay_private_key_b64 = Some(encoded);
            credential.relay_key_version = key_version;
            self.credentials.save(&credential).await?;
        }

        for rotation in 0..=MAX_RELAY_IDENTITY_ROTATIONS {
            let public_key = URL_SAFE_NO_PAD.encode(identity.public_bytes());
            if registration.as_ref().is_some_and(|registered| {
                registered.account_id == account_id
                    && registered.public_key == public_key
                    && registered.key_version == key_version
                    && registered.at.elapsed() < std::time::Duration::from_secs(60)
            }) {
                return Ok(identity);
            }
            let token = self.access_token().await?;
            let mut result = self
                .cloud
                .register_relay_identity(&token, &public_key, key_version)
                .await;
            if result
                .as_ref()
                .err()
                .and_then(|error| error.downcast_ref::<CloudRequestError>())
                .is_some_and(CloudRequestError::can_refresh_authorization)
            {
                {
                    let mut current = self.session.lock().await;
                    if current
                        .as_ref()
                        .is_some_and(|session| session.token == token)
                    {
                        *current = None;
                    }
                }
                let refreshed = self.access_token().await?;
                result = self
                    .cloud
                    .register_relay_identity(&refreshed, &public_key, key_version)
                    .await;
            }
            match result {
                Ok(response) => {
                    if response.client_id != self.runtime_id
                        || response.client_kind != "runtime"
                        || response.public_key != public_key
                        || response.key_version != key_version
                    {
                        return Err(anyhow!("cloud returned an invalid relay identity"));
                    }
                    *registration = Some(RelayIdentityRegistration {
                        account_id,
                        public_key,
                        key_version,
                        at: std::time::Instant::now(),
                    });
                    return Ok(identity);
                }
                Err(error)
                    if rotation < MAX_RELAY_IDENTITY_ROTATIONS
                        && error
                            .downcast_ref::<CloudRequestError>()
                            .is_some_and(CloudRequestError::is_relay_key_rotation_conflict) =>
                {
                    credential = self
                        .credentials
                        .load()
                        .await?
                        .ok_or_else(|| anyhow!("Alera account is signed out"))?;
                    key_version =
                        next_relay_key_version(credential.relay_key_version.max(key_version))?;
                    identity = IdentityKeyPair::generate();
                    credential.relay_private_key_b64 =
                        Some(URL_SAFE_NO_PAD.encode(identity.private_bytes()));
                    credential.relay_key_version = key_version;
                    self.credentials.save(&credential).await?;
                }
                Err(error) => return Err(error),
            }
        }
        unreachable!("relay identity rotation loop always returns")
    }

    pub(crate) async fn relay_grant(&self) -> Result<super::cloud_client::RelayGrant> {
        let _ = self.relay_identity().await?;
        let token = self.access_token().await?;
        match self.cloud.relay_grant(&token, &self.runtime_id).await {
            Err(error)
                if error
                    .downcast_ref::<CloudRequestError>()
                    .is_some_and(CloudRequestError::can_refresh_authorization) =>
            {
                {
                    let mut current = self.session.lock().await;
                    if current
                        .as_ref()
                        .is_some_and(|session| session.token == token)
                    {
                        *current = None;
                    }
                }
                let refreshed = self.access_token().await?;
                self.cloud.relay_grant(&refreshed, &self.runtime_id).await
            }
            result => result,
        }
    }

    async fn persist_subscription_count(&self, count: i64) -> Result<usize> {
        let active_subscriptions = count.max(0) as usize;
        if let Some(mut account) = self.store.alera_account().await? {
            account.push_subscription_count = active_subscriptions as i64;
            self.store.set_alera_account(&account).await?;
        }
        Ok(active_subscriptions)
    }

    pub(crate) async fn sign_out(&self) -> Result<()> {
        *self.relay_identity_registration.lock().await = None;
        let credential = self.credentials.load().await?;
        let revoke_result = match credential {
            Some(credential) => self.cloud.revoke(&credential.refresh_token).await,
            None => Ok(()),
        };
        self.credentials.delete().await?;
        *self.session.lock().await = None;
        self.store.clear_alera_account().await?;
        revoke_result
    }

    pub(crate) async fn delete_account(&self) -> Result<()> {
        let token = self.access_token().await?;
        self.cloud.delete_account(&token).await?;
        self.credentials.delete().await?;
        *self.session.lock().await = None;
        self.store.clear_alera_account().await
    }

    pub(crate) async fn transfer_runtime(&self, target_account_id: &str) -> Result<()> {
        let token = self.access_token().await?;
        self.cloud
            .transfer_runtime(&token, &self.runtime_id, target_account_id)
            .await?;
        self.credentials.delete().await?;
        *self.session.lock().await = None;
        self.store.clear_alera_account().await
    }
}

fn next_relay_key_version(current: i32) -> Result<i32> {
    let next = current
        .checked_add(1)
        .filter(|version| *version <= MAX_RELAY_KEY_VERSION)
        .ok_or_else(|| anyhow!("relay identity key version is exhausted"))?;
    Ok(next)
}

#[cfg(test)]
mod tests {
    use super::{next_relay_key_version, MAX_RELAY_KEY_VERSION};

    #[test]
    fn relay_key_versions_advance_monotonically() {
        assert_eq!(next_relay_key_version(1).unwrap(), 2);
        assert_eq!(
            next_relay_key_version(MAX_RELAY_KEY_VERSION - 1).unwrap(),
            MAX_RELAY_KEY_VERSION
        );
        assert!(next_relay_key_version(MAX_RELAY_KEY_VERSION).is_err());
    }
}
