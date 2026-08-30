use super::configuration_validation::validate_document;
use super::{agent_profile_store_helpers::agent_profile_from_row, RuntimeStore};
use anyhow::{bail, Result};
use serde_json::{json, Value};
use sha2::{Digest, Sha256};
use sqlx::SqliteConnection;

const DOCUMENT_KEY: &str = "configuration.portable.v1";
const PROFILE_COLUMNS: &str = "id, name, agentType, command, sortOrder, launchMode, managedConfig, customPrompt, description, quotaGroup, revision, createdAt, updatedAt";
const SHARED_SETTINGS: [(&str, &str); 5] = [
    ("/desktop/browser", "browser.settings.v1"),
    (
        "/desktop/settings/general/confirmProjectRemoval",
        "settings.general.confirmProjectRemoval",
    ),
    (
        "/desktop/settings/general/confirmWorkspaceRemoval",
        "settings.general.confirmWorkspaceRemoval",
    ),
    (
        "/desktop/settings/agents/defaultAgentProfileId",
        "settings.agents.defaultAgentProfileId",
    ),
    (
        "/desktop/settings/aiTextGeneration",
        "settings.aiTextGeneration",
    ),
];

impl RuntimeStore {
    pub async fn configuration_snapshot(&self, account_id: &str) -> Result<Value> {
        let mut tx = self.pool().begin().await?;
        check_account(&mut tx, account_id).await?;
        let document = snapshot_in(&mut tx).await?;
        let state = read_json(&mut tx, &state_key(account_id))
            .await?
            .unwrap_or(json!({}));
        tx.commit().await?;
        Ok(
            json!({"fingerprint": digest(&json!({"document": document, "state": state}))?, "document": document,
            "base": state.get("base"), "pending": state.get("pending")}),
        )
    }

    pub async fn configuration_seed(&self, settings: Value) -> Result<Value> {
        let mut tx = self.pool().begin_with("BEGIN IMMEDIATE").await?;
        if read_json(&mut tx, "configuration.portable.seeded.v1").await? == Some(json!(true)) {
            let snapshot = snapshot_in(&mut tx).await?;
            tx.commit().await?;
            return Ok(snapshot);
        }
        let mut document = read_json(&mut tx, DOCUMENT_KEY).await?.unwrap_or(json!({
            "schemaVersion": 1, "shared": {}, "desktop": {"settings": {}}, "mobile": {}}));
        if let Some(sections) = settings.as_object() {
            for (section, fields) in sections {
                if !document["desktop"]["settings"][section].is_object() {
                    document["desktop"]["settings"][section] = json!({});
                }
                if let (Some(target), Some(fields)) = (
                    document["desktop"]["settings"][section].as_object_mut(),
                    fields.as_object(),
                ) {
                    for (key, value) in fields {
                        target.entry(key).or_insert_with(|| value.clone());
                    }
                }
            }
        }
        put_json(&mut tx, DOCUMENT_KEY, &document).await?;
        put_json(&mut tx, "configuration.portable.seeded.v1", &json!(true)).await?;
        let snapshot = snapshot_in(&mut tx).await?;
        tx.commit().await?;
        Ok(snapshot)
    }

    pub async fn configuration_settings(&self) -> Result<Value> {
        let mut tx = self.pool().begin().await?;
        let document = snapshot_in(&mut tx).await?;
        tx.commit().await?;
        Ok(document["desktop"]["settings"].clone())
    }

    /// Settings UI patches preserve opaque future fields and never change sync state.
    pub async fn configuration_update_settings(&self, settings: Value) -> Result<()> {
        self.configuration_update_settings_for_client(settings, None)
            .await
    }

    pub async fn configuration_update_settings_for_client(
        &self,
        settings: Value,
        supported_keyboard_ids: Option<&[String]>,
    ) -> Result<()> {
        let mut tx = self.pool().begin_with("BEGIN IMMEDIATE").await?;
        let mut document = snapshot_in(&mut tx).await?;
        if let Some(sections) = settings.as_object() {
            for (section, fields) in sections {
                if !document["desktop"]["settings"][section].is_object() {
                    document["desktop"]["settings"][section] = json!({});
                }
                if let Some(fields) = fields.as_object() {
                    for (key, value) in fields {
                        let mut next = super::configuration_native_settings::edit_field(
                            &document["desktop"]["settings"][section][key],
                            value,
                            section,
                            key,
                        )?;
                        if section == "keyboard" && key == "overrides" {
                            if let Some(supported) = supported_keyboard_ids {
                                let mut preserved = document["desktop"]["settings"][section][key]
                                    .as_object()
                                    .cloned()
                                    .unwrap_or_default();
                                preserved.retain(|id, _| !supported.contains(id));
                                if let Some(incoming) = value.as_object() {
                                    preserved.extend(incoming.clone());
                                }
                                next = Value::Object(preserved);
                            }
                        }
                        document["desktop"]["settings"][section][key] = next;
                    }
                }
            }
        }
        super::configuration_validation::validate_settings(&document["desktop"]["settings"])?;
        persist_settings(&mut tx, &document).await?;
        tx.commit().await?;
        Ok(())
    }

