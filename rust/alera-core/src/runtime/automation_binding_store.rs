//! The runtime-owned `boundTarget` of reusing automations. Every write edits
//! `automations.dataJson` in place, so binding changes never bump the
//! revision or `updatedAt` that authoring conflicts are checked against.

use anyhow::Result;
use chrono::{DateTime, Utc};
use serde_json::{json, Value};
use sqlx::{Row, SqliteConnection};
use uuid::Uuid;

use super::RuntimeStore;
use super::{format_timestamp, AutomationActor, AutomationActorKind, AutomationBoundTarget};

fn binding_actor() -> AutomationActor {
    AutomationActor {
        kind: AutomationActorKind::ManagedAgent,
        id: None,
        label: Some("Alera Automation Binding".into()),
    }
}

async fn audit(
    connection: &mut SqliteConnection,
    automation_id: &str,
    action: &str,
    details: Value,
) -> Result<()> {
    sqlx::query(
        "INSERT INTO automationAuditEvents (id, automationId, runId, action, actorJson, revision, detailsJson, createdAt) VALUES (?, ?, NULL, ?, ?, NULL, ?, ?)",
    )
    .bind(Uuid::new_v4().to_string())
    .bind(automation_id)
    .bind(action)
    .bind(serde_json::to_string(&binding_actor())?)
    .bind(serde_json::to_string(&details)?)
    .bind(format_timestamp(Utc::now()))
    .execute(connection)
    .await?;
    Ok(())
}

async fn automation_ids(
    connection: &mut SqliteConnection,
    query: &'static str,
    value: &str,
) -> Result<Vec<String>> {
    sqlx::query(query)
        .bind(value)
        .fetch_all(connection)
        .await?
        .into_iter()
        .map(|row| Ok(row.try_get("id")?))
        .collect()
}

/// Forgets the tab, and with it the conversation, of every binding that
/// names `tab_id`. The workspace stays bound.
pub(super) async fn release_bound_tabs_for_tab_in(
    connection: &mut SqliteConnection,
    tab_id: &str,
    reason: &str,
) -> Result<Vec<String>> {
    let ids = automation_ids(
        connection,
        "SELECT id FROM automations WHERE json_extract(dataJson, '$.boundTarget.tabId') = ?",
        tab_id,
    )
    .await?;
    for id in &ids {
        release_tab_in(connection, id, reason).await?;
    }
    Ok(ids)
}

/// Drops every binding to `workspace_id`.
pub(super) async fn clear_bound_targets_for_workspace_in(
    connection: &mut SqliteConnection,
    workspace_id: &str,
    reason: &str,
) -> Result<Vec<String>> {
    let ids = automation_ids(
        connection,
        "SELECT id FROM automations WHERE json_extract(dataJson, '$.boundTarget.workspaceId') = ?",
        workspace_id,
    )
    .await?;
    for id in &ids {
        clear_in(connection, id, reason).await?;
    }
    Ok(ids)
}

async fn release_tab_in(
    connection: &mut SqliteConnection,
    automation_id: &str,
    reason: &str,
) -> Result<bool> {
    let tab: Option<String> = sqlx::query_scalar(
        "SELECT json_extract(dataJson, '$.boundTarget.tabId') FROM automations WHERE id = ?",
    )
    .bind(automation_id)
    .fetch_optional(&mut *connection)
    .await?
    .flatten();
    let Some(tab) = tab else {
        return Ok(false);
    };
    sqlx::query(
        "UPDATE automations SET dataJson = json_remove(dataJson, '$.boundTarget.tabId', '$.boundTarget.conversationId') WHERE id = ?",
    )
    .bind(automation_id)
    .execute(&mut *connection)
    .await?;
    audit(
        connection,
        automation_id,
        "boundTabReleased",
        json!({ "reason": reason, "tabId": tab }),
    )
    .await?;
    Ok(true)
}

