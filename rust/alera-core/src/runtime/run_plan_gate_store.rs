//! Run-scoped gates: the `plan` gate that holds a run until a person accepts
//! its plan, and `stage` gates. Their options are always approve, request
//! changes or reject. A stage gate exists from plan materialization but is
//! only due once its evidence digest is bound.

use anyhow::{anyhow, bail, Result};
use sqlx::SqliteConnection;

use super::orchestration_gate_store::{PLAN_GATE_APPROVE, PLAN_GATE_QUESTION, RUN_GATE_OPTIONS};
use super::orchestration_message_store::orchestration_id;
use super::run_event_store::{record_run_event, NewRunEvent, RunActorKind, RunEventKind};
use super::{OrchestrationDecisionGate, RunGateKind, RuntimeStore};

/// A run gate as it is first written.
pub(super) struct NewRunGate<'a> {
    pub run_id: &'a str,
    pub kind: RunGateKind,
    pub scope: &'a str,
    pub question: &'a str,
    pub plan_revision: Option<i64>,
    /// Bound evidence; a stage gate without it is not due yet.
    pub evidence_digest: Option<&'a str>,
    pub integration_sha: Option<&'a str>,
}

pub(super) async fn insert_run_gate(
    conn: &mut SqliteConnection,
    gate: &NewRunGate<'_>,
) -> Result<String> {
    let id = orchestration_id("gate");
    sqlx::query(
        "INSERT INTO runGates (id, run_id, kind, scope, question, options, plan_revision,
            evidence_digest, integration_sha) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)",
    )
    .bind(&id)
    .bind(gate.run_id)
    .bind(gate.kind.as_str())
    .bind(gate.scope)
    .bind(gate.question)
    .bind(serde_json::to_string(&RUN_GATE_OPTIONS)?)
    .bind(gate.plan_revision)
    .bind(gate.evidence_digest)
    .bind(gate.integration_sha)
    .execute(&mut *conn)
    .await?;
    if gate.kind == RunGateKind::Plan || gate.evidence_digest.is_some() {
        record_gate_opened(conn, gate.run_id, &id, gate.kind, gate.scope, gate.question).await?;
    }
    Ok(id)
}

pub(super) async fn record_gate_opened(
    conn: &mut SqliteConnection,
    run_id: &str,
    gate_id: &str,
    kind: RunGateKind,
    scope: &str,
    question: &str,
) -> Result<()> {
    let mut opened = NewRunEvent::new(run_id, RunEventKind::GateOpened);
    opened.gate_id = Some(gate_id);
    opened.summary = question;
    opened.actor_kind = Some(RunActorKind::Runtime);
    opened.payload = Some(serde_json::json!({ "kind": kind.as_str(), "scope": scope }));
    record_run_event(conn, &opened).await?;
    Ok(())
}

/// Supersedes any pending plan gate and opens one for `revision`, bound to
/// the plan digest so a decision always names the plan it accepts.
pub(super) async fn open_plan_gate(
    conn: &mut SqliteConnection,
    run_id: &str,
    revision: i64,
    plan_digest: &str,
) -> Result<String> {
    sqlx::query(
        "UPDATE runGates SET status = 'invalidated', resolved_at = datetime('now') \
         WHERE run_id = ? AND kind = 'plan' AND status = 'pending'",
    )
    .bind(run_id)
    .execute(&mut *conn)
    .await?;
    insert_run_gate(
        conn,
        &NewRunGate {
            run_id,
            kind: RunGateKind::Plan,
            scope: "plan",
            question: PLAN_GATE_QUESTION,
            plan_revision: Some(revision),
            evidence_digest: Some(plan_digest),
            integration_sha: None,
        },
    )
    .await
}

impl RuntimeStore {
    /// Opens a run-scoped `plan` or `stage` gate. A pending gate of the same
    /// run and kind is returned instead of opening a second one.
    pub async fn create_run_gate(
        &self,
        run_id: &str,
        kind: RunGateKind,
        question: &str,
    ) -> Result<OrchestrationDecisionGate> {
        if !matches!(kind, RunGateKind::Plan | RunGateKind::Stage) {
            bail!("gate_invalid_kind: only plan and stage gates belong to a run");
        }
        let mut tx = self.pool().begin().await?;
        let revision: Option<Option<i64>> = sqlx::query_scalar(
            "SELECT plan_revision FROM orchestrationCoordinatorRuns WHERE id = ?",
        )
        .bind(run_id)
        .fetch_optional(&mut *tx)
        .await?;
        let Some(revision) = revision else {
            bail!("coordinator run not found: {run_id}");
        };
        let existing: Option<String> = sqlx::query_scalar(
            "SELECT id FROM runGates WHERE run_id = ? AND kind = ? AND status = 'pending' \
             ORDER BY rowid DESC LIMIT 1",
        )
        .bind(run_id)
        .bind(kind.as_str())
        .fetch_optional(&mut *tx)
        .await?;
        let id = match existing {
            Some(id) => id,
            None => {
                insert_run_gate(
                    &mut tx,
                    &NewRunGate {
                        run_id,
                        kind,
                        scope: kind.as_str(),
                        question,
                        plan_revision: revision,
                        evidence_digest: Some(""),
                        integration_sha: None,
                    },
                )
                .await?
            }
        };
        tx.commit().await?;
        self.orchestration_gate_by_id(&id)
            .await?
            .ok_or_else(|| anyhow!("run gate not found: {id}"))
    }

    /// A pending plan gate holds the run's scheduling.
    pub async fn run_has_pending_plan_gate(&self, run_id: &str) -> Result<bool> {
        Ok(sqlx::query_scalar(
            "SELECT EXISTS(SELECT 1 FROM runGates \
             WHERE run_id = ? AND kind = 'plan' AND status = 'pending')",
        )
        .bind(run_id)
        .fetch_one(self.pool())
        .await?)
    }

    /// Whether a person already approved the run's plan.
    pub async fn run_has_approved_plan_gate(&self, run_id: &str) -> Result<bool> {
        Ok(sqlx::query_scalar(
            "SELECT EXISTS(SELECT 1 FROM runGates \
             WHERE run_id = ? AND kind = 'plan' AND status = 'resolved' AND resolution = ?)",
        )
        .bind(run_id)
        .bind(PLAN_GATE_APPROVE)
        .fetch_one(self.pool())
        .await?)
    }
}
