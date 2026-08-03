use anyhow::{anyhow, bail, Result};
use chrono::{DateTime, Utc};
use sqlx::Row;
use uuid::Uuid;

use super::super::{
    format_timestamp, AutomationActor, AutomationActorKind, AutomationAttempt, AutomationRun,
    AutomationRunStatus, RuntimeStore,
};

impl RuntimeStore {
    pub async fn complete_automation_run(
        &self,
        id: &str,
        status: AutomationRunStatus,
        summary: Option<String>,
        error: Option<String>,
        actor: AutomationActor,
    ) -> Result<AutomationRun> {
        if !matches!(
            status,
            AutomationRunStatus::Success
                | AutomationRunStatus::Failure
                | AutomationRunStatus::Blocked
        ) {
            bail!("automation complete requires success, failure, or blocked");
        }
        if summary
            .as_deref()
            .is_none_or(|value| value.trim().is_empty())
        {
            bail!("automation completion summary is required");
        }
        let mut run = self
            .find_automation_run(id)
            .await?
            .ok_or_else(|| anyhow!("automation run not found: {id}"))?;
        if run.status.is_final() {
            return Ok(run);
        }
        let now = Utc::now();
        run.status = status;
        run.summary = summary;
        run.error = error;
        run.finished_at = Some(now);
        run.updated_at = now;
        let saved = self.save_automation_run(&run).await?;
        self.finish_latest_automation_attempt(id, status, run.error.clone())
            .await?;
        self.archive_one_time_automation_if_final(&run.automation_id, actor.clone())
            .await?;
        self.insert_automation_audit_event(
            Some(&run.automation_id),
            Some(&run.id),
            "complete",
            actor,
            None,
            serde_json::json!({ "status": status.as_str() }),
        )
        .await?;
        self.prune_automation_runs(&run.automation_id, now).await?;
        Ok(saved)
    }

    pub async fn heartbeat_automation_run(
        &self,
        id: &str,
        actor: AutomationActor,
    ) -> Result<AutomationRun> {
        let mut run = self
            .find_automation_run(id)
            .await?
            .ok_or_else(|| anyhow!("automation run not found: {id}"))?;
        if run.status.is_final() {
            bail!("automation run is already final: {id}");
        }
        let now = Utc::now();
        run.last_heartbeat_at = Some(now);
        run.updated_at = now;
        let saved = self.save_automation_run(&run).await?;
        self.insert_automation_audit_event(
            Some(&run.automation_id),
            Some(&run.id),
            "heartbeat",
            actor,
            None,
            serde_json::json!({}),
        )
        .await?;
        Ok(saved)
    }

    pub async fn set_automation_run_waiting(
        &self,
        id: &str,
        actor: AutomationActor,
        waiting: bool,
    ) -> Result<AutomationRun> {
        let mut run = self
            .find_automation_run(id)
            .await?
            .ok_or_else(|| anyhow!("automation run not found: {id}"))?;
        if run.status.is_final() {
            bail!("automation run is already final: {id}");
        }
        if !waiting && run.status != AutomationRunStatus::WaitingForUser {
            bail!("automation run is not waiting for user input: {id}");
        }
        run.status = if waiting {
            AutomationRunStatus::WaitingForUser
        } else {
            AutomationRunStatus::Dispatched
        };
        run.updated_at = Utc::now();
        let saved = self.save_automation_run(&run).await?;
        self.insert_automation_audit_event(
            Some(&run.automation_id),
            Some(&run.id),
            if waiting { "waiting" } else { "waitingResumed" },
            actor,
            None,
            serde_json::json!({}),
        )
        .await?;
        Ok(saved)
    }

    pub async fn extend_waiting_automation_run(
        &self,
        id: &str,
        until: DateTime<Utc>,
        actor: AutomationActor,
    ) -> Result<AutomationRun> {
        let mut run = self
            .find_automation_run(id)
            .await?
            .ok_or_else(|| anyhow!("automation run not found: {id}"))?;
        if run.status != AutomationRunStatus::WaitingForUser {
            bail!("automation run is not waiting for user input: {id}");
        }
        run.waiting_extension_until = Some(until);
        run.absolute_deadline_at = Some(
            run.absolute_deadline_at
                .map_or(until, |current| current.max(until)),
        );
        run.updated_at = Utc::now();
        let saved = self.save_automation_run(&run).await?;
        self.insert_automation_audit_event(
            Some(&run.automation_id),
            Some(&run.id),
            "waitingExtended",
            actor,
            None,
            serde_json::json!({ "until": until }),
        )
        .await?;
        Ok(saved)
    }

    pub async fn request_automation_cancel(
        &self,
        id: &str,
        actor: AutomationActor,
    ) -> Result<AutomationRun> {
        let mut run = self
            .find_automation_run(id)
            .await?
            .ok_or_else(|| anyhow!("automation run not found: {id}"))?;
        if run.status.is_final() {
            return Ok(run);
        }
        run.cancel_requested_at.get_or_insert(Utc::now());
        run.updated_at = Utc::now();
        let saved = self.save_automation_run(&run).await?;
        self.insert_automation_audit_event(
            Some(&run.automation_id),
            Some(&run.id),
            "cancelRequested",
            actor,
            None,
            serde_json::json!({}),
        )
        .await?;
        Ok(saved)
    }