async fn clear_in(
    connection: &mut SqliteConnection,
    automation_id: &str,
    reason: &str,
) -> Result<bool> {
    let workspace: Option<String> = sqlx::query_scalar(
        "SELECT json_extract(dataJson, '$.boundTarget.workspaceId') FROM automations WHERE id = ?",
    )
    .bind(automation_id)
    .fetch_optional(&mut *connection)
    .await?
    .flatten();
    let Some(workspace) = workspace else {
        return Ok(false);
    };
    sqlx::query(
        "UPDATE automations SET dataJson = json_remove(dataJson, '$.boundTarget') WHERE id = ?",
    )
    .bind(automation_id)
    .execute(&mut *connection)
    .await?;
    audit(
        connection,
        automation_id,
        "targetUnbound",
        json!({ "reason": reason, "workspaceId": workspace }),
    )
    .await?;
    Ok(true)
}

impl RuntimeStore {
    /// Stores `binding` as the automation's bound target, replacing any
    /// earlier one. Returns false when the automation no longer exists.
    pub async fn bind_automation_target(
        &self,
        automation_id: &str,
        binding: &AutomationBoundTarget,
        reason: &str,
    ) -> Result<bool> {
        let mut transaction = self.pool().begin().await?;
        let updated = sqlx::query(
            "UPDATE automations SET dataJson = json_set(dataJson, '$.boundTarget', json(?)) WHERE id = ?",
        )
        .bind(serde_json::to_string(binding)?)
        .bind(automation_id)
        .execute(&mut *transaction)
        .await?
        .rows_affected()
            > 0;
        if updated {
            audit(
                &mut transaction,
                automation_id,
                "targetBound",
                json!({
                    "reason": reason,
                    "runId": binding.bound_run_id,
                    "workspaceId": binding.workspace_id,
                    "tabId": binding.tab_id,
                    "conversationId": binding.conversation_id,
                }),
            )
            .await?;
        }
        transaction.commit().await?;
        Ok(updated)
    }

    /// Records that `run_id` reached the bound target again.
    pub async fn touch_automation_bound_target(
        &self,
        automation_id: &str,
        run_id: &str,
        at: DateTime<Utc>,
    ) -> Result<bool> {
        Ok(sqlx::query(
            "UPDATE automations SET dataJson = json_set(dataJson, '$.boundTarget.lastRunId', ?, '$.boundTarget.lastVerifiedAt', ?) \
             WHERE id = ? AND json_type(dataJson, '$.boundTarget') = 'object'",
        )
        .bind(run_id)
        .bind(serde_json::to_value(at)?.as_str().unwrap_or_default().to_string())
        .bind(automation_id)
        .execute(self.pool())
        .await?
        .rows_affected()
            > 0)
    }

    /// Keeps the bound workspace but forgets its tab and conversation, so the
    /// next run opens a new tab there. Returns false when no tab was bound.
    pub async fn release_automation_bound_tab(
        &self,
        automation_id: &str,
        reason: &str,
    ) -> Result<bool> {
        let mut transaction = self.pool().begin().await?;
        let released = release_tab_in(&mut transaction, automation_id, reason).await?;
        transaction.commit().await?;
        Ok(released)
    }

    /// Drops the whole binding; the next run creates its target again.
    /// Returns false when nothing was bound.
    pub async fn clear_automation_bound_target(
        &self,
        automation_id: &str,
        reason: &str,
    ) -> Result<bool> {
        let mut transaction = self.pool().begin().await?;
        let cleared = clear_in(&mut transaction, automation_id, reason).await?;
        transaction.commit().await?;
        Ok(cleared)
    }

    /// Releases the tab of every binding that names `tab_id` and returns the
    /// automations it changed.
    pub async fn release_automation_bound_tabs_for_tab(
        &self,
        tab_id: &str,
        reason: &str,
    ) -> Result<Vec<String>> {
        let mut transaction = self.pool().begin().await?;
        let ids = release_bound_tabs_for_tab_in(&mut transaction, tab_id, reason).await?;
        transaction.commit().await?;
        Ok(ids)
    }

    /// Drops every binding to `workspace_id` and returns the automations it
    /// changed.
    pub async fn clear_automation_bound_targets_for_workspace(
        &self,
        workspace_id: &str,
        reason: &str,
    ) -> Result<Vec<String>> {
        let mut transaction = self.pool().begin().await?;
        let ids =
            clear_bound_targets_for_workspace_in(&mut transaction, workspace_id, reason).await?;
        transaction.commit().await?;
        Ok(ids)
    }
}
