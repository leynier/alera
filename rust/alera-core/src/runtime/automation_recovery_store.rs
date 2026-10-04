use super::{AutomationAttempt, AutomationRun, AutomationRunStatus, RuntimeStore};
use anyhow::{anyhow, bail, Result};
use chrono::{DateTime, Duration, Utc};
use serde_json::json;
use sqlx::Row;
use uuid::Uuid;

impl RuntimeStore {
    pub async fn begin_automation_attempt(
        &self,
        id: &str,
        max_attempts: i64,
    ) -> Result<AutomationRun> {
        let boot_id = self.get_metadata("automations.runtimeBootId").await?;
        let mut tx = self.pool().begin().await?;
        sqlx::query("UPDATE automationRuns SET id = id WHERE id = ?")
            .bind(id)
            .execute(&mut *tx)
            .await?;
        let query = format!("{} WHERE id = ?", super::automation_run_store::run_query());
        let row = sqlx::query(sqlx::AssertSqlSafe(query))
            .bind(id)
            .fetch_optional(&mut *tx)
            .await?
            .ok_or_else(|| anyhow!("Automation run not found"))?;
        let mut run = super::automation_run_store::decode_run(row)?;
        let now = Utc::now();
        if run.taken_over
            || run.owner_reserved
            || !matches!(
                run.status,
                AutomationRunStatus::Pending | AutomationRunStatus::Dispatching
            )
            || (run.status == AutomationRunStatus::Dispatching && run.started_at.is_some())
            || run.cancel_requested_at.is_some()
            || run.attempt_count >= max_attempts
            || run.absolute_deadline_at.is_some_and(|at| at <= now)
        {
            bail!("Automation attempt budget or deadline exhausted");
        }
        run.owner_process = None;
        run.owner_boot_id = boot_id;
        run.attempt_count += 1;
        run.status = AutomationRunStatus::Dispatching;
        run.started_at.get_or_insert(now);
        run.absolute_deadline_at
            .get_or_insert(now + Duration::hours(24));
        run.last_heartbeat_at = Some(now);
        run.last_activity_at = Some(now);
        run.retry_after = None;
        run.updated_at = now;
        let attempt = AutomationAttempt {
            id: Uuid::new_v4().to_string(),
            run_id: run.id.clone(),
            number: run.attempt_count,
            launch_kind: Some(
                if run.attempt_count == 1 {
                    "initial"
                } else {
                    "contextRetry"
                }
                .into(),
            ),
            session_id: run.session_id.clone(),
            tab_id: run.tab_id.clone(),
            interruption_code: run.recovery.as_ref().and_then(|r| r.code.clone()),
            last_activity_at: Some(now),
            status: run.status,
            error: None,
            started_at: now,
            finished_at: None,
        };
        run.attempt_id = Some(attempt.id.clone());
        sqlx::query("INSERT INTO automationAttempts (id,runId,attemptNumber,status,dataJson,startedAt,finishedAt) VALUES (?,?,?,?,?,?,NULL)")
            .bind(&attempt.id).bind(id).bind(attempt.number).bind(attempt.status.as_str()).bind(serde_json::to_string(&attempt)?).bind(super::format_timestamp(now)).execute(&mut *tx).await?;
        sqlx::query(
            "UPDATE automationRuns SET status = ?, dataJson = ?, updatedAt = ? WHERE id = ?",
        )
        .bind(run.status.as_str())
        .bind(serde_json::to_string(&run)?)
        .bind(super::format_timestamp(now))
        .bind(id)
        .execute(&mut *tx)
        .await?;
        tx.commit().await?;
        Ok(run)
    }

    pub async fn automation_attempts(&self, run_id: &str) -> Result<Vec<AutomationAttempt>> {
        let rows = sqlx::query(
            "SELECT dataJson FROM automationAttempts WHERE runId = ? ORDER BY attemptNumber",
        )
        .bind(run_id)
        .fetch_all(self.pool())
        .await?;
        rows.into_iter()
            .map(|row| {
                Ok(serde_json::from_str(
                    &row.try_get::<String, _>("dataJson")?,
                )?)
            })
            .collect()
    }

    pub async fn next_automation_run_wakeup(&self) -> Result<Option<DateTime<Utc>>> {
        let mut nearest = None;
        for run in self.list_active_automation_runs().await? {
            let definition = run
                .definition_snapshot
                .clone()
                .or(self.find_automation(&run.automation_id).await?);
            let mut deadlines = vec![
                if run.owner_reserved {
                    None
                } else {
                    run.retry_after
                },
                run.absolute_deadline_at,
                run.cancel_requested_at.map(|at| at + Duration::seconds(30)),
            ];
            if !run.owner_reserved
                && run.status != AutomationRunStatus::WaitingForUser
                && run.status != AutomationRunStatus::Pending
            {
                if let Some(definition) = definition {
                    deadlines.push(
                        run.last_heartbeat_at.or(run.last_activity_at).map(|at| {
                            at + Duration::seconds(definition.inactivity_timeout_seconds)
                        }),
                    );
                }
            }
            deadlines.push(Some(Utc::now() + Duration::seconds(5)));
            for deadline in deadlines.into_iter().flatten() {
                nearest =
                    Some(nearest.map_or(deadline, |current: DateTime<Utc>| current.min(deadline)));
            }
        }
        if !self.reserved_automation_runs().await?.is_empty() {
            let at = Utc::now() + Duration::seconds(5);
            nearest = Some(nearest.map_or(at, |n| n.min(at)));
        }
        Ok(nearest)
    }

    pub async fn reserved_automation_runs(&self) -> Result<Vec<AutomationRun>> {
        let query = format!(
            "{} WHERE json_extract(dataJson, '$.ownerReserved') = 1",
            super::automation_run_store::run_query()
        );
        sqlx::query(sqlx::AssertSqlSafe(query))
            .fetch_all(self.pool())
            .await?
            .into_iter()
            .map(super::automation_run_store::decode_run)
            .collect()
    }

    pub async fn record_automation_runtime_started(&self) -> Result<DateTime<Utc>> {
        let now = Utc::now();
        if let Some(previous) = self.get_metadata("automations.runtimeStartedAt").await? {
            self.set_metadata("automations.previousStartedAt", &previous)
                .await?;
        }
        self.set_metadata(
            "automations.runtimeStartedAt",
            &super::format_timestamp(now),
        )
        .await?;
        self.set_metadata(
            "automations.runtimeStatus",
            &json!({"startedAt":now}).to_string(),
        )
        .await?;
        Ok(now)
    }
}

impl RuntimeStore {
    pub async fn bind_automation_attempt(
        &self,
        run: &AutomationRun,
        launch_kind: &str,
    ) -> Result<()> {
        let Some(id) = run.attempt_id.as_deref() else {
            return Ok(());
        };
        let json: String = sqlx::query_scalar(
            "SELECT dataJson FROM automationAttempts WHERE id = ? AND runId = ?",
        )
        .bind(id)
        .bind(&run.id)
        .fetch_one(self.pool())
        .await?;
        let mut attempt: AutomationAttempt = serde_json::from_str(&json)?;
        attempt.session_id = run.session_id.clone();
        attempt.tab_id = run.tab_id.clone();
        attempt.launch_kind = Some(launch_kind.into());
        attempt.last_activity_at = run.last_activity_at;
        sqlx::query("UPDATE automationAttempts SET dataJson = ? WHERE id = ?")
            .bind(serde_json::to_string(&attempt)?)
            .bind(id)
            .execute(self.pool())
            .await?;
        Ok(())
    }
}
