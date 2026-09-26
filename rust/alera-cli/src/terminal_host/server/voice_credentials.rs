use crate::native_credential_entry as keyring;
use std::path::{Path, PathBuf};

use alera_core::runtime::{
    create_private_runtime_file, prepare_private_runtime_directory, set_private_file_permissions,
};
use serde::{Deserialize, Serialize};

use crate::terminal_host::diagnostics::redaction::register_secret;
use crate::terminal_host::host_error::{HostError, HostResult};

const KEYRING_SERVICE: &str = "dev.leynier.alera.voice";
const FALLBACK_FILE_NAME: &str = "voice.credentials";

#[derive(Clone, Debug, Default, Deserialize, Serialize)]
#[serde(rename_all = "camelCase")]
pub(super) struct StoredVoiceCredentials {
    #[serde(default)]
    pub(super) gemini_token: Option<String>,
    #[serde(default)]
    pub(super) openai_token: Option<String>,
}

impl StoredVoiceCredentials {
    fn register_secrets(&self) {
        if let Some(token) = self.gemini_token.as_deref() {
            register_secret(token);
        }
        if let Some(token) = self.openai_token.as_deref() {
            register_secret(token);
        }
    }

    fn is_empty(&self) -> bool {
        self.gemini_token.as_deref().is_none_or(str::is_empty)
            && self.openai_token.as_deref().is_none_or(str::is_empty)
    }
}

#[derive(Clone)]
pub(super) struct VoiceCredentialStore {
    runtime_dir: PathBuf,
    runtime_id: String,
}

impl VoiceCredentialStore {
    pub(super) fn new(runtime_dir: &Path, runtime_id: &str) -> Self {
        Self {
            runtime_dir: runtime_dir.to_path_buf(),
            runtime_id: runtime_id.to_string(),
        }
    }

    pub(super) async fn load(&self) -> HostResult<StoredVoiceCredentials> {
        let this = self.clone();
        let credentials = tokio::task::spawn_blocking(move || this.load_blocking())
            .await
            .map_err(|error| {
                HostError::state(format!("voice credential read failed: {error}"))
            })??;
        credentials.register_secrets();
        Ok(credentials)
    }

    pub(super) async fn save(&self, credentials: StoredVoiceCredentials) -> HostResult<()> {
        credentials.register_secrets();
        let this = self.clone();
        tokio::task::spawn_blocking(move || this.save_blocking(&credentials))
            .await
            .map_err(|error| HostError::state(format!("voice credential write failed: {error}")))?
    }

    pub(super) async fn delete(&self) -> HostResult<()> {
        let this = self.clone();
        tokio::task::spawn_blocking(move || this.delete_blocking())
            .await
            .map_err(|error| HostError::state(format!("voice credential delete failed: {error}")))?
    }

    fn load_blocking(&self) -> HostResult<StoredVoiceCredentials> {
        if cfg!(target_os = "linux") {
            if let Some(fallback) = self.load_fallback_if_present()? {
                return Ok(fallback);
            }
        }
        match self.keyring_entry().and_then(|entry| entry.get_password()) {
            Ok(value) => Ok(decode_credentials(&value)),
            Err(keyring::Error::NoEntry) => self.load_fallback(),
            Err(error) if cfg!(target_os = "linux") => {
                tracing::warn!("Voice keyring unavailable; using private file fallback: {error}");
                self.load_fallback()
            }
            Err(error) => Err(HostError::state(format!(
                "Voice credentials could not be read: {error}"
            ))),
        }
    }

    fn save_blocking(&self, credentials: &StoredVoiceCredentials) -> HostResult<()> {
        if credentials.is_empty() {
            return self.delete_blocking();
        }
        let value = serde_json::to_string(credentials)
            .map_err(|error| HostError::state(format!("credential encoding failed: {error}")))?;
        match self
            .keyring_entry()
            .and_then(|entry| entry.set_password(&value))
        {
            Ok(()) => remove_fallback(&self.fallback_path()),
            Err(error) if cfg!(target_os = "linux") => {
                tracing::warn!("Voice keyring unavailable; using private file fallback: {error}");
                write_fallback(&self.fallback_path(), value.as_bytes())
            }
            Err(error) => Err(HostError::state(format!(
                "Voice credentials could not be saved: {error}"
            ))),
        }
    }

