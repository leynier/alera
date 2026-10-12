use anyhow::{anyhow, bail, Result};
use chrono::{DateTime, Utc};
use sqlx::{sqlite::SqliteRow, Row};
use uuid::Uuid;

use super::{
    format_timestamp, parse_timestamp, AutomationActor, AutomationDefinition, AutomationOccurrence,
    AutomationRun, AutomationRunStatus, AutomationRunTrigger, AutomationTargetIdentity,
    RuntimeStore,
};

#[path = "automation_shared_workspace_store.rs"]
mod automation_shared_workspace_store;

#[path = "automation_run_audit_store.rs"]
mod automation_run_audit_store;
#[path = "automation_run_lifecycle_store.rs"]
mod automation_run_lifecycle_store;

pub(super) fn decode_run(row: SqliteRow) -> Result<AutomationRun> {
    let data: String = row.try_get("dataJson")?;
    let mut run: AutomationRun = serde_json::from_str(&data)?;
    run.status = AutomationRunStatus::from_db(&row.try_get::<String, _>("status")?);
    run.number = row.try_get("runNumber")?;
    run.scheduled_at = parse_timestamp(&row.try_get::<String, _>("scheduledAt")?);
    run.created_at = parse_timestamp(&row.try_get::<String, _>("createdAt")?);
    run.updated_at = parse_timestamp(&row.try_get::<String, _>("updatedAt")?);
    run.finished_at = row
        .try_get::<Option<String>, _>("finishedAt")?
        .map(|value| parse_timestamp(&value));
    Ok(run)
}

pub(super) fn run_query() -> &'static str {
    "SELECT status, runNumber, scheduledAt, dataJson, createdAt, updatedAt, finishedAt FROM automationRuns"
}

impl RuntimeStore {
    /// Counts scheduled executions that were actually admitted to the run
    /// lifecycle. Durable occurrence claims are intentionally not used here:
    /// misfires, overlap skips, queue-cap skips, and precheck skips must not
    /// consume a definition's scheduled-run limit.
    pub async fn count_scheduled_automation_executions(&self, automation_id: &str) -> Result<i64> {
        Ok(sqlx::query(
            "SELECT COUNT(*) AS count FROM automationRuns WHERE automationId = ? AND trigger = 'scheduled' AND status NOT IN ('precheckSkipped', 'misfireSkipped', 'overlapSkipped', 'queueLimitSkipped')",
        )
        .bind(automation_id)
        .fetch_one(self.pool())
        .await?
        .try_get("count")?)
    }

    pub async fn latest_automation_occurrence(
        &self,
        automation_id: &str,
    ) -> Result<Option<DateTime<Utc>>> {
        let row = sqlx::query(
            "SELECT scheduledAt FROM automationOccurrences WHERE automationId = ? AND occurrenceKey NOT LIKE 'manual|%' ORDER BY scheduledAt DESC LIMIT 1",
        )
        .bind(automation_id)
        .fetch_optional(self.pool())
        .await?;
        match row {
            Some(row) => Ok(Some(parse_timestamp(
                &row.try_get::<String, _>("scheduledAt")?,
            ))),
            None => Ok(None),
        }
    }

    pub async fn create_automation_run(
        &self,
        definition: &AutomationDefinition,
        occurrence: &AutomationOccurrence,
        trigger: AutomationRunTrigger,
    ) -> Result<AutomationRun> {
        self.admit_automation_run(definition, occurrence, trigger, false)
            .await?
            .ok_or_else(|| anyhow!("automation occurrence already admitted"))
    }

    pub async fn admit_automation_run(
        &self,
        definition: &AutomationDefinition,
        occurrence: &AutomationOccurrence,
        trigger: AutomationRunTrigger,
        claim: bool,
    ) -> Result<Option<AutomationRun>> {
        let mut tx = self.pool().begin().await?;
        if claim {
            let claimed = sqlx::query("INSERT INTO automationOccurrences (automationId, occurrenceKey, scheduledAt, claimedAt) VALUES (?, ?, ?, ?) ON CONFLICT(automationId, occurrenceKey) DO NOTHING")
                .bind(&definition.id).bind(&occurrence.key).bind(format_timestamp(occurrence.scheduled_at)).bind(format_timestamp(Utc::now())).execute(&mut *tx).await?;
            if claimed.rows_affected() == 0 {
                tx.rollback().await?;
                return Ok(None);
            }
        } else {
            sqlx::query("UPDATE automations SET id = id WHERE id = ?")
                .bind(&definition.id)
                .execute(&mut *tx)
                .await?;
        }
        let number: i64 = sqlx::query("SELECT COALESCE(MAX(runNumber), 0) + 1 AS n FROM automationRuns WHERE automationId = ?")
            .bind(&definition.id).fetch_one(&mut *tx).await?.try_get("n")?;
        let run = new_run(definition, occurrence, trigger, number);
        sqlx::query("INSERT INTO automationRuns (id,automationId,runNumber,occurrenceKey,scheduledAt,trigger,status,dataJson,createdAt,updatedAt,finishedAt) VALUES (?,?,?,?,?,?,?,?,?,?,NULL)")
            .bind(&run.id).bind(&run.automation_id).bind(run.number).bind(&run.occurrence_key).bind(format_timestamp(run.scheduled_at))
            .bind(run.trigger.as_str()).bind(run.status.as_str()).bind(serde_json::to_string(&run)?)
            .bind(format_timestamp(run.created_at)).bind(format_timestamp(run.updated_at)).execute(&mut *tx).await?;
        tx.commit().await?;
        Ok(Some(run))
    }

