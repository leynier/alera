use std::path::PathBuf;

use alera_core::runtime::{create_private_runtime_file, prepare_private_runtime_directory};
use base64::{engine::general_purpose::STANDARD, Engine};
use chacha20poly1305::{aead::Aead, ChaCha20Poly1305, KeyInit, Nonce};
use serde::{Deserialize, Serialize};

use crate::native_credential_entry as keyring;
use crate::terminal_host::diagnostics::redaction::register_secret;
use crate::terminal_host::host_error::{HostError, HostResult};

#[derive(Clone, Default, Serialize, Deserialize)]
pub(super) struct Credentials {
    #[serde(default)]
    pub plan_notice_acknowledged: bool,
    pub host_id: String,
    pub active: Option<String>,
    pub accounts: Vec<Account>,
}

#[derive(Clone, Serialize, Deserialize)]
pub(super) struct Account {
    pub client_id: String,
    pub subject: String,
    pub email: String,
    pub tokens: Option<Tokens>,
}

#[derive(Clone, Serialize, Deserialize)]
pub(super) struct Tokens {
    pub access_token: String,
    pub refresh_token: Option<String>,
    pub id_token: String,
    pub scopes: Vec<String>,
    pub expires_at: i64,
    #[serde(default)]
    pub identity_pending: bool,
}

impl Tokens {
    pub fn register_secrets(&self) {
        register_secret(&self.access_token);
        register_secret(&self.id_token);
        if let Some(value) = &self.refresh_token {
            register_secret(value);
        }
    }

    pub fn can_infer(&self) -> bool {
        self.scopes
            .iter()
            .any(|scope| scope == "chatgpt.tokens.use.direct")
    }
}

#[derive(Clone)]
pub(super) struct CredentialStore {
    directory: PathBuf,
    io: std::sync::Arc<tokio::sync::Mutex<()>>,
    #[cfg(test)]
    file_only: bool,
}

impl CredentialStore {
    pub fn new(directory: PathBuf) -> Self {
        Self {
            directory,
            io: Default::default(),
            #[cfg(test)]
            file_only: false,
        }
    }

    #[cfg(test)]
    pub fn for_test(directory: PathBuf) -> Self {
        Self {
            directory,
            io: Default::default(),
            file_only: true,
        }
    }

    pub async fn load(&self) -> HostResult<Credentials> {
        let this = self.clone();
        let guard = self.io.clone().lock_owned().await;
        tokio::task::spawn_blocking(move || {
            let _guard = guard;
            let value = this.read_value()?;
            let mut data: Credentials = match value {
                Some(value) => serde_json::from_str(&value)
                    .map_err(|_| HostError::state("ChatGPT credential storage is invalid."))?,
                None => Credentials::default(),
            };
            if data.host_id.is_empty() {
                data.host_id = format!("urn:uuid:{}", uuid::Uuid::new_v4());
                this.save_blocking(&data)?;
            }
            for account in &data.accounts {
                if let Some(tokens) = &account.tokens {
                    tokens.register_secrets();
                }
            }
            Ok(data)
        })
        .await
        .map_err(|_| HostError::state("ChatGPT credential task failed."))?
    }

    pub async fn save(&self, data: &Credentials) -> HostResult<()> {
        let this = self.clone();
        let data = data.clone();
        let guard = self.io.clone().lock_owned().await;
        // A canceled caller cannot interrupt blocking I/O. Keep subsequent
        // writes behind it until the atomic replacement actually finishes.
        tokio::task::spawn_blocking(move || {
            let _guard = guard;
            this.save_blocking(&data)
        })
        .await
        .map_err(|_| HostError::state("ChatGPT credential task failed."))?
    }

    fn read_value(&self) -> HostResult<Option<String>> {
        let Some(value) = self.read_file()? else {
            return Ok(None);
        };
        #[cfg(test)]
        if self.file_only {
            return Ok(Some(value));
        }
        let document: serde_json::Value = serde_json::from_str(&value)
            .map_err(|_| HostError::state("ChatGPT credential storage is invalid."))?;
        if document.get("sealed").is_none() && cfg!(target_os = "linux") {
            return Ok(Some(value));
        }
        let encoded = self
            .entry()
            .and_then(|entry| entry.get_password())
            .map_err(|_| {
                HostError::state("Unlock the system credential store to reconnect ChatGPT.")
            })?;
        unseal(&value, &storage_key(&encoded)?).map(Some)
    }

    fn entry(&self) -> keyring::Result<keyring::Entry> {
        keyring::native_credential_entry(
            "dev.leynier.alera.chatgpt-key",
            &self.directory.to_string_lossy(),
        )
    }

    fn read_file(&self) -> HostResult<Option<String>> {
        match std::fs::read_to_string(self.directory.join("chatgpt.credentials")) {
            Ok(value) => Ok(Some(value)),
            Err(error) if error.kind() == std::io::ErrorKind::NotFound => Ok(None),
            Err(_) => Err(HostError::state("ChatGPT credentials could not be read.")),
        }
    }

