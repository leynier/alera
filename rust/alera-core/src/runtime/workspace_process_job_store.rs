use anyhow::{bail, Result};
use serde::{Deserialize, Serialize};

use super::{RuntimeStore, Workspace};

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub enum WorkspaceProcessJobPhase {
    LaunchIntent,
    Spawned,
    SpawnFailed,
    RootExited,
    ClosureVerified,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct WorkspaceProcessJob {
    pub id: String,
    pub operation_id: String,
    pub workspace: Workspace,
    pub phase: WorkspaceProcessJobPhase,
    pub platform: String,
    pub boot_id: Option<String>,
    pub pid: Option<u32>,
    pub start_marker: Option<u64>,
}

impl RuntimeStore {
    pub(super) async fn migrate_workspace_process_jobs(&self) -> Result<()> {
        sqlx::query("CREATE TABLE IF NOT EXISTS workspaceProcessJobs (id TEXT PRIMARY KEY, workspaceId TEXT NOT NULL, instanceId TEXT NOT NULL, recordJson TEXT NOT NULL)")
            .execute(self.pool()).await?;
        sqlx::query("CREATE INDEX IF NOT EXISTS workspaceProcessJobsByOwner ON workspaceProcessJobs(workspaceId, instanceId)")
            .execute(self.pool()).await?;
        for statement in [
            "CREATE TRIGGER IF NOT EXISTS preserveUnresolvedWorkspaceProcessOwner BEFORE DELETE ON workspaces WHEN EXISTS (SELECT 1 FROM workspaceProcessJobs WHERE workspaceId = OLD.id AND COALESCE(json_extract(recordJson, '$.phase'), '') NOT IN ('spawnFailed', 'closureVerified')) BEGIN SELECT RAISE(ABORT, 'Workspace process closure is unresolved; preserve the task and recover its jobs'); END",
            "CREATE TRIGGER IF NOT EXISTS preserveUnresolvedWorkspaceProcessLocation BEFORE UPDATE ON workspaces WHEN (OLD.id != NEW.id OR OLD.instanceId != NEW.instanceId OR OLD.projectId != NEW.projectId OR OLD.hostId != NEW.hostId OR OLD.path != NEW.path OR OLD.kind != NEW.kind) AND EXISTS (SELECT 1 FROM workspaceProcessJobs WHERE workspaceId = OLD.id AND COALESCE(json_extract(recordJson, '$.phase'), '') NOT IN ('spawnFailed', 'closureVerified')) BEGIN SELECT RAISE(ABORT, 'Workspace process closure is unresolved; preserve its identity and location'); END",
        ] {
            sqlx::query(statement).execute(self.pool()).await?;
        }
        Ok(())
    }

    /// Commit before spawning. An unresolved intent is not evidence of an idle task.
    pub async fn begin_workspace_process_job(
        &self,
        workspace: &Workspace,
        operation_id: &str,
        platform: &str,
        boot_id: Option<String>,
    ) -> Result<WorkspaceProcessJob> {
        if operation_id.trim().is_empty() || platform.trim().is_empty() {
            bail!("Process operation and platform are required");
        }
        let job = WorkspaceProcessJob {
            id: uuid::Uuid::new_v4().to_string(),
            operation_id: operation_id.into(),
            workspace: workspace.clone(),
            phase: WorkspaceProcessJobPhase::LaunchIntent,
            platform: platform.into(),
            boot_id,
            pid: None,
            start_marker: None,
        };
        let mut tx = self.pool().begin().await?;
        super::workspace_checkout_relocation_barrier::require_checkout_process_launch_available(
            &mut tx,
            &workspace.id,
        )
        .await?;
        let inserted = sqlx::query("INSERT INTO workspaceProcessJobs (id, workspaceId, instanceId, recordJson) SELECT ?, id, instanceId, ? FROM workspaces WHERE id = ? AND instanceId = ? AND projectId = ? AND hostId = ? AND path = ?")
            .bind(&job.id).bind(serde_json::to_string(&job)?)
            .bind(&workspace.id).bind(&workspace.instance_id).bind(&workspace.project_id)
            .bind(&workspace.host_id).bind(&workspace.path).execute(&mut *tx).await?;
        if inserted.rows_affected() != 1 {
            bail!("Workspace identity or location changed before process launch");
        }
        tx.commit().await?;
        Ok(job)
    }

    pub async fn record_workspace_process_spawn(
        &self,
        previous: &WorkspaceProcessJob,
        pid: u32,
        start_marker: Option<u64>,
    ) -> Result<WorkspaceProcessJob> {
        if previous.phase != WorkspaceProcessJobPhase::LaunchIntent || pid == 0 {
            bail!("Only a pending launch may record its spawned process");
        }
        self.update_workspace_process_job(
            previous,
            WorkspaceProcessJob {
                phase: WorkspaceProcessJobPhase::Spawned,
                pid: Some(pid),
                start_marker,
                ..previous.clone()
            },
        )
        .await
    }

    /// `ClosureVerified` requires the caller to verify the entire owned process
    /// scope. A direct-child exit or an unavailable host is not sufficient.
    pub async fn record_workspace_process_phase(
        &self,
        previous: &WorkspaceProcessJob,
        phase: WorkspaceProcessJobPhase,
    ) -> Result<WorkspaceProcessJob> {
        use WorkspaceProcessJobPhase::*;
        if !matches!(
            (previous.phase, phase),
            (LaunchIntent, SpawnFailed) | (Spawned, RootExited) | (RootExited, ClosureVerified)
        ) {
            bail!("Invalid workspace process lifecycle transition");
        }
        self.update_workspace_process_job(
            previous,
            WorkspaceProcessJob {
                phase,
                ..previous.clone()
            },
        )
        .await
    }

    async fn update_workspace_process_job(
        &self,
        previous: &WorkspaceProcessJob,
        next: WorkspaceProcessJob,
    ) -> Result<WorkspaceProcessJob> {
        let changed = sqlx::query(
            "UPDATE workspaceProcessJobs SET recordJson = ? WHERE id = ? AND recordJson = ?",
        )
        .bind(serde_json::to_string(&next)?)
        .bind(&previous.id)
        .bind(serde_json::to_string(previous)?)
        .execute(self.pool())
        .await?;
        if changed.rows_affected() != 1 {
            bail!("Workspace process evidence changed; reload it before retrying");
        }
        Ok(next)
    }

    /// Check before physical cleanup; database triggers also protect record mutations.
    pub async fn require_workspace_process_closure(&self, workspace_id: &str) -> Result<()> {
        self.require_terminal_lifecycle_closed(workspace_id).await?;
        self.require_workspace_precheck_closure(workspace_id)
            .await?;
        let jobs = self.workspace_process_jobs(workspace_id).await?;
        let unresolved: Vec<_> = jobs
            .iter()
            .filter(|job| {
                !matches!(
                    job.phase,
                    WorkspaceProcessJobPhase::SpawnFailed
                        | WorkspaceProcessJobPhase::ClosureVerified
                )
            })
            .map(|job| format!("{} ({})", job.operation_id, job.id))
            .collect();
        if !unresolved.is_empty() {
            bail!("Workspace process closure is unresolved. Recover these jobs before removal or relocation: {}", unresolved.join(", "));
        }
        Ok(())
    }

    /// Empty history does not establish that a migrated workspace never ran jobs.
    pub async fn workspace_process_jobs(
        &self,
        workspace_id: &str,
    ) -> Result<Vec<WorkspaceProcessJob>> {
        let records: Vec<String> = sqlx::query_scalar(
            "SELECT recordJson FROM workspaceProcessJobs WHERE workspaceId = ? ORDER BY id",
        )
        .bind(workspace_id)
        .fetch_all(self.pool())
        .await?;
        records
            .into_iter()
            .map(|record| serde_json::from_str(&record).map_err(Into::into))
            .collect()
    }
}

#[cfg(test)]
#[path = "workspace_process_job_store_tests.rs"]
mod tests;