    pub async fn verify_automation_run_identity(
        &self,
        id: &str,
        actor: &AutomationActor,
        target_identity: &AutomationTargetIdentity,
    ) -> Result<AutomationRun> {
        let run = self
            .find_automation_run(id)
            .await?
            .ok_or_else(|| anyhow!("automation run not found: {id}"))?;
        if run.actor_kind != Some(actor.kind)
            || run.actor_id.as_deref() != actor.id.as_deref()
            || run
                .target_identity
                .as_ref()
                .is_none_or(|bound| !bound.matches(target_identity))
        {
            bail!("automation run target identity does not match the live run");
        }
        Ok(run)
    }

    pub async fn verify_automation_run_target(
        &self,
        id: &str,
        target_identity: &AutomationTargetIdentity,
    ) -> Result<AutomationRun> {
        let run = self
            .find_automation_run(id)
            .await?
            .ok_or_else(|| anyhow!("automation run not found: {id}"))?;
        if run
            .target_identity
            .as_ref()
            .is_none_or(|bound| !bound.matches(target_identity))
        {
            bail!("automation run target identity does not match the live run");
        }
        Ok(run)
    }

    pub async fn find_automation_run(&self, id: &str) -> Result<Option<AutomationRun>> {
        sqlx::query(sqlx::AssertSqlSafe(format!("{} WHERE id = ?", run_query())))
            .bind(id)
            .fetch_optional(self.pool())
            .await?
            .map(decode_run)
            .transpose()
    }

    pub async fn list_automation_runs(
        &self,
        automation_id: Option<&str>,
        limit: i64,
    ) -> Result<Vec<AutomationRun>> {
        let limit = limit.clamp(1, 1000);
        let query = if automation_id.is_some() {
            format!(
                "{} WHERE automationId = ? ORDER BY createdAt DESC, runNumber DESC LIMIT ?",
                run_query()
            )
        } else {
            format!(
                "{} ORDER BY createdAt DESC, rowid DESC LIMIT ?",
                run_query()
            )
        };
        let mut request = sqlx::query(sqlx::AssertSqlSafe(query));
        if let Some(automation_id) = automation_id {
            request = request.bind(automation_id);
        }
        let rows = request.bind(limit).fetch_all(self.pool()).await?;
        rows.into_iter().map(decode_run).collect()
    }

    /// The error of the newest run that recorded one.
    pub async fn latest_automation_run_error(&self, automation_id: &str) -> Result<Option<String>> {
        Ok(sqlx::query(
            "SELECT json_extract(dataJson, '$.error') AS error FROM automationRuns WHERE automationId = ? AND json_extract(dataJson, '$.error') IS NOT NULL ORDER BY createdAt DESC, runNumber DESC LIMIT 1",
        )
        .bind(automation_id)
        .fetch_optional(self.pool())
        .await?
        .map(|row| row.try_get("error"))
        .transpose()?)
    }

    pub async fn save_automation_run(&self, run: &AutomationRun) -> Result<AutomationRun> {
        let existing = self
            .find_automation_run(&run.id)
            .await?
            .ok_or_else(|| anyhow!("automation run not found: {}", run.id))?;
        if existing.status.is_final() && existing.status != run.status {
            bail!("automation run is already final: {}", run.id);
        }
        let mut tx = self.pool().begin().await?;
        sqlx::query(
            "UPDATE automationRuns SET status = ?, dataJson = ?, updatedAt = ?, finishedAt = ? WHERE id = ?",
        )
        .bind(run.status.as_str())
        .bind(serde_json::to_string(run)?)
        .bind(format_timestamp(run.updated_at))
        .bind(run.finished_at.map(format_timestamp))
        .bind(&run.id)
        .execute(&mut *tx)
        .await?;
        let query = format!("{} WHERE id = ?", run_query());
        let saved = decode_run(
            sqlx::query(sqlx::AssertSqlSafe(query))
                .bind(&run.id)
                .fetch_one(&mut *tx)
                .await?,
        )?;
        if existing.status != AutomationRunStatus::Success {
            super::automation_cleanup_attempt_store::enqueue_completed_run(&mut tx, &saved).await?;
        }
        tx.commit().await?;
        Ok(saved)
    }