    fn delete_blocking(&self) -> HostResult<()> {
        let keyring_result = self
            .keyring_entry()
            .and_then(|entry| entry.delete_credential());
        match keyring_result {
            Ok(()) | Err(keyring::Error::NoEntry) => remove_fallback(&self.fallback_path()),
            Err(error) if cfg!(target_os = "linux") => {
                tracing::warn!(
                    "Voice keyring delete failed; writing empty fallback tombstone: {error}"
                );
                write_fallback(
                    &self.fallback_path(),
                    serde_json::to_string(&StoredVoiceCredentials::default())
                        .unwrap_or_else(|_| "{}".into())
                        .as_bytes(),
                )
            }
            Err(error) => Err(HostError::state(format!(
                "Voice credentials could not be removed: {error}"
            ))),
        }
    }

    fn load_fallback_if_present(&self) -> HostResult<Option<StoredVoiceCredentials>> {
        match std::fs::read_to_string(self.fallback_path()) {
            Ok(value) => Ok(Some(decode_credentials(&value))),
            Err(error) if error.kind() == std::io::ErrorKind::NotFound => Ok(None),
            Err(error) => Err(HostError::state(format!(
                "Voice credentials could not be read: {error}"
            ))),
        }
    }

    fn load_fallback(&self) -> HostResult<StoredVoiceCredentials> {
        Ok(self.load_fallback_if_present()?.unwrap_or_default())
    }

    fn keyring_entry(&self) -> keyring::Result<keyring::Entry> {
        crate::native_credential_entry::native_credential_entry(KEYRING_SERVICE, &self.runtime_id)
    }

    fn fallback_path(&self) -> PathBuf {
        self.runtime_dir.join(FALLBACK_FILE_NAME)
    }
}

fn decode_credentials(value: &str) -> StoredVoiceCredentials {
    serde_json::from_str(value).unwrap_or_default()
}

fn write_fallback(path: &Path, contents: &[u8]) -> HostResult<()> {
    if let Some(parent) = path.parent() {
        prepare_private_runtime_directory(parent)
            .map_err(|error| HostError::state(error.to_string()))?;
    }
    let temp = path.with_extension("tmp");
    let mut file =
        create_private_runtime_file(&temp).map_err(|error| HostError::state(error.to_string()))?;
    use std::io::Write as _;
    file.write_all(contents)
        .map_err(|error| HostError::state(error.to_string()))?;
    file.sync_all()
        .map_err(|error| HostError::state(error.to_string()))?;
    std::fs::rename(&temp, path).map_err(|error| HostError::state(error.to_string()))?;
    set_private_file_permissions(path).map_err(|error| HostError::state(error.to_string()))
}

fn remove_fallback(path: &Path) -> HostResult<()> {
    match std::fs::remove_file(path) {
        Ok(()) => Ok(()),
        Err(error) if error.kind() == std::io::ErrorKind::NotFound => Ok(()),
        Err(error) => Err(HostError::state(error.to_string())),
    }
}

#[cfg(all(test, unix))]
mod tests {
    use std::os::unix::fs::PermissionsExt as _;

    use super::write_fallback;

    #[test]
    fn fallback_file_is_private() {
        let dir = tempfile::tempdir().unwrap();
        let path = dir.path().join("runtime").join("voice.credentials");
        write_fallback(&path, b"secret").unwrap();
        assert_eq!(
            std::fs::metadata(path).unwrap().permissions().mode() & 0o777,
            0o600
        );
    }

    #[test]
    fn linux_fallback_is_authoritative() {
        let dir = tempfile::tempdir().unwrap();
        let store = super::VoiceCredentialStore::new(dir.path(), "runtime");
        write_fallback(&store.fallback_path(), br#"{"geminiToken":"B"}"#).unwrap();
        let loaded = store.load_blocking().unwrap();
        assert_eq!(loaded.gemini_token.as_deref(), Some("B"));
    }

    #[test]
    fn empty_fallback_tombstone_clears_credentials() {
        let dir = tempfile::tempdir().unwrap();
        let store = super::VoiceCredentialStore::new(dir.path(), "runtime");
        write_fallback(&store.fallback_path(), b"{}").unwrap();
        let loaded = store.load_blocking().unwrap();
        assert!(loaded.gemini_token.is_none());
        assert!(loaded.openai_token.is_none());
    }
}
