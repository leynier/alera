use anyhow::Result;

use super::RuntimeStore;

impl RuntimeStore {
    pub(super) async fn migrate_workflow_plans(&self) -> Result<()> {
        let mut tx = self.pool().begin().await?;
        for statement in SCHEMA {
            sqlx::query(*statement).execute(&mut *tx).await?;
        }
        for table in [
            "workflowRuns",
            "workflowPlanRevisions",
            "workflowDecisions",
            "workflowStageGates",
            "workflowTaskEvidence",
        ] {
            for operation in ["INSERT", "UPDATE", "DELETE"] {
                sqlx::query(sqlx::AssertSqlSafe(format!(
                    "CREATE TRIGGER IF NOT EXISTS board_{table}_{operation} AFTER {operation} ON {table}
                     BEGIN UPDATE orchestrationBoardRevision SET revision = revision + 1 WHERE id = 1; END"
                ))).execute(&mut *tx).await?;
            }
        }
        tx.commit().await?;
        Ok(())
    }
}

const SCHEMA: &[&str] = &[
    "CREATE TABLE IF NOT EXISTS workflowRuns (
        run_id TEXT PRIMARY KEY REFERENCES orchestrationCoordinatorRuns(id) ON DELETE CASCADE,
        workspace_id TEXT NOT NULL, revision INTEGER NOT NULL,
        status TEXT NOT NULL CHECK(status IN ('prepared','approved','rejected','changesRequested','completed','cancelled')),
        integration_sha TEXT NOT NULL, created_at TEXT NOT NULL DEFAULT (datetime('now'))
    )",
    "CREATE TABLE IF NOT EXISTS workflowPlanRevisions (
        run_id TEXT NOT NULL REFERENCES workflowRuns(run_id) ON DELETE CASCADE,
        revision INTEGER NOT NULL, request_id TEXT NOT NULL UNIQUE, request_digest TEXT NOT NULL,
        snapshot TEXT NOT NULL, digest TEXT NOT NULL, previous_revision INTEGER, change_reason TEXT,
        PRIMARY KEY(run_id, revision)
    )",
    "CREATE TRIGGER IF NOT EXISTS workflowPlanImmutable BEFORE UPDATE ON workflowPlanRevisions
        BEGIN SELECT RAISE(ABORT, 'workflow plan revisions are immutable'); END",
    "CREATE TABLE IF NOT EXISTS workflowPlanTasks (
        task_id TEXT PRIMARY KEY REFERENCES orchestrationTasks(id) ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED,
        run_id TEXT NOT NULL REFERENCES workflowRuns(run_id) ON DELETE CASCADE,
        revision INTEGER NOT NULL, logical_id TEXT NOT NULL, frozen_task TEXT NOT NULL,
        UNIQUE(run_id, revision, logical_id)
    )",
    "CREATE TABLE IF NOT EXISTS workflowTaskEvidence (
        task_id TEXT PRIMARY KEY REFERENCES workflowPlanTasks(task_id) ON DELETE CASCADE,
        result_digest TEXT NOT NULL, artifact_digest TEXT NOT NULL, integration_sha TEXT NOT NULL
    )",
    "CREATE TABLE IF NOT EXISTS workflowApprovalChallenges (
        nonce TEXT PRIMARY KEY, run_id TEXT NOT NULL REFERENCES workflowRuns(run_id) ON DELETE CASCADE,
        audience TEXT NOT NULL, statement TEXT NOT NULL, expires_at INTEGER NOT NULL,
        decision_digest TEXT, receipt TEXT
    )",
    "CREATE INDEX IF NOT EXISTS workflowChallengeExpiry ON workflowApprovalChallenges(expires_at)",
    "CREATE TRIGGER IF NOT EXISTS workflowEvidenceUpdateInvalidatesGates AFTER UPDATE ON workflowTaskEvidence
        WHEN OLD.result_digest IS NOT NEW.result_digest OR OLD.artifact_digest IS NOT NEW.artifact_digest
          OR OLD.integration_sha IS NOT NEW.integration_sha
        BEGIN UPDATE workflowStageGates SET status = 'pending', decision_id = NULL
          WHERE run_id = (SELECT run_id FROM workflowPlanTasks WHERE task_id = NEW.task_id); END",
    "CREATE TRIGGER IF NOT EXISTS workflowEvidenceDeleteInvalidatesGates BEFORE DELETE ON workflowTaskEvidence
        BEGIN UPDATE workflowStageGates SET status = 'pending', decision_id = NULL
          WHERE run_id = (SELECT run_id FROM workflowPlanTasks WHERE task_id = OLD.task_id); END",
    "CREATE TRIGGER IF NOT EXISTS workflowResultInvalidatesGates AFTER UPDATE OF result, status ON orchestrationTasks
        WHEN OLD.status = 'completed' AND (OLD.result IS NOT NEW.result OR NEW.status <> 'completed')
        BEGIN UPDATE workflowStageGates SET status = 'pending', decision_id = NULL
          WHERE run_id = (SELECT run_id FROM workflowPlanTasks WHERE task_id = NEW.id); END",
    "CREATE TABLE IF NOT EXISTS workflowDecisions (
        id TEXT PRIMARY KEY, run_id TEXT NOT NULL REFERENCES workflowRuns(run_id) ON DELETE CASCADE,
        revision INTEGER NOT NULL, scope TEXT NOT NULL, decision TEXT NOT NULL,
        reason TEXT NOT NULL, plan_digest TEXT NOT NULL, evidence_digest TEXT NOT NULL,
        integration_sha TEXT NOT NULL, created_at TEXT NOT NULL DEFAULT (datetime('now'))
    )",
    "CREATE TABLE IF NOT EXISTS workflowStageGates (
        run_id TEXT NOT NULL REFERENCES workflowRuns(run_id) ON DELETE CASCADE,
        revision INTEGER NOT NULL, stage_id TEXT NOT NULL, status TEXT NOT NULL DEFAULT 'pending',
        decision_id TEXT REFERENCES workflowDecisions(id), PRIMARY KEY(run_id, revision, stage_id)
    )",
    // PR6 deliberately has no executable workflow path. The managed isolation
    // and integration layers replace this barrier only when both are available.
    "CREATE TRIGGER IF NOT EXISTS workflowDispatchBlocked BEFORE INSERT ON orchestrationDispatchContexts
        WHEN EXISTS(SELECT 1 FROM workflowPlanTasks WHERE task_id = NEW.task_id)
          OR EXISTS(SELECT 1 FROM workflowRuns WHERE run_id = NEW.run_id)
        BEGIN SELECT RAISE(ABORT, 'workflow execution requires managed isolation and integration'); END",
    "CREATE TRIGGER IF NOT EXISTS workflowTaskDefinitionImmutable
        BEFORE UPDATE OF spec, deps, stage_id, role_contract, run_id ON orchestrationTasks
        WHEN EXISTS(SELECT 1 FROM workflowPlanTasks WHERE task_id = OLD.id)
          AND (OLD.spec IS NOT NEW.spec OR OLD.deps IS NOT NEW.deps OR OLD.stage_id IS NOT NEW.stage_id
            OR OLD.role_contract IS NOT NEW.role_contract OR OLD.run_id IS NOT NEW.run_id)
        BEGIN SELECT RAISE(ABORT, 'workflow task definition requires a reviewed correction revision'); END",
    "CREATE TRIGGER IF NOT EXISTS workflowTaskMembershipRequired BEFORE INSERT ON orchestrationTasks
        WHEN EXISTS(SELECT 1 FROM workflowRuns WHERE run_id = NEW.run_id)
          AND NOT EXISTS(SELECT 1 FROM workflowPlanTasks WHERE task_id = NEW.id)
        BEGIN SELECT RAISE(ABORT, 'workflow tasks require approved plan membership'); END",
    "CREATE TRIGGER IF NOT EXISTS workflowTaskJoinRequiresMembership BEFORE UPDATE OF run_id ON orchestrationTasks
        WHEN EXISTS(SELECT 1 FROM workflowRuns WHERE run_id = NEW.run_id)
          AND NOT EXISTS(SELECT 1 FROM workflowPlanTasks WHERE task_id = NEW.id)
        BEGIN SELECT RAISE(ABORT, 'workflow tasks require approved plan membership'); END",
];
