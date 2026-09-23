use crate::native_credential_entry as keyring;
use std::path::{Path, PathBuf};

use alera_core::runtime::{
    create_private_runtime_file, prepare_private_runtime_directory, set_private_file_permissions,
};
use serde::{Deserialize, Serialize};

use crate::terminal_host::diagnostics::redaction::register_secret;
use crate::terminal_host::host_error::{HostError, HostResult};

const KEYRING_SERVICE: &str = "dev.leynier.alera.ai-dictation";
const FALLBACK_FILE_NAME: &str = "ai-dictation.credentials";

#[derive(Clone, Debug, Deserialize, Serialize)]
#[serde(rename_all = "camelCase")]
pub(super) struct StoredAiDictationCredential {
    pub(super) token: String,
    pub(super) origin: Option<String>,
}

#[derive(Clone)]
pub(super) struct AiDictationCredentialStore {
    runtime_dir: PathBuf,
    runtime_id: String,
}

impl AiDictationCredentialStore {
    pub(super) fn new(runtime_dir: &Path, runtime_id: &str) -> Self {
        Self {
            runtime_dir: runtime_dir.to_path_buf(),
            runtime_id: runtime_id.to_string(),
        }
    }

    pub(super) async fn load(&self) -> HostResult<Option<StoredAiDictationCredential>> {
        let this = self.clone();
        let token = tokio::task::spawn_blocking(move || this.load_blocking())
            .await
            .map_err(|error| HostError::state(format!("credential read task failed: {error}")))??;
        if let Some(credential) = token.as_ref() {
            register_secret(&credential.token);
        }
        Ok(token)
    }

    pub(super) async fn save(&self, credential: StoredAiDictationCredential) -> HostResult<()> {
        register_secret(&credential.token);
        let this = self.clone();
        tokio::task::spawn_blocking(move || this.save_blocking(&credential))
            .await
            .map_err(|error| HostError::state(format!("credential write task failed: {error}")))?
    }

    pub(super) async fn delete(&self) -> HostResult<()> {
        let this = self.clone();
        tokio::task::spawn_blocking(move || this.delete_blocking())
            .await
            .map_err(|error| HostError::state(format!("credential delete task failed: {error}")))?
    }

    fn load_blocking(&self) -> HostResult<Option<StoredAiDictationCredential>> {
        match self.keyring_entry().and_then(|entry| entry.get_password()) {
            Ok(value) => Ok(Some(decode_credential(&value))),
            Err(keyring::Error::NoEntry) => self.load_fallback(),
            Err(error) if cfg!(target_os = "linux") => {
                tracing::warn!(
                    "AI Dictation keyring unavailable; using private file fallback: {error}"
                );
                self.load_fallback()
            }
            Err(error) => Err(HostError::state(format!(
                "AI Dictation credentials could not be read: {error}"
            ))),
        }
    }

    fn save_blocking(&self, credential: &StoredAiDictationCredential) -> HostResult<()> {
        let value = serde_json::to_string(credential)
            .map_err(|error| HostError::state(format!("credential encoding failed: {error}")))?;
        match self
            .keyring_entry()
            .and_then(|entry| entry.set_password(&value))
        {
            Ok(()) => remove_fallback(&self.fallback_path()),
            Err(error) if cfg!(target_os = "linux") => {
                tracing::warn!(
                    "AI Dictation keyring unavailable; using private file fallback: {error}"
                );
                write_fallback(&self.fallback_path(), value.as_bytes())
            }
            Err(error) => Err(HostError::state(format!(
                "AI Dictation credentials could not be saved: {error}"
            ))),
        }
    }

    fn delete_blocking(&self) -> HostResult<()> {
        let keyring_result = self
            .keyring_entry()
            .and_then(|entry| entry.delete_credential());
        if let Err(error) = keyring_result {
            if !matches!(error, keyring::Error::NoEntry) && !cfg!(target_os = "linux") {
                return Err(HostError::state(format!(
                    "AI Dictation credentials could not be removed: {error}"
                )));
            }
        }
        remove_fallback(&self.fallback_path())
    }

    fn load_fallback(&self) -> HostResult<Option<StoredAiDictationCredential>> {
        match std::fs::read_to_string(self.fallback_path()) {
            Ok(value) => Ok(Some(decode_credential(&value))),
            Err(error) if error.kind() == std::io::ErrorKind::NotFound => Ok(None),
            Err(error) => Err(HostError::state(format!(
                "AI Dictation credentials could not be read: {error}"
            ))),
        }
    }

    fn keyring_entry(&self) -> keyring::Result<keyring::Entry> {
        crate::native_credential_entry::native_credential_entry(KEYRING_SERVICE, &self.runtime_id)
    }

    fn fallback_path(&self) -> PathBuf {
        self.runtime_dir.join(FALLBACK_FILE_NAME)
    }
}

fn decode_credential(value: &str) -> StoredAiDictationCredential {
    serde_json::from_str(value).unwrap_or_else(|_| StoredAiDictationCredential {
        token: value.to_string(),
        origin: None,
    })
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

    use super::{decode_credential, write_fallback};

    #[test]
    fn fallback_file_is_private() {
        let dir = tempfile::tempdir().unwrap();
        let path = dir.path().join("runtime").join("credentials");
        write_fallback(&path, b"secret").unwrap();

        assert_eq!(
            std::fs::metadata(path).unwrap().permissions().mode() & 0o777,
            0o600
        );
    }

    #[test]
    fn legacy_raw_tokens_decode_without_an_origin() {
        let credential = decode_credential("legacy-secret");
        assert_eq!(credential.token, "legacy-secret");
        assert_eq!(credential.origin, None);
    }
}
