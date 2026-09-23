use anyhow::{anyhow, bail, Result};
use serde::{Deserialize, Serialize};

use super::{
    AutomationDefinition, AutomationPrecheck, AutomationRun, AutomationRunStatus, RuntimeStore,
    WorkspaceProcessJobPhase,
};

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
#[serde(rename_all = "camelCase")]
pub struct AutomationPrecheckProcess {
    pub id: String,
    pub run_id: String,
    pub attempt_count: i64,
    pub project_id: String,
    pub host_id: String,
    pub path: String,
    pub precheck: AutomationPrecheck,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub workspace: Option<super::AutomationPrecheckWorkspace>,
    pub phase: WorkspaceProcessJobPhase,
    pub platform: String,
    pub boot_id: Option<String>,
    pub pid: Option<u32>,
    pub start_marker: Option<u64>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub closure_boot_id: Option<String>,
}

impl RuntimeStore {
    pub(super) async fn migrate_automation_precheck_processes(&self) -> Result<()> {
        for statement in [
            "CREATE TABLE IF NOT EXISTS remoteAutomationPrecheckResults (id TEXT PRIMARY KEY, jobJson TEXT NOT NULL, processesJson TEXT NOT NULL)",
            "CREATE TABLE IF NOT EXISTS automationPrecheckProcesses (id TEXT PRIMARY KEY, runId TEXT NOT NULL, projectId TEXT NOT NULL, recordJson TEXT NOT NULL)",
            "CREATE TRIGGER IF NOT EXISTS cleanupRemotePrecheckResult AFTER DELETE ON automationPrecheckProcesses BEGIN DELETE FROM remoteAutomationPrecheckResults WHERE id = OLD.id; END",
            "CREATE INDEX IF NOT EXISTS automationPrecheckProcessesByRun ON automationPrecheckProcesses(runId)",
            "CREATE UNIQUE INDEX IF NOT EXISTS oneUnclosedPrecheckPerRun ON automationPrecheckProcesses(runId) WHERE COALESCE(json_extract(recordJson, '$.phase'), '') NOT IN ('spawnFailed','closureVerified')",
            "CREATE TRIGGER IF NOT EXISTS preservePrecheckRunCompletion BEFORE UPDATE ON automationRuns WHEN EXISTS (SELECT 1 FROM automationPrecheckProcesses p WHERE p.runId = OLD.id AND COALESCE(json_extract(p.recordJson, '$.phase'), '') NOT IN ('spawnFailed','closureVerified')) AND (NEW.id != OLD.id OR NEW.automationId != OLD.automationId OR NEW.status NOT IN ('dispatching','waitingForUser') OR json_extract(NEW.dataJson, '$.attemptCount') IS NOT json_extract(OLD.dataJson, '$.attemptCount')) BEGIN SELECT RAISE(ABORT, 'Automation precheck process closure is unverified; retain the run and its dependencies'); END",
            "CREATE TRIGGER IF NOT EXISTS preservePrecheckRunDeletion BEFORE DELETE ON automationRuns WHEN EXISTS (SELECT 1 FROM automationPrecheckProcesses p WHERE p.runId = OLD.id AND COALESCE(json_extract(p.recordJson, '$.phase'), '') NOT IN ('spawnFailed','closureVerified')) BEGIN SELECT RAISE(ABORT, 'Automation precheck process closure is unverified; retain its run'); END",
            "CREATE TRIGGER IF NOT EXISTS preservePrecheckProject BEFORE DELETE ON projects WHEN EXISTS (SELECT 1 FROM automationPrecheckProcesses p WHERE p.projectId = OLD.id AND COALESCE(json_extract(p.recordJson, '$.phase'), '') NOT IN ('spawnFailed','closureVerified')) BEGIN SELECT RAISE(ABORT, 'Automation precheck process closure is unverified; retain its project'); END",
            "CREATE TRIGGER IF NOT EXISTS preservePrecheckDefinition BEFORE DELETE ON automations WHEN EXISTS (SELECT 1 FROM automationRuns r JOIN automationPrecheckProcesses p ON p.runId = r.id WHERE r.automationId = OLD.id AND COALESCE(json_extract(p.recordJson, '$.phase'), '') NOT IN ('spawnFailed','closureVerified')) BEGIN SELECT RAISE(ABORT, 'Automation precheck process closure is unverified; retain its automation'); END",
            "CREATE TRIGGER IF NOT EXISTS cleanupClosedPrecheckProcesses AFTER DELETE ON automationRuns BEGIN DELETE FROM automationPrecheckProcesses WHERE runId = OLD.id; END",
        ] {
            sqlx::query(statement).execute(self.pool()).await?;
        }
        self.migrate_precheck_workspace_fences().await?;
        Ok(())
    }

