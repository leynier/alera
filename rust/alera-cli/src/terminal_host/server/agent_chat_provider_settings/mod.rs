//! Human administration of host-owned provider overrides and chat preferences.

pub(crate) mod credentials;
pub(crate) mod discovery;
mod envelope;
mod migration;
mod preferences;
pub(crate) mod probe;
pub(crate) mod setup;
pub(crate) mod status;

use super::agent_chat_runtime::{CallerCtx, InstanceDirectory};
use crate::terminal_host::host_error::{HostError, HostResult};
use alera_core::runtime::{
    agent_chat_command_digest, agent_chat_provider_instances_response,
    AgentChatProviderInstanceMutation, AgentChatProviderInstances, AgentChatReceipt,
    AgentChatReceiptCheck, AgentChatSettingsOutcome, RuntimeStore,
};
use credentials::{ProviderCredentialStore, ProviderSecrets};
use preferences::{revision, text};
use serde_json::{json, Value};
use std::path::{Path, PathBuf};
use std::sync::Arc;

pub(crate) type ProviderSettingsEventSink = Arc<dyn Fn(&str, Value) + Send + Sync>;

#[derive(Clone)]
pub(crate) struct ProviderSettingsService {
    store: RuntimeStore,
    instances: Arc<InstanceDirectory>,
    runtime_dir: PathBuf,
    runtime_id: String,
    secrets: Arc<dyn ProviderSecrets>,
    events: ProviderSettingsEventSink,
    mutation_lock: Arc<tokio::sync::Mutex<()>>,
    migration_error: Arc<std::sync::RwLock<Option<String>>>,
}

impl ProviderSettingsService {
    pub(crate) fn new(
        store: RuntimeStore,
        instances: Arc<InstanceDirectory>,
        runtime_dir: &Path,
        runtime_id: &str,
        events: ProviderSettingsEventSink,
    ) -> Self {
        Self {
            store,
            instances,
            runtime_dir: runtime_dir.into(),
            runtime_id: runtime_id.into(),
            secrets: Arc::new(ProviderCredentialStore::new(runtime_dir, runtime_id)),
            events,
            mutation_lock: Default::default(),
            migration_error: Default::default(),
        }
    }

    pub(crate) async fn initialize(&self) -> HostResult<()> {
        let _guard = self.mutation_lock.lock().await;
        let failed = if let Err(error) = migration::import_legacy(
            &self.store,
            &*self.secrets,
            &self.runtime_dir,
            &self.runtime_id,
        )
        .await
        {
            if let Ok(mut message) = self.migration_error.write() {
                *message = Some(error.wire_message());
            }
            true
        } else if let Ok(mut message) = self.migration_error.write() {
            *message = None;
            false
        } else {
            false
        };
        if failed
            && self
                .store
                .agent_chat_provider_instances()
                .await
                .map_err(store_error)?
                .revision
                == 0
        {
            // Failed import must preserve the last-known launch definitions.
            return Ok(());
        }
        self.synchronize().await
    }

    pub(crate) fn handles(verb: &str) -> bool {
        matches!(
            verb,
            "agentChat.preferences.get"
                | "agentChat.preferences.update"
                | "agentChat.providerInstances.get"
                | "agentChat.providerInstances.upsert"
                | "agentChat.providerInstances.remove"
                | "agentChat.providerInstances.removalImpact"
                | "agentChat.secrets.set"
                | "agentChat.secrets.clear"
        )
    }