    fn save_blocking(&self, data: &Credentials) -> HostResult<()> {
        let value = serde_json::to_string(data)
            .map_err(|_| HostError::state("ChatGPT credentials could not be encoded."))?;
        #[cfg(test)]
        if self.file_only {
            return write_private(&self.directory, value.as_bytes());
        }
        // Windows Credential Manager has a 2560-byte blob limit. Keep only
        // the encryption key there; a multi-account OAuth record exceeds it.
        let key = self.entry().and_then(|entry| match entry.get_password() {
            Ok(value) => Ok(value),
            Err(keyring::Error::NoEntry) => {
                let value = STANDARD.encode(rand::random::<[u8; 32]>());
                entry.set_password(&value)?;
                Ok(value)
            }
            Err(error) => Err(error),
        });
        match key {
            Ok(key) => write_private(
                &self.directory,
                seal(&value, &storage_key(&key)?)?.as_bytes(),
            ),
            Err(_) if cfg!(target_os = "linux") => write_private(&self.directory, value.as_bytes()),
            Err(_) => Err(HostError::state("ChatGPT credentials could not be saved.")),
        }
    }
}

fn storage_key(encoded: &str) -> HostResult<[u8; 32]> {
    register_secret(encoded);
    STANDARD
        .decode(encoded)
        .ok()
        .and_then(|bytes| bytes.try_into().ok())
        .ok_or_else(|| HostError::state("ChatGPT storage key is invalid."))
}

fn seal(value: &str, key: &[u8; 32]) -> HostResult<String> {
    let nonce = rand::random::<[u8; 12]>();
    let cipher = ChaCha20Poly1305::new_from_slice(key).unwrap();
    let ciphertext = cipher
        .encrypt(&Nonce::from(nonce), value.as_bytes())
        .map_err(|_| HostError::state("ChatGPT credentials could not be encrypted."))?;
    Ok(serde_json::json!({"sealed":1, "nonce":STANDARD.encode(nonce), "ciphertext":STANDARD.encode(ciphertext)}).to_string())
}

fn unseal(value: &str, key: &[u8; 32]) -> HostResult<String> {
    let invalid = || HostError::state("ChatGPT credentials could not be decrypted.");
    let value: serde_json::Value = serde_json::from_str(value).map_err(|_| invalid())?;
    if value.get("sealed").and_then(serde_json::Value::as_u64) != Some(1) {
        return Err(invalid());
    }
    let nonce: [u8; 12] = STANDARD
        .decode(value["nonce"].as_str().ok_or_else(invalid)?)
        .map_err(|_| invalid())?
        .try_into()
        .map_err(|_| invalid())?;
    let ciphertext = STANDARD
        .decode(value["ciphertext"].as_str().ok_or_else(invalid)?)
        .map_err(|_| invalid())?;
    let cipher = ChaCha20Poly1305::new_from_slice(key).unwrap();
    let plaintext = cipher
        .decrypt(&Nonce::from(nonce), ciphertext.as_ref())
        .map_err(|_| invalid())?;
    String::from_utf8(plaintext).map_err(|_| invalid())
}

fn write_private(directory: &std::path::Path, contents: &[u8]) -> HostResult<()> {
    use std::io::Write as _;
    let write = || -> anyhow::Result<()> {
        prepare_private_runtime_directory(directory)?;
        let temporary = directory.join("chatgpt.credentials.tmp");
        let mut file = create_private_runtime_file(&temporary)?;
        file.write_all(contents)?;
        file.sync_all()?;
        std::fs::rename(temporary, directory.join("chatgpt.credentials"))?;
        Ok(())
    };
    write().map_err(|_| HostError::state("ChatGPT credentials could not be saved."))
}

#[cfg(all(test, unix))]
mod tests {
    #[test]
    fn sealed_credentials_support_large_records_and_reject_tampering() {
        let key = rand::random::<[u8; 32]>();
        let mut wrong_key = key;
        wrong_key[0] ^= 1;
        let text = "synthetic-credentials".repeat(1000);
        let sealed = super::seal(&text, &key).unwrap();
        assert!(!sealed.contains("synthetic-credentials"));
        assert_eq!(super::unseal(&sealed, &key).unwrap(), text);
        assert!(super::unseal(&sealed, &wrong_key).is_err());
        let mut value: serde_json::Value = serde_json::from_str(&sealed).unwrap();
        value["nonce"] = serde_json::json!("invalid");
        assert!(super::unseal(&value.to_string(), &key).is_err());
        assert_ne!(super::seal(&text, &key).unwrap(), sealed);
    }
    #[test]
    fn credentials_are_private_and_replaced() {
        use std::os::unix::fs::PermissionsExt;
        let dir = tempfile::tempdir().unwrap();
        super::write_private(dir.path(), b"first").unwrap();
        super::write_private(dir.path(), b"second").unwrap();
        let path = dir.path().join("chatgpt.credentials");
        assert_eq!(std::fs::read(&path).unwrap(), b"second");
        assert_eq!(
            std::fs::metadata(path).unwrap().permissions().mode() & 0o777,
            0o600
        );
    }
}