    /// Persist before spawning. A launch intent also protects against a crash
    /// between process creation and recording its native identity.
    pub async fn begin_automation_precheck_process(
        &self,
        run: &AutomationRun,
        definition: &AutomationDefinition,
        operation_id: &str,
        platform: &str,
        boot_id: Option<String>,
    ) -> Result<AutomationPrecheckProcess> {
        if operation_id.trim().is_empty() || platform.trim().is_empty() {
            bail!("Precheck operation identity and platform are required");
        }
        let mut tx = self.pool().begin().await?;
        let query = format!("{} WHERE id = ?", super::automation_run_store::run_query());
        let row = sqlx::query(sqlx::AssertSqlSafe(query))
            .bind(&run.id)
            .fetch_one(&mut *tx)
            .await?;
        let current = super::automation_run_store::decode_run(row)?;
        if current.status != AutomationRunStatus::Dispatching
            || current.precheck != Some(true)
            || current.started_at.is_some()
            || current.cancel_requested_at.is_some()
            || current.attempt_count != run.attempt_count
            || current.automation_id != definition.id
        {
            bail!("Automation precheck reservation is cancelled, stale or no longer current");
        }
        let json: String = sqlx::query_scalar("SELECT dataJson FROM automations WHERE id = ?")
            .bind(&definition.id)
            .fetch_one(&mut *tx)
            .await?;
        let latest: AutomationDefinition = serde_json::from_str(&json)?;
        if latest.revision != definition.revision
            || latest.state != definition.state
            || latest.target != definition.target
            || latest.precheck != definition.precheck
        {
            bail!("Automation changed before precheck process launch");
        }
        let precheck = latest
            .precheck
            .ok_or_else(|| anyhow!("Automation has no precheck"))?;
        let (project_id, host_id, path): (String, String, String) = if let Some((project, host)) =
            latest.target.project_checkout()
        {
            sqlx::query_as("SELECT projectId, hostId, path FROM repositoryCheckouts WHERE projectId = ? AND hostId = ? AND kind = 'project'")
                .bind(project).bind(host).fetch_one(&mut *tx).await?
        } else {
            let workspace = latest
                .target
                .source_workspace_id()
                .ok_or_else(|| anyhow!("Precheck target workspace is missing"))?;
            sqlx::query_as("SELECT projectId, hostId, path FROM workspaces WHERE id = ?")
                .bind(workspace)
                .fetch_one(&mut *tx)
                .await?
        };
        let workspace = super::automation_precheck_workspace_store::capture_workspace(
            &mut tx,
            latest.target.source_workspace_id(),
        )
        .await?;
        let record = AutomationPrecheckProcess {
            id: operation_id.into(),
            run_id: run.id.clone(),
            attempt_count: run.attempt_count,
            project_id,
            host_id,
            path,
            precheck,
            workspace,
            phase: WorkspaceProcessJobPhase::LaunchIntent,
            platform: platform.into(),
            boot_id,
            pid: None,
            start_marker: None,
            closure_boot_id: None,
        };
        sqlx::query("INSERT INTO automationPrecheckProcesses(id, runId, projectId, recordJson) VALUES (?, ?, ?, ?)")
            .bind(&record.id).bind(&record.run_id).bind(&record.project_id).bind(serde_json::to_string(&record)?)
            .execute(&mut *tx).await?;
        tx.commit().await?;
        Ok(record)
    }