    pub(crate) async fn dispatch(
        &self,
        verb: &str,
        payload: &Value,
        caller: &CallerCtx,
    ) -> HostResult<Value> {
        // Connection-derived caller identity survives authenticated hub forwarding.
        if caller.scope.starts_with("chat:")
            || caller.scope.starts_with("satellite:")
            || caller.scope.starts_with("agent:")
        {
            return Err(HostError::conflict(
                "notAllowed",
                "Provider settings require an authenticated human client.",
                json!({}),
            ));
        }
        match verb {
            "agentChat.preferences.get" => {
                return self
                    .store
                    .agent_chat_preferences()
                    .await
                    .map_err(store_error)
            }
            "agentChat.providerInstances.get" => return self.snapshot().await,
            "agentChat.providerInstances.removalImpact" => {
                return self
                    .removal_impact(&text(payload, "providerInstanceId")?)
                    .await
            }
            _ => {}
        }
        if !Self::handles(verb) {
            return Err(HostError::format("Unknown provider settings request."));
        }
        let _guard = self.mutation_lock.lock().await;
        let receipt = receipt(verb, payload, caller)?;
        match self
            .store
            .check_agent_chat_receipt(&receipt.caller_scope, &receipt.request_id, &receipt.digest)
            .await
            .map_err(store_error)?
        {
            AgentChatReceiptCheck::Replay(value) => {
                return Ok(if verb == "agentChat.preferences.update" {
                    value
                } else {
                    provider_reply(value)
                })
            }
            AgentChatReceiptCheck::Conflict => return Err(receipt_conflict()),
            AgentChatReceiptCheck::New => {}
        }
        let expected = revision(payload)?;
        if verb == "agentChat.preferences.update" {
            let outcome = self
                .store
                .update_agent_chat_preferences(
                    expected,
                    &preferences::operations(payload)?,
                    &receipt,
                )
                .await
                .map_err(store_error)?;
            return self.finish(outcome, "agentChatPreferencesChanged").await;
        }
        let records = self
            .store
            .agent_chat_provider_instances()
            .await
            .map_err(store_error)?;
        if records.revision == 0
            && self
                .migration_error
                .read()
                .map(|error| error.is_some())
                .unwrap_or(false)
        {
            return Err(HostError::conflict("providerMigrationRequired","Legacy provider settings must be imported before editing agent instances. The original file is retained.",json!({})));
        }
        let id = if verb == "agentChat.providerInstances.upsert" {
            text(&payload["instance"], "providerInstanceId")?
        } else {
            text(payload, "providerInstanceId")?
        };
        let current = records
            .instances
            .iter()
            .find(|record| record.provider_instance_id == id);
        let default = envelope::default_envelope(&id);
        let base = current.map(|record| &record.envelope).or(default.as_ref());
        let operation = match verb {
            "agentChat.providerInstances.upsert" => AgentChatProviderInstanceMutation::Upsert {
                provider_instance_id: id.clone(),
                envelope: envelope::normalize(&payload["instance"], base, caller.mobile)?,
            },
            "agentChat.providerInstances.remove" => {
                if caller.mobile {
                    return Err(envelope::not_allowed());
                }
                let impact = self.removal_impact(&id).await?;
                if default.is_none()
                    && impact["count"].as_u64().unwrap_or(0) > 0
                    && payload["allowInUse"] != true
                {
                    return Err(HostError::conflict(
                        "providerInstanceInUse",
                        "Open chats use this agent instance.",
                        impact,
                    ));
                }
                AgentChatProviderInstanceMutation::Remove {
                    provider_instance_id: id.clone(),
                }
            }
            "agentChat.secrets.set" | "agentChat.secrets.clear" => {
                return self
                    .mutate_secret(verb, payload, &receipt, &records, &id, base)
                    .await;
            }
            _ => unreachable!("settings verb validated"),
        };
        let outcome = self
            .store
            .mutate_agent_chat_provider_instances(expected, &operation, &receipt)
            .await
            .map_err(store_error)?;
        let result = self.finish(outcome, "agentChatProvidersChanged").await?;
        if let Some(current) = current {
            for reference in current.secret_refs.values() {
                self.clear_unreferenced(reference).await;
            }
        }
        Ok(result)
    }

    async fn mutate_secret(
        &self,
        verb: &str,
        payload: &Value,
        receipt: &AgentChatReceipt,
        records: &AgentChatProviderInstances,
        id: &str,
        base: Option<&Value>,
    ) -> HostResult<Value> {
        let expected = revision(payload)?;
        let name = text(payload, "name")?;
        let base = base.ok_or_else(|| {
            HostError::conflict(
                "providerMissing",
                "Agent instance no longer exists.",
                json!({}),
            )
        })?;
        if !envelope::declared(base, &name) {
            return Err(HostError::format("Secret must be declared sensitive."));
        }
        if expected != records.revision {
            return Err(revision_conflict(records.revision));
        }
        let reference = if verb == "agentChat.secrets.set" {
            let value = payload["value"]
                .as_str()
                .filter(|value| !value.is_empty() && value.len() <= 64 * 1024)
                .ok_or_else(|| HostError::format("A nonempty secret value is required."))?;
            let reference = format!("provider:{}", uuid::Uuid::new_v4());
            self.secrets.save(&reference, value).await?;
            Some(reference)
        } else {
            None
        };
        let operation = AgentChatProviderInstanceMutation::UpsertWithSecretRef {
            provider_instance_id: id.into(),
            envelope: base.clone(),
            name: name.clone(),
            secret_ref: reference.clone(),
        };
        let outcome = self
            .store
            .mutate_agent_chat_provider_instances(expected, &operation, receipt)
            .await
            .map_err(store_error);
        // A failed transaction cannot make its staged credential reachable.
        if !matches!(&outcome, Ok(AgentChatSettingsOutcome::Applied(_))) {
            if let Some(reference) = &reference {
                self.clear_unreferenced(reference).await;
            }
        }
        let result = self.finish(outcome?, "agentChatProvidersChanged").await?;
        // Never clear a ref until its replacement is durably committed.
        if let Some(old) = records
            .instances
            .iter()
            .find(|record| record.provider_instance_id == id)
            .and_then(|record| record.secret_refs.get(&name))
        {
            if reference.as_ref() != Some(old) {
                self.clear_unreferenced(old).await;
            }
        }
        Ok(result)
    }

