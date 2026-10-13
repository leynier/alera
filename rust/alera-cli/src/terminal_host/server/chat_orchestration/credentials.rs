use std::collections::HashMap;
use std::fs::{self, OpenOptions};
use std::io::Write;
use std::path::{Path, PathBuf};
use std::sync::{Arc, Mutex};

use alera_core::runtime::{
    hash_chat_orchestration_credential, new_chat_orchestration_credential_secret, RuntimeStore,
};
use alera_provider_protocol::{McpServerSpec, McpTransport};
use async_trait::async_trait;
use serde_json::Value;
use uuid::Uuid;

use crate::terminal_host::host_error::{HostError, HostResult};
use crate::terminal_host::server::agent_chat_runtime::provider_factory::{
    ProviderLaunch, ProviderLaunchHook,
};

const CREDENTIAL_DIR: &str = "agent-chat-mcp";
const CREDENTIAL_ENV: &str = "ALERA_CHAT_CREDENTIAL_FILE";

#[derive(Debug, Clone, PartialEq, Eq)]
pub(crate) struct CredentialBinding {
    pub chat_id: String,
    pub generation: i64,
    pub credential_hash: String,
}

#[derive(Debug, Clone)]
struct IssuedCredential {
    chat_id: String,
    path: PathBuf,
}

/// Mints one private token file for each provider generation and injects the
/// local MCP server command into the typed launch. The secret is never put in
/// `ProviderLaunch`, argv, snapshots or logs.
pub(crate) struct ChatCredentialLaunchHook {
    store: RuntimeStore,
    runtime_dir: PathBuf,
    current: Mutex<HashMap<(String, i64), IssuedCredential>>,
}

impl ChatCredentialLaunchHook {
    pub(crate) fn new(store: RuntimeStore, runtime_dir: PathBuf) -> HostResult<Arc<Self>> {
        let directory = runtime_dir.join(CREDENTIAL_DIR);
        fs::create_dir_all(&directory).map_err(|error| {
            HostError::state(format!(
                "could not create chat credential directory: {error}"
            ))
        })?;
        set_private_directory(&directory)?;
        Ok(Arc::new(Self {
            store,
            runtime_dir,
            current: Mutex::new(HashMap::new()),
        }))
    }

    fn credential_directory(&self) -> PathBuf {
        self.runtime_dir.join(CREDENTIAL_DIR)
    }

    fn issue_file(&self, secret: &str) -> HostResult<PathBuf> {
        let credential_id = Uuid::new_v4().simple().to_string();
        let path = self
            .credential_directory()
            .join(format!("{credential_id}.token"));
        let mut options = OpenOptions::new();
        options.write(true).create_new(true);
        #[cfg(unix)]
        {
            use std::os::unix::fs::OpenOptionsExt;
            options.mode(0o600);
        }
        let mut file = options.open(&path).map_err(|error| {
            HostError::state(format!("could not create chat credential: {error}"))
        })?;
        if let Err(error) = file
            .write_all(secret.as_bytes())
            .and_then(|_| file.sync_all())
        {
            let _ = fs::remove_file(&path);
            return Err(HostError::state(format!(
                "could not write chat credential: {error}"
            )));
        }
        set_private_file(&path)?;
        Ok(path)
    }

    async fn issue(&self, chat_id: &str, generation: i64) -> Result<PathBuf, String> {
        self.revoke_chat(chat_id, "providerGenerationReplaced")
            .await
            .map_err(|error| error.to_string())?;
        let secret = new_chat_orchestration_credential_secret();
        crate::terminal_host::diagnostics::redaction::register_secret(&secret);
        let hash = hash_chat_orchestration_credential(&secret);
        let path = self
            .issue_file(&secret)
            .map_err(|error| error.to_string())?;
        if let Err(error) = self
            .store
            .issue_chat_orchestration_credential(chat_id, generation, &hash)
            .await
        {
            let _ = fs::remove_file(&path);
            return Err(error.to_string());
        }
        let previous = self
            .current
            .lock()
            .ok()
            .map(|mut values| {
                let old = values
                    .extract_if(|key, _| key.0 == chat_id)
                    .map(|(_, value)| value.path)
                    .collect::<Vec<_>>();
                values.insert(
                    (chat_id.to_owned(), generation),
                    IssuedCredential {
                        chat_id: chat_id.to_owned(),
                        path: path.clone(),
                    },
                );
                old
            })
            .unwrap_or_default();
        for previous in previous {
            let _ = fs::remove_file(previous);
        }
        Ok(path)
    }

