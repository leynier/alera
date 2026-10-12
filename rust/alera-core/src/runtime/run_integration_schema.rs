use anyhow::Result;

pub(super) async fn install(conn: &mut sqlx::SqliteConnection) -> Result<()> {
    for statement in SCHEMA {
        sqlx::query(*statement).execute(&mut *conn).await?;
    }
    Ok(())
}

// Receipts survive run deletion just like owned workspaces. A missing owner is
// not permission to discard evidence of a Git operation awaiting reconciliation.
const SCHEMA: &[&str] = &[
    "CREATE TABLE IF NOT EXISTS runIntegrations (
        sequence INTEGER PRIMARY KEY AUTOINCREMENT, id TEXT NOT NULL UNIQUE,
        request_id TEXT NOT NULL UNIQUE, request_digest TEXT NOT NULL,
        run_id TEXT NOT NULL, revision INTEGER NOT NULL, task_id TEXT NOT NULL,
        workspace_id TEXT NOT NULL REFERENCES runWorkspaces(id), request TEXT NOT NULL,
        state TEXT NOT NULL CHECK(state IN ('pending','prepared','integrated','conflict','attention')),
        receipt TEXT, conflict_paths TEXT NOT NULL DEFAULT '[]', conflicts_truncated INTEGER NOT NULL DEFAULT 0,
        error TEXT, created_at TEXT NOT NULL DEFAULT (datetime('now')),
        updated_at TEXT NOT NULL DEFAULT (datetime('now')),
        cancelled INTEGER NOT NULL DEFAULT 0
    )",
    "CREATE UNIQUE INDEX IF NOT EXISTS runUnsettledIntegration ON runIntegrations(run_id)
        WHERE state IN ('pending','prepared','attention')",
    "CREATE UNIQUE INDEX IF NOT EXISTS runIntegratedTask ON runIntegrations(task_id) WHERE state = 'integrated'",
    "CREATE INDEX IF NOT EXISTS runIntegrationRun ON runIntegrations(run_id, sequence)",
    "CREATE INDEX IF NOT EXISTS runIntegrationTaskHistory ON runIntegrations(task_id, sequence)",
    "CREATE TRIGGER IF NOT EXISTS runIntegrationIdentityImmutable
        BEFORE UPDATE OF id, request_id, request_digest, run_id, revision, task_id, workspace_id, request ON runIntegrations
        BEGIN SELECT RAISE(ABORT, 'workflow integration identity is immutable'); END",
    "CREATE TRIGGER IF NOT EXISTS runIntegrationRetained BEFORE DELETE ON runIntegrations
        BEGIN SELECT RAISE(ABORT, 'workflow integration receipts require reviewed cleanup'); END",
    "CREATE TRIGGER IF NOT EXISTS runIntegratedReceiptImmutable BEFORE UPDATE ON runIntegrations
        WHEN OLD.state = 'integrated'
        BEGIN SELECT RAISE(ABORT, 'integrated workflow receipt is immutable'); END",
    "CREATE TRIGGER IF NOT EXISTS runCancelledIntegrationImmutable BEFORE UPDATE ON runIntegrations
        WHEN OLD.cancelled=1 BEGIN SELECT RAISE(ABORT, 'cancelled integration settlement is immutable'); END",
];
