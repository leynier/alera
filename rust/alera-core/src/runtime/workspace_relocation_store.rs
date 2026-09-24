use anyhow::{anyhow, bail, Result};

use super::{RuntimeStore, Workspace, WorkspaceRelocation, WorkspaceRelocationPhase};

type RelocationRecoveryRow = (String, Option<String>, Option<String>, Option<String>);

impl RuntimeStore {
    pub async fn list_workspace_relocation_recovery(
        &self,
        workspace_id: &str,
        limit: u32,
    ) -> Result<Vec<super::WorkspaceRelocationRecovery>> {
        let rows: Vec<RelocationRecoveryRow> = sqlx::query_as("SELECT r.dataJson, s.configJson, s.attemptId, s.reportJson FROM workspaceRelocations r LEFT JOIN relocationSetupReceipts s ON s.relocationId = r.id WHERE r.workspaceId = ? ORDER BY r.rowid DESC LIMIT ?")
            .bind(workspace_id).bind(limit.clamp(1, 100)).fetch_all(self.pool()).await?;
        let mut recovery: Vec<super::WorkspaceRelocationRecovery> = rows
            .into_iter()
            .map(|(data, config, attempt_id, report)| {
                let relocation: WorkspaceRelocation = serde_json::from_str(&data)?;
                let setup = config
                    .map(|config| -> Result<_> {
                        Ok(super::RelocationSetupReceipt {
                            relocation_id: relocation.id.clone(),
                            config: serde_json::from_str(&config)?,
                            attempt_id,
                            report: report
                                .map(|report| serde_json::from_str(&report))
                                .transpose()?,
                        })
                    })
                    .transpose()?;
                Ok(super::WorkspaceRelocationRecovery {
                    relocation,
                    setup,
                    setup_root_processes: Vec::new(),
                    setup_descendants: Vec::new(),
                    setup_root_observations: Vec::new(),
                    setup_cancellation_requested: false,
                })
            })
            .collect::<Result<_>>()?;
        for item in &mut recovery {
            if let Some(receipt) = &item.setup {
                item.setup_root_processes = self.list_setup_root_processes(receipt).await?;
                item.setup_descendants = self.list_setup_descendants(receipt).await?;
                if receipt.attempt_id.is_some() {
                    item.setup_cancellation_requested =
                        self.setup_cancellation_requested(receipt).await?;
                }
            }
        }
        Ok(recovery)
    }

    pub(super) async fn migrate_workspace_relocations(&self) -> Result<()> {
        sqlx::query("CREATE TABLE IF NOT EXISTS workspaceRelocations (id TEXT PRIMARY KEY, workspaceId TEXT NOT NULL, projectId TEXT NOT NULL, hostId TEXT NOT NULL, completed INTEGER NOT NULL DEFAULT 0, dataJson TEXT NOT NULL)")
            .execute(self.pool()).await?;
        sqlx::query("CREATE UNIQUE INDEX IF NOT EXISTS workspaceRelocationOwnerIdx ON workspaceRelocations(projectId, hostId) WHERE completed = 0")
            .execute(self.pool()).await?;
        sqlx::query("CREATE INDEX IF NOT EXISTS workspaceRelocationTaskIdx ON workspaceRelocations(workspaceId, hostId)")
            .execute(self.pool()).await?;
        sqlx::query("CREATE TRIGGER IF NOT EXISTS retainRelocatingWorkspace BEFORE DELETE ON workspaces WHEN EXISTS (SELECT 1 FROM workspaceRelocations WHERE workspaceId = OLD.id AND completed = 0) BEGIN SELECT RAISE(ABORT, 'Workspace has an unfinished relocation; recover it before removal'); END")
            .execute(self.pool()).await?;
        sqlx::query("CREATE TRIGGER IF NOT EXISTS retainRelocatingWorkspaceIdentity BEFORE UPDATE ON workspaces WHEN EXISTS (SELECT 1 FROM workspaceRelocations WHERE workspaceId = OLD.id AND completed = 0) AND (NEW.id IS NOT OLD.id OR NEW.instanceId IS NOT OLD.instanceId OR NEW.projectId IS NOT OLD.projectId OR NEW.hostId IS NOT OLD.hostId OR NEW.status IS NOT OLD.status) BEGIN SELECT RAISE(ABORT, 'Workspace identity is reserved by an unfinished relocation'); END")
            .execute(self.pool()).await?;
        // Only the journal's atomic commit may change the location while its
        // recovery intent is active. Metadata edits such as renaming stay valid.
        sqlx::query("CREATE TRIGGER IF NOT EXISTS retainRelocatingWorkspaceLocation BEFORE UPDATE ON workspaces WHEN (NEW.path IS NOT OLD.path OR NEW.kind IS NOT OLD.kind) AND EXISTS (SELECT 1 FROM workspaceRelocations WHERE workspaceId = OLD.id AND completed = 0 AND NOT (json_extract(dataJson, '$.phase') = 'committed' AND json_extract(dataJson, '$.source.path') = OLD.path AND json_extract(dataJson, '$.source.kind') = OLD.kind AND json_extract(dataJson, '$.destination.path') = NEW.path AND json_extract(dataJson, '$.destination.kind') = NEW.kind)) BEGIN SELECT RAISE(ABORT, 'Workspace location is reserved by an unfinished relocation'); END")
            .execute(self.pool()).await?;
        sqlx::query("CREATE TRIGGER IF NOT EXISTS retainRelocatingProject BEFORE DELETE ON projects WHEN EXISTS (SELECT 1 FROM workspaceRelocations WHERE projectId = OLD.id AND completed = 0) BEGIN SELECT RAISE(ABORT, 'Project has an unfinished workspace relocation; recover it before removal'); END")
            .execute(self.pool()).await?;
        Ok(())
    }

