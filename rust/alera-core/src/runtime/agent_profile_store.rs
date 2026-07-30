use anyhow::Result;
use chrono::Utc;
use sqlx::Row;

use super::{
    format_timestamp, parse_timestamp, AgentProfile, AgentProfileLaunchMode, RuntimeStore,
    RuntimeStoreError,
};

const PROFILE_COLUMNS: &str =
    "id, name, agentType, command, launchMode, managedConfig, description, quotaGroup, createdAt, updatedAt";

impl RuntimeStore {
    pub async fn list_agent_profiles(&self) -> Result<Vec<AgentProfile>> {
        let rows = sqlx::query(sqlx::AssertSqlSafe(format!(
            "SELECT {PROFILE_COLUMNS} FROM agentProfiles ORDER BY name COLLATE NOCASE ASC"
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

    pub async fn upsert_agent_profile(&self, profile: AgentProfile) -> Result<AgentProfile> {
        let profile = normalize_agent_profile(profile)?;
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
        sqlx::query(
            "INSERT INTO agentProfiles \
             (id, name, agentType, command, launchMode, managedConfig, description, quotaGroup, createdAt, updatedAt) \
             VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?) \
             ON CONFLICT(id) DO UPDATE SET \
             name = excluded.name, agentType = excluded.agentType, command = excluded.command, \
             launchMode = excluded.launchMode, managedConfig = excluded.managedConfig, \
             description = excluded.description, quotaGroup = excluded.quotaGroup, \
             updatedAt = excluded.updatedAt",
        )
        .bind(&profile.id)
        .bind(&profile.name)
        .bind(&profile.agent_type)
        .bind(&profile.command)
        .bind(profile.launch_mode.as_str())
        .bind(
            profile
                .managed_config
                .as_ref()
                .map(serde_json::to_string)
                .transpose()?,
        )
        .bind(&profile.description)
        .bind(&profile.quota_group)
        .bind(format_timestamp(profile.created_at))
        .bind(&now)
        .execute(self.pool())
        .await?;
        self.find_agent_profile(&profile.id).await?.ok_or_else(|| {
            anyhow::anyhow!(RuntimeStoreError::Message(format!(
                "agent profile not found after upsert: {}",
                profile.id
            )))
        })
    }

    pub async fn remove_agent_profile(&self, profile_id: &str) -> Result<bool> {
        let result = sqlx::query("DELETE FROM agentProfiles WHERE id = ?")
            .bind(profile_id)
            .execute(self.pool())
            .await?;
        Ok(result.rows_affected() > 0)
    }
}

fn normalize_agent_profile(mut profile: AgentProfile) -> Result<AgentProfile> {
    profile.id = profile.id.trim().to_string();
    profile.name = profile.name.trim().to_string();
    profile.agent_type = profile.agent_type.trim().to_string();
    profile.command = profile.command.trim().to_string();
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
        description: row.try_get("description")?,
        quota_group: row.try_get("quotaGroup")?,
        created_at: parse_timestamp(row.try_get::<String, _>("createdAt")?.as_str()),
        updated_at: parse_timestamp(row.try_get::<String, _>("updatedAt")?.as_str()),
    })
}
