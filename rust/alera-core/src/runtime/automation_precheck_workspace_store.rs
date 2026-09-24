use anyhow::{bail, Result};
use serde::{Deserialize, Serialize};
use sqlx::SqliteConnection;

use super::{OwnerAutomationPrecheckRequest, RuntimeStore, WorkspaceKind, LOCAL_HOST_ID};

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct AutomationPrecheckWorkspace {
    pub workspace_id: String,
    pub instance_id: String,
    pub kind: WorkspaceKind,
    pub repository_path: Option<String>,
}

pub(super) async fn capture_workspace(
    connection: &mut SqliteConnection,
    workspace_id: Option<&str>,
) -> Result<Option<AutomationPrecheckWorkspace>> {
    let Some(id) = workspace_id else {
        return Ok(None);
    };
    let (instance_id, kind, repository_path): (String, String, Option<String>) = sqlx::query_as(
        "SELECT w.instanceId, w.kind, c.repositoryPath FROM workspaces w JOIN workspaceCheckoutBindings b ON b.workspaceId = w.id JOIN repositoryCheckouts c ON c.id = b.checkoutId AND c.projectId = w.projectId AND c.hostId = w.hostId AND c.path = w.path WHERE w.id = ? AND w.status = 'active' AND ((w.kind = 'main' AND c.kind = 'project') OR (w.kind = 'linked' AND c.kind = 'linked'))",
    ).bind(id).fetch_one(&mut *connection).await?;
    if instance_id.trim().is_empty() {
        bail!("A precheck requires stable workspace instance ownership");
    }
    Ok(Some(AutomationPrecheckWorkspace {
        workspace_id: id.into(),
        instance_id,
        kind: WorkspaceKind::from_db(&kind),
        repository_path,
    }))
}

pub(super) async fn owner_target_registered(
    connection: &mut SqliteConnection,
    request: &OwnerAutomationPrecheckRequest,
) -> Result<bool> {
    let Some(workspace) = &request.workspace else {
        return Ok(sqlx::query_scalar("SELECT EXISTS (SELECT 1 FROM repositoryCheckouts c JOIN projects p ON p.id = c.projectId WHERE c.projectId = ? AND c.hostId = ? AND c.path = ? AND c.kind = 'project')")
            .bind(&request.project_id).bind(LOCAL_HOST_ID).bind(&request.path).fetch_one(&mut *connection).await?);
    };
    if workspace.kind != WorkspaceKind::Linked
        || workspace.workspace_id.trim().is_empty()
        || workspace.instance_id.trim().is_empty()
        || workspace
            .repository_path
            .as_ref()
            .is_none_or(|path| path.trim().is_empty())
    {
        bail!(
            "An owner linked precheck requires its exact workspace, instance and repository origin"
        );
    }
    Ok(sqlx::query_scalar("SELECT EXISTS (SELECT 1 FROM workspaces w JOIN projects p ON p.id = w.projectId JOIN workspaceCheckoutBindings b ON b.workspaceId = w.id JOIN repositoryCheckouts c ON c.id = b.checkoutId WHERE w.id = ? AND w.instanceId = ? AND w.projectId = ? AND w.hostId = ? AND w.path = ? AND w.kind = 'linked' AND w.status = 'active' AND c.projectId = w.projectId AND c.hostId = w.hostId AND c.path = w.path AND c.kind = 'linked' AND c.repositoryPath = ?)")
        .bind(&workspace.workspace_id).bind(&workspace.instance_id).bind(&request.project_id)
        .bind(LOCAL_HOST_ID).bind(&request.path).bind(&workspace.repository_path)
        .fetch_one(&mut *connection).await?)
}

