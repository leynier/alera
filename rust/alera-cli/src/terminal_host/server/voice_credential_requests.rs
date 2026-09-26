//! Voice credential RPCs backed by the keyring store.

use serde_json::{json, Value};

use super::voice_credentials::VoiceCredentialStore;
use super::ServerActor;
use crate::terminal_host::host_error::{HostError, HostResult};

impl ServerActor {
    pub(super) async fn voice_credential_status_request(&self) -> HostResult<Value> {
        let credentials = self.voice_credential_store().load().await?;
        Ok(json!({
            "geminiConfigured": credentials
                .gemini_token
                .as_deref()
                .is_some_and(|value| !value.trim().is_empty()),
            "openaiConfigured": credentials
                .openai_token
                .as_deref()
                .is_some_and(|value| !value.trim().is_empty()),
        }))
    }

    pub(super) async fn voice_credential_save_request(&self, payload: &Value) -> HostResult<Value> {
        let mut credentials = self.voice_credential_store().load().await?;
        if let Some(token) = optional_credential(payload, "geminiToken")? {
            credentials.gemini_token = token;
        }
        if let Some(token) = optional_credential(payload, "openaiToken")? {
            credentials.openai_token = token;
        }
        self.voice_credential_store().save(credentials).await?;
        self.voice_credential_status_request().await
    }

    pub(super) async fn voice_credential_clear_request(
        &self,
        payload: &Value,
    ) -> HostResult<Value> {
        let provider = payload.get("provider").and_then(Value::as_str);
        match provider {
            Some("gemini") => {
                let mut credentials = self.voice_credential_store().load().await?;
                credentials.gemini_token = None;
                self.voice_credential_store().save(credentials).await?;
            }
            Some("openai") => {
                let mut credentials = self.voice_credential_store().load().await?;
                credentials.openai_token = None;
                self.voice_credential_store().save(credentials).await?;
            }
            Some(other) => {
                return Err(HostError::format(format!(
                    "unknown voice credential provider: {other}"
                )));
            }
            None => self.voice_credential_store().delete().await?,
        }
        self.voice_credential_status_request().await
    }

    pub(super) fn voice_credential_store(&self) -> VoiceCredentialStore {
        VoiceCredentialStore::new(&self.runtime_dir, self.account_push.service.runtime_id())
    }
}

pub(super) fn optional_credential(
    payload: &Value,
    key: &str,
) -> HostResult<Option<Option<String>>> {
    match payload.get(key) {
        None => Ok(None),
        Some(Value::Null) => Ok(Some(None)),
        Some(Value::String(value)) => {
            let trimmed = value.trim();
            if trimmed.is_empty() {
                Ok(Some(None))
            } else {
                Ok(Some(Some(trimmed.to_string())))
            }
        }
        Some(_) => Err(HostError::format(format!("{key} must be a string."))),
    }
}
