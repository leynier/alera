use std::path::{Path, PathBuf};

use alera_core::runtime::{
    create_private_runtime_file, prepare_private_runtime_directory, set_private_file_permissions,
};
use async_trait::async_trait;
use sha2::{Digest, Sha256};

use crate::native_credential_entry as keyring;
use crate::terminal_host::diagnostics::redaction::register_secret;
use crate::terminal_host::host_error::{HostError, HostResult};

const SERVICE: &str = "dev.leynier.alera.agent-chat-provider";

#[async_trait]
pub(crate) trait ProviderSecrets: Send + Sync {
    async fn load(&self, reference: &str) -> HostResult<Option<String>>;
    async fn save(&self, reference: &str, value: &str) -> HostResult<()>;
    async fn clear(&self, reference: &str) -> HostResult<()>;
}

#[derive(Clone)]
pub(crate) struct ProviderCredentialStore {
    runtime_dir: PathBuf,
    runtime_id: String,
}

impl ProviderCredentialStore {
    pub(crate) fn new(runtime_dir: &Path, runtime_id: &str) -> Self {
        Self {
            runtime_dir: runtime_dir.to_owned(),
            runtime_id: runtime_id.to_owned(),
        }
    }

    fn entry(&self, reference: &str) -> keyring::Result<keyring::Entry> {
        keyring::native_credential_entry(SERVICE, &format!("{}:{reference}", self.runtime_id))
    }

    fn path(&self, reference: &str) -> PathBuf {
        self.runtime_dir
            .join("agent-chat-credentials")
            .join(hex::encode(Sha256::digest(reference.as_bytes())))
    }

    fn load_blocking(&self, reference: &str) -> HostResult<Option<String>> {
        let value = match self.entry(reference).and_then(|entry| entry.get_password()) {
            Ok(value) => Some(value),
            Err(keyring::Error::NoEntry) => read_fallback(&self.path(reference))?,
            Err(_) if cfg!(target_os = "linux") => read_fallback(&self.path(reference))?,
            Err(_) => return Err(HostError::state("Provider credentials could not be read.")),
        };
        if let Some(value) = &value {
            register_secret(value);
        }
        Ok(value)
    }

    fn save_blocking(&self, reference: &str, value: &str) -> HostResult<()> {
        match self
            .entry(reference)
            .and_then(|entry| entry.set_password(value))
        {
            Ok(()) => remove_fallback(&self.path(reference)),
            Err(_) if cfg!(target_os = "linux") => write_fallback(&self.path(reference), value),
            Err(_) => Err(HostError::state("Provider credentials could not be saved.")),
        }
    }
}

#[async_trait]
impl ProviderSecrets for ProviderCredentialStore {
    async fn load(&self, reference: &str) -> HostResult<Option<String>> {
        let this = self.clone();
        let reference = reference.to_owned();
        tokio::task::spawn_blocking(move || this.load_blocking(&reference))
            .await
            .map_err(|_| HostError::state("Provider credential read task failed."))?
    }

    async fn save(&self, reference: &str, value: &str) -> HostResult<()> {
        register_secret(value);
        let this = self.clone();
        let reference = reference.to_owned();
        let value = value.to_owned();
        tokio::task::spawn_blocking(move || this.save_blocking(&reference, &value))
            .await
            .map_err(|_| HostError::state("Provider credential write task failed."))?
    }

    async fn clear(&self, reference: &str) -> HostResult<()> {
        let this = self.clone();
        let reference = reference.to_owned();
        tokio::task::spawn_blocking(move || {
            match this
                .entry(&reference)
                .and_then(|entry| entry.delete_credential())
            {
                Ok(()) | Err(keyring::Error::NoEntry) => {}
                Err(_) if cfg!(target_os = "linux") => {}
                Err(_) => {
                    return Err(HostError::state(
                        "Provider credentials could not be cleared.",
                    ))
                }
            }
            remove_fallback(&this.path(&reference))
        })
        .await
        .map_err(|_| HostError::state("Provider credential clear task failed."))?
    }
}

fn read_fallback(path: &Path) -> HostResult<Option<String>> {
    match std::fs::read_to_string(path) {
        Ok(value) => {
            set_private_file_permissions(path)
                .map_err(|_| HostError::state("Provider credentials could not be protected."))?;
            Ok(Some(value))
        }
        Err(error) if error.kind() == std::io::ErrorKind::NotFound => Ok(None),
        Err(_) => Err(HostError::state("Provider credentials could not be read.")),
    }
}

fn write_fallback(path: &Path, value: &str) -> HostResult<()> {
    let fail = || HostError::state("Provider credentials could not be saved.");
    prepare_private_runtime_directory(path.parent().expect("credential parent"))
        .map_err(|_| fail())?;
    let temp = path.with_extension(uuid::Uuid::new_v4().to_string());
    let result = (|| {
        use std::io::Write as _;
        let mut file = create_private_runtime_file(&temp).map_err(|_| fail())?;
        file.write_all(value.as_bytes()).map_err(|_| fail())?;
        file.sync_all().map_err(|_| fail())?;
        std::fs::rename(&temp, path).map_err(|_| fail())?;
        set_private_file_permissions(path).map_err(|_| fail())
    })();
    if result.is_err() {
        let _ = std::fs::remove_file(temp);
    }
    result
}

fn remove_fallback(path: &Path) -> HostResult<()> {
    match std::fs::remove_file(path) {
        Ok(()) => Ok(()),
        Err(error) if error.kind() == std::io::ErrorKind::NotFound => Ok(()),
        Err(_) => Err(HostError::state(
            "Provider credentials could not be cleared.",
        )),
    }
}

#[cfg(all(test, unix))]
mod tests {
    use super::*;
    use std::os::unix::fs::PermissionsExt;

    #[test]
    fn fallback_is_private_and_opaque() {
        let dir = tempfile::tempdir().unwrap();
        let store = ProviderCredentialStore::new(dir.path(), "runtime");
        let path = store.path("API_TOKEN");
        write_fallback(&path, "synthetic-secret").unwrap();
        assert!(!path.to_string_lossy().contains("API_TOKEN"));
        assert_eq!(
            std::fs::metadata(&path).unwrap().permissions().mode() & 0o777,
            0o600
        );
        assert_eq!(
            read_fallback(&path).unwrap().as_deref(),
            Some("synthetic-secret")
        );
        remove_fallback(&path).unwrap();
        assert!(read_fallback(&path).unwrap().is_none());
    }
}