    pub async fn configuration_apply(
        &self,
        account_id: &str,
        expected: &str,
        document: &Value,
        base: &Value,
        pending: &Value,
    ) -> Result<()> {
        validate_document(document)?;
        let mut tx = self.pool().begin_with("BEGIN IMMEDIATE").await?;
        check_account(&mut tx, account_id).await?;
        let before = snapshot_in(&mut tx).await?;
        let state = read_json(&mut tx, &state_key(account_id))
            .await?
            .unwrap_or(json!({}));
        if digest(&json!({"document": before, "state": state}))? != expected {
            bail!("Local configuration changed. Review it again.");
        }
        super::configuration_profiles::apply_profiles(&mut tx, document).await?;
        persist_settings(&mut tx, document).await?;
        {
            let empty = json!({"items": {}, "order": []});
            let catalog = document.pointer("/shared/textActions").unwrap_or(&empty);
            let actions = ordered_items(catalog)?;
            put_json(
                &mut tx,
                "settings.textActions",
                &json!({"actions": actions}),
            )
            .await?;
        }
        put_json(
            &mut tx,
            &format!("configuration.backup.{account_id}"),
            &before,
        )
        .await?;
        put_json(
            &mut tx,
            &state_key(account_id),
            &json!({"base": base, "pending": pending}),
        )
        .await?;
        tx.commit().await?;
        Ok(())
    }

    pub async fn configuration_published(
        &self,
        account_id: &str,
        operation_id: &str,
        revision: &Value,
    ) -> Result<()> {
        let mut tx = self.pool().begin_with("BEGIN IMMEDIATE").await?;
        check_account(&mut tx, account_id).await?;
        let state = read_json(&mut tx, &state_key(account_id))
            .await?
            .unwrap_or(json!({}));
        if state
            .pointer("/pending/operationId")
            .and_then(Value::as_str)
            != Some(operation_id)
        {
            bail!("Pending configuration upload changed. Review again.");
        }
        put_json(
            &mut tx,
            &state_key(account_id),
            &json!({"base": revision, "pending": null}),
        )
        .await?;
        tx.commit().await?;
        Ok(())
    }
}

async fn snapshot_in(connection: &mut SqliteConnection) -> Result<Value> {
    let mut document = read_json(connection, DOCUMENT_KEY).await?.unwrap_or(json!({
        "schemaVersion": 1, "shared": {}, "desktop": {"settings": {}}, "mobile": {}}));
    for (pointer, key) in SHARED_SETTINGS {
        let raw: Option<String> =
            sqlx::query_scalar("SELECT value FROM runtimeMetadata WHERE key = ?")
                .bind(key)
                .fetch_optional(&mut *connection)
                .await?;
        if let Some(raw) = raw {
            let value = if key.ends_with("defaultAgentProfileId") {
                json!(raw)
            } else {
                serde_json::from_str(&raw)?
            };
            let value = super::configuration_native_settings::overlay(
                document.pointer(pointer),
                value,
                key,
            )?;
            set_pointer(&mut document, pointer, value);
        } else if key.ends_with("defaultAgentProfileId") {
            set_pointer(&mut document, pointer, Value::Null);
        } else if key == "browser.settings.v1" {
            set_pointer(&mut document, pointer, json!({"searchEngine": "google"}));
        }
    }
    let rows = sqlx::query(sqlx::AssertSqlSafe(format!(
        "SELECT {PROFILE_COLUMNS} FROM agentProfiles ORDER BY sortOrder, name, id"
    )))
    .fetch_all(&mut *connection)
    .await?;
    let mut profiles = Vec::new();
    for row in rows {
        let mut profile = serde_json::to_value(agent_profile_from_row(row)?)?;
        let id = profile["id"].as_str().unwrap_or_default().to_owned();
        if let Some(previous) = document["shared"]["agentProfiles"]["items"][&id].as_object() {
            let mut preserved = previous.clone();
            if let Some(fields) = profile.as_object() {
                preserved.extend(fields.clone());
            }
            profile = Value::Object(preserved);
        }
        if let Some(object) = profile.as_object_mut() {
            for key in ["revision", "createdAt", "updatedAt", "sortOrder"] {
                object.remove(key);
            }
        }
        profiles.push(profile);
    }
    document["shared"]["agentProfiles"] =
        catalog(&document["shared"]["agentProfiles"], profiles, false);
    if let Some(actions) = read_json(connection, "settings.textActions").await? {
        document["shared"]["textActions"] = catalog(
            &document["shared"]["textActions"],
            actions["actions"].as_array().cloned().unwrap_or_default(),
            true,
        );
    }
    Ok(document)
}

