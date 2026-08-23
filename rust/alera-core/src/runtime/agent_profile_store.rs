use std::collections::HashSet;

use anyhow::Result;
use chrono::Utc;
use sqlx::Row;

use super::{
    format_timestamp, parse_timestamp, AgentProfile, AgentProfileLaunchMode, RuntimeStore,
    RuntimeStoreError,
};

const PROFILE_COLUMNS: &str =
    "id, name, agentType, command, sortOrder, launchMode, managedConfig, customPrompt, description, quotaGroup, revision, createdAt, updatedAt";

impl RuntimeStore {
    pub async fn list_agent_profiles(&self) -> Result<Vec<AgentProfile>> {
        let rows = sqlx::query(sqlx::AssertSqlSafe(format!(
            "SELECT {PROFILE_COLUMNS} FROM agentProfiles \
             ORDER BY sortOrder ASC, name COLLATE NOCASE ASC, id ASC"
        )))
        .fetch_all(self.pool())
        .await?;
        rows.into_iter().map(agent_profile_from_row).collect()
    }

    pub async fn find_agent_profile(&self, profile_id: &str) -> Result<Option<AgentProfile>> {
        let row = sqlx::query(sqlx::AssertSqlSafe(format!(
            "SELECT {PROFILE_COLUMNS} FROM agentProfiles WHERE id = ?"
        )))
        .bind(profile_id)
        .fetch_optional(self.pool())
        .await?;
        row.map(agent_profile_from_row).transpose()
    }

    /// Profiles are addressed by name in execution policies, so name lookup is
    /// the primary resolution path for spawning and fallback selection.
    pub async fn agent_profile_by_name(&self, name: &str) -> Result<Option<AgentProfile>> {
        let row = sqlx::query(sqlx::AssertSqlSafe(format!(
            "SELECT {PROFILE_COLUMNS} FROM agentProfiles WHERE name = ? COLLATE NOCASE"
        )))
        .bind(name.trim())
        .fetch_optional(self.pool())
        .await?;
        row.map(agent_profile_from_row).transpose()
    }

    pub async fn upsert_agent_profile(
        &self,
        profile: AgentProfile,
        expected_revision: Option<i64>,
    ) -> Result<AgentProfile> {
        let mut profile = normalize_agent_profile(profile)?;
        let existing = self.find_agent_profile(&profile.id).await?;
        if existing.as_ref().map(|item| item.revision) != expected_revision
            && (existing.is_some() || expected_revision.is_some())
        {
            return Err(agent_profile_revision_conflict(
                &profile.id,
                expected_revision,
                existing.as_ref().map(|item| item.revision),
            ));
        }
        profile.sort_order = match existing {
            Some(existing) => existing.sort_order.max(0),
            None => self.next_agent_profile_sort_order().await?,
        };
        // Pre-check instead of relying on the unique index, so a duplicate name
        // reports which profile already owns it rather than a SQLite error.
        let conflict = sqlx::query(
            "SELECT id FROM agentProfiles WHERE name = ? COLLATE NOCASE AND id <> ? LIMIT 1",
        )
        .bind(&profile.name)
        .bind(&profile.id)
        .fetch_optional(self.pool())
        .await?;
        if conflict.is_some() {
            anyhow::bail!(RuntimeStoreError::Message(format!(
                "agent profile name already exists: {}",
                profile.name
            )));
        }
        let now = format_timestamp(Utc::now());
        let result = sqlx::query(
            "INSERT INTO agentProfiles \
             (id, name, agentType, command, sortOrder, launchMode, managedConfig, customPrompt, description, quotaGroup, revision, createdAt, updatedAt) \
             VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 0, ?, ?) \
             ON CONFLICT(id) DO UPDATE SET \
             name = excluded.name, agentType = excluded.agentType, command = excluded.command, \
             launchMode = excluded.launchMode, managedConfig = excluded.managedConfig, \
             customPrompt = excluded.customPrompt, \
             description = excluded.description, quotaGroup = excluded.quotaGroup, \
             revision = agentProfiles.revision + 1, updatedAt = excluded.updatedAt \
             WHERE agentProfiles.revision = ?",
        )
        .bind(&profile.id)
        .bind(&profile.name)
        .bind(&profile.agent_type)
        .bind(&profile.command)
        .bind(profile.sort_order)
        .bind(profile.launch_mode.as_str())
        .bind(
            profile
                .managed_config
                .as_ref()
                .map(serde_json::to_string)
                .transpose()?,
        )
        .bind(&profile.custom_prompt)
        .bind(&profile.description)
        .bind(&profile.quota_group)
        .bind(format_timestamp(profile.created_at))
        .bind(&now)
        .bind(expected_revision)
        .execute(self.pool())
        .await?
        .rows_affected();
        if result == 0 {
            let current = self.find_agent_profile(&profile.id).await?;
            return Err(agent_profile_revision_conflict(
                &profile.id,
                expected_revision,
                current.map(|item| item.revision),
            ));
        }
        self.find_agent_profile(&profile.id).await?.ok_or_else(|| {
            anyhow::anyhow!(RuntimeStoreError::Message(format!(
                "agent profile not found after upsert: {}",
                profile.id
            )))
        })
    }

