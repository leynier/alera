//! Stage gate evidence. A stage gate becomes due once every task of its stage
//! and of the stages before it is completed (and, in an isolated run,
//! integrated with validated evidence). Its evidence digest is bound then,
//! and an approval only counts for that exact evidence.

use std::collections::BTreeSet;

use anyhow::{anyhow, Result};
use serde::Serialize;
use sqlx::{Row, SqliteConnection};

use super::run_event_store::{record_run_event, NewRunEvent, RunActorKind, RunEventKind};
use super::run_plan::workflow_digest;
use super::run_plan_gate_store::record_gate_opened;
use super::{RunGateKind, RuntimeStore, SharedRunPlanSnapshot, WorkflowPlanSnapshot};

#[derive(Serialize)]
struct TaskEvidence {
    id: String,
    result_digest: Option<String>,
    artifact_digest: Option<String>,
    integration_sha: Option<String>,
}

/// The stage and every stage it depends on, transitively.
fn ancestors(plan: &WorkflowPlanSnapshot, stage_id: &str) -> Result<BTreeSet<String>> {
    let mut seen = BTreeSet::new();
    let mut remaining = vec![stage_id.to_string()];
    while let Some(id) = remaining.pop() {
        if seen.insert(id.clone()) {
            let stage = plan
                .recipe
                .recipe
                .stages
                .iter()
                .find(|stage| stage.id == id)
                .ok_or_else(|| anyhow!("run stage dependency is missing"))?;
            remaining.extend(stage.depends_on.clone());
        }
    }
    Ok(seen)
}

/// Whether every gated stage before `stage_id` was approved for `revision`.
pub(super) async fn prerequisite_gates_approved(
    conn: &mut SqliteConnection,
    run_id: &str,
    revision: i64,
    plan: &WorkflowPlanSnapshot,
    stage_id: &str,
) -> Result<bool> {
    for prior in ancestors(plan, stage_id)? {
        if prior == stage_id {
            continue;
        }
        let gated = plan
            .recipe
            .recipe
            .stages
            .iter()
            .any(|stage| stage.id == prior && stage.gate.is_some());
        if gated && !stage_gate_approved(conn, run_id, revision, &prior).await? {
            return Ok(false);
        }
    }
    Ok(true)
}

pub(super) async fn stage_gate_approved(
    conn: &mut SqliteConnection,
    run_id: &str,
    revision: i64,
    stage_id: &str,
) -> Result<bool> {
    Ok(sqlx::query_scalar(
        "SELECT EXISTS(SELECT 1 FROM runGates WHERE run_id = ? AND kind = 'stage'
            AND scope = ? AND plan_revision = ? AND status = 'resolved' AND resolution = 'approve')",
    )
    .bind(run_id)
    .bind(stage_id)
    .bind(revision)
    .fetch_one(&mut *conn)
    .await?)
}

/// The evidence digest of an isolated stage, or `None` while any of its
/// tasks (or of the stages before it) is not integrated with evidence.
pub(super) async fn isolated_stage_evidence(
    conn: &mut SqliteConnection,
    run_id: &str,
    revision: i64,
    plan: &WorkflowPlanSnapshot,
    stage_id: &str,
) -> Result<Option<String>> {
    let unsettled: bool = sqlx::query_scalar(
        "SELECT EXISTS(SELECT 1 FROM runIntegrations
        WHERE run_id = ? AND cancelled=0 AND state IN ('pending','prepared','attention'))",
    )
    .bind(run_id)
    .fetch_one(&mut *conn)
    .await?;
    if unsettled || !prerequisite_gates_approved(conn, run_id, revision, plan, stage_id).await? {
        return Ok(None);
    }
    let stages = ancestors(plan, stage_id)?;
    let rows = sqlx::query(
        "SELECT t.logical_id, t.status, t.result, t.stage_id,
        e.result_digest, e.artifact_digest, e.integration_sha
        FROM orchestrationTasks t LEFT JOIN runTaskEvidence e ON e.task_id = t.id
        WHERE t.run_id = ? AND t.plan_revision = ? ORDER BY t.logical_id",
    )
    .bind(run_id)
    .bind(revision)
    .fetch_all(&mut *conn)
    .await?;
    let expected = plan
        .tasks
        .iter()
        .filter(|task| stages.contains(&task.task.stage_id))
        .count();
    let mut evidence = Vec::new();
    for row in rows {
        if !stages.contains(&row.try_get::<String, _>("stage_id")?) {
            continue;
        }
        let result: Option<String> = row.try_get("result")?;
        let result_digest: Option<String> = row.try_get("result_digest")?;
        let artifact_digest: Option<String> = row.try_get("artifact_digest")?;
        let sha: Option<String> = row.try_get("integration_sha")?;
        if row.try_get::<String, _>("status")? != "completed"
            || result.is_none()
            || artifact_digest.is_none()
            || sha.is_none()
            || result_digest.as_ref() != Some(&workflow_digest(&result)?)
        {
            return Ok(None);
        }
        evidence.push(TaskEvidence {
            id: row.try_get("logical_id")?,
            result_digest,
            artifact_digest,
            integration_sha: sha,
        });
    }
    if evidence.len() != expected || expected == 0 {
        return Ok(None);
    }
    Ok(Some(workflow_digest(&evidence)?))
}

