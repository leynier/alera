use anyhow::{anyhow, bail, Result};
use chrono::Utc;
use sqlx::{sqlite::SqliteRow, Row};

use super::{
    format_timestamp, parse_timestamp, validate_prompt_template, validate_schedule,
    AutomationActor, AutomationDefinition, AutomationState, RuntimeStore, RuntimeStoreError,
};

fn decode_definition(row: SqliteRow) -> Result<AutomationDefinition> {
    let data: String = row.try_get("dataJson")?;
    let mut definition: AutomationDefinition = serde_json::from_str(&data)?;
    definition.state = AutomationState::from_db(&row.try_get::<String, _>("state")?);
    definition.revision = row.try_get("revision")?;
    Ok(definition)
}

fn validate_definition(definition: &AutomationDefinition) -> Result<()> {
    if definition.id.trim().is_empty() {
        bail!(RuntimeStoreError::Message(
            "automation id is required".to_string()
        ));
    }
    if definition.slug.trim().is_empty() {
        bail!(RuntimeStoreError::Message(
            "automation slug is required".to_string()
        ));
    }
    if definition.name.trim().is_empty() {
        bail!(RuntimeStoreError::Message(
            "automation name is required".to_string()
        ));
    }
    validate_prompt_template(&definition.prompt_template).map_err(|error| anyhow!(error))?;
    validate_schedule(&definition.schedule).map_err(|error| anyhow!(error))?;
    if definition.queue_cap < 1 || definition.queue_cap > 10 {
        bail!(RuntimeStoreError::Message(
            "automation queue cap must be between 1 and 10".to_string()
        ));
    }
    if definition.inactivity_timeout_seconds < 1
        || definition.inactivity_timeout_seconds > super::AUTOMATION_MAX_INACTIVITY_TIMEOUT_SECONDS
    {
        bail!(RuntimeStoreError::Message(
            "automation inactivity timeout must be between 1 second and 24 hours".to_string()
        ));
    }
    if definition.heartbeat_interval_seconds < 1
        || definition.heartbeat_interval_seconds > definition.inactivity_timeout_seconds
    {
        bail!(RuntimeStoreError::Message(
            "automation heartbeat interval must be positive and no longer than inactivity timeout"
                .to_string()
        ));
    }
    if definition.misfire_grace_seconds < 0 || definition.misfire_grace_seconds > 24 * 60 * 60 {
        bail!(RuntimeStoreError::Message(
            "automation misfire grace must be between 0 and 24 hours".to_string()
        ));
    }
    if !(1..=3).contains(&definition.retry_max_attempts) {
        bail!(RuntimeStoreError::Message(
            "automation retry max attempts must be between 1 and 3 attempts (at most two retries)"
                .to_string()
        ));
    }
    if !(1..=24 * 60 * 60).contains(&definition.retry_backoff_seconds) {
        bail!(RuntimeStoreError::Message(
            "automation retry backoff must be between 1 second and 24 hours".to_string()
        ));
    }
    if !(1..=10).contains(&definition.circuit_failure_threshold) {
        bail!(RuntimeStoreError::Message(
            "automation circuit failure threshold must be between 1 and 10".to_string()
        ));
    }
    if !(1..=7 * 24 * 60 * 60).contains(&definition.circuit_open_seconds) {
        bail!(RuntimeStoreError::Message(
            "automation circuit open duration must be between 1 second and 7 days".to_string()
        ));
    }
    if let Some(precheck) = &definition.precheck {
        if precheck.command.trim().is_empty() {
            bail!(RuntimeStoreError::Message(
                "automation precheck command is required".to_string()
            ));
        }
        if !(1..=15 * 60).contains(&precheck.timeout_seconds) {
            bail!(RuntimeStoreError::Message(
                "automation precheck timeout must be between 1 second and 15 minutes".to_string()
            ));
        }
    }
    Ok(())
}

impl RuntimeStore {
    pub async fn has_active_automations(&self) -> Result<bool> {
        let count: i64 =
            sqlx::query("SELECT COUNT(*) AS count FROM automations WHERE state = 'active'")
                .fetch_one(self.pool())
                .await?
                .try_get("count")?;
        Ok(count > 0)
    }

    pub async fn list_automations(
        &self,
        include_trashed: bool,
    ) -> Result<Vec<AutomationDefinition>> {
        let query = if include_trashed {
            "SELECT state, revision, dataJson FROM automations"
        } else {
            "SELECT state, revision, dataJson FROM automations WHERE state <> 'trashed'"
        };
        let rows = sqlx::query(query).fetch_all(self.pool()).await?;
        let mut definitions = rows
            .into_iter()
            .map(decode_definition)
            .collect::<Result<Vec<_>>>()?;
        definitions.sort_by_cached_key(|definition| definition.name.to_lowercase());
        Ok(definitions)
    }