    pub async fn find_workspace_relocation(&self, id: &str) -> Result<Option<WorkspaceRelocation>> {
        let data: Option<String> =
            sqlx::query_scalar("SELECT dataJson FROM workspaceRelocations WHERE id = ?")
                .bind(id)
                .fetch_optional(self.pool())
                .await?;
        data.map(|data| serde_json::from_str(&data).map_err(Into::into))
            .transpose()
    }

    pub async fn active_workspace_relocation(
        &self,
        project_id: &str,
        host_id: &str,
    ) -> Result<Option<WorkspaceRelocation>> {
        let data: Option<String> = sqlx::query_scalar("SELECT dataJson FROM workspaceRelocations WHERE projectId = ? AND hostId = ? AND completed = 0")
            .bind(project_id).bind(host_id).fetch_optional(self.pool()).await?;
        data.map(|data| serde_json::from_str(&data).map_err(Into::into))
            .transpose()
    }

    pub async fn find_relocated_worktree_ownership(
        &self,
        workspace: &Workspace,
    ) -> Result<Option<WorkspaceRelocation>> {
        if workspace.kind != super::WorkspaceKind::Linked {
            return Ok(None);
        }
        let record: Option<String> = sqlx::query_scalar("SELECT dataJson FROM workspaceRelocations WHERE workspaceId = ? AND projectId = ? AND hostId = ? AND completed = 1 AND json_extract(dataJson, '$.source.kind') = 'main' AND json_extract(dataJson, '$.destination.kind') = 'linked' AND json_extract(dataJson, '$.destination.instanceId') = ? AND json_extract(dataJson, '$.destination.path') = ? ORDER BY rowid DESC LIMIT 1")
            .bind(&workspace.id).bind(&workspace.project_id).bind(&workspace.host_id)
            .bind(&workspace.instance_id).bind(&workspace.path).fetch_optional(self.pool()).await?;
        record
            .map(|record| serde_json::from_str(&record).map_err(Into::into))
            .transpose()
    }

    pub async fn workspace_location_was_relocated(&self, workspace: &Workspace) -> Result<bool> {
        Ok(sqlx::query_scalar::<_, i64>("SELECT EXISTS(SELECT 1 FROM workspaceRelocations WHERE workspaceId = ? AND hostId = ? AND json_extract(dataJson, '$.destination.instanceId') = ? AND json_extract(dataJson, '$.destination.path') = ?)")
            .bind(&workspace.id).bind(&workspace.host_id).bind(&workspace.instance_id).bind(&workspace.path)
            .fetch_one(self.pool()).await? != 0)
    }

