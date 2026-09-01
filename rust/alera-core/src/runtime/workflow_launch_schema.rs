use anyhow::Result;

use super::RuntimeStore;

impl RuntimeStore {
    pub(super) async fn migrate_workflow_launches(&self) -> Result<()> {
        let mut tx = self.pool().begin().await?;
        for statement in SCHEMA {
            sqlx::query(*statement).execute(&mut *tx).await?;
        }
        tx.commit().await?;
        Ok(())
    }
}

const SCHEMA: &[&str] = &[
    "CREATE TABLE IF NOT EXISTS workflowLaunches (
        sequence INTEGER PRIMARY KEY AUTOINCREMENT, id TEXT NOT NULL UNIQUE,
        request_id TEXT NOT NULL UNIQUE, request_digest TEXT NOT NULL, request TEXT NOT NULL,
        run_id TEXT NOT NULL, revision INTEGER NOT NULL, task_id TEXT NOT NULL,
        workspace_id TEXT NOT NULL UNIQUE REFERENCES workflowWorkspaces(id),
        terminal_handle TEXT NOT NULL UNIQUE, dispatch_id TEXT NOT NULL UNIQUE,
        base_sha TEXT NOT NULL, profile_id TEXT NOT NULL, profile_revision INTEGER NOT NULL,
        inputs TEXT NOT NULL, context_hash TEXT NOT NULL,
        status TEXT NOT NULL CHECK(status IN ('reserved','starting','started','attention')),
        error TEXT, created_at TEXT NOT NULL DEFAULT (datetime('now')),
        updated_at TEXT NOT NULL DEFAULT (datetime('now'))
    )",
    "CREATE INDEX IF NOT EXISTS workflowLaunchRun ON workflowLaunches(run_id, sequence)",
    "CREATE TRIGGER IF NOT EXISTS workflowLaunchTabInsert BEFORE INSERT ON workspaceTabs
        WHEN EXISTS(SELECT 1 FROM workflowLaunches l WHERE l.terminal_handle = NEW.id
          AND (l.workspace_id IS NOT NEW.workspaceId OR NEW.kind <> 'terminal'
            OR json_extract(NEW.payloadJson,'$.terminalSessionId') IS NOT l.terminal_handle
            OR (l.status <> 'starting' AND NOT EXISTS(SELECT 1 FROM workspaceTabs WHERE id = NEW.id))))
        BEGIN SELECT RAISE(ABORT, 'workflow terminal identity requires its one-shot launch'); END",
    "CREATE TRIGGER IF NOT EXISTS workflowLaunchTabUpdate BEFORE UPDATE OF id, workspaceId, kind, payloadJson ON workspaceTabs
        WHEN EXISTS(SELECT 1 FROM workflowLaunches l WHERE l.terminal_handle = OLD.id
          AND (NEW.id IS NOT OLD.id OR l.workspace_id IS NOT NEW.workspaceId OR NEW.kind <> 'terminal'
            OR json_extract(NEW.payloadJson,'$.terminalSessionId') IS NOT l.terminal_handle))
        BEGIN SELECT RAISE(ABORT, 'workflow terminal identity is immutable'); END",
    "CREATE TRIGGER IF NOT EXISTS workflowLaunchTabRetained BEFORE DELETE ON workspaceTabs
        WHEN EXISTS(SELECT 1 FROM workflowLaunches l WHERE l.terminal_handle = OLD.id)
        BEGIN SELECT RAISE(ABORT, 'workflow terminals require reviewed cleanup'); END",
    "CREATE TRIGGER IF NOT EXISTS workflowCompletedTaskRetained BEFORE UPDATE OF status ON orchestrationTasks
        WHEN OLD.status = 'completed' AND NEW.status <> 'completed'
          AND EXISTS(SELECT 1 FROM workflowPlanTasks WHERE task_id = OLD.id)
        BEGIN SELECT RAISE(ABORT, 'completed workflow tasks require a correction revision'); END",
    "CREATE TRIGGER IF NOT EXISTS workflowDispatchAcceptance BEFORE UPDATE OF status ON orchestrationDispatchContexts
        WHEN NEW.status = 'dispatched' AND OLD.status <> 'dispatched'
          AND EXISTS(SELECT 1 FROM workflowLaunches WHERE dispatch_id = OLD.id)
          AND NOT EXISTS(SELECT 1 FROM workflowLaunches l JOIN workflowRuns r ON r.run_id = l.run_id
            AND r.revision = l.revision WHERE l.dispatch_id = OLD.id AND l.status IN ('starting','started') AND r.status = 'approved')
        BEGIN SELECT RAISE(ABORT, 'workflow dispatch acceptance requires its current approved launch'); END",
    "CREATE TRIGGER IF NOT EXISTS workflowLaunchImmutable BEFORE UPDATE OF
        id,request_id,request_digest,request,run_id,revision,task_id,workspace_id,terminal_handle,dispatch_id,base_sha,profile_id,profile_revision,inputs,context_hash ON workflowLaunches
        BEGIN SELECT RAISE(ABORT, 'workflow launch identity is immutable'); END",
    "CREATE TRIGGER IF NOT EXISTS workflowLaunchRetained BEFORE DELETE ON workflowLaunches
        BEGIN SELECT RAISE(ABORT, 'workflow launch receipts require reviewed cleanup'); END",
    // Install only after its referenced tables exist, replacing the PR6 blanket
    // barrier with a reservation proof that ordinary dispatch cannot manufacture.
    "DROP TRIGGER IF EXISTS workflowDispatchBlocked",
    "CREATE TRIGGER workflowDispatchBlocked BEFORE INSERT ON orchestrationDispatchContexts
        WHEN (EXISTS(SELECT 1 FROM workflowPlanTasks WHERE task_id = NEW.task_id)
          OR EXISTS(SELECT 1 FROM workflowRuns WHERE run_id = NEW.run_id))
          AND NOT EXISTS(SELECT 1 FROM workflowLaunches l
            JOIN workflowWorkspaces x ON x.id = l.workspace_id
            JOIN workflowRuns r ON r.run_id = l.run_id AND r.revision = l.revision
            WHERE l.dispatch_id = NEW.id AND l.task_id = NEW.task_id AND l.run_id = NEW.run_id
              AND l.workspace_id = NEW.workspace_id AND l.terminal_handle = NEW.assignee_handle
              AND l.context_hash = NEW.context_token_hash AND l.status = 'reserved'
              AND r.status = 'approved' AND x.phase = 'ready' AND x.dispatch_id = NEW.id
              AND NEW.status = 'awaiting_acceptance' AND NEW.coordinator_handle = ''
              AND NEW.completion_policy = 'return-immediately' AND NEW.terminal_policy = 'keep-open')
        BEGIN SELECT RAISE(ABORT, 'workflow execution requires an approved isolated launch reservation'); END",
    "CREATE TRIGGER IF NOT EXISTS workflowDispatchIdentityImmutable BEFORE UPDATE OF
        id,task_id,run_id,workspace_id,assignee_handle,coordinator_handle,context_token_hash ON orchestrationDispatchContexts
        WHEN EXISTS(SELECT 1 FROM workflowLaunches WHERE dispatch_id = OLD.id)
          AND (OLD.id IS NOT NEW.id OR OLD.task_id IS NOT NEW.task_id OR OLD.run_id IS NOT NEW.run_id
            OR OLD.workspace_id IS NOT NEW.workspace_id OR OLD.assignee_handle IS NOT NEW.assignee_handle
            OR OLD.coordinator_handle IS NOT NEW.coordinator_handle OR OLD.context_token_hash IS NOT NEW.context_token_hash)
        BEGIN SELECT RAISE(ABORT, 'workflow dispatch identity is immutable'); END",
    "CREATE TRIGGER IF NOT EXISTS workflowCompletionShaImmutable BEFORE UPDATE OF completion_sha ON orchestrationDispatchContexts
        WHEN OLD.completion_sha IS NOT NULL AND NEW.completion_sha IS NOT OLD.completion_sha
        BEGIN SELECT RAISE(ABORT, 'workflow completion SHA is immutable'); END",
    "CREATE TRIGGER IF NOT EXISTS workflowCompletionShaRequired BEFORE UPDATE OF status ON orchestrationDispatchContexts
        WHEN NEW.status = 'completed' AND EXISTS(SELECT 1 FROM workflowLaunches WHERE dispatch_id = OLD.id)
          AND NEW.completion_sha IS NULL
        BEGIN SELECT RAISE(ABORT, 'workflow completion requires its exact result SHA'); END",
];