    pub async fn mark_automation_run_taken_over(
        &self,
        id: &str,
        actor: AutomationActor,
    ) -> Result<AutomationRun> {
        let mut run = self
            .find_automation_run(id)
            .await?
            .ok_or_else(|| anyhow!("automation run not found: {id}"))?;
        if run.status.is_final() || run.taken_over {
            return Ok(run);
        }
        run.taken_over = true;
        run.updated_at = Utc::now();
        let saved = self.save_automation_run(&run).await?;
        self.insert_automation_audit_event(
            Some(&run.automation_id),
            Some(&run.id),
            "takenOver",
            actor,
            None,
            serde_json::json!({ "reason": "user attached to automation-owned tab" }),
        )
        .await?;
        Ok(saved)
    }

    pub async fn update_automation_run_status(
        &self,
        id: &str,
        status: AutomationRunStatus,
        error: Option<String>,
    ) -> Result<AutomationRun> {
        let mut run = self
            .find_automation_run(id)
            .await?
            .ok_or_else(|| anyhow!("automation run not found: {id}"))?;
        run.status = status;
        run.error = error;
        run.updated_at = Utc::now();
        if status.is_final() {
            run.finished_at = Some(run.updated_at);
        }
        let saved = self.save_automation_run(&run).await?;
        if status.is_final() {
            self.finish_latest_automation_attempt(id, status, run.error.clone())
                .await?;
            let _ = self
                .archive_one_time_automation_if_final(
                    &run.automation_id,
                    AutomationActor {
                        kind: AutomationActorKind::ManagedAgent,
                        id: run.actor_id.clone(),
                        label: Some("one-time automation finalizer".to_string()),
                    },
                )
                .await?;
        }
        Ok(saved)
    }

    pub async fn schedule_automation_retry(
        &self,
        id: &str,
        retry_after: DateTime<Utc>,
        error: String,
        actor: AutomationActor,
    ) -> Result<AutomationRun> {
        let mut run = self
            .find_automation_run(id)
            .await?
            .ok_or_else(|| anyhow!("automation run not found: {id}"))?;
        if run.status.is_final() {
            bail!("automation run is already final: {id}");
        }
        run.status = AutomationRunStatus::Pending;
        run.error = Some(error.clone());
        run.retry_after = Some(retry_after);
        run.finished_at = None;
        run.updated_at = Utc::now();
        let saved = self.save_automation_run(&run).await?;
        self.finish_latest_automation_attempt(
            id,
            AutomationRunStatus::Failure,
            Some(error.clone()),
        )
        .await?;
        self.insert_automation_audit_event(
            Some(&run.automation_id),
            Some(id),
            "retryScheduled",
            actor,
            None,
            serde_json::json!({ "retryAt": retry_after, "error": error }),
        )
        .await?;
        Ok(saved)
    }

    pub async fn insert_automation_attempt(
        &self,
        run_id: &str,
        status: AutomationRunStatus,
        error: Option<String>,
    ) -> Result<AutomationAttempt> {
        let number: i64 = sqlx::query(
            "SELECT COALESCE(MAX(attemptNumber), 0) + 1 AS nextNumber FROM automationAttempts WHERE runId = ?",
        )
        .bind(run_id)
        .fetch_one(self.pool())
        .await?
        .try_get("nextNumber")?;
        let attempt = AutomationAttempt {
            id: Uuid::new_v4().to_string(),
            run_id: run_id.to_string(),
            number,
            status,
            error,
            started_at: Utc::now(),
            finished_at: None,
        };
        sqlx::query(
            "INSERT INTO automationAttempts (id, runId, attemptNumber, status, dataJson, startedAt, finishedAt) VALUES (?, ?, ?, ?, ?, ?, NULL)",
        )
        .bind(&attempt.id)
        .bind(&attempt.run_id)
        .bind(attempt.number)
        .bind(attempt.status.as_str())
        .bind(serde_json::to_string(&attempt)?)
        .bind(format_timestamp(attempt.started_at))
        .execute(self.pool())
        .await?;
        Ok(attempt)
    }

    async fn finish_latest_automation_attempt(
        &self,
        run_id: &str,
        status: AutomationRunStatus,
        error: Option<String>,
    ) -> Result<()> {
        let Some(row) = sqlx::query(
            "SELECT id, dataJson FROM automationAttempts WHERE runId = ? ORDER BY attemptNumber DESC LIMIT 1",
        )
        .bind(run_id)
        .fetch_optional(self.pool())
        .await?
        else {
            return Ok(());
        };
        let id: String = row.try_get("id")?;
        let mut attempt: AutomationAttempt =
            serde_json::from_str(&row.try_get::<String, _>("dataJson")?)?;
        attempt.status = status;
        attempt.error = error;
        attempt.finished_at = Some(Utc::now());
        sqlx::query(
            "UPDATE automationAttempts SET status = ?, dataJson = ?, finishedAt = ? WHERE id = ?",
        )
        .bind(status.as_str())
        .bind(serde_json::to_string(&attempt)?)
        .bind(format_timestamp(attempt.finished_at.unwrap()))
        .bind(id)
        .execute(self.pool())
        .await?;
        Ok(())
    }
}
