use anyhow::Result;

pub(super) async fn install(conn: &mut sqlx::SqliteConnection) -> Result<()> {
    for statement in SCHEMA {
        sqlx::query(*statement).execute(&mut *conn).await?;
    }
    Ok(())
}

// Ownership intentionally survives legacy run/project resets. Neither resetting
// metadata nor cancelling a run grants permission to remove its Git resources.
const SCHEMA: &[&str] = &[
    "CREATE TABLE IF NOT EXISTS runWorkspaces (
        sequence INTEGER PRIMARY KEY AUTOINCREMENT, id TEXT NOT NULL UNIQUE,
        run_id TEXT NOT NULL, revision INTEGER NOT NULL, task_id TEXT,
        attempt INTEGER NOT NULL, path TEXT NOT NULL UNIQUE, identity TEXT NOT NULL,
        phase TEXT NOT NULL CHECK(phase IN ('reserved','creating','created','setupRunning','ready','attention')),
        setup_report TEXT, error TEXT, dispatch_id TEXT,
        created_at TEXT NOT NULL DEFAULT (datetime('now')),
        updated_at TEXT NOT NULL DEFAULT (datetime('now'))
    )",
    "CREATE UNIQUE INDEX IF NOT EXISTS runIntegrationWorkspace ON runWorkspaces(run_id) WHERE task_id IS NULL",
    "CREATE UNIQUE INDEX IF NOT EXISTS runTaskAttempt ON runWorkspaces(task_id, attempt) WHERE task_id IS NOT NULL",
    "CREATE INDEX IF NOT EXISTS runWorkspaceRun ON runWorkspaces(run_id, sequence DESC)",
    "CREATE INDEX IF NOT EXISTS runWorkspacePhase ON runWorkspaces(run_id, revision, phase)",
    "CREATE TABLE IF NOT EXISTS runWorkspaceRequests (
        request_id TEXT PRIMARY KEY, digest TEXT NOT NULL, workspace_id TEXT NOT NULL REFERENCES runWorkspaces(id)
    )",
    "CREATE TRIGGER IF NOT EXISTS runWorkspaceIdentityImmutable
        BEFORE UPDATE OF id, run_id, revision, task_id, attempt, path, identity ON runWorkspaces
        BEGIN SELECT RAISE(ABORT, 'workflow resource identity is immutable'); END",
    "CREATE TRIGGER IF NOT EXISTS runWorkspaceRecordProtected BEFORE DELETE ON runWorkspaces
        BEGIN SELECT RAISE(ABORT, 'workflow resources require reviewed cleanup'); END",
    "CREATE TRIGGER IF NOT EXISTS runManagedWorkspaceIdentityProtected
        BEFORE UPDATE OF id, instanceId, projectId, hostId, path, branch, kind ON workspaces
        WHEN EXISTS(SELECT 1 FROM runWorkspaces WHERE id = OLD.id)
          AND (OLD.id IS NOT NEW.id OR OLD.instanceId IS NOT NEW.instanceId
            OR OLD.projectId IS NOT NEW.projectId OR OLD.hostId IS NOT NEW.hostId
            OR OLD.path IS NOT NEW.path OR OLD.branch IS NOT NEW.branch OR OLD.kind IS NOT NEW.kind)
        BEGIN SELECT RAISE(ABORT, 'workflow workspace identity cannot be replaced'); END",
];