    pub(crate) async fn verify(&self, token: &str) -> HostResult<CredentialBinding> {
        let token = token.trim();
        if token.is_empty() {
            return Err(invalid_credential());
        }
        let hash = hash_chat_orchestration_credential(token);
        let credential = self
            .store
            .find_chat_orchestration_credential(&hash)
            .await
            .map_err(|error| HostError::state(error.to_string()))?
            .ok_or_else(invalid_credential)?;
        Ok(CredentialBinding {
            chat_id: credential.chat_id,
            generation: credential.generation,
            credential_hash: hash,
        })
    }

    pub(crate) async fn revoke_chat(&self, chat_id: &str, reason: &str) -> HostResult<()> {
        self.store
            .revoke_chat_orchestration_credentials(chat_id, reason)
            .await
            .map_err(|error| HostError::state(error.to_string()))?;
        let paths: Vec<PathBuf> = self
            .current
            .lock()
            .ok()
            .map(|mut values| {
                values
                    .extract_if(|key, value| key.0 == chat_id && value.chat_id == chat_id)
                    .map(|(_, value)| value.path)
                    .collect()
            })
            .unwrap_or_default();
        for path in paths {
            let _ = fs::remove_file(path);
        }
        Ok(())
    }
}

#[async_trait]
impl ProviderLaunchHook for ChatCredentialLaunchHook {
    async fn prepare(&self, launch: &mut ProviderLaunch) -> Result<(), String> {
        let path = self.issue(&launch.chat_id, launch.generation).await?;
        let executable = std::env::current_exe().map_err(|error| error.to_string())?;
        let runtime_dir = self.runtime_dir.to_string_lossy().into_owned();
        let credential_path = path.to_string_lossy().into_owned();
        launch.mcp_servers.push(McpServerSpec {
            name: "alera".into(),
            transport: McpTransport::Stdio {
                command: executable,
                args: vec![
                    "mcp".into(),
                    "--runtime-dir".into(),
                    runtime_dir,
                    "serve".into(),
                    "--chat-credential-file".into(),
                    credential_path.clone(),
                ],
                env: Default::default(),
                cwd: None,
            },
        });
        launch.env.insert(CREDENTIAL_ENV.into(), credential_path);
        Ok(())
    }

    async fn revoke(&self, chat_id: &str, _generation: i64, reason: &str) -> Result<(), String> {
        self.revoke_chat(chat_id, reason)
            .await
            .map_err(|error| error.to_string())
    }
}

fn invalid_credential() -> HostError {
    HostError::conflict(
        "chat_credential_invalid",
        "The chat credential is invalid or expired.",
        Value::Object(Default::default()),
    )
}

fn set_private_directory(path: &Path) -> HostResult<()> {
    #[cfg(unix)]
    {
        use std::os::unix::fs::PermissionsExt;
        fs::set_permissions(path, fs::Permissions::from_mode(0o700)).map_err(|error| {
            HostError::state(format!(
                "could not protect chat credential directory: {error}"
            ))
        })?;
    }
    Ok(())
}

fn set_private_file(path: &Path) -> HostResult<()> {
    #[cfg(unix)]
    {
        use std::os::unix::fs::PermissionsExt;
        fs::set_permissions(path, fs::Permissions::from_mode(0o600)).map_err(|error| {
            HostError::state(format!("could not protect chat credential: {error}"))
        })?;
    }
    Ok(())
}
