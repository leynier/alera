use anyhow::{bail, Context, Result};
use serde::{Deserialize, Serialize};

use super::{
    AutomationPrecheck, AutomationPrecheckProcess, RuntimeStore, WorkspaceProcessJobPhase,
    LOCAL_HOST_ID,
};

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct OwnerAutomationPrecheckRequest {
    pub operation_id: String,
    pub origin_id: String,
    pub run_id: String,
    pub project_id: String,
    pub path: String,
    pub precheck: AutomationPrecheck,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub workspace: Option<super::AutomationPrecheckWorkspace>,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct OwnerAutomationPrecheck {
    pub request: OwnerAutomationPrecheckRequest,
    pub cancel_requested: bool,
    pub process_id: Option<String>,
    pub outcome: Option<OwnerAutomationPrecheckOutcome>,
    pub attention: Option<String>,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(tag = "kind", content = "message", rename_all = "camelCase")]
pub enum OwnerAutomationPrecheckOutcome {
    Passed,
    Rejected,
    Cancelled,
    TimedOut,
    Failed(String),
}

impl RuntimeStore {
    pub(super) async fn migrate_owner_automation_prechecks(&self) -> Result<()> {
        for statement in [
            "CREATE TABLE IF NOT EXISTS ownerAutomationPrechecks (id TEXT PRIMARY KEY, projectId TEXT NOT NULL, requestJson TEXT NOT NULL, cancelRequested INTEGER NOT NULL DEFAULT 0, processId TEXT)",
            "CREATE TRIGGER IF NOT EXISTS preservePendingOwnerPrecheckProject BEFORE DELETE ON projects WHEN EXISTS (SELECT 1 FROM ownerAutomationPrechecks p WHERE p.projectId = OLD.id AND p.cancelRequested = 0 AND p.processId IS NULL) BEGIN SELECT RAISE(ABORT, 'An owner precheck is reserved; cancel it before removing its project'); END",
            "CREATE TRIGGER IF NOT EXISTS preserveOwnerPrecheckEvidence BEFORE DELETE ON ownerAutomationPrechecks WHEN EXISTS (SELECT 1 FROM automationPrecheckProcesses p WHERE p.id = OLD.processId AND COALESCE(json_extract(p.recordJson, '$.phase'), '') NOT IN ('spawnFailed','closureVerified')) BEGIN SELECT RAISE(ABORT, 'Owner precheck process closure is unverified'); END",
        ] {
            sqlx::query(statement).execute(self.pool()).await?;
        }
        self.ensure_column("ownerAutomationPrechecks", "resultJson", "TEXT")
            .await?;
        self.ensure_column("ownerAutomationPrechecks", "attention", "TEXT")
            .await?;
        self.migrate_pending_owner_precheck_fences().await?;
        Ok(())
    }

    /// Native callers must first inspect authorization and canonicalize the path
    /// on this host. Registration creates no workspace, profile or automation.
    pub async fn register_owner_automation_precheck(
        &self,
        request: &OwnerAutomationPrecheckRequest,
    ) -> Result<OwnerAutomationPrecheck> {
        self.register_owner_precheck(request, false).await
    }

    async fn register_owner_precheck(
        &self,
        request: &OwnerAutomationPrecheckRequest,
        cancelled: bool,
    ) -> Result<OwnerAutomationPrecheck> {
        let operation = uuid::Uuid::parse_str(&request.operation_id)?;
        if operation.is_nil()
            || operation.to_string() != request.operation_id
            || request.origin_id.trim().is_empty()
            || request.run_id.trim().is_empty()
            || request.project_id.trim().is_empty()
            || request.path.trim().is_empty()
            || request.precheck.command.trim().is_empty()
            || !(1..=15 * 60).contains(&request.precheck.timeout_seconds)
        {
            bail!("Owner precheck requires exact origin, run, project, checkout and bounded command identities");
        }
        let mut tx = self.pool().begin().await?;
        let registered =
            super::automation_precheck_workspace_store::owner_target_registered(&mut tx, request)
                .await?;
        if !registered {
            bail!("Register and inspect the owner project checkout before reserving a precheck");
        }
        sqlx::query("INSERT OR IGNORE INTO ownerAutomationPrechecks(id, projectId, requestJson, cancelRequested) VALUES (?, ?, ?, ?)")
            .bind(&request.operation_id).bind(&request.project_id).bind(serde_json::to_string(request)?)
            .bind(cancelled)
            .execute(&mut *tx).await?;
        let row = sqlx::query_as::<_, (String, bool, Option<String>, Option<String>, Option<String>)>("SELECT requestJson, cancelRequested, processId, resultJson, attention FROM ownerAutomationPrechecks WHERE id = ?")
            .bind(&request.operation_id).fetch_one(&mut *tx).await?;
        let mut job = decode(row)?;
        if job.request != *request {
            bail!("Owner precheck operation already belongs to a different request");
        }
        if cancelled && !job.cancel_requested {
            sqlx::query("UPDATE ownerAutomationPrechecks SET cancelRequested = 1 WHERE id = ?")
                .bind(&request.operation_id)
                .execute(&mut *tx)
                .await?;
            job.cancel_requested = true;
        }
        tx.commit().await?;
        Ok(job)
    }

    pub async fn find_owner_automation_precheck(
        &self,
        operation_id: &str,
    ) -> Result<Option<OwnerAutomationPrecheck>> {
        sqlx::query_as::<_, (String, bool, Option<String>, Option<String>, Option<String>)>("SELECT requestJson, cancelRequested, processId, resultJson, attention FROM ownerAutomationPrechecks WHERE id = ?")
            .bind(operation_id).fetch_optional(self.pool()).await?.map(decode).transpose()
    }

    pub async fn cancel_owner_automation_precheck(
        &self,
        request: &OwnerAutomationPrecheckRequest,
    ) -> Result<()> {
        let changed = sqlx::query("UPDATE ownerAutomationPrechecks SET cancelRequested = 1 WHERE id = ? AND requestJson = ?")
            .bind(&request.operation_id).bind(serde_json::to_string(request)?).execute(self.pool()).await?;
        if changed.rows_affected() != 1 {
            // A Cancel can arrive before an in-flight SSH Start. The first
            // persisted version must already be cancelled, never claimable.
            self.register_owner_precheck(request, true).await?;
        }
        Ok(())
    }

    pub async fn set_owner_precheck_attention(
        &self,
        request: &OwnerAutomationPrecheckRequest,
        reason: Option<&str>,
    ) -> Result<()> {
        let reason = reason
            .map(|text| super::redact_known_patterns(&text.chars().take(2048).collect::<String>()));
        let changed = sqlx::query("UPDATE ownerAutomationPrechecks SET attention = ? WHERE id = ? AND requestJson = ? AND resultJson IS NULL")
            .bind(reason).bind(&request.operation_id).bind(serde_json::to_string(request)?)
            .execute(self.pool()).await?;
        if changed.rows_affected() != 1 {
            bail!("Owner precheck identity changed or is missing");
        }
        Ok(())
    }

    /// None means this request was cancelled or already claimed. Never repeat
    /// its command after losing a response, even if only launch intent remains.
    pub async fn claim_owner_automation_precheck(
        &self,
        request: &OwnerAutomationPrecheckRequest,
        platform: &str,
        boot_id: Option<String>,
    ) -> Result<Option<AutomationPrecheckProcess>> {
        if !matches!(platform, "linux" | "macos" | "windows") {
            bail!("Unsupported precheck owner platform");
        }
        let mut tx = self.pool().begin().await?;
        let row = sqlx::query_as::<_, (String, bool, Option<String>, Option<String>, Option<String>)>("SELECT requestJson, cancelRequested, processId, resultJson, attention FROM ownerAutomationPrechecks WHERE id = ?")
            .bind(&request.operation_id).fetch_optional(&mut *tx).await?.context("Owner precheck reservation is missing")?;
        let job = decode(row)?;
        if job.request != *request {
            bail!("Owner precheck request changed before launch");
        }
        if job.cancel_requested || job.process_id.is_some() {
            return Ok(None);
        }
        let registered =
            super::automation_precheck_workspace_store::owner_target_registered(&mut tx, request)
                .await?;
        if !registered {
            bail!("Owner precheck checkout changed before launch");
        }
        let process_id = format!("owner-precheck:{}", request.operation_id);
        let process = AutomationPrecheckProcess {
            id: process_id.clone(),
            run_id: process_id.clone(),
            attempt_count: 0,
            project_id: request.project_id.clone(),
            host_id: LOCAL_HOST_ID.into(),
            path: request.path.clone(),
            precheck: request.precheck.clone(),
            workspace: request.workspace.clone(),
            phase: WorkspaceProcessJobPhase::LaunchIntent,
            platform: platform.into(),
            boot_id,
            pid: None,
            start_marker: None,
            closure_boot_id: None,
        };
        sqlx::query("INSERT INTO automationPrecheckProcesses(id, runId, projectId, recordJson) VALUES (?, ?, ?, ?)")
            .bind(&process.id).bind(&process.run_id).bind(&process.project_id).bind(serde_json::to_string(&process)?)
            .execute(&mut *tx).await?;
        sqlx::query("UPDATE ownerAutomationPrechecks SET processId = ? WHERE id = ?")
            .bind(&process_id)
            .bind(&request.operation_id)
            .execute(&mut *tx)
            .await?;
        tx.commit().await?;
        Ok(Some(process))
    }

    pub async fn finish_owner_automation_precheck(
        &self,
        request: &OwnerAutomationPrecheckRequest,
        outcome: &OwnerAutomationPrecheckOutcome,
    ) -> Result<()> {
        let mut tx = self.pool().begin().await?;
        let row = sqlx::query_as::<_, (String, bool, Option<String>, Option<String>, Option<String>)>(
            "SELECT requestJson, cancelRequested, processId, resultJson, attention FROM ownerAutomationPrechecks WHERE id = ?",
        ).bind(&request.operation_id).fetch_optional(&mut *tx).await?
            .context("Owner precheck reservation is missing")?;
        let job = decode(row)?;
        if job.request != *request {
            bail!("Owner precheck identity changed before completion");
        }
        if let Some(previous) = job.outcome {
            if previous != *outcome {
                bail!("Owner precheck already has a different result");
            }
            return Ok(());
        }
        if let Some(process_id) = job.process_id {
            let json: String = sqlx::query_scalar(
                "SELECT recordJson FROM automationPrecheckProcesses WHERE id = ?",
            )
            .bind(process_id)
            .fetch_one(&mut *tx)
            .await?;
            let process: AutomationPrecheckProcess = serde_json::from_str(&json)?;
            if process.closure_boot_id.is_some()
                && matches!(
                    outcome,
                    OwnerAutomationPrecheckOutcome::Passed
                        | OwnerAutomationPrecheckOutcome::Rejected
                )
            {
                bail!("A reboot proves process closure but cannot recover its command result");
            }
            let closed = match process.phase {
                WorkspaceProcessJobPhase::ClosureVerified => true,
                WorkspaceProcessJobPhase::SpawnFailed => matches!(
                    outcome,
                    OwnerAutomationPrecheckOutcome::Cancelled
                        | OwnerAutomationPrecheckOutcome::TimedOut
                        | OwnerAutomationPrecheckOutcome::Failed(_)
                ),
                _ => false,
            };
            if !closed {
                bail!("Owner precheck process closure is unverified; retain its reservation");
            }
        } else if !job.cancel_requested || *outcome != OwnerAutomationPrecheckOutcome::Cancelled {
            bail!("Only cancellation before launch can complete without process evidence");
        }
        sqlx::query(
            "UPDATE ownerAutomationPrechecks SET resultJson = ?, attention = NULL WHERE id = ?",
        )
        .bind(serde_json::to_string(outcome)?)
        .bind(&request.operation_id)
        .execute(&mut *tx)
        .await?;
        tx.commit().await?;
        Ok(())
    }
}

fn decode(
    (request, cancel_requested, process_id, result, attention): (
        String,
        bool,
        Option<String>,
        Option<String>,
        Option<String>,
    ),
) -> Result<OwnerAutomationPrecheck> {
    Ok(OwnerAutomationPrecheck {
        request: serde_json::from_str(&request)?,
        cancel_requested,
        process_id,
        outcome: result.as_deref().map(serde_json::from_str).transpose()?,
        attention,
    })
}

#[cfg(test)]
#[path = "owner_automation_precheck_store_tests.rs"]
mod tests;