    pub async fn automation_precheck_processes(
        &self,
        run_id: &str,
    ) -> Result<Vec<AutomationPrecheckProcess>> {
        let records: Vec<String> = sqlx::query_scalar(
            "SELECT recordJson FROM automationPrecheckProcesses WHERE runId = ? ORDER BY id",
        )
        .bind(run_id)
        .fetch_all(self.pool())
        .await?;
        records
            .into_iter()
            .map(|json| serde_json::from_str(&json).map_err(Into::into))
            .collect()
    }

    pub async fn record_automation_precheck_spawn(
        &self,
        previous: &AutomationPrecheckProcess,
        pid: u32,
        start_marker: Option<u64>,
    ) -> Result<AutomationPrecheckProcess> {
        if previous.phase != WorkspaceProcessJobPhase::LaunchIntent || pid == 0 {
            bail!("Invalid precheck spawn transition");
        }
        self.update_precheck_process(
            previous,
            AutomationPrecheckProcess {
                pid: Some(pid),
                start_marker,
                phase: WorkspaceProcessJobPhase::Spawned,
                ..previous.clone()
            },
        )
        .await
    }

    pub async fn record_automation_precheck_phase(
        &self,
        previous: &AutomationPrecheckProcess,
        phase: WorkspaceProcessJobPhase,
    ) -> Result<AutomationPrecheckProcess> {
        use WorkspaceProcessJobPhase::*;
        if !matches!(
            (previous.phase, phase),
            (LaunchIntent, SpawnFailed) | (Spawned, RootExited) | (RootExited, ClosureVerified)
        ) {
            bail!("Invalid precheck process lifecycle transition");
        }
        self.update_precheck_process(
            previous,
            AutomationPrecheckProcess {
                phase,
                ..previous.clone()
            },
        )
        .await
    }

    /// A different verified Linux boot proves that the previous process tree
    /// cannot survive, including a crash before its PID was recorded.
    pub async fn close_automation_precheck_from_previous_boot(
        &self,
        previous: &AutomationPrecheckProcess,
        current_boot_id: &str,
    ) -> Result<AutomationPrecheckProcess> {
        if previous.host_id != super::LOCAL_HOST_ID || previous.platform != "linux" {
            bail!("Precheck reboot recovery requires evidence from its owning Linux host");
        }
        let old_boot = uuid::Uuid::parse_str(previous.boot_id.as_deref().unwrap_or(""))?;
        let current_boot = uuid::Uuid::parse_str(current_boot_id)?;
        if old_boot == current_boot || old_boot.is_nil() || current_boot.is_nil() {
            bail!("Precheck reboot recovery requires a different verified boot");
        }
        if matches!(
            previous.phase,
            WorkspaceProcessJobPhase::SpawnFailed | WorkspaceProcessJobPhase::ClosureVerified
        ) {
            bail!("Precheck process is already closed");
        }
        self.update_precheck_process(
            previous,
            AutomationPrecheckProcess {
                phase: WorkspaceProcessJobPhase::ClosureVerified,
                closure_boot_id: Some(current_boot.to_string()),
                ..previous.clone()
            },
        )
        .await
    }

    async fn update_precheck_process(
        &self,
        previous: &AutomationPrecheckProcess,
        next: AutomationPrecheckProcess,
    ) -> Result<AutomationPrecheckProcess> {
        let changed = sqlx::query(
            "UPDATE automationPrecheckProcesses SET recordJson = ? WHERE id = ? AND recordJson = ?",
        )
        .bind(serde_json::to_string(&next)?)
        .bind(&previous.id)
        .bind(serde_json::to_string(previous)?)
        .execute(self.pool())
        .await?;
        if changed.rows_affected() != 1 {
            bail!("Precheck process evidence changed; reload before retrying");
        }
        Ok(next)
    }
}