    async fn finish(&self, outcome: AgentChatSettingsOutcome, event: &str) -> HostResult<Value> {
        match outcome {
            AgentChatSettingsOutcome::Applied(value) => {
                if event == "agentChatProvidersChanged" {
                    self.synchronize().await?;
                }
                (self.events)(event, json!({"revision":value["revision"]}));
                Ok(if event == "agentChatProvidersChanged" {
                    provider_reply(value)
                } else {
                    value
                })
            }
            AgentChatSettingsOutcome::Replay(value) => {
                Ok(if event == "agentChatProvidersChanged" {
                    provider_reply(value)
                } else {
                    value
                })
            }
            AgentChatSettingsOutcome::RevisionConflict { revision } => {
                Err(revision_conflict(revision))
            }
            AgentChatSettingsOutcome::ReceiptConflict => Err(receipt_conflict()),
        }
    }

    async fn clear_unreferenced(&self, reference: &str) {
        if let Ok(stored) = self.store.agent_chat_provider_instances().await {
            if !stored
                .instances
                .iter()
                .any(|record| record.secret_refs.values().any(|value| value == reference))
            {
                let _ = self.secrets.clear(reference).await;
            }
        }
    }

    async fn synchronize(&self) -> HostResult<()> {
        let records = self
            .store
            .agent_chat_provider_instances()
            .await
            .map_err(store_error)?;
        let configs = records
            .instances
            .into_iter()
            .map(|record| {
                let mut config = envelope::config(&record.envelope, record.secret_refs);
                config.credential_scope = Some((self.runtime_dir.clone(), self.runtime_id.clone()));
                config
            })
            .collect();
        self.instances.replace(configs).await;
        Ok(())
    }

    async fn snapshot(&self) -> HostResult<Value> {
        let mut records = self
            .store
            .agent_chat_provider_instances()
            .await
            .map_err(store_error)?;
        records.instances = envelope::records_with_defaults(records.instances);
        let mut response = agent_chat_provider_instances_response(&records);
        if let Ok(message) = self.migration_error.read() {
            if let Some(message) = &*message {
                response["migrationError"] = json!(message);
            }
        }
        Ok(response)
    }

    async fn removal_impact(&self, id: &str) -> HostResult<Value> {
        let chats = self
            .store
            .list_all_agent_chats(false)
            .await
            .map_err(store_error)?;
        let chats: Vec<Value> = chats.into_iter().filter(|chat| chat.provider_instance_id == id).map(|chat| json!({"chatId":chat.chat_id,"workspaceId":chat.workspace_id,"title":chat.snapshot["thread"]["title"]})).collect();
        Ok(json!({"providerInstanceId":id,"count":chats.len(),"openChats":chats}))
    }
}

fn receipt(verb: &str, payload: &Value, caller: &CallerCtx) -> HostResult<AgentChatReceipt> {
    Ok(AgentChatReceipt {
        caller_scope: format!("provider-settings:{}", caller.scope),
        request_id: text(payload, "requestId")?,
        digest: agent_chat_command_digest(&json!({"verb":verb,"payload":payload})),
        receipt: Value::Null,
    })
}

fn provider_reply(mut response: Value) -> Value {
    if let Some(instances) = response["instances"].as_array_mut() {
        let defaults = AgentChatProviderInstances {
            instances: envelope::records_with_defaults(Vec::new()),
            revision: 0,
        };
        for default in agent_chat_provider_instances_response(&defaults)["instances"]
            .as_array()
            .into_iter()
            .flatten()
        {
            if !instances
                .iter()
                .any(|instance| instance["providerInstanceId"] == default["providerInstanceId"])
            {
                instances.push(default.clone());
            }
        }
    }
    response
}

fn store_error(_: anyhow::Error) -> HostError {
    HostError::state(
        "Provider settings could not be saved or read. Check the request and try again.",
    )
}
fn revision_conflict(revision: i64) -> HostError {
    HostError::conflict(
        "revisionConflict",
        "Provider settings changed. Refresh and try again.",
        json!({"revision":revision}),
    )
}
fn receipt_conflict() -> HostError {
    HostError::conflict(
        "receiptConflict",
        "This request ID was already used for another change.",
        json!({}),
    )
}

#[cfg(test)]
mod tests;
