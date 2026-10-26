//! Durable provider override rows and write-only credential references.

use anyhow::Result;
use serde_json::{json, Value};
use sqlx::{Row, SqliteConnection};

use super::agent_chat_provider_validation::{declared_secrets, require_provider_envelope};
use super::agent_chat_settings_store::*;
use super::agent_chat_validation::require_id;
use super::*;

const DOMAIN: &str = "providers";

fn record_from_row(row: sqlx::sqlite::SqliteRow) -> Result<AgentChatProviderInstanceRecord> {
    Ok(AgentChatProviderInstanceRecord {
        provider_instance_id: row.try_get("providerInstanceId")?,
        envelope: serde_json::from_str(row.try_get::<&str, _>("envelopeJson")?)?,
        secret_refs: serde_json::from_str(row.try_get::<&str, _>("secretRefsJson")?)?,
        revision: row.try_get("revision")?,
    })
}

async fn instance_in(
    connection: &mut SqliteConnection,
    id: &str,
) -> Result<Option<AgentChatProviderInstanceRecord>> {
    sqlx::query("SELECT * FROM agentChatProviderInstances WHERE providerInstanceId = ?")
        .bind(id)
        .fetch_optional(&mut *connection)
        .await?
        .map(record_from_row)
        .transpose()
}

async fn instances_in(connection: &mut SqliteConnection) -> Result<AgentChatProviderInstances> {
    let rows =
        sqlx::query("SELECT * FROM agentChatProviderInstances ORDER BY providerInstanceId LIMIT ?")
            .bind(AGENT_CHAT_SETTINGS_MAX_ENTRIES as i64 + 1)
            .fetch_all(&mut *connection)
            .await?;
    if rows.len() > AGENT_CHAT_SETTINGS_MAX_ENTRIES {
        anyhow::bail!(AgentChatStoreError::Invalid(
            "too many provider overrides".into()
        ));
    }
    Ok(AgentChatProviderInstances {
        instances: rows
            .into_iter()
            .map(record_from_row)
            .collect::<Result<_>>()?,
        revision: revision_in(connection, DOMAIN).await?,
    })
}

/// Only safe envelopes can be serialized to a response or durable receipt.
pub fn agent_chat_provider_instances_response(instances: &AgentChatProviderInstances) -> Value {
    let envelopes: Vec<Value> = instances
        .instances
        .iter()
        .map(|record| {
            let mut envelope = record.envelope.clone();
            envelope["revision"] = json!(record.revision);
            if let Some(environment) = envelope
                .get_mut("environment")
                .and_then(Value::as_array_mut)
            {
                for entry in environment {
                    if entry.get("sensitive").and_then(Value::as_bool) == Some(true) {
                        let saved = entry
                            .get("name")
                            .and_then(Value::as_str)
                            .is_some_and(|name| record.secret_refs.contains_key(name));
                        entry.as_object_mut().unwrap().remove("value");
                        entry["secretSaved"] = json!(saved);
                    }
                }
            }
            let secret_options: Vec<Value> = declared_secrets(&envelope)
                .into_iter()
                .filter_map(|name| {
                    name.strip_prefix("option:").map(|key| {
                        json!({
                            "name": key, "secretSaved": record.secret_refs.contains_key(&name),
                        })
                    })
                })
                .collect();
            if !secret_options.is_empty() {
                envelope["secretOptions"] = json!(secret_options);
            }
            envelope
        })
        .collect();
    json!({"instances": envelopes, "revision": instances.revision})
}

async fn put_in(
    connection: &mut SqliteConnection,
    record: &AgentChatProviderInstanceRecord,
) -> Result<()> {
    let refs = serde_json::to_string(&record.secret_refs)?;
    if refs.len() > AGENT_CHAT_SETTINGS_MAX_BYTES {
        anyhow::bail!(AgentChatStoreError::Invalid(
            "secret references exceed the byte budget".into()
        ));
    }
    sqlx::query(
        "INSERT INTO agentChatProviderInstances (providerInstanceId, envelopeJson, secretRefsJson, revision) \
         VALUES (?, ?, ?, ?) ON CONFLICT(providerInstanceId) DO UPDATE SET \
         envelopeJson = excluded.envelopeJson, secretRefsJson = excluded.secretRefsJson, revision = excluded.revision",
    ).bind(&record.provider_instance_id).bind(bounded_json(&record.envelope)?)
        .bind(refs).bind(record.revision).execute(&mut *connection).await?;
    Ok(())
}

