use anyhow::{bail, Result};
use serde::{Deserialize, Serialize};
use sqlx::{Sqlite, Transaction};

use super::{RuntimeStore, Workspace, WorkspaceKind, LOCAL_HOST_ID};

/// The authenticated Home runtime supplies this scope after checking its run
/// and original allocation. The owner independently checks its current state.
#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct RemoteAutomationCleanup {
    pub run_id: String,
    pub workspace: Workspace,
    pub tab_ids: Vec<String>,
}

impl RuntimeStore {
    pub async fn require_remote_automation_cleanup(
        &self,
        scope: &RemoteAutomationCleanup,
        workspace: &Workspace,
    ) -> Result<()> {
        let mut tx = self.pool().begin().await?;
        validate(&mut tx, scope, workspace).await?;
        tx.commit().await?;
        Ok(())
    }

    /// Call only after the owning runtime has verified buffers and process closure.
    pub async fn retire_verified_remote_automation_workspace(
        &self,
        scope: &RemoteAutomationCleanup,
        workspace: &Workspace,
    ) -> Result<()> {
        self.remove_workspace_with_receipt(&workspace.id, true, Some(workspace), None, Some(scope))
            .await
    }
}

pub(super) async fn validate(
    tx: &mut Transaction<'_, Sqlite>,
    scope: &RemoteAutomationCleanup,
    workspace: &Workspace,
) -> Result<()> {
    let expected = &scope.workspace;
    let ids: std::collections::HashSet<_> = scope.tab_ids.iter().collect();
    if scope.run_id.trim().is_empty()
        || ids.len() != scope.tab_ids.len()
        || scope.tab_ids.iter().any(|id| id.trim().is_empty())
        || expected.host_id != LOCAL_HOST_ID
        || workspace.host_id != LOCAL_HOST_ID
        || expected.kind != WorkspaceKind::Main
        || workspace.kind != WorkspaceKind::Main
        || expected.id != workspace.id
        || expected.instance_id != workspace.instance_id
        || expected.project_id != workspace.project_id
        || expected.path != workspace.path
        || expected.name != workspace.name
    {
        bail!("Remote automation cleanup scope does not match this task instance");
    }
    let untouched: i64 = sqlx::query_scalar("SELECT count(*) FROM workspaces w JOIN workspaceCheckoutBindings b ON b.workspaceId = w.id JOIN repositoryCheckouts c ON c.id = b.checkoutId WHERE w.id = ? AND w.instanceId = ? AND w.projectId = ? AND w.hostId = 'local' AND w.path = ? AND w.name = ? AND w.kind = 'main' AND w.status = 'active' AND w.isPinned = 0 AND w.isArchived = 0 AND c.kind = 'project' AND c.projectId = w.projectId AND c.hostId = w.hostId AND c.path = w.path AND NOT EXISTS (SELECT 1 FROM workspaceRelations r WHERE r.parentWorkspaceId = w.id OR r.childWorkspaceId = w.id) AND NOT EXISTS (SELECT 1 FROM workspaceTagAssignments t WHERE t.workspaceId = w.id) AND NOT EXISTS (SELECT 1 FROM workspaceSectionAssignments s WHERE s.workspaceId = w.id)")
        .bind(&expected.id).bind(&expected.instance_id).bind(&expected.project_id)
        .bind(&expected.path).bind(&expected.name).fetch_one(&mut **tx).await?;
    if untouched != 1 {
        bail!("Remote automation task identity or organization changed");
    }
    super::automation_shared_workspace_cleanup::validate_dependencies(tx, &workspace.id).await?;
    let tabs: Vec<(String, String)> =
        sqlx::query_as("SELECT id, payloadJson FROM workspaceTabs WHERE workspaceId = ?")
            .bind(&workspace.id)
            .fetch_all(&mut **tx)
            .await?;
    for (id, json) in tabs {
        let payload: serde_json::Value = serde_json::from_str(&json)?;
        if !ids.contains(&id)
            || payload["automationOwned"] != true
            || payload["automationRunId"].as_str() != Some(scope.run_id.as_str())
        {
            bail!("Remote task contains a tab outside this automation cleanup scope");
        }
    }
    Ok(())
}

#[cfg(test)]
#[path = "remote_automation_cleanup_tests.rs"]
mod tests;
