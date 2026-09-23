use anyhow::{anyhow, bail, Result};
use chrono::Utc;
use sqlx::Row;

use crate::runtime::{
    format_timestamp, AutomationRun, AutomationRunStatus, RuntimeStore, Workspace, WorkspaceKind,
    WorkspaceStatus,
};

impl RuntimeStore {
    pub(in crate::runtime) async fn migrate_automation_shared_workspace_allocations(
        &self,
    ) -> Result<()> {
        sqlx::query("CREATE TABLE IF NOT EXISTS automationSharedWorkspaceAllocations (runId TEXT PRIMARY KEY, workspaceId TEXT NOT NULL UNIQUE, workspaceJson TEXT NOT NULL)")
            .execute(self.pool()).await?;
        sqlx::query("CREATE TRIGGER IF NOT EXISTS preserveAutomationSharedWorkspaceAllocation BEFORE UPDATE ON automationRuns WHEN EXISTS (SELECT 1 FROM automationSharedWorkspaceAllocations a WHERE a.runId = OLD.id AND (NEW.id != OLD.id OR COALESCE(json_extract(NEW.dataJson, '$.workspaceId'), '') != a.workspaceId OR COALESCE(json_extract(NEW.dataJson, '$.ownedWorkspace'), 0) != 1)) BEGIN SELECT RAISE(ABORT, 'Automation run task ownership changed; reload the current run'); END")
            .execute(self.pool()).await?;
        Ok(())
    }

