use anyhow::Result;

use super::RuntimeStore;

impl RuntimeStore {
    pub(super) async fn migrate_workflow_integrations(&self) -> Result<()> {
        let mut tx = self.pool().begin().await?;
        for statement in SCHEMA {
            sqlx::query(*statement).execute(&mut *tx).await?;
        }
        tx.commit().await?;
        Ok(())
    }
}

// Receipts survive run deletion just like owned workspaces. A missing owner is
// not permission to discard evidence of a Git operation awaiting reconciliation.
const SCHEMA: &[&str] = &[
    "CREATE TABLE IF NOT EXISTS workflowIntegrations (
        sequence INTEGER PRIMARY KEY AUTOINCREMENT, id TEXT NOT NULL UNIQUE,
        request_id TEXT NOT NULL UNIQUE, request_digest TEXT NOT NULL,
        run_id TEXT NOT NULL, revision INTEGER NOT NULL, task_id TEXT NOT NULL,
        workspace_id TEXT NOT NULL REFERENCES workflowWorkspaces(id), request TEXT NOT NULL,
        state TEXT NOT NULL CHECK(state IN ('pending','prepared','integrated','conflict','attention')),
        receipt TEXT, conflict_paths TEXT NOT NULL DEFAULT '[]', conflicts_truncated INTEGER NOT NULL DEFAULT 0,
        error TEXT, created_at TEXT NOT NULL DEFAULT (datetime('now')),
        updated_at TEXT NOT NULL DEFAULT (datetime('now'))
    )",
    "CREATE UNIQUE INDEX IF NOT EXISTS workflowUnsettledIntegration ON workflowIntegrations(run_id)
        WHERE state IN ('pending','prepared','attention')",
    "CREATE UNIQUE INDEX IF NOT EXISTS workflowIntegratedTask ON workflowIntegrations(task_id) WHERE state = 'integrated'",
    "CREATE INDEX IF NOT EXISTS workflowIntegrationRun ON workflowIntegrations(run_id, sequence)",
    "CREATE TRIGGER IF NOT EXISTS workflowIntegrationIdentityImmutable
        BEFORE UPDATE OF id, request_id, request_digest, run_id, revision, task_id, workspace_id, request ON workflowIntegrations
        BEGIN SELECT RAISE(ABORT, 'workflow integration identity is immutable'); END",
    "CREATE TRIGGER IF NOT EXISTS workflowIntegrationRetained BEFORE DELETE ON workflowIntegrations
        BEGIN SELECT RAISE(ABORT, 'workflow integration receipts require reviewed cleanup'); END",
    "CREATE TRIGGER IF NOT EXISTS workflowIntegratedReceiptImmutable BEFORE UPDATE ON workflowIntegrations
        WHEN OLD.state = 'integrated'
        BEGIN SELECT RAISE(ABORT, 'integrated workflow receipt is immutable'); END",
];