    pub async fn find_automation(&self, id: &str) -> Result<Option<AutomationDefinition>> {
        sqlx::query("SELECT state, revision, dataJson FROM automations WHERE id = ?")
            .bind(id)
            .fetch_optional(self.pool())
            .await?
            .map(decode_definition)
            .transpose()
    }

    pub async fn find_automation_by_slug(
        &self,
        slug: &str,
    ) -> Result<Option<AutomationDefinition>> {
        sqlx::query(
            "SELECT state, revision, dataJson FROM automations WHERE slug = ? COLLATE NOCASE",
        )
        .bind(slug.trim())
        .fetch_optional(self.pool())
        .await?
        .map(decode_definition)
        .transpose()
    }

    pub async fn upsert_automation(
        &self,
        mut definition: AutomationDefinition,
        actor: AutomationActor,
    ) -> Result<AutomationDefinition> {
        definition.id = definition.id.trim().to_string();
        definition.slug = definition.slug.trim().to_ascii_lowercase();
        definition.name = definition.name.trim().to_string();
        definition.description = definition.description.trim().to_string();
        definition.project_id = definition
            .project_id
            .as_deref()
            .map(str::trim)
            .filter(|value| !value.is_empty())
            .map(str::to_string);
        definition
            .tag_ids
            .retain(|tag_id| !tag_id.trim().is_empty());
        let existing = self.find_automation(&definition.id).await?;
        if let Some(conflict) = sqlx::query(
            "SELECT id FROM automations WHERE slug = ? COLLATE NOCASE AND id <> ? LIMIT 1",
        )
        .bind(&definition.slug)
        .bind(&definition.id)
        .fetch_optional(self.pool())
        .await?
        {
            let owner: String = conflict.try_get("id")?;
            bail!(RuntimeStoreError::Message(format!(
                "automation slug already exists: {owner}"
            )));
        }
        validate_definition(&definition)?;
        let now = Utc::now();
        let material_changed = existing.as_ref().is_some_and(|previous| {
            previous.material_fingerprint() != definition.material_fingerprint()
        });
        let (revision, created_at, approved_revision) = match existing.as_ref() {
            Some(previous) => {
                definition.created_by = previous.created_by.clone();
                let revision = previous.revision + 1;
                (
                    revision,
                    previous.created_at,
                    (!material_changed && previous.is_approved()).then_some(revision),
                )
            }
            None => {
                definition.created_by = actor.clone();
                (1, definition.created_at, None)
            }
        };
        if material_changed {
            definition.state = AutomationState::Draft;
        }
        definition.revision = revision;
        definition.created_at = created_at;
        definition.updated_at = now;
        definition.modified_by = actor.clone();
        definition.approved_revision = approved_revision;
        let encoded = serde_json::to_string(&definition)?;
        sqlx::query(
            "INSERT INTO automations (id, slug, state, revision, dataJson, createdAt, updatedAt, trashedAt) \
             VALUES (?, ?, ?, ?, ?, ?, ?, NULL) \
             ON CONFLICT(id) DO UPDATE SET slug = excluded.slug, state = excluded.state, \
             revision = excluded.revision, dataJson = excluded.dataJson, updatedAt = excluded.updatedAt, \
             trashedAt = CASE WHEN excluded.state = 'trashed' THEN excluded.updatedAt ELSE NULL END",
        )
        .bind(&definition.id)
        .bind(&definition.slug)
        .bind(definition.state.as_str())
        .bind(definition.revision)
        .bind(encoded)
        .bind(format_timestamp(definition.created_at))
        .bind(format_timestamp(definition.updated_at))
        .execute(self.pool())
        .await?;
        self.set_automation_tags(&definition.id, &definition.tag_ids)
            .await?;
        self.insert_automation_audit_event(
            Some(&definition.id),
            None,
            "edit",
            actor,
            Some(definition.revision),
            serde_json::json!({
                "material": material_changed,
                "approvalPreserved": definition.is_approved() && !material_changed,
            }),
        )
        .await?;
        self.find_automation(&definition.id)
            .await?
            .ok_or_else(|| anyhow!("automation disappeared after upsert"))
    }

    pub async fn set_automation_state(
        &self,
        id: &str,
        state: AutomationState,
        actor: AutomationActor,
        reason: Option<&str>,
    ) -> Result<AutomationDefinition> {
        let mut definition = self
            .find_automation(id)
            .await?
            .ok_or_else(|| anyhow!("automation not found: {id}"))?;
        if !(definition.state.is_editable()
            || definition.state == AutomationState::Trashed && state == AutomationState::Draft)
        {
            bail!("automation is archived or trashed");
        }
        if state == AutomationState::Active && !definition.is_approved() {
            bail!("automation revision must be approved before activation");
        }
        definition.state = state;
        definition.updated_at = Utc::now();
        definition.modified_by = actor.clone();
        sqlx::query(
            "UPDATE automations SET state = ?, dataJson = ?, updatedAt = ?, \
             trashedAt = CASE WHEN ? = 'trashed' THEN ? ELSE NULL END WHERE id = ?",
        )
        .bind(state.as_str())
        .bind(serde_json::to_string(&definition)?)
        .bind(format_timestamp(definition.updated_at))
        .bind(state.as_str())
        .bind(format_timestamp(definition.updated_at))
        .bind(id)
        .execute(self.pool())
        .await?;
        self.insert_automation_audit_event(
            Some(id),
            None,
            state.as_str(),
            actor,
            Some(definition.revision),
            serde_json::json!({ "reason": reason }),
        )
        .await?;
        Ok(definition)
    }