impl RuntimeStore {
    pub(super) async fn migrate_precheck_workspace_fences(&self) -> Result<()> {
        for statement in [
            "CREATE TRIGGER IF NOT EXISTS preservePrecheckWorkspaceDeletion BEFORE DELETE ON workspaces WHEN EXISTS (SELECT 1 FROM automationPrecheckProcesses p WHERE json_extract(p.recordJson, '$.workspace.workspaceId') = OLD.id AND COALESCE(json_extract(p.recordJson, '$.phase'), '') NOT IN ('spawnFailed','closureVerified')) BEGIN SELECT RAISE(ABORT, 'Workspace precheck closure is unverified'); END",
            "CREATE TRIGGER IF NOT EXISTS preservePrecheckWorkspaceIdentity BEFORE UPDATE ON workspaces WHEN (NEW.id != OLD.id OR NEW.instanceId != OLD.instanceId OR NEW.projectId != OLD.projectId OR NEW.hostId != OLD.hostId OR NEW.path != OLD.path OR NEW.kind != OLD.kind OR NEW.status != OLD.status) AND EXISTS (SELECT 1 FROM automationPrecheckProcesses p WHERE json_extract(p.recordJson, '$.workspace.workspaceId') = OLD.id AND COALESCE(json_extract(p.recordJson, '$.phase'), '') NOT IN ('spawnFailed','closureVerified')) BEGIN SELECT RAISE(ABORT, 'Workspace precheck closure is unverified'); END",
            "CREATE TRIGGER IF NOT EXISTS preservePrecheckBindingDeletion BEFORE DELETE ON workspaceCheckoutBindings WHEN EXISTS (SELECT 1 FROM automationPrecheckProcesses p WHERE json_extract(p.recordJson, '$.workspace.workspaceId') = OLD.workspaceId AND COALESCE(json_extract(p.recordJson, '$.phase'), '') NOT IN ('spawnFailed','closureVerified')) BEGIN SELECT RAISE(ABORT, 'Precheck checkout ownership is still reserved'); END",
            "CREATE TRIGGER IF NOT EXISTS preservePrecheckBindingUpdate BEFORE UPDATE ON workspaceCheckoutBindings WHEN (NEW.workspaceId != OLD.workspaceId OR NEW.checkoutId != OLD.checkoutId) AND EXISTS (SELECT 1 FROM automationPrecheckProcesses p WHERE json_extract(p.recordJson, '$.workspace.workspaceId') = OLD.workspaceId AND COALESCE(json_extract(p.recordJson, '$.phase'), '') NOT IN ('spawnFailed','closureVerified')) BEGIN SELECT RAISE(ABORT, 'Precheck checkout ownership is still reserved'); END",
            "CREATE TRIGGER IF NOT EXISTS preservePrecheckCheckoutDeletion BEFORE DELETE ON repositoryCheckouts WHEN EXISTS (SELECT 1 FROM automationPrecheckProcesses p WHERE p.projectId = OLD.projectId AND json_extract(p.recordJson, '$.hostId') = OLD.hostId AND json_extract(p.recordJson, '$.path') = OLD.path AND COALESCE(json_extract(p.recordJson, '$.phase'), '') NOT IN ('spawnFailed','closureVerified')) BEGIN SELECT RAISE(ABORT, 'Checkout precheck closure is unverified'); END",
            "CREATE TRIGGER IF NOT EXISTS preservePrecheckCheckoutUpdate BEFORE UPDATE ON repositoryCheckouts WHEN (NEW.id != OLD.id OR NEW.projectId != OLD.projectId OR NEW.hostId != OLD.hostId OR NEW.path != OLD.path OR NEW.kind != OLD.kind OR NEW.repositoryPath IS NOT OLD.repositoryPath) AND EXISTS (SELECT 1 FROM automationPrecheckProcesses p WHERE p.projectId = OLD.projectId AND json_extract(p.recordJson, '$.hostId') = OLD.hostId AND json_extract(p.recordJson, '$.path') = OLD.path AND COALESCE(json_extract(p.recordJson, '$.phase'), '') NOT IN ('spawnFailed','closureVerified')) BEGIN SELECT RAISE(ABORT, 'Checkout precheck closure is unverified'); END",
        ] { sqlx::query(statement).execute(self.pool()).await?; }
        Ok(())
    }
}

