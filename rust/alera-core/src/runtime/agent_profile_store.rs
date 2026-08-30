use std::collections::HashSet;

use anyhow::Result;
use chrono::Utc;
use sqlx::{Row, SqliteConnection};

use super::agent_profile_store_helpers::{agent_profile_from_row, normalize_agent_profile};
use super::{
    format_timestamp, AgentProfile, AgentProfileRemovalImpact, AgentProfileTabReference,
    AutomationDefinition, RuntimeStore, RuntimeStoreError,
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

    pub async fn agent_profile_removal_impact(
        &self,
        profile_id: &str,
        expected_revision: i64,
    ) -> Result<AgentProfileRemovalImpact> {
        let mut connection = self.pool().acquire().await?;
        agent_profile_removal_impact_in(&mut connection, profile_id, expected_revision).await
    }

    /// Removes a profile only when no automation or recoverable tab depends on
    /// it. The OCC check, subordinate cleanup and delete share one immediate
    /// transaction.
    pub async fn remove_agent_profile(
        &self,
        profile_id: &str,
        expected_revision: i64,
    ) -> Result<bool> {
        let mut connection = self.pool().acquire().await?;
        sqlx::query("BEGIN IMMEDIATE")
            .execute(&mut *connection)
            .await?;
        let operation: Result<bool> = async {
            let impact = agent_profile_removal_impact_in(
                &mut connection,
                profile_id,
                expected_revision,
            )
            .await?;
            if !impact.exists {
                return Ok(false);
            }
            if impact.has_blocking_references() {
                anyhow::bail!(RuntimeStoreError::Message(format!(
                    "agent profile removal is blocked by {} reference(s)",
                    impact.automation_ids.len()
                        + impact.execution_policy_run_ids.len()
                        + impact.tabs.len()
                )));
            }
            sqlx::query(
                "DELETE FROM runtimeMetadata WHERE key = 'settings.agents.defaultAgentProfileId' AND trim(value) = ?",
            )
            .bind(profile_id)
            .execute(&mut *connection)
            .await?;
            sqlx::query("DELETE FROM automationAgentPolicies WHERE profileId = ?")
                .bind(profile_id)
                .execute(&mut *connection)
                .await?;
            let result = sqlx::query("DELETE FROM agentProfiles WHERE id = ? AND revision = ?")
                .bind(profile_id)
                .bind(expected_revision)
                .execute(&mut *connection)
                .await?;
            if result.rows_affected() == 0 {
                let current = sqlx::query_scalar::<_, i64>(
                    "SELECT revision FROM agentProfiles WHERE id = ?",
                )
                .bind(profile_id)
                .fetch_optional(&mut *connection)
                .await?;
                return Err(agent_profile_revision_conflict(
                    profile_id,
                    Some(expected_revision),
                    current,
                ));
            }
            Ok(true)
        }
        .await;
        match operation {
            Ok(removed) => {
                sqlx::query("COMMIT").execute(&mut *connection).await?;
                Ok(removed)
            }
            Err(error) => {
                let _ = sqlx::query("ROLLBACK").execute(&mut *connection).await;
                Err(error)
            }
        }
    }
}

pub(super) async fn agent_profile_removal_impact_in(
    connection: &mut SqliteConnection,
    profile_id: &str,
    expected_revision: i64,
) -> Result<AgentProfileRemovalImpact> {
    let profile =
        sqlx::query_as::<_, (i64, String)>("SELECT revision, name FROM agentProfiles WHERE id = ?")
            .bind(profile_id)
            .fetch_optional(&mut *connection)
            .await?;
    let revision = profile.as_ref().map(|(revision, _)| *revision);
    if revision.is_some_and(|current| current != expected_revision) {
        return Err(agent_profile_revision_conflict(
            profile_id,
            Some(expected_revision),
            revision,
        ));
    }
    let is_default = sqlx::query_scalar::<_, Option<String>>(
        "SELECT value FROM runtimeMetadata WHERE key = 'settings.agents.defaultAgentProfileId'",
    )
    .fetch_optional(&mut *connection)
    .await?
    .flatten()
    .is_some_and(|value| value.trim() == profile_id);
    let has_automation_policy = sqlx::query_scalar::<_, i64>(
        "SELECT COUNT(*) FROM automationAgentPolicies WHERE profileId = ?",
    )
    .bind(profile_id)
    .fetch_one(&mut *connection)
    .await?
        > 0;

    let automation_rows = sqlx::query("SELECT dataJson FROM automations")
        .fetch_all(&mut *connection)
        .await?;
    let mut automation_ids = Vec::new();
    for row in automation_rows {
        let encoded: String = row.try_get("dataJson")?;
        let definition: AutomationDefinition = serde_json::from_str(&encoded)?;
        if definition.target.agent_profile_id() == Some(profile_id) {
            automation_ids.push(definition.id);
        }
    }
    automation_ids.sort();

    let mut execution_policy_run_ids = Vec::new();
    if let Some((_, profile_name)) = profile.as_ref() {
        let policy_rows = sqlx::query(
            "SELECT id, execution_policy FROM orchestrationCoordinatorRuns \
             WHERE status NOT IN ('completed', 'failed', 'stopped') \
               AND execution_policy_status IN ('draft', 'approved') \
               AND execution_policy IS NOT NULL",
        )
        .fetch_all(&mut *connection)
        .await?;
        for row in policy_rows {
            let policy: serde_json::Value =
                serde_json::from_str(&row.try_get::<String, _>("execution_policy")?)?;
            let references_profile = policy
                .get("stages")
                .and_then(serde_json::Value::as_array)
                .is_some_and(|stages| {
                    stages.iter().any(|stage| {
                        stage
                            .get("profile")
                            .and_then(serde_json::Value::as_str)
                            .is_some_and(|name| name.eq_ignore_ascii_case(profile_name))
                            || stage
                                .get("fallbacks")
                                .and_then(serde_json::Value::as_array)
                                .is_some_and(|fallbacks| {
                                    fallbacks.iter().any(|fallback| {
                                        fallback.as_str().is_some_and(|name| {
                                            name.eq_ignore_ascii_case(profile_name)
                                        })
                                    })
                                })
                    })
                });
            if references_profile {
                execution_policy_run_ids.push(row.try_get("id")?);
            }
        }
        execution_policy_run_ids.sort();
    }

    let tab_rows = sqlx::query("SELECT id, workspaceId, payloadJson FROM workspaceTabs")
        .fetch_all(&mut *connection)
        .await?;
    let mut tabs = Vec::new();
    for row in tab_rows {
        let payload: serde_json::Value =
            serde_json::from_str(&row.try_get::<String, _>("payloadJson")?)?;
        let references_snapshot = payload
            .pointer("/agentProfileLaunchV1/profile/id")
            .and_then(serde_json::Value::as_str)
            == Some(profile_id);
        let references_legacy = payload
            .get("agentProfileId")
            .and_then(serde_json::Value::as_str)
            == Some(profile_id);
        if references_snapshot || references_legacy {
            tabs.push(AgentProfileTabReference {
                workspace_id: row.try_get("workspaceId")?,
                tab_id: row.try_get("id")?,
            });
        }
    }
    tabs.sort_by(|left, right| {
        left.workspace_id
            .cmp(&right.workspace_id)
            .then_with(|| left.tab_id.cmp(&right.tab_id))
    });

    Ok(AgentProfileRemovalImpact {
        profile_id: profile_id.to_string(),
        exists: revision.is_some(),
        revision,
        is_default,
        automation_ids,
        has_automation_policy,
        execution_policy_run_ids,
        tabs,
    })
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
