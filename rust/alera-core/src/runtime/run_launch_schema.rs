use anyhow::Result;

pub(super) async fn install(conn: &mut sqlx::SqliteConnection) -> Result<()> {
    for statement in SCHEMA {
        sqlx::query(*statement).execute(&mut *conn).await?;
    }
    Ok(())
}

const SCHEMA: &[&str] = &[
    "CREATE TABLE IF NOT EXISTS runLaunches (
        sequence INTEGER PRIMARY KEY AUTOINCREMENT, id TEXT NOT NULL UNIQUE,
        request_id TEXT NOT NULL UNIQUE, request_digest TEXT NOT NULL, request TEXT NOT NULL,
        run_id TEXT NOT NULL, revision INTEGER NOT NULL, task_id TEXT NOT NULL,
        workspace_id TEXT NOT NULL UNIQUE REFERENCES runWorkspaces(id),
        terminal_handle TEXT NOT NULL UNIQUE, dispatch_id TEXT NOT NULL UNIQUE,
        base_sha TEXT NOT NULL, profile_id TEXT NOT NULL, profile_revision INTEGER NOT NULL,
        inputs TEXT NOT NULL, context_hash TEXT NOT NULL,
        status TEXT NOT NULL CHECK(status IN ('reserved','starting','started','attention')),
        error TEXT, created_at TEXT NOT NULL DEFAULT (datetime('now')),
        updated_at TEXT NOT NULL DEFAULT (datetime('now'))
    )",
    "CREATE INDEX IF NOT EXISTS runLaunchRun ON runLaunches(run_id, sequence)",
    "CREATE TRIGGER IF NOT EXISTS runLaunchTabInsert BEFORE INSERT ON workspaceTabs
        WHEN EXISTS(SELECT 1 FROM runLaunches l WHERE l.terminal_handle = NEW.id
          AND (l.workspace_id IS NOT NEW.workspaceId OR NEW.kind <> 'terminal'
            OR json_extract(NEW.payloadJson,'$.terminalSessionId') IS NOT l.terminal_handle
            OR (l.status <> 'starting' AND NOT EXISTS(SELECT 1 FROM workspaceTabs WHERE id = NEW.id))))
        BEGIN SELECT RAISE(ABORT, 'workflow terminal identity requires its one-shot launch'); END",
    "CREATE TRIGGER IF NOT EXISTS runLaunchTabUpdate BEFORE UPDATE OF id, workspaceId, kind, payloadJson ON workspaceTabs
        WHEN EXISTS(SELECT 1 FROM runLaunches l WHERE l.terminal_handle = OLD.id
          AND (NEW.id IS NOT OLD.id OR l.workspace_id IS NOT NEW.workspaceId OR NEW.kind <> 'terminal'
            OR json_extract(NEW.payloadJson,'$.terminalSessionId') IS NOT l.terminal_handle))
        BEGIN SELECT RAISE(ABORT, 'workflow terminal identity is immutable'); END",
    "CREATE TRIGGER IF NOT EXISTS runLaunchTabRetained BEFORE DELETE ON workspaceTabs
        WHEN EXISTS(SELECT 1 FROM runLaunches l WHERE l.terminal_handle = OLD.id)
        BEGIN SELECT RAISE(ABORT, 'workflow terminals require reviewed cleanup'); END",
    "CREATE TRIGGER IF NOT EXISTS runCompletedTaskRetained BEFORE UPDATE OF status ON orchestrationTasks
        WHEN OLD.status = 'completed' AND NEW.status <> 'completed'
          AND OLD.plan_revision IS NOT NULL AND EXISTS(SELECT 1 FROM orchestrationCoordinatorRuns
            WHERE id = OLD.run_id AND isolation = 'isolated')
        BEGIN SELECT RAISE(ABORT, 'completed run tasks require a new plan revision'); END",
    "CREATE TRIGGER IF NOT EXISTS runStalledTaskRequiresSettlement BEFORE UPDATE OF status ON orchestrationTasks
        WHEN OLD.status = 'stalled' AND NEW.status IN ('ready','failed')
          AND OLD.plan_revision IS NOT NULL AND EXISTS(SELECT 1 FROM orchestrationCoordinatorRuns
            WHERE id = OLD.run_id AND isolation = 'isolated')
        BEGIN SELECT RAISE(ABORT, 'stalled isolated tasks require terminal settlement and a fresh attempt'); END",
    "DROP TRIGGER IF EXISTS runDispatchAcceptance",
    "CREATE TRIGGER runDispatchAcceptance BEFORE UPDATE OF status ON orchestrationDispatchContexts
        WHEN NEW.status = 'dispatched' AND OLD.status <> 'dispatched'
          AND EXISTS(SELECT 1 FROM runLaunches WHERE dispatch_id = OLD.id)
          AND NOT EXISTS(SELECT 1 FROM runLaunches l JOIN orchestrationCoordinatorRuns r ON r.id = l.run_id
            AND r.plan_revision = l.revision WHERE l.dispatch_id = OLD.id AND r.status IN ('running','paused')
              AND ((OLD.status = 'awaiting_acceptance' AND l.status IN ('starting','started'))
                OR (OLD.status = 'stalled' AND OLD.accepted_at IS NOT NULL
                  AND l.status IN ('starting','started','attention'))))
        BEGIN SELECT RAISE(ABORT, 'workflow dispatch acceptance requires its current approved launch'); END",
    "CREATE TRIGGER IF NOT EXISTS runLaunchImmutable BEFORE UPDATE OF
        id,request_id,request_digest,request,run_id,revision,task_id,workspace_id,terminal_handle,dispatch_id,base_sha,profile_id,profile_revision,inputs,context_hash ON runLaunches
        BEGIN SELECT RAISE(ABORT, 'workflow launch identity is immutable'); END",
    "CREATE TRIGGER IF NOT EXISTS runLaunchRetained BEFORE DELETE ON runLaunches
        BEGIN SELECT RAISE(ABORT, 'workflow launch receipts require reviewed cleanup'); END",
    // Isolated runs dispatch only through the attempt launch reserved for
    // the dispatch, which ordinary dispatch cannot manufacture.
    "DROP TRIGGER IF EXISTS runDispatchRequiresLaunch",
    "CREATE TRIGGER runDispatchRequiresLaunch BEFORE INSERT ON orchestrationDispatchContexts
        WHEN EXISTS(SELECT 1 FROM orchestrationCoordinatorRuns WHERE id = NEW.run_id AND isolation = 'isolated')
          AND NOT EXISTS(SELECT 1 FROM runLaunches l
            JOIN runWorkspaces x ON x.id = l.workspace_id
            JOIN orchestrationCoordinatorRuns r ON r.id = l.run_id AND r.plan_revision = l.revision
            WHERE l.dispatch_id = NEW.id AND l.task_id = NEW.task_id AND l.run_id = NEW.run_id
              AND l.workspace_id = NEW.workspace_id AND l.terminal_handle = NEW.assignee_handle
              AND l.context_hash = NEW.context_token_hash AND l.status = 'reserved'
              AND r.status = 'running' AND x.phase = 'ready' AND x.dispatch_id = NEW.id
              AND NEW.status = 'awaiting_acceptance' AND NEW.coordinator_handle = ''
              AND NEW.terminal_policy = 'keep-open')
        BEGIN SELECT RAISE(ABORT, 'isolated runs dispatch only through a reserved attempt launch'); END",
    "CREATE TRIGGER IF NOT EXISTS runDispatchIdentityImmutable BEFORE UPDATE OF
        id,task_id,run_id,workspace_id,assignee_handle,coordinator_handle,context_token_hash ON orchestrationDispatchContexts
        WHEN EXISTS(SELECT 1 FROM runLaunches WHERE dispatch_id = OLD.id)
          AND (OLD.id IS NOT NEW.id OR OLD.task_id IS NOT NEW.task_id OR OLD.run_id IS NOT NEW.run_id
            OR OLD.workspace_id IS NOT NEW.workspace_id OR OLD.assignee_handle IS NOT NEW.assignee_handle
            OR OLD.coordinator_handle IS NOT NEW.coordinator_handle OR OLD.context_token_hash IS NOT NEW.context_token_hash)
        BEGIN SELECT RAISE(ABORT, 'workflow dispatch identity is immutable'); END",
    "CREATE TRIGGER IF NOT EXISTS runCompletionShaImmutable BEFORE UPDATE OF completion_sha ON orchestrationDispatchContexts
        WHEN OLD.completion_sha IS NOT NULL AND NEW.completion_sha IS NOT OLD.completion_sha
        BEGIN SELECT RAISE(ABORT, 'workflow completion SHA is immutable'); END",
    "CREATE TRIGGER IF NOT EXISTS runCompletionShaRequired BEFORE UPDATE OF status ON orchestrationDispatchContexts
        WHEN NEW.status = 'completed' AND EXISTS(SELECT 1 FROM runLaunches WHERE dispatch_id = OLD.id)
          AND NEW.completion_sha IS NULL
        BEGIN SELECT RAISE(ABORT, 'workflow completion requires its exact result SHA'); END",
];
