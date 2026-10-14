//! Entry-level preference edits with an optimistic host revision.

use anyhow::Result;
use serde_json::{json, Map, Value};
use sqlx::{Row, SqliteConnection};

use super::agent_chat_secrets::reject_secret_fields;
use super::agent_chat_settings_store::*;
use super::agent_chat_validation::require_id;
use super::*;

const DOMAIN: &str = "preferences";

fn require_selection(value: &Value) -> Result<()> {
    let object = value
        .as_object()
        .ok_or_else(|| AgentChatStoreError::Invalid("a selection must be an object".into()))?;
    if object.keys().any(|key| {
        !matches!(
            key.as_str(),
            "providerInstanceId" | "model" | "runtimeMode" | "interactionMode"
        )
    }) {
        anyhow::bail!(AgentChatStoreError::Invalid(
            "unknown selection field".into()
        ));
    }
    require_id(
        "providerInstanceId",
        object
            .get("providerInstanceId")
            .and_then(Value::as_str)
            .unwrap_or(""),
    )?;
    for key in ["model", "runtimeMode", "interactionMode"] {
        if let Some(value) = object.get(key).filter(|value| !value.is_null()) {
            require_id(key, value.as_str().unwrap_or(""))?;
        }
    }
    Ok(())
}

fn require_models(value: &Value) -> Result<()> {
    let Some(object) = value.as_object() else {
        anyhow::bail!(AgentChatStoreError::Invalid(
            "models must be an object".into()
        ));
    };
    if object
        .keys()
        .any(|key| !matches!(key.as_str(), "hidden" | "order"))
    {
        anyhow::bail!(AgentChatStoreError::Invalid("unknown models field".into()));
    }
    for key in ["hidden", "order"] {
        if let Some(list) = object.get(key) {
            let Some(list) = list.as_array() else {
                anyhow::bail!(AgentChatStoreError::Invalid(
                    "model ids must be a list".into()
                ));
            };
            if list.len() > AGENT_CHAT_SETTINGS_MAX_ENTRIES {
                anyhow::bail!(AgentChatStoreError::Invalid("too many model ids".into()));
            }
            let mut seen = std::collections::BTreeSet::new();
            for model in list {
                let id = model.as_str().unwrap_or("");
                require_id("model", id)?;
                if !seen.insert(id) {
                    anyhow::bail!(AgentChatStoreError::Invalid("duplicate model id".into()));
                }
            }
        }
    }
    Ok(())
}

fn require_operation(operation: &AgentChatPreferenceOperation) -> Result<()> {
    let map = match operation.section.as_str() {
        "rememberedSelection" | "defaultSelection" => false,
        "projectDefaults" | "models" | "favorites" => true,
        _ => anyhow::bail!(AgentChatStoreError::Invalid(
            "unknown preference section".into()
        )),
    };
    if map {
        if operation.section != "favorites" || operation.key.is_some() {
            require_id("preference key", operation.key.as_deref().unwrap_or(""))?;
        }
    } else if operation.key.is_some() {
        anyhow::bail!(AgentChatStoreError::Invalid(
            "singleton preference cannot have a key".into()
        ));
    }
    if let Some(value) = operation.value.as_ref().filter(|value| !value.is_null()) {
        reject_secret_fields("preferences", value)?;
        bounded_json(value)?;
        if operation.section == "favorites" && operation.key.is_none() {
            let favorites = value
                .as_array()
                .ok_or_else(|| AgentChatStoreError::Invalid("favorites must be a list".into()))?;
            if favorites.len() > AGENT_CHAT_SETTINGS_MAX_ENTRIES {
                anyhow::bail!(AgentChatStoreError::Invalid("too many favorites".into()));
            }
            for selection in favorites {
                require_selection(selection)?;
            }
        } else if operation.section == "models" {
            require_models(value)?;
        } else {
            require_selection(value)?;
        }
    }
    Ok(())
}

async fn preferences_in(connection: &mut SqliteConnection) -> Result<Value> {
    let rows = sqlx::query(
        "SELECT section, entryKey, valueJson FROM agentChatPreferences \
         ORDER BY section, entryKey LIMIT ?",
    )
    .bind(AGENT_CHAT_SETTINGS_MAX_ENTRIES as i64 + 1)
    .fetch_all(&mut *connection)
    .await?;
    if rows.len() > AGENT_CHAT_SETTINGS_MAX_ENTRIES {
        anyhow::bail!(AgentChatStoreError::Invalid(
            "too many preference entries".into()
        ));
    }
    let mut result = json!({
        "projectDefaults": {}, "models": {}, "favorites": [],
        "revision": revision_in(connection, DOMAIN).await?,
    });
    for row in rows {
        let section: String = row.try_get("section")?;
        let key: String = row.try_get("entryKey")?;
        let json: String = row.try_get("valueJson")?;
        let value: Value = serde_json::from_str(&json)?;
        if section == "favorites" {
            result["favorites"].as_array_mut().unwrap().push(value);
        } else if matches!(section.as_str(), "rememberedSelection" | "defaultSelection") {
            result[section] = value;
        } else {
            let entries: &mut Map<String, Value> =
                result[section].as_object_mut().ok_or_else(|| {
                    AgentChatStoreError::Invalid("unknown stored preference section".into())
                })?;
            entries.insert(key, value);
        }
    }
    bounded_json(&result)?;
    Ok(result)
}