    /// Counts consecutive failed scheduled runs, newest first. Reading stops at
    /// `threshold` (at most 10) because the circuit breaker only compares
    /// the streak with it.
    pub async fn count_automation_failure_streak(
        &self,
        automation_id: &str,
        threshold: i64,
    ) -> Result<i64> {
        let rows = sqlx::query(
            "SELECT status FROM automationRuns WHERE automationId = ? AND trigger = 'scheduled' ORDER BY createdAt DESC, runNumber DESC LIMIT ?",
        )
        .bind(automation_id)
        .bind(threshold.clamp(1, 10))
        .fetch_all(self.pool())
        .await?;
        let mut streak = 0;
        for row in rows {
            if !AutomationRunStatus::from_db(&row.try_get::<String, _>("status")?)
                .counts_as_failure()
            {
                break;
            }
            streak += 1;
        }
        Ok(streak)
    }

    /// Claims scheduled occurrences that will never run, without run rows, so
    /// the schedule cursor moves past them. Returns how many were new.
    pub async fn claim_skipped_automation_occurrences(
        &self,
        automation_id: &str,
        occurrences: &[AutomationOccurrence],
    ) -> Result<u64> {
        let mut tx = self.pool().begin().await?;
        let claimed_at = format_timestamp(Utc::now());
        let mut claimed = 0;
        for occurrence in occurrences {
            claimed += sqlx::query("INSERT INTO automationOccurrences (automationId, occurrenceKey, scheduledAt, claimedAt) VALUES (?, ?, ?, ?) ON CONFLICT(automationId, occurrenceKey) DO NOTHING")
                .bind(automation_id)
                .bind(&occurrence.key)
                .bind(format_timestamp(occurrence.scheduled_at))
                .bind(&claimed_at)
                .execute(&mut *tx)
                .await?
                .rows_affected();
        }
        tx.commit().await?;
        Ok(claimed)
    }

    pub async fn list_active_automation_runs(&self) -> Result<Vec<AutomationRun>> {
        let query = format!("{} WHERE status NOT IN ('precheckSkipped','misfireSkipped','overlapSkipped','queueLimitSkipped','success','failure','blocked','timeout','cancelled') ORDER BY createdAt", run_query());
        sqlx::query(sqlx::AssertSqlSafe(query))
            .fetch_all(self.pool())
            .await?
            .into_iter()
            .map(decode_run)
            .collect()
    }
}

#[cfg(test)]
#[path = "automation_run_store_tests.rs"]
mod tests;

#[cfg(test)]
#[path = "project_automation_dependencies_tests.rs"]
mod project_dependency_tests;

fn new_run(
    definition: &AutomationDefinition,
    occurrence: &AutomationOccurrence,
    trigger: AutomationRunTrigger,
    number: i64,
) -> AutomationRun {
    let now = Utc::now();
    AutomationRun {
        id: Uuid::new_v4().to_string(),
        automation_id: definition.id.clone(),
        number,
        definition_revision: Some(definition.revision),
        definition_snapshot: Some(definition.clone()),
        attempt_id: None,
        native_conversation_id: None,
        recovery: None,
        last_activity_at: None,
        continue_from_run_id: None,
        owner_process: None,
        owner_boot_id: None,
        owner_reserved: false,
        occurrence_key: occurrence.key.clone(),
        scheduled_at: occurrence.scheduled_at,
        trigger,
        actor_kind: None,
        actor_id: None,
        target_identity: None,
        overlap_policy: None,
        precheck: None,
        status: AutomationRunStatus::Pending,
        summary: None,
        error: None,
        rendered_prompt: None,
        reuse: None,
        workspace_id: definition.target.workspace_id().map(str::to_string),
        tab_id: None,
        setup_tab_id: None,
        workspace_branch: None,
        session_id: None,
        owned_workspace: false,
        owned_tab: false,
        taken_over: false,
        attempt_count: 0,
        started_at: None,
        last_heartbeat_at: None,
        absolute_deadline_at: None,
        waiting_extension_until: None,
        cancel_requested_at: None,
        retry_after: None,
        finished_at: None,
        created_at: now,
        updated_at: now,
    }
}
