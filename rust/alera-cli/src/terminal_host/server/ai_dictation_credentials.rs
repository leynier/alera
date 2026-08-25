use std::path::{Path, PathBuf};

use alera_core::runtime::{
    create_private_runtime_file, prepare_private_runtime_directory, set_private_file_permissions,
};

use crate::terminal_host::diagnostics::redaction::register_secret;
use crate::terminal_host::host_error::{HostError, HostResult};

const KEYRING_SERVICE: &str = "dev.leynier.alera.ai-dictation";
const FALLBACK_FILE_NAME: &str = "ai-dictation.credentials";

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

    pub(super) async fn load(&self) -> HostResult<Option<String>> {
        let this = self.clone();
        let token = tokio::task::spawn_blocking(move || this.load_blocking())
            .await
            .map_err(|error| HostError::state(format!("credential read task failed: {error}")))??;
        if let Some(token) = token.as_deref() {
            register_secret(token);
        }
        Ok(token)
    }

    pub(super) async fn save(&self, token: String) -> HostResult<()> {
        register_secret(&token);
        let this = self.clone();
        tokio::task::spawn_blocking(move || this.save_blocking(&token))
            .await
            .map_err(|error| HostError::state(format!("credential write task failed: {error}")))?
    }

    pub(super) async fn delete(&self) -> HostResult<()> {
        let this = self.clone();
        tokio::task::spawn_blocking(move || this.delete_blocking())
            .await
            .map_err(|error| HostError::state(format!("credential delete task failed: {error}")))?
    }

    fn load_blocking(&self) -> HostResult<Option<String>> {
        match self.keyring_entry().and_then(|entry| entry.get_password()) {
            Ok(token) => Ok(Some(token)),
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

    fn save_blocking(&self, token: &str) -> HostResult<()> {
        match self
            .keyring_entry()
            .and_then(|entry| entry.set_password(token))
        {
            Ok(()) => remove_fallback(&self.fallback_path()),
            Err(error) if cfg!(target_os = "linux") => {
                tracing::warn!(
                    "AI Dictation keyring unavailable; using private file fallback: {error}"
                );
                write_fallback(&self.fallback_path(), token.as_bytes())
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

    fn load_fallback(&self) -> HostResult<Option<String>> {
        match std::fs::read_to_string(self.fallback_path()) {
            Ok(token) => Ok(Some(token)),
            Err(error) if error.kind() == std::io::ErrorKind::NotFound => Ok(None),
            Err(error) => Err(HostError::state(format!(
                "AI Dictation credentials could not be read: {error}"
            ))),
        }
    }

    fn keyring_entry(&self) -> keyring::Result<keyring::Entry> {
        keyring::Entry::new(KEYRING_SERVICE, &self.runtime_id)
    }

    fn fallback_path(&self) -> PathBuf {
        self.runtime_dir.join(FALLBACK_FILE_NAME)
    }
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
        let path = dir.path().join("runtime").join("credentials");
        write_fallback(&path, b"secret").unwrap();

        assert_eq!(
            std::fs::metadata(path).unwrap().permissions().mode() & 0o777,
            0o600
        );
    }
}