    /// Save the complete intent before any Git mutation, without moving the task.
    pub async fn begin_workspace_relocation(&self, relocation: &WorkspaceRelocation) -> Result<()> {
        self.validate_workspace_setup_idle(&relocation.source.id)
            .await?;
        let source = &relocation.source;
        let destination = &relocation.destination;
        if relocation.id.trim().is_empty()
            || relocation.phase != WorkspaceRelocationPhase::Prepared
            || relocation.recovery_stash_oid.is_some()
            || source.id != destination.id
            || source.instance_id != destination.instance_id
            || source.project_id != destination.project_id
            || source.host_id != destination.host_id
            || source.path == destination.path
            || destination.path.trim().is_empty()
            || source.kind == destination.kind
        {
            bail!("Relocation requires the same task and host with a different checkout kind and path");
        }
        let mut tx = self.pool().begin().await?;
        let current: Option<(String, String, String)> = sqlx::query_as("SELECT instanceId, path, kind FROM workspaces WHERE id = ? AND projectId = ? AND hostId = ?")
            .bind(&source.id).bind(&source.project_id).bind(&source.host_id).fetch_optional(&mut *tx).await?;
        if current
            != Some((
                source.instance_id.clone(),
                source.path.clone(),
                source.kind.as_str().to_string(),
            ))
        {
            bail!("Workspace location changed before relocation; refresh and prepare again");
        }
        sqlx::query("INSERT INTO workspaceRelocations(id, workspaceId, projectId, hostId, dataJson) VALUES (?, ?, ?, ?, ?)")
            .bind(&relocation.id).bind(&source.id).bind(&source.project_id).bind(&source.host_id)
            .bind(serde_json::to_string(relocation)?).execute(&mut *tx).await?;
        tx.commit().await?;
        Ok(())
    }

    /// Compare-and-swap prevents a stale retry from erasing newer recovery data.
    pub async fn advance_workspace_relocation(
        &self,
        previous: &WorkspaceRelocation,
        phase: WorkspaceRelocationPhase,
        recovery_stash_oid: Option<String>,
    ) -> Result<WorkspaceRelocation> {
        use WorkspaceRelocationPhase as Phase;
        let valid = matches!(
            (previous.phase, phase),
            (Phase::Prepared, Phase::Snapshotting)
                | (Phase::Snapshotting, Phase::Snapshotted)
                | (Phase::Snapshotted, Phase::PreparingDestination)
                | (Phase::PreparingDestination, Phase::DestinationReady)
                | (Phase::DestinationReady, Phase::ApplyingChanges)
                | (Phase::ApplyingChanges, Phase::ChangesApplied)
                | (Phase::Committed, Phase::RemovingSource)
                | (Phase::Committed, Phase::Completed)
                | (Phase::RemovingSource, Phase::Completed)
        );
        if !valid
            || (previous.recovery_stash_oid.is_none()
                && recovery_stash_oid.is_some()
                && previous.phase != Phase::Snapshotting)
            || (previous.phase == Phase::Committed
                && phase == Phase::Completed
                && previous.source.kind == super::WorkspaceKind::Linked)
            || (previous.recovery_stash_oid.is_some()
                && previous.recovery_stash_oid != recovery_stash_oid)
        {
            bail!("Invalid relocation phase or recovery reference change");
        }
        let mut next = previous.clone();
        next.phase = phase;
        next.recovery_stash_oid = recovery_stash_oid;
        let result = sqlx::query("UPDATE workspaceRelocations SET dataJson = ?, completed = ? WHERE id = ? AND dataJson = ? AND completed = 0")
            .bind(serde_json::to_string(&next)?).bind(phase == Phase::Completed).bind(&next.id)
            .bind(serde_json::to_string(previous)?).execute(self.pool()).await?;
        if result.rows_affected() != 1 {
            bail!("Relocation changed concurrently; reload its recovery state");
        }
        Ok(next)
    }

    /// Update only location fields and tab paths. Organization and history keep
    /// their existing owner, and the journal commits in the same transaction.
    pub async fn commit_workspace_relocation(
        &self,
        previous: &WorkspaceRelocation,
    ) -> Result<Workspace> {
        if previous.phase != WorkspaceRelocationPhase::ChangesApplied {
            bail!("Verify the destination and transferred files before committing relocation");
        }
        let mut next = previous.clone();
        next.phase = WorkspaceRelocationPhase::Committed;
        let source = &previous.source;
        let destination = &previous.destination;
        let mut tx = self.pool().begin().await?;
        let journal = sqlx::query("UPDATE workspaceRelocations SET dataJson = ? WHERE id = ? AND dataJson = ? AND completed = 0")
            .bind(serde_json::to_string(&next)?).bind(&previous.id).bind(serde_json::to_string(previous)?).execute(&mut *tx).await?;
        if journal.rows_affected() != 1 {
            bail!("Relocation changed concurrently; reload its recovery state");
        }
        super::workspace_relocation_location_write::write_relocated_workspace(
            &mut tx,
            source,
            destination,
            &previous.repository_path,
        )
        .await?;
        tx.commit().await?;
        self.find_workspace(&source.id)
            .await?
            .ok_or_else(|| anyhow!("Workspace disappeared after relocation"))
    }
}
