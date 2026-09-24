use anyhow::{bail, Result};
use chrono::{DateTime, Utc};
use sqlx::Row;

use super::{AutomationRun, RuntimeStore, Workspace};

#[derive(Debug, Clone)]
pub struct AutomationCleanupAttempt {
    pub id: String,
    pub run: AutomationRun,
    pub workspace: Workspace,
}

impl RuntimeStore {
    pub(super) async fn migrate_automation_cleanup_attempts(&self) -> Result<()> {
        sqlx::query("CREATE TABLE IF NOT EXISTS automationSharedCleanupIntents (runId TEXT PRIMARY KEY, runJson TEXT NOT NULL, workspaceId TEXT NOT NULL, instanceId TEXT NOT NULL, workspaceJson TEXT NOT NULL, state TEXT NOT NULL CHECK(state IN ('pending','running','completed','preserved')), attemptId TEXT, readyAt INTEGER NOT NULL, attempts INTEGER NOT NULL DEFAULT 0, lastError TEXT)")
            .execute(self.pool()).await?;
        sqlx::query("CREATE INDEX IF NOT EXISTS automationSharedCleanupDue ON automationSharedCleanupIntents(state, readyAt)")
            .execute(self.pool()).await?;
        Ok(())
    }

    /// An intent retains its original identity and snapshot across retries and restarts.
    pub async fn request_automation_shared_cleanup(
        &self,
        run: &AutomationRun,
        workspace: &Workspace,
        now: DateTime<Utc>,
    ) -> Result<()> {
        let mut tx = self.pool().begin().await?;
        super::automation_shared_workspace_cleanup::validate_cleanup(&mut tx, run, workspace)
            .await?;
        sqlx::query("INSERT INTO automationSharedCleanupIntents (runId, runJson, workspaceId, instanceId, workspaceJson, state, readyAt) VALUES (?, ?, ?, ?, ?, 'pending', ?) ON CONFLICT(runId) DO NOTHING")
            .bind(&run.id).bind(serde_json::to_string(run)?).bind(&workspace.id)
            .bind(&workspace.instance_id).bind(serde_json::to_string(workspace)?)
            .bind(now.timestamp_millis()).execute(&mut *tx).await?;
        let existing: (String, String) = sqlx::query_as(
            "SELECT workspaceId, instanceId FROM automationSharedCleanupIntents WHERE runId = ?",
        )
        .bind(&run.id)
        .fetch_one(&mut *tx)
        .await?;
        if existing != (workspace.id.clone(), workspace.instance_id.clone()) {
            bail!("Automation cleanup intent belongs to a different task instance");
        }
        tx.commit().await?;
        Ok(())
    }

    pub async fn next_automation_shared_cleanup_at(&self) -> Result<Option<DateTime<Utc>>> {
        let timestamp: Option<i64> = sqlx::query_scalar("SELECT MIN(readyAt) FROM automationSharedCleanupIntents WHERE state IN ('pending','running')")
            .fetch_one(self.pool()).await?;
        timestamp
            .map(|value| {
                DateTime::from_timestamp_millis(value)
                    .ok_or_else(|| anyhow::anyhow!("Invalid automation cleanup recovery timestamp"))
            })
            .transpose()
    }

    pub async fn due_automation_shared_cleanups(&self, now: DateTime<Utc>) -> Result<Vec<String>> {
        Ok(sqlx::query_scalar("SELECT runId FROM automationSharedCleanupIntents WHERE state IN ('pending','running') AND readyAt <= ? ORDER BY readyAt, runId LIMIT 8")
            .bind(now.timestamp_millis()).fetch_all(self.pool()).await?)
    }

