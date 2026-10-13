//! Orchestration schema v3: runs, tasks, dispatches, messages, gates and the
//! run timeline. Every statement is idempotent so a v3 store reapplies it on
//! each open; `store_runs_v3_reset` applies it inside the reset transaction.

use anyhow::Result;
use sqlx::SqliteConnection;

pub(super) const ORCHESTRATION_SCHEMA_VERSION: &str = "3";
pub(super) const ORCHESTRATION_SCHEMA_VERSION_KEY: &str = "orchestration.schemaVersion";

// Timestamps in orchestration tables use SQLite's datetime('now') TEXT shape
// (UTC, second precision) so threshold comparisons can rely on lexicographic
// ordering. SQLite cannot ALTER a CHECK constraint, so widening an enum below
// needs a table rebuild.
const ORCHESTRATION_TABLES: &[&str] = &[
    "CREATE TABLE IF NOT EXISTS orchestrationMessages (
        id TEXT NOT NULL,
        from_handle TEXT NOT NULL,
        to_handle TEXT NOT NULL,
        subject TEXT NOT NULL,
        body TEXT NOT NULL DEFAULT '',
        type TEXT NOT NULL DEFAULT 'status'
            CHECK(type IN ('status','dispatch','merge_ready','escalation','handoff',
                           'decision_gate','question')),
        priority TEXT NOT NULL DEFAULT 'normal'
            CHECK(priority IN ('normal','high','urgent')),
        thread_id TEXT,
        payload TEXT,
        read INTEGER NOT NULL DEFAULT 0,
        sequence INTEGER PRIMARY KEY AUTOINCREMENT,
        created_at TEXT NOT NULL DEFAULT (datetime('now')),
        delivered_at TEXT,
        run_id TEXT,
        workspace_id TEXT,
        task_id TEXT,
        dispatch_id TEXT,
        state TEXT NOT NULL DEFAULT 'queued'
            CHECK(state IN ('queued','delivered','read','expired','obsolete')),
        expires_at TEXT,
        obsolete_at TEXT,
        reply_to_id TEXT,
        external_meta TEXT,
        delivery TEXT NOT NULL DEFAULT 'turn_end' CHECK(delivery IN ('now','turn_end'))
    )",
    "CREATE UNIQUE INDEX IF NOT EXISTS orchestrationMessagesIdIdx ON orchestrationMessages(id)",
    "CREATE INDEX IF NOT EXISTS orchestrationMessagesInboxIdx ON orchestrationMessages(to_handle, read)",
    "CREATE INDEX IF NOT EXISTS orchestrationMessagesUndeliveredIdx ON orchestrationMessages(to_handle, read, delivered_at, sequence)",
    "CREATE INDEX IF NOT EXISTS orchestrationMessagesThreadIdx ON orchestrationMessages(thread_id)",
    "CREATE INDEX IF NOT EXISTS orchestrationMessagesFromIdx ON orchestrationMessages(from_handle, sequence)",
    "CREATE INDEX IF NOT EXISTS orchestrationMessagesReplyToIdx ON orchestrationMessages(reply_to_id)",
    "CREATE TABLE IF NOT EXISTS orchestrationTasks (
        id TEXT PRIMARY KEY,
        parent_id TEXT,
        created_by_terminal_handle TEXT,
        task_title TEXT,
        display_name TEXT,
        spec TEXT NOT NULL,
        status TEXT NOT NULL DEFAULT 'pending'
            CHECK(status IN ('pending','ready','dispatched','completed','failed','blocked','stalled','cancelled')),
        deps TEXT NOT NULL DEFAULT '[]',
        result TEXT,
        created_at TEXT NOT NULL DEFAULT (datetime('now')),
        completed_at TEXT,
        run_id TEXT,
        workspace_id TEXT NOT NULL,
        coordinator_handle TEXT NOT NULL,
        result_schema TEXT,
        startup_failure_count INTEGER NOT NULL DEFAULT 0,
        cancelled_at TEXT,
        stalled_at TEXT,
        stage_id TEXT,
        role_contract TEXT,
        plan_revision INTEGER,
        logical_id TEXT,
        role_id TEXT,
        inputs TEXT,
        corrects_task_id TEXT
    )",
    "CREATE INDEX IF NOT EXISTS orchestrationTasksStatusIdx ON orchestrationTasks(status)",
    "CREATE INDEX IF NOT EXISTS orchestrationTasksParentIdx ON orchestrationTasks(parent_id)",
    "CREATE TRIGGER IF NOT EXISTS orchestrationRoleContractImmutable
        BEFORE UPDATE OF role_contract ON orchestrationTasks
        WHEN OLD.role_contract IS NOT NEW.role_contract
        BEGIN SELECT RAISE(ABORT, 'role contract snapshot is immutable'); END",
    "CREATE TABLE IF NOT EXISTS orchestrationDispatchContexts (
        id TEXT PRIMARY KEY,
        task_id TEXT NOT NULL,
        assignee_handle TEXT,
        status TEXT NOT NULL DEFAULT 'pending'
            CHECK(status IN ('pending','dispatched','completed','failed','circuit_broken','awaiting_acceptance','startup_failed','stalled','cancelled','superseded')),
        failure_count INTEGER NOT NULL DEFAULT 0,
        last_failure TEXT,
        dispatched_at TEXT,
        completed_at TEXT,
        created_at TEXT NOT NULL DEFAULT (datetime('now')),
        run_id TEXT,
        workspace_id TEXT NOT NULL,
        coordinator_handle TEXT NOT NULL,
        accepted_at TEXT,
        last_activity_at TEXT,
        context_token_hash TEXT,
        terminal_policy TEXT NOT NULL DEFAULT 'keep-open',
        startup_error TEXT,
        completion_sha TEXT,
        agent_profile TEXT,
        agent_quota_group TEXT
    )",
    "CREATE INDEX IF NOT EXISTS orchestrationDispatchTaskIdx ON orchestrationDispatchContexts(task_id)",
    "CREATE INDEX IF NOT EXISTS orchestrationDispatchStatusIdx ON orchestrationDispatchContexts(status)",
    // A run holds its workspace from `planning` until it finishes; a cancelled
    // run keeps it until its cancellation settles and stamps `completed_at`.
    // `execution_policy` mirrors the stage profiles of a shared run's current
    // plan so profile removal guards can read it without parsing revisions.
    // `control_sequence` is the optimistic token of `runs.control`.
    "CREATE TABLE IF NOT EXISTS orchestrationCoordinatorRuns (
        id TEXT PRIMARY KEY,
        spec TEXT NOT NULL,
        status TEXT NOT NULL DEFAULT 'planning'
            CHECK(status IN ('planning','awaitingApproval','running','paused','completed','failed','cancelled')),
        coordinator_handle TEXT,
        poll_interval_ms INTEGER NOT NULL DEFAULT 2000,
        created_at TEXT NOT NULL DEFAULT (datetime('now')),
        completed_at TEXT,
        workspace_id TEXT NOT NULL,
        max_concurrent INTEGER NOT NULL DEFAULT 4,
        last_activity_at TEXT NOT NULL DEFAULT (datetime('now')),
        stop_reason TEXT,
        execution_policy TEXT,
        isolation TEXT NOT NULL DEFAULT 'shared' CHECK(isolation IN ('shared','isolated')),
        approval_required INTEGER NOT NULL DEFAULT 0,
        paused_by TEXT CHECK(paused_by IS NULL OR paused_by IN ('user','runtime')),
        plan_revision INTEGER,
        recipe_source TEXT,
        recipe_snapshot TEXT,
        profiles_snapshot TEXT,
        source_snapshot TEXT,
        coordinator_profile_id TEXT,
        coordinator_tab_id TEXT,
        coordinator_state TEXT NOT NULL DEFAULT 'none'
            CHECK(coordinator_state IN ('none','reserved','started','attention')),
        coordinator_error TEXT,
        integration_workspace_id TEXT,
        integration_branch TEXT,
        integration_sha TEXT,
        control_sequence INTEGER NOT NULL DEFAULT 0,
        attention_reason TEXT,
        stall_policy TEXT NOT NULL DEFAULT 'ask' CHECK(stall_policy IN ('ask','auto-failover','wait'))
    )",
    "CREATE UNIQUE INDEX IF NOT EXISTS orchestrationCoordinatorRunsActiveWorkspaceIdx
        ON orchestrationCoordinatorRuns(workspace_id)
        WHERE status IN ('planning','awaitingApproval','running','paused')
            OR (status = 'cancelled' AND completed_at IS NULL)",
    "CREATE UNIQUE INDEX IF NOT EXISTS orchestrationCoordinatorRunsTabIdx
        ON orchestrationCoordinatorRuns(coordinator_tab_id) WHERE coordinator_tab_id IS NOT NULL",
    "CREATE TABLE IF NOT EXISTS orchestrationAuditEvents (
        id TEXT PRIMARY KEY,
        actor_handle TEXT,
        action TEXT NOT NULL,
        target_id TEXT,
        reason TEXT NOT NULL,
        payload TEXT,
        created_at TEXT NOT NULL DEFAULT (datetime('now')),
        actor_kind TEXT,
        actor_id TEXT
    )",
    // Decision and stall gates follow their task, which may predate any run,
    // so only run-scoped kinds require `run_id`.
    "CREATE TABLE IF NOT EXISTS runGates (
        id TEXT PRIMARY KEY,
        run_id TEXT,
        task_id TEXT,
        kind TEXT NOT NULL CHECK(kind IN ('decision','stall','plan','stage')),
        scope TEXT NOT NULL DEFAULT '',
        question TEXT NOT NULL,
        options TEXT NOT NULL DEFAULT '[]',
        status TEXT NOT NULL DEFAULT 'pending'
            CHECK(status IN ('pending','resolved','timeout','invalidated')),
        resolution TEXT,
        reason TEXT,
        plan_revision INTEGER,
        evidence_digest TEXT,
        integration_sha TEXT,
        actor_kind TEXT CHECK(actor_kind IS NULL
            OR actor_kind IN ('desktop','mobile','cli','mcp','agent','runtime')),
        actor_id TEXT,
        audit_id TEXT,
        created_at TEXT NOT NULL DEFAULT (datetime('now')),
        resolved_at TEXT,
        CHECK(kind IN ('decision','stall') OR (run_id IS NOT NULL AND task_id IS NULL)),
        CHECK(kind IN ('plan','stage') OR task_id IS NOT NULL)
    )",
    "CREATE INDEX IF NOT EXISTS runGatesTaskIdx ON runGates(task_id, status)",
    "CREATE INDEX IF NOT EXISTS runGatesRunIdx ON runGates(run_id, kind, status)",
    "CREATE TABLE IF NOT EXISTS runEvents (
        sequence INTEGER PRIMARY KEY AUTOINCREMENT,
        id TEXT NOT NULL UNIQUE,
        run_id TEXT NOT NULL,
        task_id TEXT,
        dispatch_id TEXT,
        gate_id TEXT,
        kind TEXT NOT NULL,
        actor_kind TEXT,
        actor_id TEXT,
        summary TEXT NOT NULL DEFAULT '' CHECK(length(CAST(summary AS BLOB)) <= 512),
        payload TEXT CHECK(payload IS NULL OR length(CAST(payload AS BLOB)) <= 8192),
        created_at TEXT NOT NULL DEFAULT (datetime('now'))
    )",
    "CREATE INDEX IF NOT EXISTS runEventsRunIdx ON runEvents(run_id, sequence DESC)",
    "CREATE TRIGGER IF NOT EXISTS orchestrationPolicyProfileUpdateGuard
     BEFORE UPDATE OF execution_policy, status ON orchestrationCoordinatorRuns
     WHEN NEW.execution_policy IS NOT NULL
       AND NEW.status NOT IN ('completed', 'failed', 'cancelled')
       AND COALESCE((SELECT g.resolution FROM runGates g
           WHERE g.run_id = NEW.id AND g.kind = 'plan' AND g.status <> 'invalidated'
           ORDER BY g.rowid DESC LIMIT 1), '') <> 'reject'
       AND EXISTS (
         SELECT 1 FROM json_each(json_extract(NEW.execution_policy, '$.stages')) AS stage
         WHERE NOT EXISTS (
           SELECT 1 FROM agentProfiles
           WHERE name = json_extract(stage.value, '$.profile') COLLATE NOCASE
         ) OR EXISTS (
           SELECT 1 FROM json_each(json_extract(stage.value, '$.fallbacks')) AS fallback
           WHERE NOT EXISTS (
             SELECT 1 FROM agentProfiles
             WHERE name = fallback.value COLLATE NOCASE
           )
         )
       )
     BEGIN SELECT RAISE(ABORT, 'agent profile reference does not exist'); END",
];

/// Creates every v3 orchestration and run object that does not exist yet.
/// Order matters: run triggers reference orchestration tables, and the board
/// view and revision triggers reference both.
pub(super) async fn install_runs_v3_schema(conn: &mut SqliteConnection) -> Result<()> {
    for statement in ORCHESTRATION_TABLES {
        sqlx::query(*statement).execute(&mut *conn).await?;
    }
    super::run_schema::install_run_schema(conn).await?;
    super::orchestration_board_schema::install_board_schema(conn).await?;
    super::inbox_store::install_inbox_schema(conn).await?;
    super::conversation_store::install_conversation_schema(conn).await?;
    Ok(())
}
