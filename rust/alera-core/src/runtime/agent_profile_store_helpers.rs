use anyhow::Result;
use sqlx::Row;

use super::{parse_timestamp, AgentProfile, AgentProfileLaunchMode, RuntimeStoreError};

pub(super) fn normalize_agent_profile(mut profile: AgentProfile) -> Result<AgentProfile> {
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

pub(super) fn agent_profile_from_row(row: sqlx::sqlite::SqliteRow) -> Result<AgentProfile> {
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