impl RuntimeStore {
    pub async fn agent_chat_preferences(&self) -> Result<Value> {
        let mut tx = self.pool().begin().await?;
        let result = preferences_in(&mut tx).await?;
        tx.commit().await?;
        Ok(result)
    }

    /// All entry edits and their receipt either commit together or roll back.
    pub async fn update_agent_chat_preferences(
        &self,
        expected_revision: i64,
        operations: &[AgentChatPreferenceOperation],
        receipt: &AgentChatReceipt,
    ) -> Result<AgentChatSettingsOutcome> {
        if operations.is_empty() || operations.len() > AGENT_CHAT_SETTINGS_MAX_OPERATIONS {
            anyhow::bail!(AgentChatStoreError::Invalid(
                "invalid preference operation count".into()
            ));
        }
        for operation in operations {
            require_operation(operation)?;
        }
        let mut tx = self.pool().begin_with("BEGIN IMMEDIATE").await?;
        if let Some(outcome) = admit_in(&mut tx, DOMAIN, expected_revision, receipt).await? {
            tx.commit().await?;
            return Ok(outcome);
        }
        let revision = advance_revision_in(&mut tx, DOMAIN, expected_revision).await?;
        for operation in operations {
            let key = operation.key.as_deref().unwrap_or("");
            if operation.section == "favorites" && operation.key.is_none() {
                sqlx::query("DELETE FROM agentChatPreferences WHERE section = 'favorites'")
                    .execute(&mut *tx)
                    .await?;
                for value in operation
                    .value
                    .as_ref()
                    .and_then(Value::as_array)
                    .into_iter()
                    .flatten()
                {
                    let key = super::agent_chat_validation::agent_chat_command_digest(value);
                    sqlx::query("INSERT INTO agentChatPreferences (section, entryKey, valueJson, revision) \
                        VALUES ('favorites', ?, ?, ?) ON CONFLICT(section, entryKey) DO NOTHING")
                        .bind(key).bind(bounded_json(value)?).bind(revision).execute(&mut *tx).await?;
                }
                continue;
            }
            if let Some(value) = operation.value.as_ref().filter(|value| !value.is_null()) {
                sqlx::query(
                    "INSERT INTO agentChatPreferences (section, entryKey, valueJson, revision) \
                     VALUES (?, ?, ?, ?) ON CONFLICT(section, entryKey) \
                     DO UPDATE SET valueJson = excluded.valueJson, revision = excluded.revision",
                )
                .bind(&operation.section)
                .bind(key)
                .bind(bounded_json(value)?)
                .bind(revision)
                .execute(&mut *tx)
                .await?;
            } else {
                sqlx::query("DELETE FROM agentChatPreferences WHERE section = ? AND entryKey = ?")
                    .bind(&operation.section)
                    .bind(key)
                    .execute(&mut *tx)
                    .await?;
            }
        }
        let response = preferences_in(&mut tx).await?;
        let outcome = finish_in(&mut tx, response, receipt).await?;
        tx.commit().await?;
        Ok(outcome)
    }

    /// Host-only first-send memory. Serializes with human entry edits and
    /// touches only rememberedSelection, preserving explicit/project defaults.
    pub async fn remember_agent_chat_selection(
        &self,
        selection: &Value,
        receipt: &AgentChatReceipt,
    ) -> Result<AgentChatSettingsOutcome> {
        require_selection(selection)?;
        let mut tx = self.pool().begin_with("BEGIN IMMEDIATE").await?;
        let current = revision_in(&mut tx, DOMAIN).await?;
        if let Some(outcome) = admit_in(&mut tx, DOMAIN, current, receipt).await? {
            tx.commit().await?;
            return Ok(outcome);
        }
        let revision = advance_revision_in(&mut tx, DOMAIN, current).await?;
        sqlx::query(
            "INSERT INTO agentChatPreferences (section, entryKey, valueJson, revision) \
            VALUES ('rememberedSelection', '', ?, ?) ON CONFLICT(section, entryKey) \
            DO UPDATE SET valueJson = excluded.valueJson, revision = excluded.revision",
        )
        .bind(bounded_json(selection)?)
        .bind(revision)
        .execute(&mut *tx)
        .await?;
        let response = preferences_in(&mut tx).await?;
        let outcome = finish_in(&mut tx, response, receipt).await?;
        tx.commit().await?;
        Ok(outcome)
    }
}