impl RuntimeStore {
    /// Legacy migration commits every sanitized envelope/reference together.
    /// Revision zero is required even if human edits removed all override rows.
    pub async fn import_agent_chat_provider_instances_if_empty(
        &self,
        records: &[AgentChatProviderInstanceRecord],
    ) -> Result<bool> {
        if records.len() > AGENT_CHAT_SETTINGS_MAX_ENTRIES {
            anyhow::bail!(AgentChatStoreError::Invalid(
                "too many provider overrides".into()
            ));
        }
        let mut ids = std::collections::BTreeSet::new();
        for record in records {
            require_provider_envelope(&record.provider_instance_id, &record.envelope)?;
            if !ids.insert(&record.provider_instance_id) {
                anyhow::bail!(AgentChatStoreError::Invalid(
                    "duplicate imported provider instance".into()
                ));
            }
            let names = declared_secrets(&record.envelope);
            for (name, reference) in &record.secret_refs {
                if !names.contains(name) {
                    anyhow::bail!(AgentChatStoreError::Invalid(
                        "imported secret must be declared sensitive".into()
                    ));
                }
                require_id("secret reference", reference)?;
            }
        }
        let mut tx = self.pool().begin_with("BEGIN IMMEDIATE").await?;
        let rows: bool =
            sqlx::query_scalar("SELECT EXISTS(SELECT 1 FROM agentChatProviderInstances)")
                .fetch_one(&mut *tx)
                .await?;
        if rows || revision_in(&mut tx, DOMAIN).await? != 0 {
            tx.commit().await?;
            return Ok(false);
        }
        let revision = advance_revision_in(&mut tx, DOMAIN, 0).await?;
        for record in records {
            let mut record = record.clone();
            record.revision = revision;
            put_in(&mut tx, &record).await?;
        }
        bounded_json(&agent_chat_provider_instances_response(
            &instances_in(&mut tx).await?,
        ))?;
        tx.commit().await?;
        Ok(true)
    }

    /// Internal records include opaque refs; use the response projection for wire.
    pub async fn agent_chat_provider_instances(&self) -> Result<AgentChatProviderInstances> {
        let mut tx = self.pool().begin().await?;
        let result = instances_in(&mut tx).await?;
        bounded_json(&agent_chat_provider_instances_response(&result))?;
        tx.commit().await?;
        Ok(result)
    }

    pub async fn mutate_agent_chat_provider_instances(
        &self,
        expected_revision: i64,
        operation: &AgentChatProviderInstanceMutation,
        receipt: &AgentChatReceipt,
    ) -> Result<AgentChatSettingsOutcome> {
        let id = match operation {
            AgentChatProviderInstanceMutation::Upsert {
                provider_instance_id,
                envelope,
            }
            | AgentChatProviderInstanceMutation::UpsertWithSecretRef {
                provider_instance_id,
                envelope,
                ..
            } => {
                require_provider_envelope(provider_instance_id, envelope)?;
                provider_instance_id
            }
            AgentChatProviderInstanceMutation::Remove {
                provider_instance_id,
            }
            | AgentChatProviderInstanceMutation::SetSecretRef {
                provider_instance_id,
                ..
            } => provider_instance_id,
        };
        require_id("providerInstanceId", id)?;
        let mut tx = self.pool().begin_with("BEGIN IMMEDIATE").await?;
        if let Some(outcome) = admit_in(&mut tx, DOMAIN, expected_revision, receipt).await? {
            tx.commit().await?;
            return Ok(outcome);
        }
        let revision = advance_revision_in(&mut tx, DOMAIN, expected_revision).await?;
        match operation {
            AgentChatProviderInstanceMutation::Upsert { envelope, .. }
            | AgentChatProviderInstanceMutation::UpsertWithSecretRef { envelope, .. } => {
                let previous = instance_in(&mut tx, id).await?;
                if previous
                    .as_ref()
                    .is_some_and(|record| record.envelope["provider"] != envelope["provider"])
                {
                    anyhow::bail!(AgentChatStoreError::Invalid(
                        "provider kind of an existing instance is immutable".into()
                    ));
                }
                let mut secret_refs = previous
                    .map(|record| record.secret_refs)
                    .unwrap_or_default();
                let names = declared_secrets(envelope);
                secret_refs.retain(|name, _| names.contains(name));
                if let AgentChatProviderInstanceMutation::UpsertWithSecretRef {
                    name,
                    secret_ref,
                    ..
                } = operation
                {
                    require_id("secret name", name)?;
                    if !names.contains(name) {
                        anyhow::bail!(AgentChatStoreError::Invalid(
                            "secret must be declared sensitive".into()
                        ));
                    }
                    if let Some(reference) = secret_ref {
                        require_id("secret reference", reference)?;
                        secret_refs.insert(name.clone(), reference.clone());
                    } else {
                        secret_refs.remove(name);
                    }
                }
                put_in(
                    &mut tx,
                    &AgentChatProviderInstanceRecord {
                        provider_instance_id: id.clone(),
                        envelope: envelope.clone(),
                        secret_refs,
                        revision,
                    },
                )
                .await?;
            }
            AgentChatProviderInstanceMutation::Remove { .. } => {
                sqlx::query("DELETE FROM agentChatProviderInstances WHERE providerInstanceId = ?")
                    .bind(id)
                    .execute(&mut *tx)
                    .await?;
            }
            AgentChatProviderInstanceMutation::SetSecretRef {
                name, secret_ref, ..
            } => {
                require_id("secret name", name)?;
                let mut record = instance_in(&mut tx, id).await?.ok_or_else(|| {
                    AgentChatStoreError::Invalid("provider override not found".into())
                })?;
                if !declared_secrets(&record.envelope).contains(name) {
                    anyhow::bail!(AgentChatStoreError::Invalid(
                        "secret must be declared sensitive".into()
                    ));
                }
                if let Some(reference) = secret_ref {
                    require_id("secret reference", reference)?;
                    record.secret_refs.insert(name.clone(), reference.clone());
                } else {
                    record.secret_refs.remove(name);
                }
                record.revision = revision;
                put_in(&mut tx, &record).await?;
            }
        }
        let response = agent_chat_provider_instances_response(&instances_in(&mut tx).await?);
        let outcome = finish_in(&mut tx, response, receipt).await?;
        tx.commit().await?;
        Ok(outcome)
    }
}
