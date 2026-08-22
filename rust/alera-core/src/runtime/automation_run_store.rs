use anyhow::{anyhow, bail, Result};
use chrono::{DateTime, Utc};
use sqlx::{sqlite::SqliteRow, Row};
use uuid::Uuid;

use super::{
    format_timestamp, parse_timestamp, AutomationActor, AutomationDefinition, AutomationOccurrence,
    AutomationRun, AutomationRunStatus, AutomationRunTrigger, AutomationTargetIdentity,
    RuntimeStore,
};

#[path = "automation_run_audit_store.rs"]
mod automation_run_audit_store;
#[path = "automation_run_lifecycle_store.rs"]
mod automation_run_lifecycle_store;

fn decode_run(row: SqliteRow) -> Result<AutomationRun> {
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

fn run_query() -> &'static str {
    "SELECT status, runNumber, scheduledAt, dataJson, createdAt, updatedAt, finishedAt FROM automationRuns"
}

impl RuntimeStore {
    pub async fn count_automation_occurrences(&self, automation_id: &str) -> Result<i64> {
        Ok(sqlx::query(
            "SELECT COUNT(*) AS count FROM automationOccurrences WHERE automationId = ? AND occurrenceKey NOT LIKE 'manual|%'",
        )
        .bind(automation_id)
        .fetch_one(self.pool())
        .await?
        .try_get("count")?)
    }

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

    pub async fn claim_automation_occurrence(
        &self,
        occurrence: &AutomationOccurrence,
    ) -> Result<bool> {
        let result = sqlx::query(
            "INSERT INTO automationOccurrences (automationId, occurrenceKey, scheduledAt, claimedAt) \
             VALUES (?, ?, ?, ?) ON CONFLICT(automationId, occurrenceKey) DO NOTHING",
        )
        .bind(&occurrence.automation_id)
        .bind(&occurrence.key)
        .bind(format_timestamp(occurrence.scheduled_at))
        .bind(format_timestamp(Utc::now()))
        .execute(self.pool())
        .await?;
        Ok(result.rows_affected() == 1)
    }

    pub async fn create_automation_run(
        &self,
        definition: &AutomationDefinition,
        occurrence: &AutomationOccurrence,
        trigger: AutomationRunTrigger,
    ) -> Result<AutomationRun> {
        let now = Utc::now();
        let number: i64 = sqlx::query(
            "SELECT COALESCE(MAX(runNumber), 0) + 1 AS nextNumber FROM automationRuns WHERE automationId = ?",
        )
        .bind(&definition.id)
        .fetch_one(self.pool())
        .await?
        .try_get("nextNumber")?;
        let run = AutomationRun {
            id: Uuid::new_v4().to_string(),
            automation_id: definition.id.clone(),
            number,
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
        };
        self.insert_automation_run(&run).await?;
        Ok(run)
    }

    pub async fn bind_automation_run(
        &self,
        id: &str,
        actor: &AutomationActor,
        target_identity: AutomationTargetIdentity,
    ) -> Result<AutomationRun> {
        if target_identity.is_empty() {
            bail!("automation run target identity is required");
        }
        let mut run = self
            .find_automation_run(id)
            .await?
            .ok_or_else(|| anyhow!("automation run not found: {id}"))?;
        if run.status.is_final() {
            bail!("automation run is already final: {id}");
        }
        run.actor_kind = Some(actor.kind);
        run.actor_id = actor.id.clone();
        run.target_identity = Some(target_identity);
        run.updated_at = Utc::now();
        self.save_automation_run(&run).await
    }

    pub async fn set_automation_run_target_identity(
        &self,
        id: &str,
        target_identity: AutomationTargetIdentity,
    ) -> Result<AutomationRun> {
        if target_identity.is_empty() {
            bail!("automation run target identity is required");
        }
        let mut run = self
            .find_automation_run(id)
            .await?
            .ok_or_else(|| anyhow!("automation run not found: {id}"))?;
        if run.status.is_final() {
            bail!("automation run is already final: {id}");
        }
        run.target_identity = Some(target_identity);
        run.updated_at = Utc::now();
        self.save_automation_run(&run).await
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

    pub async fn insert_automation_run(&self, run: &AutomationRun) -> Result<()> {
        sqlx::query(
            "INSERT INTO automationRuns (id, automationId, runNumber, occurrenceKey, scheduledAt, trigger, status, dataJson, createdAt, updatedAt, finishedAt) \
             VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)",
        )
        .bind(&run.id)
        .bind(&run.automation_id)
        .bind(run.number)
        .bind(&run.occurrence_key)
        .bind(format_timestamp(run.scheduled_at))
        .bind(run.trigger.as_str())
        .bind(run.status.as_str())
        .bind(serde_json::to_string(run)?)
        .bind(format_timestamp(run.created_at))
        .bind(format_timestamp(run.updated_at))
        .bind(run.finished_at.map(format_timestamp))
        .execute(self.pool())
        .await?;
        Ok(())
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
                "{} WHERE automationId = ? ORDER BY createdAt DESC LIMIT ?",
                run_query()
            )
        } else {
            format!("{} ORDER BY createdAt DESC LIMIT ?", run_query())
        };
        let mut request = sqlx::query(sqlx::AssertSqlSafe(query));
        if let Some(automation_id) = automation_id {
            request = request.bind(automation_id);
        }
        let rows = request.bind(limit).fetch_all(self.pool()).await?;
        rows.into_iter().map(decode_run).collect()
    }

    pub async fn save_automation_run(&self, run: &AutomationRun) -> Result<AutomationRun> {
        let existing = self
            .find_automation_run(&run.id)
            .await?
            .ok_or_else(|| anyhow!("automation run not found: {}", run.id))?;
        if existing.status.is_final() && existing.status != run.status {
            bail!("automation run is already final: {}", run.id);
        }
        sqlx::query(
            "UPDATE automationRuns SET status = ?, dataJson = ?, updatedAt = ?, finishedAt = ? WHERE id = ?",
        )
        .bind(run.status.as_str())
        .bind(serde_json::to_string(run)?)
        .bind(format_timestamp(run.updated_at))
        .bind(run.finished_at.map(format_timestamp))
        .bind(&run.id)
        .execute(self.pool())
        .await?;
        self.find_automation_run(&run.id)
            .await?
            .ok_or_else(|| anyhow!("automation run disappeared after save"))
    }

    pub async fn count_automation_failure_streak(&self, automation_id: &str) -> Result<i64> {
        let runs = self.list_automation_runs(Some(automation_id), 1000).await?;
        Ok(runs
            .into_iter()
            .filter(|run| run.trigger == AutomationRunTrigger::Scheduled)
            .take_while(|run| run.status.counts_as_failure())
            .count() as i64)
    }

    pub async fn list_active_automation_runs(&self) -> Result<Vec<AutomationRun>> {
        let runs = self.list_automation_runs(None, 1000).await?;
        Ok(runs
            .into_iter()
            .filter(|run| !run.status.is_final())
            .collect())
    }
}

#[cfg(test)]
#[path = "automation_run_store_tests.rs"]
mod tests;
