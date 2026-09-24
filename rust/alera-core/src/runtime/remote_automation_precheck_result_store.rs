use anyhow::{bail, Context, Result};

use super::{
    AutomationPrecheckProcess, OwnerAutomationPrecheck, OwnerAutomationPrecheckOutcome,
    OwnerAutomationPrecheckRequest, RuntimeStore, WorkspaceProcessJobPhase, LOCAL_HOST_ID,
};

impl AutomationPrecheckProcess {
    pub fn remote_owner_request(&self) -> Result<OwnerAutomationPrecheckRequest> {
        let operation = uuid::Uuid::parse_str(&self.id)?;
        if operation.is_nil()
            || operation.to_string() != self.id
            || self.host_id == LOCAL_HOST_ID
            || self.host_id.trim().is_empty()
            || self.run_id.trim().is_empty()
        {
            bail!("A remote precheck requires its retained Home operation and run identities");
        }
        Ok(OwnerAutomationPrecheckRequest {
            operation_id: self.id.clone(),
            // Run IDs are globally generated UUIDs; this origin stays stable
            // when Home reconnects or its profile directory moves.
            origin_id: format!("automation-run:{}", self.run_id),
            run_id: self.run_id.clone(),
            project_id: self.project_id.clone(),
            path: self.path.clone(),
            precheck: self.precheck.clone(),
            workspace: self
                .workspace
                .clone()
                .filter(|workspace| workspace.kind == super::WorkspaceKind::Linked),
        })
    }
}

impl RuntimeStore {
    /// An SSH exit status is not process closure. Retain the exact owner result
    /// and its native evidence atomically with releasing Home's dependency fence.
    pub async fn record_remote_precheck_result(
        &self,
        previous: &AutomationPrecheckProcess,
        job: &OwnerAutomationPrecheck,
        processes: &[AutomationPrecheckProcess],
    ) -> Result<AutomationPrecheckProcess> {
        validate_result(previous, job, processes)?;
        let next = AutomationPrecheckProcess {
            phase: WorkspaceProcessJobPhase::ClosureVerified,
            ..previous.clone()
        };
        let mut tx = self.pool().begin().await?;
        let changed = sqlx::query(
            "UPDATE automationPrecheckProcesses SET recordJson = ? WHERE id = ? AND recordJson = ?",
        )
        .bind(serde_json::to_string(&next)?)
        .bind(&previous.id)
        .bind(serde_json::to_string(previous)?)
        .execute(&mut *tx)
        .await?;
        if changed.rows_affected() != 1 {
            bail!("Home precheck evidence changed; reload before accepting the owner result");
        }
        sqlx::query("INSERT INTO remoteAutomationPrecheckResults(id, jobJson, processesJson) VALUES (?, ?, ?)")
            .bind(&previous.id).bind(serde_json::to_string(job)?)
            .bind(serde_json::to_string(processes)?).execute(&mut *tx).await?;
        tx.commit().await?;
        Ok(next)
    }

    pub async fn remote_precheck_result(
        &self,
        operation_id: &str,
    ) -> Result<Option<OwnerAutomationPrecheck>> {
        let json: Option<String> =
            sqlx::query_scalar("SELECT jobJson FROM remoteAutomationPrecheckResults WHERE id = ?")
                .bind(operation_id)
                .fetch_optional(self.pool())
                .await?;
        json.map(|json| serde_json::from_str(&json).map_err(Into::into))
            .transpose()
    }
}

fn validate_result(
    home: &AutomationPrecheckProcess,
    job: &OwnerAutomationPrecheck,
    processes: &[AutomationPrecheckProcess],
) -> Result<()> {
    use OwnerAutomationPrecheckOutcome::{Cancelled, Failed, Passed, Rejected, TimedOut};
    use WorkspaceProcessJobPhase::{ClosureVerified, LaunchIntent, SpawnFailed};
    if home.phase != LaunchIntent
        || job.request != home.remote_owner_request()?
        || job.attention.is_some()
        || home.pid.is_some()
        || home.boot_id.is_some()
    {
        bail!("Owner result does not match Home's retained remote precheck intent");
    }
    let outcome = job
        .outcome
        .as_ref()
        .context("Owner precheck is not complete")?;
    let Some(process_id) = &job.process_id else {
        if !job.cancel_requested || *outcome != Cancelled || !processes.is_empty() {
            bail!("Only verified cancellation before claim can omit owner process evidence");
        }
        return Ok(());
    };
    let [process] = processes else {
        bail!("Owner result must include its exact process evidence");
    };
    if process_id != &format!("owner-precheck:{}", home.id)
        || process.id != *process_id
        || process.run_id != *process_id
        || process.project_id != home.project_id
        || process.host_id != LOCAL_HOST_ID
        || process.path != home.path
        || process.precheck != home.precheck
        || process.workspace != job.request.workspace
        || process.platform != home.platform
        || process.attempt_count != 0
        || !matches!(process.phase, ClosureVerified | SpawnFailed)
        || ((process.phase == SpawnFailed || process.closure_boot_id.is_some())
            && !matches!(outcome, Cancelled | TimedOut | Failed(_)))
        || (matches!(outcome, Passed | Rejected) && process.pid.is_none())
    {
        bail!("Owner process evidence does not prove closure and the reported command result");
    }
    Ok(())
}
