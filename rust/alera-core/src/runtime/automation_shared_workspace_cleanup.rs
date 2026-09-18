use anyhow::{anyhow, bail, Result};
use sqlx::{Sqlite, Transaction};

use super::{
    AutomationCleanupPolicy, AutomationDefinition, AutomationRun, AutomationRunStatus,
    RuntimeStore, Workspace, WorkspaceKind,
};

impl RuntimeStore {
    pub async fn require_automation_shared_workspace_cleanup(
        &self,
        run: &AutomationRun,
        workspace: &Workspace,
    ) -> Result<()> {
        let mut tx = self.pool().begin().await?;
        validate_cleanup(&mut tx, run, workspace).await?;
        tx.commit().await?;
        Ok(())
    }

    /// The caller must first verify editor buffers and owned process shutdown on the owning host.
    /// Ownership is rechecked inside the retirement transaction to reject takeover races.
    pub async fn retire_verified_automation_shared_workspace(
        &self,
        run: &AutomationRun,
        workspace: &Workspace,
    ) -> Result<()> {
        self.remove_workspace_with_receipt(&workspace.id, true, Some(workspace), Some(run), None)
            .await
    }
}

pub(super) async fn validate_cleanup(
    tx: &mut Transaction<'_, Sqlite>,
    run: &AutomationRun,
    workspace: &Workspace,
) -> Result<()> {
    let query = format!("{} WHERE id = ?", super::automation_run_store::run_query());
    let current_row = sqlx::query(sqlx::AssertSqlSafe(query))
        .bind(&run.id)
        .fetch_optional(&mut **tx)
        .await?
        .ok_or_else(|| anyhow!("Automation run no longer exists"))?;
    let current = super::automation_run_store::decode_run(current_row)?;
    if current != *run
        || run.status != AutomationRunStatus::Success
        || run.taken_over
        || !run.owned_workspace
        || run.cancel_requested_at.is_some()
        || run.workspace_id.as_deref() != Some(&workspace.id)
    {
        bail!("Automation run changed or does not own a successful cleanup target");
    }
    let definition_json: String =
        sqlx::query_scalar("SELECT dataJson FROM automations WHERE id = ?")
            .bind(&run.automation_id)
            .fetch_optional(&mut **tx)
            .await?
            .ok_or_else(|| anyhow!("Automation definition no longer exists"))?;
    let definition: AutomationDefinition = serde_json::from_str(&definition_json)?;
    if definition.cleanup_policy != Some(AutomationCleanupPolicy::OnSuccess)
        || definition.target.project_checkout()
            != Some((workspace.project_id.as_str(), workspace.host_id.as_str()))
    {
        bail!("Automation no longer requests cleanup on this project checkout");
    }
    let allocation_json: String = sqlx::query_scalar("SELECT workspaceJson FROM automationSharedWorkspaceAllocations WHERE runId = ? AND workspaceId = ?")
        .bind(&run.id).bind(&workspace.id).fetch_optional(&mut **tx).await?.ok_or_else(|| anyhow!("Automation task allocation could not be proven"))?;
    let allocated: Workspace = serde_json::from_str(&allocation_json)?;
    if workspace.kind != WorkspaceKind::Main
        || allocated.id != workspace.id
        || allocated.instance_id != workspace.instance_id
        || allocated.project_id != workspace.project_id
        || allocated.host_id != workspace.host_id
        || allocated.path != workspace.path
        || allocated.name != workspace.name
    {
        bail!("Automation task identity, location or name changed");
    }
    let untouched: i64 = sqlx::query_scalar("SELECT count(*) FROM workspaces w WHERE w.id = ? AND w.instanceId = ? AND w.projectId = ? AND w.hostId = ? AND w.path = ? AND w.name = ? AND w.kind = 'main' AND w.status = 'active' AND w.isPinned = 0 AND w.isArchived = 0 AND NOT EXISTS (SELECT 1 FROM workspaceRelations r WHERE r.parentWorkspaceId = w.id OR r.childWorkspaceId = w.id) AND NOT EXISTS (SELECT 1 FROM workspaceTagAssignments t WHERE t.workspaceId = w.id) AND NOT EXISTS (SELECT 1 FROM workspaceSectionAssignments s WHERE s.workspaceId = w.id)")
        .bind(&workspace.id).bind(&allocated.instance_id).bind(&allocated.project_id).bind(&allocated.host_id).bind(&allocated.path).bind(&allocated.name).fetch_one(&mut **tx).await?;
    if untouched != 1 {
        bail!("Automation task was reorganized or is no longer active");
    }
    let bound: i64 = sqlx::query_scalar("SELECT count(*) FROM workspaceCheckoutBindings b JOIN repositoryCheckouts c ON c.id = b.checkoutId WHERE b.workspaceId = ? AND c.kind = 'project' AND c.projectId = ? AND c.hostId = ? AND c.path = ?")
        .bind(&workspace.id).bind(&workspace.project_id).bind(&workspace.host_id).bind(&workspace.path).fetch_one(&mut **tx).await?;
    if bound != 1 {
        bail!("Automation project checkout binding changed");
    }
    validate_dependencies(tx, &workspace.id).await?;
    let tabs: Vec<(String, String)> =
        sqlx::query_as("SELECT id, payloadJson FROM workspaceTabs WHERE workspaceId = ?")
            .bind(&workspace.id)
            .fetch_all(&mut **tx)
            .await?;
    for (id, json) in tabs {
        let payload: serde_json::Value = serde_json::from_str(&json)?;
        let owned_id = (run.owned_tab && run.tab_id.as_deref() == Some(&id))
            || run.setup_tab_id.as_deref() == Some(&id);
        if !owned_id
            || payload["automationRunId"].as_str() != Some(&run.id)
            || payload["automationOwned"].as_bool() != Some(true)
        {
            bail!("Automation task contains a tab owned or changed by another user or execution");
        }
    }
    Ok(())
}

pub(super) async fn validate_dependencies(
    tx: &mut Transaction<'_, Sqlite>,
    workspace_id: &str,
) -> Result<()> {
    let dependent_runs = format!("SELECT count(*) FROM automationRuns WHERE status NOT IN ({}) AND (json_extract(dataJson, '$.workspaceId') = ? OR json_extract(dataJson, '$.targetIdentity.workspaceId') = ?)", super::project_automation_dependencies::FINAL_RUNS);
    let live_runs: i64 = sqlx::query_scalar(sqlx::AssertSqlSafe(dependent_runs))
        .bind(workspace_id)
        .bind(workspace_id)
        .fetch_one(&mut **tx)
        .await?;
    let active_targets: i64 = sqlx::query_scalar("SELECT count(*) FROM automations WHERE state = 'active' AND COALESCE(json_extract(dataJson, '$.target.existingTab.workspaceId'), json_extract(dataJson, '$.target.existingTab.workspace_id'), json_extract(dataJson, '$.target.freshTab.workspaceId'), json_extract(dataJson, '$.target.freshTab.workspace_id'), json_extract(dataJson, '$.target.managedWorkspace.sourceWorkspaceId'), json_extract(dataJson, '$.target.managedWorkspace.source_workspace_id')) = ?")
        .bind(workspace_id).fetch_one(&mut **tx).await?;
    if live_runs != 0 || active_targets != 0 {
        bail!("Another automation still depends on this task");
    }
    Ok(())
}