    /// The scheduler supplies an inspected checkout and its current run snapshot.
    /// Allocation and run ownership commit together; retry never adopts an existing task.
    pub async fn allocate_automation_shared_workspace(
        &self,
        expected_run: &AutomationRun,
        mut workspace: Workspace,
    ) -> Result<(AutomationRun, Workspace)> {
        validate_new_task(&workspace)?;
        let checkout_path = self.checkout_path_for_write(&workspace).await?;
        workspace.path = checkout_path.clone();
        let row = sqlx::query(sqlx::AssertSqlSafe(format!(
            "{} WHERE id = ?",
            super::run_query()
        )))
        .bind(&expected_run.id)
        .fetch_optional(self.pool())
        .await?
        .ok_or_else(|| anyhow!("Automation run no longer exists"))?;
        let previous_json: String = row.try_get("dataJson")?;
        let mut run = super::decode_run(row)?;
        if &run != expected_run
            || run.status != AutomationRunStatus::Dispatching
            || run.cancel_requested_at.is_some()
            || run.taken_over
        {
            bail!("Automation run changed or is not ready to allocate a task");
        }
        let mut tx = self.pool().begin().await?;
        // Acquire the write lock using the observed revision before reading ownership.
        let locked = sqlx::query("UPDATE automationRuns SET updatedAt = updatedAt WHERE id = ? AND status = 'dispatching' AND dataJson = ?")
            .bind(&run.id).bind(&previous_json).execute(&mut *tx).await?;
        if locked.rows_affected() != 1 {
            bail!("Automation run changed before task allocation");
        }
        let definition_json: String =
            sqlx::query_scalar("SELECT dataJson FROM automations WHERE id = ?")
                .bind(&run.automation_id)
                .fetch_optional(&mut *tx)
                .await?
                .ok_or_else(|| anyhow!("Automation definition no longer exists"))?;
        let definition: crate::runtime::AutomationDefinition =
            serde_json::from_str(&definition_json)?;
        if definition.target.project_checkout()
            != Some((workspace.project_id.as_str(), workspace.host_id.as_str()))
        {
            bail!("Automation target does not match the requested project and execution host");
        }
        if definition
            .project_id
            .as_deref()
            .is_some_and(|id| id != workspace.project_id)
        {
            bail!("Automation project does not match the requested checkout");
        }
        let receipt: Option<String> = sqlx::query_scalar(
            "SELECT workspaceJson FROM automationSharedWorkspaceAllocations WHERE runId = ?",
        )
        .bind(&run.id)
        .fetch_optional(&mut *tx)
        .await?;
        if let Some(receipt) = receipt {
            let owned: Workspace = serde_json::from_str(&receipt)?;
            if !run.owned_workspace
                || run.workspace_id.as_deref() != Some(&owned.id)
                || owned.project_id != workspace.project_id
                || owned.host_id != workspace.host_id
                || owned.path != checkout_path
            {
                bail!("Automation task allocation no longer matches the requested checkout");
            }
            tx.commit().await?;
            let live = self.find_workspace(&owned.id).await?.ok_or_else(|| {
                anyhow!("The allocated automation task was removed; it will not be recreated")
            })?;
            if live.instance_id != owned.instance_id
                || live.project_id != owned.project_id
                || live.host_id != owned.host_id
                || live.path != owned.path
                || live.kind != WorkspaceKind::Main
            {
                bail!("The allocated automation task identity or location changed");
            }
            return Ok((run, live));
        }
        if run.workspace_id.is_some()
            || run.owned_workspace
            || run.tab_id.is_some()
            || run.session_id.is_some()
        {
            bail!("Automation run already has a different target");
        }
        let registered: i64 = sqlx::query_scalar("SELECT count(*) FROM repositoryCheckouts c JOIN projects p ON p.id = c.projectId WHERE c.projectId = ? AND c.hostId = ? AND c.path = ? AND c.kind = 'project'")
            .bind(&workspace.project_id).bind(&workspace.host_id).bind(&checkout_path)
            .fetch_one(&mut *tx).await?;
        if registered != 1 {
            bail!("Register the project checkout on the execution host before allocating an automation task");
        }
        crate::runtime::checkout_store::bind_workspace_checkout(
            &mut tx,
            &workspace,
            &checkout_path,
        )
        .await?;
        crate::runtime::workspace_record_write::write_workspace_record(&mut tx, &workspace, false)
            .await?;
        run.workspace_id = Some(workspace.id.clone());
        run.workspace_branch = workspace.branch.clone();
        run.owned_workspace = true;
        run.updated_at = Utc::now();
        if let Some(identity) = run.target_identity.as_mut() {
            identity.workspace_id = Some(workspace.id.clone());
        }
        sqlx::query("UPDATE automationRuns SET dataJson = ?, updatedAt = ? WHERE id = ?")
            .bind(serde_json::to_string(&run)?)
            .bind(format_timestamp(run.updated_at))
            .bind(&run.id)
            .execute(&mut *tx)
            .await?;
        sqlx::query("INSERT INTO automationSharedWorkspaceAllocations (runId, workspaceId, workspaceJson) VALUES (?, ?, ?)")
            .bind(&run.id).bind(&workspace.id).bind(serde_json::to_string(&workspace)?)
            .execute(&mut *tx).await?;
        tx.commit().await?;
        let persisted = self
            .find_automation_run(&run.id)
            .await?
            .ok_or_else(|| anyhow!("Automation run disappeared after task allocation"))?;
        Ok((persisted, workspace))
    }
}

fn validate_new_task(workspace: &Workspace) -> Result<()> {
    if workspace.kind != WorkspaceKind::Main
        || workspace.status != WorkspaceStatus::Active
        || workspace.id.trim().is_empty()
        || workspace.instance_id.trim().is_empty()
        || workspace.host_id.trim().is_empty()
        || workspace.name.trim().is_empty()
        || workspace.parent_workspace_id.is_some()
        || workspace.source_branch.is_some()
        || workspace.reuses_existing_branch
        || workspace.is_pinned
        || workspace.section_id.is_some()
        || !workspace.tag_ids.is_empty()
        || !workspace.tag_names.is_empty()
        || workspace.child_count != 0
    {
        bail!("An automation allocation requires fresh task state on a project checkout");
    }
    Ok(())
}

#[cfg(test)]
#[path = "automation_shared_workspace_store_tests.rs"]
mod tests;