    async fn next_agent_profile_sort_order(&self) -> Result<i64> {
        let max_order =
            sqlx::query_scalar::<_, Option<i64>>("SELECT MAX(sortOrder) FROM agentProfiles")
                .fetch_one(self.pool())
                .await?;
        Ok(max_order.unwrap_or(-1).saturating_add(1))
    }

    pub async fn reorder_agent_profiles(
        &self,
        profile_ids: &[String],
        expected_revisions: &std::collections::HashMap<String, i64>,
    ) -> Result<Vec<AgentProfile>> {
        let mut connection = self.pool().acquire().await?;
        sqlx::query("BEGIN IMMEDIATE")
            .execute(&mut *connection)
            .await?;
        let operation: Result<Vec<AgentProfile>> = async {
            let rows = sqlx::query(sqlx::AssertSqlSafe(format!(
                "SELECT {PROFILE_COLUMNS} FROM agentProfiles \
                 ORDER BY sortOrder ASC, name COLLATE NOCASE ASC, id ASC"
            )))
            .fetch_all(&mut *connection)
            .await?;
            let current = rows
                .into_iter()
                .map(agent_profile_from_row)
                .collect::<Result<Vec<_>>>()?;
            let current_ids = current
                .iter()
                .map(|profile| profile.id.as_str())
                .collect::<HashSet<_>>();
            let requested_ids = profile_ids
                .iter()
                .map(String::as_str)
                .collect::<HashSet<_>>();
            if requested_ids.len() != profile_ids.len() {
                anyhow::bail!(RuntimeStoreError::Message(
                    "agent profile order must contain each profile exactly once".to_string()
                ));
            }
            if requested_ids != current_ids || expected_revisions.len() != current.len() {
                let conflict_id = profile_ids
                    .iter()
                    .find(|id| !current_ids.contains(id.as_str()))
                    .cloned()
                    .or_else(|| {
                        current
                            .iter()
                            .find(|profile| !requested_ids.contains(profile.id.as_str()))
                            .map(|profile| profile.id.clone())
                    })
                    .or_else(|| {
                        current
                            .iter()
                            .find(|profile| !expected_revisions.contains_key(&profile.id))
                            .map(|profile| profile.id.clone())
                    })
                    .unwrap_or_else(|| "catalog".to_string());
                return Err(agent_profile_revision_conflict(
                    &conflict_id,
                    expected_revisions.get(&conflict_id).copied(),
                    current
                        .iter()
                        .find(|profile| profile.id == conflict_id)
                        .map(|profile| profile.revision),
                ));
            }

            for profile in &current {
                if expected_revisions.get(&profile.id) != Some(&profile.revision) {
                    return Err(agent_profile_revision_conflict(
                        &profile.id,
                        expected_revisions.get(&profile.id).copied(),
                        Some(profile.revision),
                    ));
                }
            }

            let updated_at = format_timestamp(Utc::now());
            for (sort_order, profile_id) in profile_ids.iter().enumerate() {
                let Some(profile) = current.iter().find(|profile| profile.id == *profile_id) else {
                    unreachable!("catalog membership was validated above")
                };
                if profile.sort_order == sort_order as i64 {
                    continue;
                }
                let result = sqlx::query(
                    "UPDATE agentProfiles SET sortOrder = ?, revision = revision + 1, updatedAt = ? \
                     WHERE id = ? AND revision = ?",
                )
                .bind(sort_order as i64)
                .bind(&updated_at)
                .bind(profile_id)
                .bind(profile.revision)
                .execute(&mut *connection)
                .await?;
                if result.rows_affected() == 0 {
                    let current_revision = sqlx::query_scalar::<_, i64>(
                        "SELECT revision FROM agentProfiles WHERE id = ?",
                    )
                    .bind(profile_id)
                    .fetch_optional(&mut *connection)
                    .await?;
                    return Err(agent_profile_revision_conflict(
                        profile_id,
                        Some(profile.revision),
                        current_revision,
                    ));
                }
            }
            let rows = sqlx::query(sqlx::AssertSqlSafe(format!(
                "SELECT {PROFILE_COLUMNS} FROM agentProfiles \
                 ORDER BY sortOrder ASC, name COLLATE NOCASE ASC, id ASC"
            )))
            .fetch_all(&mut *connection)
            .await?;
            rows.into_iter().map(agent_profile_from_row).collect()
        }
        .await;
        match operation {
            Ok(profiles) => {
                sqlx::query("COMMIT").execute(&mut *connection).await?;
                Ok(profiles)
            }
            Err(error) => {
                let _ = sqlx::query("ROLLBACK").execute(&mut *connection).await;
                Err(error)
            }
        }
    }

