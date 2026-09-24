use anyhow::{bail, Result};
use serde::{Deserialize, Serialize};

use super::{RuntimeStore, Workspace, LOCAL_HOST_ID};

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub enum TerminalLifecycleAction {
    Close,
    Restart,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct TerminalLifecycleOperation {
    pub id: String,
    pub workspace: Workspace,
    pub tab_id: String,
    pub session_id: String,
    pub session_generation: u64,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub initiator_epoch: Option<String>,
    pub action: TerminalLifecycleAction,
    pub closure_verified: bool,
}

impl RuntimeStore {
    pub async fn terminal_restart_launch_token(
        &self,
        workspace: &Workspace,
        tab_id: &str,
        session_id: &str,
    ) -> Result<Option<String>> {
        Ok(sqlx::query_scalar("SELECT id FROM terminalLifecycleOperations WHERE workspaceId = ? AND tabId = ? AND sessionId = ? AND closed = 1 AND json_extract(recordJson, '$.workspace.instanceId') = ? AND json_extract(recordJson, '$.action') = 'restart' AND COALESCE(json_extract(recordJson, '$.initiatorEpoch'), '') NOT LIKE 'natural-exit:%' ORDER BY rowid DESC LIMIT 1")
            .bind(&workspace.id).bind(tab_id).bind(session_id).bind(&workspace.instance_id)
            .fetch_optional(self.pool()).await?)
    }

    pub(super) async fn migrate_terminal_lifecycle_operations(&self) -> Result<()> {
        for statement in [
            "CREATE TABLE IF NOT EXISTS terminalLifecycleOperations (id TEXT PRIMARY KEY, workspaceId TEXT NOT NULL, tabId TEXT NOT NULL, sessionId TEXT NOT NULL, closed INTEGER NOT NULL DEFAULT 0, recordJson TEXT NOT NULL)",
            "CREATE UNIQUE INDEX IF NOT EXISTS pendingTerminalLifecycleSession ON terminalLifecycleOperations(sessionId) WHERE closed = 0",
            "CREATE TRIGGER IF NOT EXISTS preservePendingTerminalWorkspace BEFORE DELETE ON workspaces WHEN EXISTS (SELECT 1 FROM terminalLifecycleOperations WHERE workspaceId = OLD.id AND closed = 0) BEGIN SELECT RAISE(ABORT, 'Terminal process closure is unverified'); END",
            "CREATE TRIGGER IF NOT EXISTS preservePendingTerminalLocation BEFORE UPDATE ON workspaces WHEN (OLD.id != NEW.id OR OLD.instanceId != NEW.instanceId OR OLD.hostId != NEW.hostId OR OLD.projectId != NEW.projectId OR OLD.path != NEW.path OR OLD.kind != NEW.kind) AND EXISTS (SELECT 1 FROM terminalLifecycleOperations WHERE workspaceId = OLD.id AND closed = 0) BEGIN SELECT RAISE(ABORT, 'Terminal process closure is unverified'); END",
            "CREATE TRIGGER IF NOT EXISTS preservePendingTerminalTabIdentity BEFORE UPDATE ON workspaceTabs WHEN (OLD.id != NEW.id OR OLD.workspaceId != NEW.workspaceId OR OLD.kind != NEW.kind OR COALESCE(json_extract(OLD.payloadJson, '$.terminalSessionId'), '') != COALESCE(json_extract(NEW.payloadJson, '$.terminalSessionId'), '')) AND EXISTS (SELECT 1 FROM terminalLifecycleOperations WHERE tabId = OLD.id AND closed = 0) BEGIN SELECT RAISE(ABORT, 'Terminal process closure is unverified'); END",
            "CREATE TRIGGER IF NOT EXISTS preservePendingTerminalTab BEFORE DELETE ON workspaceTabs WHEN EXISTS (SELECT 1 FROM terminalLifecycleOperations WHERE tabId = OLD.id AND closed = 0) BEGIN SELECT RAISE(ABORT, 'Terminal process closure is unverified'); END",
        ] {
            sqlx::query(statement).execute(self.pool()).await?;
        }
        Ok(())
    }

    pub async fn terminal_lifecycle_operation(
        &self,
        id: &str,
    ) -> Result<Option<TerminalLifecycleOperation>> {
        let record: Option<String> =
            sqlx::query_scalar("SELECT recordJson FROM terminalLifecycleOperations WHERE id = ?")
                .bind(id)
                .fetch_optional(self.pool())
                .await?;
        record
            .map(|record| serde_json::from_str(&record).map_err(Into::into))
            .transpose()
    }

    /// Record before signalling the captured session. Reuse never targets a new generation.
    pub async fn begin_terminal_lifecycle_operation(
        &self,
        operation: &TerminalLifecycleOperation,
    ) -> Result<TerminalLifecycleOperation> {
        if operation.workspace.host_id != LOCAL_HOST_ID {
            bail!("Owner terminal actions require a local workspace");
        }
        self.begin_scoped_terminal_lifecycle_operation(operation, false)
            .await
    }

    pub async fn begin_remote_terminal_lifecycle_operation(
        &self,
        operation: &TerminalLifecycleOperation,
    ) -> Result<TerminalLifecycleOperation> {
        if operation.workspace.host_id.trim().is_empty()
            || operation.workspace.host_id == LOCAL_HOST_ID
        {
            bail!("Remote terminal actions require an SSH workspace");
        }
        self.begin_scoped_terminal_lifecycle_operation(operation, false)
            .await
    }

    pub async fn begin_never_started_terminal_close(
        &self,
        operation: &TerminalLifecycleOperation,
    ) -> Result<TerminalLifecycleOperation> {
        if operation.workspace.host_id != LOCAL_HOST_ID
            || operation.action != TerminalLifecycleAction::Close
        {
            bail!("Never-started terminal closure requires a local owner and Close action");
        }
        self.begin_scoped_terminal_lifecycle_operation(operation, true)
            .await
    }

    pub async fn begin_never_started_terminal_operation(
        &self,
        operation: &TerminalLifecycleOperation,
    ) -> Result<TerminalLifecycleOperation> {
        if operation.workspace.host_id != LOCAL_HOST_ID {
            bail!("Never-started terminal recovery requires a local owner");
        }
        self.begin_scoped_terminal_lifecycle_operation(operation, true)
            .await
    }

    pub async fn pending_terminal_lifecycle_for_session(
        &self,
        session_id: &str,
    ) -> Result<Option<TerminalLifecycleOperation>> {
        let record: Option<String> = sqlx::query_scalar(
            "SELECT recordJson FROM terminalLifecycleOperations WHERE sessionId = ? AND closed = 0",
        )
        .bind(session_id)
        .fetch_optional(self.pool())
        .await?;
        record
            .map(|record| serde_json::from_str(&record).map_err(Into::into))
            .transpose()
    }

    pub async fn terminal_lifecycle_for_generation(
        &self,
        session_id: &str,
        generation: u64,
        epoch: Option<&str>,
        action: TerminalLifecycleAction,
    ) -> Result<Option<TerminalLifecycleOperation>> {
        let record: Option<String> = sqlx::query_scalar("SELECT recordJson FROM terminalLifecycleOperations WHERE sessionId = ? AND json_extract(recordJson, '$.sessionGeneration') = ? AND json_extract(recordJson, '$.initiatorEpoch') IS ? AND json_extract(recordJson, '$.action') = ? ORDER BY rowid DESC LIMIT 1")
            .bind(session_id).bind(generation as i64).bind(epoch)
            .bind(serde_json::to_value(action)?.as_str().unwrap_or_default())
            .fetch_optional(self.pool()).await?;
        record
            .map(|record| serde_json::from_str(&record).map_err(Into::into))
            .transpose()
    }

    async fn begin_scoped_terminal_lifecycle_operation(
        &self,
        operation: &TerminalLifecycleOperation,
        require_never_started: bool,
    ) -> Result<TerminalLifecycleOperation> {
        if operation.closure_verified
            || operation.id.trim().is_empty()
            || operation.tab_id.trim().is_empty()
            || operation.session_id.trim().is_empty()
            || operation.session_generation == 0
        {
            bail!("A pending terminal action requires exact task and session identities");
        }
        let mut tx = self.pool().begin().await?;
        let existing: Option<String> =
            sqlx::query_scalar("SELECT recordJson FROM terminalLifecycleOperations WHERE id = ?")
                .bind(&operation.id)
                .fetch_optional(&mut *tx)
                .await?;
        if let Some(existing) = existing {
            let saved: TerminalLifecycleOperation = serde_json::from_str(&existing)?;
            let mut expected = saved.clone();
            expected.closure_verified = false;
            if &expected != operation {
                bail!("Terminal action identity changed; preserve the original operation");
            }
            if require_never_started {
                let attempted: Option<bool> = sqlx::query_scalar("SELECT attempted FROM terminalLaunchAttempts WHERE workspaceId = ? AND instanceId = ? AND tabId = ? AND sessionId = ?")
                    .bind(&operation.workspace.id).bind(&operation.workspace.instance_id)
                    .bind(&operation.tab_id).bind(&operation.session_id)
                    .fetch_optional(&mut *tx).await?;
                if attempted != Some(false) {
                    bail!("The terminal has no verified never-started evidence");
                }
            }
            return Ok(saved);
        }
        let workspace = &operation.workspace;
        let inserted = sqlx::query("INSERT INTO terminalLifecycleOperations (id, workspaceId, tabId, sessionId, recordJson) SELECT ?, w.id, t.id, ?, ? FROM workspaces w JOIN workspaceTabs t ON t.workspaceId = w.id WHERE w.id = ? AND w.instanceId = ? AND w.hostId = ? AND w.projectId = ? AND w.path = ? AND w.kind = ? AND w.status = 'active' AND t.id = ? AND t.kind = 'terminal' AND json_extract(t.payloadJson, '$.terminalSessionId') = ? AND (? = 0 OR EXISTS (SELECT 1 FROM terminalLaunchAttempts a WHERE a.workspaceId = w.id AND a.instanceId = w.instanceId AND a.tabId = t.id AND a.sessionId = json_extract(t.payloadJson, '$.terminalSessionId') AND a.attempted = 0))")
            .bind(&operation.id).bind(&operation.session_id).bind(serde_json::to_string(operation)?)
            .bind(&workspace.id).bind(&workspace.instance_id).bind(&workspace.host_id).bind(&workspace.project_id).bind(&workspace.path)
            .bind(workspace.kind.as_str()).bind(&operation.tab_id).bind(&operation.session_id).bind(require_never_started).execute(&mut *tx).await?;
        if inserted.rows_affected() != 1 {
            bail!("Terminal task or tab ownership changed before closure");
        }
        tx.commit().await?;
        Ok(operation.clone())
    }

    /// Call only after verifying the whole process scope captured before termination.
    pub async fn complete_terminal_lifecycle_operation(
        &self,
        operation: &TerminalLifecycleOperation,
    ) -> Result<TerminalLifecycleOperation> {
        if operation.workspace.host_id != LOCAL_HOST_ID {
            bail!("Remote terminal closure requires evidence from its owner");
        }
        self.complete_scoped_terminal_lifecycle_operation(operation)
            .await
    }

    pub async fn complete_remote_terminal_lifecycle_operation(
        &self,
        operation: &TerminalLifecycleOperation,
        owner: &TerminalLifecycleOperation,
    ) -> Result<TerminalLifecycleOperation> {
        let mut expected_workspace = operation.workspace.clone();
        expected_workspace.host_id = LOCAL_HOST_ID.into();
        let actual = &owner.workspace;
        if operation.workspace.host_id == LOCAL_HOST_ID
            || !owner.closure_verified
            || owner.session_generation == 0
            || owner.id != operation.id
            || owner.tab_id != operation.tab_id
            || owner.session_id != operation.session_id
            || owner.action != operation.action
            || actual.id != expected_workspace.id
            || actual.instance_id != expected_workspace.instance_id
            || actual.project_id != expected_workspace.project_id
            || actual.host_id != expected_workspace.host_id
            || actual.path != expected_workspace.path
            || actual.kind != expected_workspace.kind
        {
            bail!("Remote terminal closure evidence belongs to another operation or checkout");
        }
        self.complete_scoped_terminal_lifecycle_operation(operation)
            .await
    }

    async fn complete_scoped_terminal_lifecycle_operation(
        &self,
        operation: &TerminalLifecycleOperation,
    ) -> Result<TerminalLifecycleOperation> {
        let mut completed = operation.clone();
        completed.closure_verified = true;
        let mut tx = self.pool().begin().await?;
        let updated = sqlx::query("UPDATE terminalLifecycleOperations SET closed = 1, recordJson = ? WHERE id = ? AND recordJson = ?")
            .bind(serde_json::to_string(&completed)?).bind(&operation.id).bind(serde_json::to_string(operation)?).execute(&mut *tx).await?;
        if updated.rows_affected() != 1 {
            bail!("Terminal closure evidence changed; reload the original operation");
        }
        if operation.action == TerminalLifecycleAction::Close {
            // Release the launch barrier and remove its tab atomically, so a
            // replacement cannot appear between acknowledgement and cleanup.
            let removed = sqlx::query("DELETE FROM workspaceTabs WHERE id = ? AND workspaceId = ? AND kind = 'terminal' AND json_extract(payloadJson, '$.terminalSessionId') = ?")
                .bind(&operation.tab_id).bind(&operation.workspace.id).bind(&operation.session_id)
                .execute(&mut *tx).await?;
            if removed.rows_affected() != 1 {
                bail!("Terminal tab ownership changed before verified closure was recorded");
            }
        }
        tx.commit().await?;
        Ok(completed)
    }

    pub async fn require_terminal_lifecycle_closed(&self, workspace_id: &str) -> Result<()> {
        let pending: Option<String> = sqlx::query_scalar("SELECT id FROM terminalLifecycleOperations WHERE workspaceId = ? AND closed = 0 LIMIT 1")
            .bind(workspace_id).fetch_optional(self.pool()).await?;
        if let Some(id) = pending {
            bail!("Terminal operation {id} has unverified process closure; recover it before replacing processes or moving this task");
        }
        Ok(())
    }
}

#[cfg(test)]
#[path = "terminal_lifecycle_store_tests.rs"]
mod tests;
