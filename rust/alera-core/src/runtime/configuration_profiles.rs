use super::{
    agent_profile_store::agent_profile_removal_impact_in,
    agent_profile_store_helpers::normalize_agent_profile, configuration_store::ordered_items,
    AgentProfile,
};
use anyhow::{bail, Result};
use chrono::Utc;
use serde_json::Value;
use sqlx::{Row, SqliteConnection};
use std::collections::HashSet;

pub(super) async fn apply_profiles(
    connection: &mut SqliteConnection,
    document: &Value,
) -> Result<()> {
    let empty = serde_json::json!({"items": {}, "order": []});
    let catalog = document.pointer("/shared/agentProfiles").unwrap_or(&empty);
    let mut profiles = Vec::new();
    let mut names = HashSet::new();
    for (index, mut item) in ordered_items(catalog)?.into_iter().enumerate() {
        item["createdAt"] = serde_json::json!(Utc::now());
        item["updatedAt"] = serde_json::json!(Utc::now());
        item["revision"] = serde_json::json!(0);
        item["sortOrder"] = serde_json::json!(index);
        let profile = normalize_agent_profile(serde_json::from_value::<AgentProfile>(item)?)?;
        if !names.insert(profile.name.to_lowercase()) {
            bail!("Agent profile names must be unique.");
        }
        profiles.push(profile);
    }
    if let Some(default_id) = document
        .pointer("/desktop/settings/agents/defaultAgentProfileId")
        .and_then(Value::as_str)
    {
        if !profiles.iter().any(|p| p.id == default_id) {
            bail!("The default agent profile is missing.");
        }
    }
    let existing = sqlx::query("SELECT id, name, revision FROM agentProfiles")
        .fetch_all(&mut *connection)
        .await?;
    for row in &existing {
        let id: String = row.try_get("id")?;
        let name: String = row.try_get("name")?;
        let next = profiles.iter().find(|p| p.id == id);
        if next.is_none() || next.is_some_and(|p| p.name != name) {
            let impact =
                agent_profile_removal_impact_in(connection, &id, row.try_get("revision")?).await?;
            if next.is_none() && impact.has_blocking_references()
                || next.is_some() && !impact.execution_policy_run_ids.is_empty()
            {
                bail!("Profile {name} is used by an automation, execution policy or tab. Keep it or resolve those references first.");
            }
        }
        if next.is_none() {
            sqlx::query("DELETE FROM automationAgentPolicies WHERE profileId = ?")
                .bind(&id)
                .execute(&mut *connection)
                .await?;
            sqlx::query("DELETE FROM agentProfiles WHERE id = ?")
                .bind(&id)
                .execute(&mut *connection)
                .await?;
        }
    }
    // Stage names within the transaction so swapping two names obeys the unique index.
    let suffix = uuid::Uuid::new_v4().to_string();
    sqlx::query("UPDATE agentProfiles SET name = id || ?")
        .bind(suffix)
        .execute(&mut *connection)
        .await?;
    for profile in profiles {
        sqlx::query("INSERT INTO agentProfiles (id, name, agentType, command, sortOrder, launchMode, managedConfig, customPrompt, description, quotaGroup, revision, createdAt, updatedAt) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 0, ?, ?) ON CONFLICT(id) DO UPDATE SET name = excluded.name, agentType = excluded.agentType, command = excluded.command, sortOrder = excluded.sortOrder, launchMode = excluded.launchMode, managedConfig = excluded.managedConfig, customPrompt = excluded.customPrompt, description = excluded.description, quotaGroup = excluded.quotaGroup, revision = agentProfiles.revision + 1, updatedAt = excluded.updatedAt")
            .bind(profile.id).bind(profile.name).bind(profile.agent_type).bind(profile.command)
            .bind(profile.sort_order).bind(profile.launch_mode.as_str())
            .bind(profile.managed_config.map(|v| v.to_string())).bind(profile.custom_prompt)
            .bind(profile.description).bind(profile.quota_group)
            .bind(profile.created_at.to_rfc3339()).bind(profile.updated_at.to_rfc3339())
            .execute(&mut *connection).await?;
    }
    Ok(())
}
