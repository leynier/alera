use anyhow::Result;

pub(super) async fn install(conn: &mut sqlx::SqliteConnection) -> Result<()> {
    for statement in SCHEMA {
        sqlx::query(*statement).execute(&mut *conn).await?;
    }
    for statement in evidence_triggers() {
        sqlx::query(sqlx::AssertSqlSafe(statement))
            .execute(&mut *conn)
            .await?;
    }
    Ok(())
}

/// Changed evidence revokes every stage gate that was bound to it: a due
/// gate and an approval both describe evidence that no longer exists. A fresh
/// gate of the same stage replaces each one and becomes due again once the
/// stage is integrated with its new evidence. `{run}` names the run id.
const STAGE_GATE_INVALIDATION: &str = "INSERT INTO runGates
        (id, run_id, kind, scope, question, options, plan_revision)
        SELECT 'gate_' || lower(hex(randomblob(16))), g.run_id, 'stage', g.scope, g.question,
            g.options, g.plan_revision
        FROM runGates g JOIN orchestrationCoordinatorRuns r ON r.id = g.run_id
        WHERE g.run_id = {run} AND g.kind = 'stage' AND g.evidence_digest IS NOT NULL
          AND g.plan_revision IS r.plan_revision
          AND (g.status = 'pending' OR (g.status = 'resolved' AND g.resolution = 'approve'));
    UPDATE runGates SET status = 'invalidated', resolved_at = COALESCE(resolved_at, datetime('now'))
        WHERE run_id = {run} AND kind = 'stage' AND evidence_digest IS NOT NULL
          AND (status = 'pending' OR (status = 'resolved' AND resolution = 'approve'));";

fn invalidation(run: &str) -> String {
    STAGE_GATE_INVALIDATION.replace("{run}", run)
}

fn evidence_triggers() -> [String; 3] {
    let by_new_evidence =
        invalidation("(SELECT run_id FROM orchestrationTasks WHERE id = NEW.task_id)");
    let by_old_evidence =
        invalidation("(SELECT run_id FROM orchestrationTasks WHERE id = OLD.task_id)");
    let by_task = invalidation("NEW.run_id");
    [
        format!(
            "CREATE TRIGGER IF NOT EXISTS runEvidenceUpdateInvalidatesGates AFTER UPDATE ON runTaskEvidence
            WHEN OLD.result_digest IS NOT NEW.result_digest OR OLD.artifact_digest IS NOT NEW.artifact_digest
              OR OLD.integration_sha IS NOT NEW.integration_sha
            BEGIN {by_new_evidence} END"
        ),
        format!(
            "CREATE TRIGGER IF NOT EXISTS runEvidenceDeleteInvalidatesGates BEFORE DELETE ON runTaskEvidence
            BEGIN {by_old_evidence} END"
        ),
        format!(
            "CREATE TRIGGER IF NOT EXISTS runResultInvalidatesGates AFTER UPDATE OF result, status ON orchestrationTasks
            WHEN OLD.status = 'completed' AND (OLD.result IS NOT NEW.result OR NEW.status <> 'completed')
              AND NEW.plan_revision IS NOT NULL
            BEGIN {by_task} END"
        ),
    ]
}

/// Plan revisions belong to their run. Tasks of a plan carry `plan_revision`
/// and `logical_id`; the frozen task definition is the revision snapshot.
const SCHEMA: &[&str] = &[
    "CREATE TABLE IF NOT EXISTS runPlanRevisions (
        run_id TEXT NOT NULL REFERENCES orchestrationCoordinatorRuns(id) ON DELETE CASCADE,
        revision INTEGER NOT NULL, request_id TEXT NOT NULL UNIQUE, request_digest TEXT NOT NULL,
        snapshot TEXT NOT NULL, digest TEXT NOT NULL, previous_revision INTEGER, change_reason TEXT,
        change_task_ids TEXT,
        created_at TEXT NOT NULL DEFAULT (datetime('now')),
        PRIMARY KEY(run_id, revision)
    )",
    "CREATE TRIGGER IF NOT EXISTS runPlanImmutable BEFORE UPDATE ON runPlanRevisions
        BEGIN SELECT RAISE(ABORT, 'run plan revisions are immutable'); END",
    "CREATE UNIQUE INDEX IF NOT EXISTS runPlanTaskLogicalIdx
        ON orchestrationTasks(run_id, plan_revision, logical_id) WHERE plan_revision IS NOT NULL",
    "CREATE TABLE IF NOT EXISTS runTaskEvidence (
        task_id TEXT PRIMARY KEY REFERENCES orchestrationTasks(id) ON DELETE CASCADE,
        result_digest TEXT NOT NULL, artifact_digest TEXT NOT NULL, integration_sha TEXT NOT NULL
    )",
    "CREATE TRIGGER IF NOT EXISTS runResultChangeInvalidatesEvidence AFTER UPDATE OF result ON orchestrationTasks
        WHEN OLD.result IS NOT NEW.result
          AND EXISTS(SELECT 1 FROM runTaskEvidence WHERE task_id = NEW.id)
        BEGIN DELETE FROM runTaskEvidence WHERE task_id = NEW.id; END",
    "CREATE TRIGGER IF NOT EXISTS runTaskDefinitionImmutable
        BEFORE UPDATE OF spec, deps, stage_id, role_contract, run_id, plan_revision, logical_id ON orchestrationTasks
        WHEN OLD.plan_revision IS NOT NULL
          AND (OLD.spec IS NOT NEW.spec OR OLD.deps IS NOT NEW.deps OR OLD.stage_id IS NOT NEW.stage_id
            OR OLD.role_contract IS NOT NEW.role_contract OR OLD.run_id IS NOT NEW.run_id
            OR OLD.plan_revision IS NOT NEW.plan_revision OR OLD.logical_id IS NOT NEW.logical_id)
        BEGIN SELECT RAISE(ABORT, 'a planned task definition requires a new plan revision'); END",
    "CREATE TRIGGER IF NOT EXISTS runTaskMembershipRequired BEFORE INSERT ON orchestrationTasks
        WHEN NEW.plan_revision IS NULL AND EXISTS(SELECT 1 FROM orchestrationCoordinatorRuns
            WHERE id = NEW.run_id AND isolation = 'isolated')
        BEGIN SELECT RAISE(ABORT, 'isolated run tasks require plan membership'); END",
    "CREATE TRIGGER IF NOT EXISTS runTaskJoinRequiresMembership BEFORE UPDATE OF run_id ON orchestrationTasks
        WHEN NEW.plan_revision IS NULL AND EXISTS(SELECT 1 FROM orchestrationCoordinatorRuns
            WHERE id = NEW.run_id AND isolation = 'isolated')
        BEGIN SELECT RAISE(ABORT, 'isolated run tasks require plan membership'); END",
];