async fn persist_settings(connection: &mut SqliteConnection, document: &Value) -> Result<()> {
    put_json(connection, DOCUMENT_KEY, document).await?;
    for (pointer, key) in SHARED_SETTINGS {
        if let Some(value) = document.pointer(pointer) {
            if key.ends_with("defaultAgentProfileId") {
                if let Some(id) = value.as_str() {
                    sqlx::query("INSERT INTO runtimeMetadata (key, value, updatedAt) VALUES (?, ?, strftime('%Y-%m-%dT%H:%M:%fZ', 'now')) ON CONFLICT(key) DO UPDATE SET value = excluded.value, updatedAt = excluded.updatedAt")
                        .bind(key).bind(id).execute(&mut *connection).await?;
                } else {
                    sqlx::query("DELETE FROM runtimeMetadata WHERE key = ?")
                        .bind(key)
                        .execute(&mut *connection)
                        .await?;
                }
            } else {
                put_json(connection, key, value).await?;
            }
        } else {
            sqlx::query("DELETE FROM runtimeMetadata WHERE key = ?")
                .bind(key)
                .execute(&mut *connection)
                .await?;
        }
    }
    Ok(())
}

pub(super) async fn read_json(
    connection: &mut SqliteConnection,
    key: &str,
) -> Result<Option<Value>> {
    let raw: Option<String> = sqlx::query_scalar("SELECT value FROM runtimeMetadata WHERE key = ?")
        .bind(key)
        .fetch_optional(&mut *connection)
        .await?;
    raw.map(|value| serde_json::from_str(&value).map_err(Into::into))
        .transpose()
}
async fn put_json(connection: &mut SqliteConnection, key: &str, value: &Value) -> Result<()> {
    sqlx::query("INSERT INTO runtimeMetadata (key, value, updatedAt) VALUES (?, ?, strftime('%Y-%m-%dT%H:%M:%fZ', 'now')) ON CONFLICT(key) DO UPDATE SET value = excluded.value, updatedAt = excluded.updatedAt")
        .bind(key).bind(serde_json::to_string(value)?).execute(&mut *connection).await?;
    Ok(())
}
async fn check_account(connection: &mut SqliteConnection, expected: &str) -> Result<()> {
    let actual: Option<String> =
        sqlx::query_scalar("SELECT accountId FROM aleraAccount WHERE id = 1")
            .fetch_optional(&mut *connection)
            .await?;
    if actual.as_deref() != Some(expected) {
        bail!("The selected account does not own this runtime.");
    }
    Ok(())
}
fn state_key(account: &str) -> String {
    format!("configuration.state.{account}")
}
fn digest(value: &Value) -> Result<String> {
    Ok(format!("{:x}", Sha256::digest(serde_json::to_vec(value)?)))
}
fn catalog(previous: &Value, items: Vec<Value>, preserve_item_fields: bool) -> Value {
    let mut by_id = serde_json::Map::new();
    let mut order = Vec::new();
    for item in items {
        if let Some(id) = item["id"].as_str() {
            order.push(json!(id));
            let mut preserved = previous["items"][id]
                .as_object()
                .filter(|_| preserve_item_fields)
                .cloned()
                .unwrap_or_default();
            if let Some(fields) = item.as_object() {
                preserved.extend(fields.clone());
            }
            by_id.insert(id.to_owned(), Value::Object(preserved));
        }
    }
    let mut result = previous.as_object().cloned().unwrap_or_default();
    result.insert("items".into(), Value::Object(by_id));
    result.insert("order".into(), json!(order));
    Value::Object(result)
}
pub(super) fn ordered_items(catalog: &Value) -> Result<Vec<Value>> {
    let items = catalog["items"]
        .as_object()
        .ok_or_else(|| anyhow::anyhow!("Invalid configuration catalog."))?;
    let mut ids = Vec::new();
    for id in catalog["order"]
        .as_array()
        .into_iter()
        .flatten()
        .filter_map(Value::as_str)
    {
        if items.contains_key(id) && !ids.contains(&id) {
            ids.push(id);
        }
    }
    for id in items.keys() {
        if !ids.contains(&id.as_str()) {
            ids.push(id);
        }
    }
    Ok(ids
        .into_iter()
        .map(|id| {
            let mut item = items[id].clone();
            item["id"] = json!(id);
            item
        })
        .collect())
}
fn set_pointer(value: &mut Value, pointer: &str, next: Value) {
    let keys: Vec<_> = pointer.trim_start_matches('/').split('/').collect();
    let mut parent = value;
    for key in &keys[..keys.len() - 1] {
        if !parent[*key].is_object() {
            parent[*key] = json!({});
        }
        parent = &mut parent[*key];
    }
    parent[keys[keys.len() - 1]] = next;
}
