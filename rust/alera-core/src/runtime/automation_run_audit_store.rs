use anyhow::Result;
use chrono::{DateTime, Duration, Utc};
use sqlx::Row;
use uuid::Uuid;

use super::super::{
    format_timestamp, parse_timestamp, AutomationActor, AutomationAuditEvent, RuntimeStore,
};

impl RuntimeStore {
    pub async fn insert_automation_audit_event(
        &self,
        automation_id: Option<&str>,
        run_id: Option<&str>,
        action: &str,
        actor: AutomationActor,
        revision: Option<i64>,
        details: serde_json::Value,
    ) -> Result<AutomationAuditEvent> {
        let event = AutomationAuditEvent {
            id: Uuid::new_v4().to_string(),
            automation_id: automation_id.map(str::to_string),
            run_id: run_id.map(str::to_string),
            action: action.to_string(),
            actor,
            revision,
            details,
            created_at: Utc::now(),
        };
        sqlx::query(
            "INSERT INTO automationAuditEvents (id, automationId, runId, action, actorJson, revision, detailsJson, createdAt) VALUES (?, ?, ?, ?, ?, ?, ?, ?)",
        )
        .bind(&event.id)
        .bind(&event.automation_id)
        .bind(&event.run_id)
        .bind(&event.action)
        .bind(serde_json::to_string(&event.actor)?)
        .bind(event.revision)
        .bind(serde_json::to_string(&event.details)?)
        .bind(format_timestamp(event.created_at))
        .execute(self.pool())
        .await?;
        Ok(event)
    }

    pub async fn list_automation_audit_events(
        &self,
        automation_id: Option<&str>,
        limit: i64,
    ) -> Result<Vec<AutomationAuditEvent>> {
        let limit = limit.clamp(1, 1000);
        let query = if automation_id.is_some() {
            "SELECT id, automationId, runId, action, actorJson, revision, detailsJson, createdAt FROM automationAuditEvents WHERE automationId = ? ORDER BY createdAt DESC LIMIT ?"
        } else {
            "SELECT id, automationId, runId, action, actorJson, revision, detailsJson, createdAt FROM automationAuditEvents ORDER BY createdAt DESC LIMIT ?"
        };
        let mut request = sqlx::query(query);
        if let Some(automation_id) = automation_id {
            request = request.bind(automation_id);
        }
        let rows = request.bind(limit).fetch_all(self.pool()).await?;
        rows.into_iter()
            .map(|row| {
                Ok(AutomationAuditEvent {
                    id: row.try_get("id")?,
                    automation_id: row.try_get("automationId")?,
                    run_id: row.try_get("runId")?,
                    action: row.try_get("action")?,
                    actor: serde_json::from_str(&row.try_get::<String, _>("actorJson")?)?,
                    revision: row.try_get("revision")?,
                    details: serde_json::from_str(&row.try_get::<String, _>("detailsJson")?)?,
                    created_at: parse_timestamp(&row.try_get::<String, _>("createdAt")?),
                })
            })
            .collect()
    }

    pub(super) async fn prune_automation_runs(
        &self,
        automation_id: &str,
        now: DateTime<Utc>,
    ) -> Result<()> {
        let settings = self.automation_settings().await?;
        self.prune_automation_runs_with_limits(automation_id, now, settings.run_retention_days)
            .await
    }

    async fn prune_automation_runs_with_limits(
        &self,
        automation_id: &str,
        now: DateTime<Utc>,
        retention_days: i64,
    ) -> Result<()> {
        let cutoff = format_timestamp(now - Duration::days(retention_days.max(1)));
        sqlx::query(
            "DELETE FROM automationRuns WHERE automationId = ? AND status IN ('precheckSkipped', 'misfireSkipped', 'overlapSkipped', 'queueLimitSkipped', 'success', 'failure', 'blocked', 'timeout', 'cancelled') AND (createdAt < ? OR id NOT IN (SELECT id FROM automationRuns WHERE automationId = ? AND status IN ('precheckSkipped', 'misfireSkipped', 'overlapSkipped', 'queueLimitSkipped', 'success', 'failure', 'blocked', 'timeout', 'cancelled') ORDER BY createdAt DESC LIMIT 100))",
        )
        .bind(automation_id)
        .bind(cutoff)
        .bind(automation_id)
        .execute(self.pool())
        .await?;
        Ok(())
    }

    pub async fn prune_automation_history(&self, now: DateTime<Utc>) -> Result<()> {
        let settings = self.automation_settings().await?;
        let automation_ids = sqlx::query("SELECT id FROM automations")
            .fetch_all(self.pool())
            .await?;
        for row in automation_ids {
            let id: String = row.try_get("id")?;
            self.prune_automation_runs_with_limits(&id, now, settings.run_retention_days)
                .await?;
        }
        let audit_cutoff =
            format_timestamp(now - Duration::days(settings.audit_retention_days.max(1)));
        sqlx::query("DELETE FROM automationAuditEvents WHERE createdAt < ?")
            .bind(audit_cutoff)
            .execute(self.pool())
            .await?;
        Ok(())
    }
}