/// The evidence digest of a shared stage, or `None` while any of its tasks
/// is not completed.
pub(super) async fn shared_stage_evidence(
    conn: &mut SqliteConnection,
    run_id: &str,
    revision: i64,
    stage_id: &str,
) -> Result<Option<String>> {
    let rows = sqlx::query(
        "SELECT logical_id, status, result FROM orchestrationTasks
        WHERE run_id = ? AND plan_revision = ? AND stage_id = ? ORDER BY logical_id",
    )
    .bind(run_id)
    .bind(revision)
    .bind(stage_id)
    .fetch_all(&mut *conn)
    .await?;
    if rows.is_empty() {
        return Ok(None);
    }
    let mut evidence = Vec::new();
    for row in rows {
        if row.try_get::<String, _>("status")? != "completed" {
            return Ok(None);
        }
        let result: Option<String> = row.try_get("result")?;
        evidence.push(TaskEvidence {
            id: row.try_get("logical_id")?,
            result_digest: Some(workflow_digest(&result)?),
            artifact_digest: None,
            integration_sha: None,
        });
    }
    Ok(Some(workflow_digest(&evidence)?))
}

/// The current evidence of a run's stage, whatever its isolation.
pub(super) async fn stage_evidence(
    conn: &mut SqliteConnection,
    run_id: &str,
    stage_id: &str,
) -> Result<Option<(String, Option<String>)>> {
    let row = sqlx::query(
        "SELECT r.isolation, r.plan_revision, r.integration_sha, p.snapshot
        FROM orchestrationCoordinatorRuns r
        JOIN runPlanRevisions p ON p.run_id = r.id AND p.revision = r.plan_revision
        WHERE r.id = ?",
    )
    .bind(run_id)
    .fetch_optional(&mut *conn)
    .await?;
    let Some(row) = row else { return Ok(None) };
    let revision: i64 = row.try_get("plan_revision")?;
    let snapshot: String = row.try_get("snapshot")?;
    if row.try_get::<String, _>("isolation")? == "isolated" {
        let plan: WorkflowPlanSnapshot = serde_json::from_str(&snapshot)?;
        let digest = isolated_stage_evidence(conn, run_id, revision, &plan, stage_id).await?;
        Ok(digest.map(|digest| (digest, row.try_get("integration_sha").ok().flatten())))
    } else {
        let _: SharedRunPlanSnapshot = serde_json::from_str(&snapshot)?;
        Ok(shared_stage_evidence(conn, run_id, revision, stage_id)
            .await?
            .map(|digest| (digest, None)))
    }
}

impl RuntimeStore {
    /// Binds the evidence of every stage gate that became due and pauses the
    /// run for a person. Returns the ids of the gates that opened.
    pub async fn open_due_stage_gates(&self, run_id: &str) -> Result<Vec<String>> {
        let mut tx = self.pool().begin().await?;
        sqlx::query("UPDATE orchestrationBoardRevision SET revision = revision WHERE id = 1")
            .execute(&mut *tx)
            .await?;
        let candidates = sqlx::query(
            "SELECT g.id, g.scope, g.question FROM runGates g
            JOIN orchestrationCoordinatorRuns r ON r.id = g.run_id
            WHERE g.run_id = ? AND g.kind = 'stage' AND g.status = 'pending'
              AND g.evidence_digest IS NULL AND g.plan_revision IS r.plan_revision
              AND r.status = 'running'",
        )
        .bind(run_id)
        .fetch_all(&mut *tx)
        .await?;
        let mut opened = Vec::new();
        for candidate in candidates {
            let id: String = candidate.try_get("id")?;
            let scope: String = candidate.try_get("scope")?;
            let question: String = candidate.try_get("question")?;
            let Some((digest, sha)) = stage_evidence(&mut tx, run_id, &scope).await? else {
                continue;
            };
            sqlx::query(
                "UPDATE runGates SET evidence_digest = ?, integration_sha = ?
                WHERE id = ? AND status = 'pending' AND evidence_digest IS NULL",
            )
            .bind(&digest)
            .bind(&sha)
            .bind(&id)
            .execute(&mut *tx)
            .await?;
            record_gate_opened(&mut tx, run_id, &id, RunGateKind::Stage, &scope, &question).await?;
            opened.push(id);
        }
        if !opened.is_empty() {
            let paused = sqlx::query(
                "UPDATE orchestrationCoordinatorRuns SET status = 'paused', paused_by = 'runtime',
                    control_sequence = control_sequence + 1, last_activity_at = datetime('now')
                WHERE id = ? AND status = 'running'",
            )
            .bind(run_id)
            .execute(&mut *tx)
            .await?
            .rows_affected();
            if paused == 1 {
                let mut event = NewRunEvent::new(run_id, RunEventKind::Paused);
                event.actor_kind = Some(RunActorKind::Runtime);
                event.summary = "A stage gate is waiting for a decision.";
                record_run_event(&mut tx, &event).await?;
            }
        }
        tx.commit().await?;
        Ok(opened)
    }
}