    pub async fn claim_automation_shared_cleanup(
        &self,
        run_id: &str,
        now: DateTime<Utc>,
    ) -> Result<Option<AutomationCleanupAttempt>> {
        let id = uuid::Uuid::new_v4().to_string();
        // The worker has a 90-second deadline. Its reservation lasts longer so
        // normal scheduler ticks cannot start a competing attempt.
        let row = sqlx::query("UPDATE automationSharedCleanupIntents SET state = 'running', attemptId = ?, readyAt = ?, attempts = attempts + 1 WHERE runId = ? AND state IN ('pending','running') AND readyAt <= ? RETURNING runJson, workspaceJson")
            .bind(&id).bind(now.timestamp_millis() + 120_000).bind(run_id)
            .bind(now.timestamp_millis()).fetch_optional(self.pool()).await?;
        row.map(|row| {
            Ok(AutomationCleanupAttempt {
                id,
                run: serde_json::from_str(row.try_get("runJson")?)?,
                workspace: serde_json::from_str(row.try_get("workspaceJson")?)?,
            })
        })
        .transpose()
    }

    /// Only a receipt for this exact task instance proves completion. A late
    /// worker cannot overwrite a newer attempt's recovery state.
    pub async fn settle_automation_shared_cleanup(
        &self,
        attempt: &AutomationCleanupAttempt,
        retry: bool,
        error: Option<&str>,
        now: DateTime<Utc>,
    ) -> Result<bool> {
        let result = sqlx::query("UPDATE automationSharedCleanupIntents SET state = CASE WHEN EXISTS (SELECT 1 FROM workspaceRetirements r WHERE r.workspaceId = automationSharedCleanupIntents.workspaceId AND r.instanceId = automationSharedCleanupIntents.instanceId) THEN 'completed' WHEN ? THEN 'pending' ELSE 'preserved' END, readyAt = ?, lastError = ? WHERE runId = ? AND attemptId = ? AND state = 'running' AND workspaceId = ? AND instanceId = ?")
            .bind(retry).bind(now.timestamp_millis() + 60_000).bind(error)
            .bind(&attempt.run.id).bind(&attempt.id).bind(&attempt.workspace.id)
            .bind(&attempt.workspace.instance_id).execute(self.pool()).await?;
        Ok(result.rows_affected() == 1)
    }
}

/// Persist the optional cleanup decision with the successful run, before any
/// scheduler callback or history pruning can intervene. Recovery revalidates
/// mutable task state before touching buffers or processes.
pub(super) async fn enqueue_completed_run(
    tx: &mut sqlx::Transaction<'_, sqlx::Sqlite>,
    run: &AutomationRun,
) -> Result<()> {
    use super::{AutomationCleanupPolicy, AutomationDefinition, AutomationRunStatus};
    if run.status != AutomationRunStatus::Success
        || !run.owned_workspace
        || run.taken_over
        || run.cancel_requested_at.is_some()
    {
        return Ok(());
    }
    let Some(workspace_id) = run.workspace_id.as_deref() else {
        return Ok(());
    };
    let definition_json: Option<String> =
        sqlx::query_scalar("SELECT dataJson FROM automations WHERE id = ?")
            .bind(&run.automation_id)
            .fetch_optional(&mut **tx)
            .await?;
    let Some(definition_json) = definition_json else {
        return Ok(());
    };
    let definition: AutomationDefinition = serde_json::from_str(&definition_json)?;
    if definition.cleanup_policy != Some(AutomationCleanupPolicy::OnSuccess)
        || definition.target.project_checkout().is_none()
    {
        return Ok(());
    }
    let allocation: Option<String> = sqlx::query_scalar("SELECT workspaceJson FROM automationSharedWorkspaceAllocations WHERE runId = ? AND workspaceId = ?")
        .bind(&run.id).bind(workspace_id).fetch_optional(&mut **tx).await?;
    let Some(allocation) = allocation else {
        return Ok(());
    };
    let workspace: Workspace = serde_json::from_str(&allocation)?;
    if definition.target.project_checkout()
        != Some((workspace.project_id.as_str(), workspace.host_id.as_str()))
    {
        return Ok(());
    }
    sqlx::query("INSERT INTO automationSharedCleanupIntents (runId, runJson, workspaceId, instanceId, workspaceJson, state, readyAt) VALUES (?, ?, ?, ?, ?, 'pending', ?) ON CONFLICT(runId) DO NOTHING")
        .bind(&run.id).bind(serde_json::to_string(run)?).bind(&workspace.id)
        .bind(&workspace.instance_id).bind(allocation).bind(Utc::now().timestamp_millis())
        .execute(&mut **tx).await?;
    Ok(())
}