    pub async fn set_automation_circuit_opened(
        &self,
        id: &str,
        opened: bool,
        actor: AutomationActor,
        reason: Option<&str>,
    ) -> Result<AutomationDefinition> {
        let mut definition = self
            .find_automation(id)
            .await?
            .ok_or_else(|| anyhow!("automation not found: {id}"))?;
        if definition.circuit_opened == opened {
            return Ok(definition);
        }
        definition.circuit_opened = opened;
        definition.updated_at = Utc::now();
        definition.modified_by = actor.clone();
        sqlx::query("UPDATE automations SET dataJson = ?, updatedAt = ? WHERE id = ?")
            .bind(serde_json::to_string(&definition)?)
            .bind(format_timestamp(definition.updated_at))
            .bind(id)
            .execute(self.pool())
            .await?;
        self.insert_automation_audit_event(
            Some(id),
            None,
            if opened {
                "circuitOpened"
            } else {
                "circuitReset"
            },
            actor,
            Some(definition.revision),
            serde_json::json!({ "reason": reason }),
        )
        .await?;
        Ok(definition)
    }

    pub async fn approve_automation(
        &self,
        id: &str,
        revision: i64,
        actor: AutomationActor,
    ) -> Result<AutomationDefinition> {
        let mut definition = self
            .find_automation(id)
            .await?
            .ok_or_else(|| anyhow!("automation not found: {id}"))?;
        if definition.revision != revision {
            bail!("automation revision is stale; refresh before approving");
        }
        definition.approved_revision = Some(revision);
        definition.state = AutomationState::Active;
        definition.updated_at = Utc::now();
        definition.modified_by = actor.clone();
        sqlx::query(
            "UPDATE automations SET state = 'active', dataJson = ?, updatedAt = ? WHERE id = ?",
        )
        .bind(serde_json::to_string(&definition)?)
        .bind(format_timestamp(definition.updated_at))
        .bind(id)
        .execute(self.pool())
        .await?;
        self.insert_automation_audit_event(
            Some(id),
            None,
            "approve",
            actor,
            Some(revision),
            serde_json::json!({}),
        )
        .await?;
        Ok(definition)
    }

    pub async fn purge_trashed_automations(&self, before: chrono::DateTime<Utc>) -> Result<u64> {
        let result =
            sqlx::query("DELETE FROM automations WHERE state = 'trashed' AND trashedAt < ?")
                .bind(format_timestamp(before))
                .execute(self.pool())
                .await?;
        Ok(result.rows_affected())
    }

    pub async fn purge_trashed_automations_with_retention(
        &self,
        now: chrono::DateTime<Utc>,
        retention_days: i64,
    ) -> Result<u64> {
        let before = now - chrono::Duration::days(retention_days.max(1));
        let result =
            sqlx::query("DELETE FROM automations WHERE state = 'trashed' AND trashedAt < ?")
                .bind(format_timestamp(before))
                .execute(self.pool())
                .await?;
        Ok(result.rows_affected())
    }

    pub async fn archive_one_time_automation_if_final(
        &self,
        automation_id: &str,
        actor: AutomationActor,
    ) -> Result<bool> {
        let Some(mut definition) = self.find_automation(automation_id).await? else {
            return Ok(false);
        };
        if !matches!(
            definition.schedule,
            super::AutomationSchedule::OneTime { .. }
        ) || matches!(
            definition.state,
            AutomationState::Archived | AutomationState::Trashed
        ) {
            return Ok(false);
        }
        definition.state = AutomationState::Archived;
        definition.updated_at = Utc::now();
        definition.modified_by = actor.clone();
        sqlx::query(
            "UPDATE automations SET state = 'archived', dataJson = ?, updatedAt = ? WHERE id = ?",
        )
        .bind(serde_json::to_string(&definition)?)
        .bind(format_timestamp(definition.updated_at))
        .bind(automation_id)
        .execute(self.pool())
        .await?;
        self.insert_automation_audit_event(
            Some(automation_id),
            None,
            "archived",
            actor,
            Some(definition.revision),
            serde_json::json!({ "reason": "one-time run reached a final outcome" }),
        )
        .await?;
        Ok(true)
    }
}

#[allow(dead_code)]
fn _timestamp_round_trip(value: &str) -> String {
    format_timestamp(parse_timestamp(value))
}

#[cfg(test)]
#[path = "automation_store_tests.rs"]
mod tests;