    pub async fn remove_agent_profile(
        &self,
        profile_id: &str,
        expected_revision: i64,
    ) -> Result<bool> {
        let result = sqlx::query("DELETE FROM agentProfiles WHERE id = ? AND revision = ?")
            .bind(profile_id)
            .bind(expected_revision)
            .execute(self.pool())
            .await?;
        let removed = result.rows_affected() > 0;
        if !removed {
            let current = self.find_agent_profile(profile_id).await?;
            if let Some(current) = current {
                return Err(agent_profile_revision_conflict(
                    profile_id,
                    Some(expected_revision),
                    Some(current.revision),
                ));
            }
        }
        if removed && self.default_agent_profile_id().await?.as_deref() == Some(profile_id) {
            self.set_default_agent_profile_id(None).await?;
        }
        Ok(removed)
    }
}

fn agent_profile_revision_conflict(
    profile_id: &str,
    expected: Option<i64>,
    current: Option<i64>,
) -> anyhow::Error {
    RuntimeStoreError::AgentProfileRevisionConflict {
        profile_id: profile_id.to_string(),
        expected,
        current,
    }
    .into()
}

fn normalize_agent_profile(mut profile: AgentProfile) -> Result<AgentProfile> {
    profile.id = profile.id.trim().to_string();
    profile.name = profile.name.trim().to_string();
    profile.agent_type = profile.agent_type.trim().to_string();
    profile.command = profile.command.trim().to_string();
    profile.custom_prompt = profile.custom_prompt.trim().to_string();
    profile.description = profile.description.trim().to_string();
    profile.quota_group = profile
        .quota_group
        .map(|group| group.trim().to_string())
        .filter(|group| !group.is_empty());
    if profile.id.is_empty() {
        anyhow::bail!(RuntimeStoreError::Message(
            "agent profile id is required".to_string()
        ));
    }
    if profile.name.is_empty() {
        anyhow::bail!(RuntimeStoreError::Message(
            "agent profile name is required".to_string()
        ));
    }
    if profile.agent_type.is_empty() {
        anyhow::bail!(RuntimeStoreError::Message(
            "agent profile agent type is required".to_string()
        ));
    }
    if profile.command.is_empty() {
        anyhow::bail!(RuntimeStoreError::Message(
            "agent profile command is required".to_string()
        ));
    }
    match profile.launch_mode {
        AgentProfileLaunchMode::Command => {
            profile.managed_config = None;
        }
        AgentProfileLaunchMode::Managed => {
            if !profile
                .managed_config
                .as_ref()
                .is_some_and(serde_json::Value::is_object)
            {
                anyhow::bail!(RuntimeStoreError::Message(
                    "managed agent profile config must be an object".to_string()
                ));
            }
        }
    }
    Ok(profile)
}

fn agent_profile_from_row(row: sqlx::sqlite::SqliteRow) -> Result<AgentProfile> {
    Ok(AgentProfile {
        id: row.try_get("id")?,
        name: row.try_get("name")?,
        sort_order: row.try_get("sortOrder")?,
        agent_type: row.try_get("agentType")?,
        command: row.try_get("command")?,
        launch_mode: row
            .try_get::<String, _>("launchMode")?
            .parse()
            .map_err(|error: String| anyhow::anyhow!(error))?,
        managed_config: row
            .try_get::<Option<String>, _>("managedConfig")?
            .map(|value| serde_json::from_str(&value))
            .transpose()?,
        custom_prompt: row.try_get("customPrompt")?,
        description: row.try_get("description")?,
        quota_group: row.try_get("quotaGroup")?,
        revision: row.try_get("revision")?,
        created_at: parse_timestamp(row.try_get::<String, _>("createdAt")?.as_str()),
        updated_at: parse_timestamp(row.try_get::<String, _>("updatedAt")?.as_str()),
    })
}
