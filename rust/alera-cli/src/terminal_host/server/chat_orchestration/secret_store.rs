//! Where a provided secret goes (`chatOrchestration.requestSecret`): a
//! one-use `secretRef` in the provider-secret store, or an owner-only file.
//! Both expire after a day. Neither keeps the value anywhere else.

use std::path::{Path, PathBuf};
use std::sync::Arc;
use std::time::{Duration, SystemTime, UNIX_EPOCH};

use alera_core::runtime::{
    create_private_runtime_file, prepare_private_runtime_directory, set_private_file_permissions,
};
use serde_json::{json, Value};
use sha2::{Digest, Sha256};

use crate::terminal_host::host_error::{HostError, HostResult};
use crate::terminal_host::server::agent_chat_provider_settings::credentials::ProviderSecrets;

/// How long a ref or a file lives.
pub(crate) const SECRET_TTL: Duration = Duration::from_secs(24 * 60 * 60);

const REF_PREFIX: &str = "secret-ref:";
const STORE_PREFIX: &str = "chat-secret:";

pub(super) const REF_UNKNOWN: &str =
    "That secretRef was already used or does not exist. Ask the person again with request_secret.";
pub(super) const REF_EXPIRED: &str =
    "That secretRef expired. Ask the person again with request_secret.";
const REF_INVALID: &str = "That secretRef is not valid.";
const REF_CONSUME_FAILED: &str = "Could not use that secretRef. Try again.";

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub(crate) enum SecretDelivery {
    Ref,
    File,
}

impl SecretDelivery {
    pub(crate) fn parse(value: Option<&str>) -> HostResult<Self> {
        match value {
            None | Some("file") => Ok(Self::File),
            Some("ref") => Ok(Self::Ref),
            Some(_) => Err(HostError::format("delivery must be file or ref")),
        }
    }
}

pub(crate) struct SecretVault {
    secrets: Arc<dyn ProviderSecrets>,
    directory: PathBuf,
    ttl: Duration,
    /// Serializes ref reads, so a ref is handed out once.
    reads: tokio::sync::Mutex<()>,
}

impl SecretVault {
    pub(crate) fn new(secrets: Arc<dyn ProviderSecrets>, directory: PathBuf) -> Self {
        Self {
            secrets,
            directory,
            ttl: SECRET_TTL,
            reads: tokio::sync::Mutex::new(()),
        }
    }

    #[cfg(test)]
    pub(crate) fn with_ttl(mut self, ttl: Duration) -> Self {
        self.ttl = ttl;
        self
    }

    fn refs(&self) -> PathBuf {
        self.directory.join("refs")
    }

    fn files(&self) -> PathBuf {
        self.directory.join("files")
    }

    fn index(&self, secret_ref: &str) -> PathBuf {
        self.refs()
            .join(hex::encode(Sha256::digest(secret_ref.as_bytes())))
    }

    /// Stores `value` and answers `{status: saved, secretRef}` or
    /// `{status: saved, file}`.
    pub(crate) async fn deliver(
        &self,
        chat_id: &str,
        delivery: SecretDelivery,
        value: &str,
    ) -> HostResult<Value> {
        let fail = || HostError::state("The secret could not be stored.");
        let token = uuid::Uuid::new_v4().simple().to_string();
        match delivery {
            SecretDelivery::Ref => {
                let secret_ref = format!("{REF_PREFIX}{token}");
                let expires = now_ms() + self.ttl.as_millis() as u64;
                write_private(
                    &self.index(&secret_ref),
                    json!({"chatId": chat_id, "secretRef": secret_ref, "expiresAtMs": expires})
                        .to_string()
                        .as_bytes(),
                )
                .map_err(|_| fail())?;
                if let Err(error) = self
                    .secrets
                    .save(&format!("{STORE_PREFIX}{secret_ref}"), value)
                    .await
                {
                    let _ = std::fs::remove_file(self.index(&secret_ref));
                    return Err(error);
                }
                Ok(json!({"status": "saved", "delivery": "ref", "secretRef": secret_ref}))
            }
            SecretDelivery::File => {
                let path = self.files().join(token);
                write_private(&path, value.as_bytes()).map_err(|_| fail())?;
                Ok(json!({
                    "status": "saved",
                    "delivery": "file",
                    "file": path.to_string_lossy(),
                }))
            }
        }
    }

    /// Removes what [Self::deliver] stored, when its request could not settle.
    pub(crate) async fn discard(&self, saved: &Value) {
        if let Some(secret_ref) = saved["secretRef"].as_str() {
            let _ = self
                .secrets
                .clear(&format!("{STORE_PREFIX}{secret_ref}"))
                .await;
            let _ = std::fs::remove_file(self.index(secret_ref));
        }
        if let Some(file) = saved["file"].as_str() {
            let _ = std::fs::remove_file(file);
        }
    }