impl RuntimeStore {
    pub(super) async fn migrate_pending_owner_precheck_fences(&self) -> Result<()> {
        let pending_workspace = "EXISTS (SELECT 1 FROM ownerAutomationPrechecks p WHERE p.cancelRequested = 0 AND p.processId IS NULL AND json_extract(p.requestJson, '$.workspace.workspaceId') = OLD.id)";
        let pending_binding = "EXISTS (SELECT 1 FROM ownerAutomationPrechecks p WHERE p.cancelRequested = 0 AND p.processId IS NULL AND json_extract(p.requestJson, '$.workspace.workspaceId') = OLD.workspaceId)";
        let pending_checkout = "OLD.hostId = 'local' AND EXISTS (SELECT 1 FROM ownerAutomationPrechecks p WHERE p.cancelRequested = 0 AND p.processId IS NULL AND p.projectId = OLD.projectId AND json_extract(p.requestJson, '$.path') = OLD.path AND json_extract(p.requestJson, '$.workspace') IS NOT NULL)";
        for (name, operation, table, changed, pending) in [
            ("preservePendingOwnerWorkspaceDelete", "DELETE", "workspaces", "1", pending_workspace),
            ("preservePendingOwnerWorkspaceUpdate", "UPDATE", "workspaces", "NEW.id != OLD.id OR NEW.instanceId != OLD.instanceId OR NEW.projectId != OLD.projectId OR NEW.hostId != OLD.hostId OR NEW.path != OLD.path OR NEW.kind != OLD.kind OR NEW.status != OLD.status", pending_workspace),
            ("preservePendingOwnerBindingDelete", "DELETE", "workspaceCheckoutBindings", "1", pending_binding),
            ("preservePendingOwnerBindingUpdate", "UPDATE", "workspaceCheckoutBindings", "NEW.workspaceId != OLD.workspaceId OR NEW.checkoutId != OLD.checkoutId", pending_binding),
            ("preservePendingOwnerCheckoutDelete", "DELETE", "repositoryCheckouts", "1", pending_checkout),
            ("preservePendingOwnerCheckoutUpdate", "UPDATE", "repositoryCheckouts", "NEW.id != OLD.id OR NEW.projectId != OLD.projectId OR NEW.hostId != OLD.hostId OR NEW.path != OLD.path OR NEW.kind != OLD.kind OR NEW.repositoryPath IS NOT OLD.repositoryPath", pending_checkout),
        ] {
            let statement = format!("CREATE TRIGGER IF NOT EXISTS {name} BEFORE {operation} ON {table} WHEN ({changed}) AND ({pending}) BEGIN SELECT RAISE(ABORT, 'An owner precheck reserves this workspace; cancel it before retirement'); END");
            sqlx::query(sqlx::AssertSqlSafe(statement)).execute(self.pool()).await?;
        }
        Ok(())
    }
}

impl RuntimeStore {
    pub(super) async fn require_workspace_precheck_closure(
        &self,
        workspace_id: &str,
    ) -> Result<()> {
        // Linked retirement changes physical storage, including registrations
        // under another project. Shared task retirement only removes task state.
        let pending: bool = sqlx::query_scalar("SELECT EXISTS (SELECT 1 FROM ownerAutomationPrechecks p WHERE p.cancelRequested = 0 AND p.processId IS NULL AND (json_extract(p.requestJson, '$.workspace.workspaceId') = ? OR EXISTS (SELECT 1 FROM workspaces w LEFT JOIN workspaceCheckoutBindings b ON b.workspaceId = w.id LEFT JOIN repositoryCheckouts c ON c.id = b.checkoutId WHERE w.id = ? AND w.kind = 'linked' AND w.hostId = 'local' AND COALESCE(c.path, w.path) = json_extract(p.requestJson, '$.path')))) OR EXISTS (SELECT 1 FROM automationPrecheckProcesses p WHERE COALESCE(json_extract(p.recordJson, '$.phase'), '') NOT IN ('spawnFailed', 'closureVerified') AND (json_extract(p.recordJson, '$.workspace.workspaceId') = ? OR EXISTS (SELECT 1 FROM workspaces w LEFT JOIN workspaceCheckoutBindings b ON b.workspaceId = w.id LEFT JOIN repositoryCheckouts c ON c.id = b.checkoutId WHERE w.id = ? AND w.kind = 'linked' AND w.hostId = json_extract(p.recordJson, '$.hostId') AND COALESCE(c.path, w.path) = json_extract(p.recordJson, '$.path'))))")
            .bind(workspace_id).bind(workspace_id).bind(workspace_id).bind(workspace_id).fetch_one(self.pool()).await?;
        if pending {
            bail!("Workspace precheck closure is unresolved; cancel or recover its precheck before removal or relocation");
        }
        Ok(())
    }
}
