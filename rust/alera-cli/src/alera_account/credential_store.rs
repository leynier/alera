use std::path::{Path, PathBuf};

use alera_core::runtime::{
    create_private_runtime_file, prepare_private_runtime_directory, set_private_file_permissions,
};
use anyhow::{Context as _, Result};
use serde::{Deserialize, Serialize};

const KEYRING_SERVICE: &str = "dev.leynier.alera.account";
const FALLBACK_FILE_NAME: &str = "alera-account.credentials.json";

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub(crate) struct StoredAccountCredential {
    pub(crate) refresh_token: String,
}

#[derive(Clone)]
pub(crate) struct AccountCredentialStore {
    runtime_dir: PathBuf,
    runtime_id: String,
}

impl AccountCredentialStore {
    pub(crate) fn new(runtime_dir: PathBuf, runtime_id: String) -> Self {
        Self {
            runtime_dir,
            runtime_id,
        }
    }

    pub(crate) async fn load(&self) -> Result<Option<StoredAccountCredential>> {
        let this = self.clone();
        tokio::task::spawn_blocking(move || this.load_blocking())
            .await
            .context("credential read task failed")?
    }

    pub(crate) async fn save(&self, credential: &StoredAccountCredential) -> Result<()> {
        let this = self.clone();
        let credential = credential.clone();
        tokio::task::spawn_blocking(move || this.save_blocking(&credential))
            .await
            .context("credential write task failed")?
    }

    pub(crate) async fn delete(&self) -> Result<()> {
        let this = self.clone();
        tokio::task::spawn_blocking(move || this.delete_blocking())
            .await
            .context("credential delete task failed")?
    }

    fn load_blocking(&self) -> Result<Option<StoredAccountCredential>> {
        match self.keyring_entry().and_then(|entry| entry.get_password()) {
            Ok(value) => Ok(Some(serde_json::from_str(&value)?)),
            Err(keyring::Error::NoEntry) => self.load_fallback(),
            Err(error) if cfg!(target_os = "linux") => {
                eprintln!("alera keyring unavailable, using private file fallback: {error}");
                self.load_fallback()
            }
            Err(error) => Err(error.into()),
        }
    }

    fn save_blocking(&self, credential: &StoredAccountCredential) -> Result<()> {
        let value = serde_json::to_string(credential)?;
        match self
            .keyring_entry()
            .and_then(|entry| entry.set_password(&value))
        {
            Ok(()) => {
                remove_fallback(&self.fallback_path())?;
                Ok(())
            }
            Err(error) if cfg!(target_os = "linux") => {
                eprintln!("alera keyring unavailable, using private file fallback: {error}");
                write_fallback(&self.fallback_path(), value.as_bytes())
            }
            Err(error) => Err(error.into()),
        }
    }

    fn delete_blocking(&self) -> Result<()> {
        let keyring_result = self
            .keyring_entry()
            .and_then(|entry| entry.delete_credential());
        if let Err(error) = keyring_result {
            if !matches!(error, keyring::Error::NoEntry) && !cfg!(target_os = "linux") {
                return Err(error.into());
            }
        }
        remove_fallback(&self.fallback_path())
    }

    fn load_fallback(&self) -> Result<Option<StoredAccountCredential>> {
        let path = self.fallback_path();
        if !path.exists() {
            return Ok(None);
        }
        let value = std::fs::read_to_string(&path)?;
        Ok(Some(serde_json::from_str(&value)?))
    }

    fn keyring_entry(&self) -> keyring::Result<keyring::Entry> {
        keyring::Entry::new(KEYRING_SERVICE, &self.runtime_id)
    }

    fn fallback_path(&self) -> PathBuf {
        self.runtime_dir.join(FALLBACK_FILE_NAME)
    }
}

fn write_fallback(path: &Path, contents: &[u8]) -> Result<()> {
    if let Some(parent) = path.parent() {
        prepare_private_runtime_directory(parent)?;
    }
    let temp = path.with_extension("json.tmp");
    let mut file = create_private_runtime_file(&temp)?;
    use std::io::Write as _;
    file.write_all(contents)?;
    file.sync_all()?;
    std::fs::rename(&temp, path)?;
    set_private_file_permissions(path)?;
    Ok(())
}

fn remove_fallback(path: &Path) -> Result<()> {
    match std::fs::remove_file(path) {
        Ok(()) => Ok(()),
        Err(error) if error.kind() == std::io::ErrorKind::NotFound => Ok(()),
        Err(error) => Err(error.into()),
    }
}

#[cfg(all(test, unix))]
mod tests {
    use super::{write_fallback, StoredAccountCredential};

    #[cfg(unix)]
    #[test]
    fn fallback_file_is_private() {
        use std::os::unix::fs::PermissionsExt as _;

        let dir = tempfile::tempdir().unwrap();
        let path = dir.path().join("runtime").join("credentials.json");
        let value = serde_json::to_vec(&StoredAccountCredential {
            refresh_token: "secret".to_string(),
        })
        .unwrap();
        write_fallback(&path, &value).unwrap();

        assert_eq!(
            std::fs::metadata(path).unwrap().permissions().mode() & 0o777,
            0o600
        );
    }
}