    /// Hands out a ref's value once. `chat_id` is the reading agent's chat;
    /// a ref saved for another chat reads as unknown.
    pub(crate) async fn consume(
        &self,
        secret_ref: &str,
        chat_id: Option<&str>,
    ) -> HostResult<String> {
        let unknown = || HostError::conflict("secretRefUnavailable", REF_UNKNOWN, json!({}));
        let valid = secret_ref
            .strip_prefix(REF_PREFIX)
            .is_some_and(|hex| hex.len() == 32 && hex.bytes().all(|b| b.is_ascii_hexdigit()));
        if !valid {
            return Err(HostError::conflict(
                "secretRefInvalid",
                REF_INVALID,
                json!({}),
            ));
        }
        let _guard = self.reads.lock().await;
        let index = self.index(secret_ref);
        let Ok(text) = std::fs::read_to_string(&index) else {
            return Err(unknown());
        };
        let entry: Value = serde_json::from_str(&text).unwrap_or(Value::Null);
        if chat_id.is_some_and(|chat_id| entry["chatId"].as_str() != Some(chat_id)) {
            return Err(unknown());
        }
        let key = format!("{STORE_PREFIX}{secret_ref}");
        if entry["expiresAtMs"].as_u64().unwrap_or(0) <= now_ms() {
            let _ = self.secrets.clear(&key).await;
            let _ = std::fs::remove_file(&index);
            return Err(HostError::conflict(
                "secretRefExpired",
                REF_EXPIRED,
                json!({}),
            ));
        }
        let value = self.secrets.load(&key).await?.ok_or_else(unknown)?;
        // Spent before it is handed out: a failed delete fails the read.
        self.secrets.clear(&key).await.map_err(|_| {
            HostError::conflict("secretRefConsumeFailed", REF_CONSUME_FAILED, json!({}))
        })?;
        std::fs::remove_file(&index).map_err(|_| {
            HostError::conflict("secretRefConsumeFailed", REF_CONSUME_FAILED, json!({}))
        })?;
        Ok(value)
    }

    /// Deletes expired refs and files.
    pub(crate) async fn sweep(&self) {
        let now = now_ms();
        for path in entries(&self.refs()) {
            let expired = std::fs::read_to_string(&path)
                .ok()
                .and_then(|text| serde_json::from_str::<Value>(&text).ok())
                .is_none_or(|entry| entry["expiresAtMs"].as_u64().unwrap_or(0) <= now);
            if !expired {
                continue;
            }
            // The index file is named by a hash; it records its ref.
            if let Some(secret_ref) = self.ref_of_index(&path) {
                let _ = self
                    .secrets
                    .clear(&format!("{STORE_PREFIX}{secret_ref}"))
                    .await;
            }
            let _ = std::fs::remove_file(&path);
        }
        let cutoff = SystemTime::now().checked_sub(self.ttl);
        for path in entries(&self.files()) {
            let old = std::fs::metadata(&path)
                .and_then(|metadata| metadata.modified())
                .map(|modified| cutoff.is_none_or(|cutoff| modified <= cutoff))
                .unwrap_or(true);
            if old {
                let _ = std::fs::remove_file(&path);
            }
        }
    }

    fn ref_of_index(&self, path: &Path) -> Option<String> {
        std::fs::read_to_string(path)
            .ok()
            .and_then(|text| serde_json::from_str::<Value>(&text).ok())
            .and_then(|entry| entry["secretRef"].as_str().map(str::to_owned))
    }
}

fn entries(directory: &Path) -> Vec<PathBuf> {
    std::fs::read_dir(directory)
        .into_iter()
        .flatten()
        .flatten()
        .map(|entry| entry.path())
        .filter(|path| path.is_file())
        .collect()
}

fn now_ms() -> u64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|elapsed| elapsed.as_millis() as u64)
        .unwrap_or(0)
}

/// Writes an owner-only file in an owner-only directory, through a partial
/// file renamed into place.
fn write_private(path: &Path, bytes: &[u8]) -> std::io::Result<()> {
    use std::io::Write as _;
    prepare_private_runtime_directory(path.parent().expect("secret parent"))?;
    let partial = path.with_extension("partial");
    let result = (|| {
        let mut file = create_private_runtime_file(&partial)?;
        file.write_all(bytes)?;
        file.sync_all()?;
        std::fs::rename(&partial, path)?;
        set_private_file_permissions(path)
    })();
    if result.is_err() {
        let _ = std::fs::remove_file(&partial);
    }
    result
}
