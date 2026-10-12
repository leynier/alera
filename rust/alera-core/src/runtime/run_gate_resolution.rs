//! `runs.resolveGate`: every gate kind resolves here. The actor comes from
//! the authenticated connection and is written on the gate, the audit row
//! and the timeline in one transaction. A replayed request id returns its
//! original receipt.

use anyhow::{anyhow, bail, Result};
use serde::{Deserialize, Serialize};
use sqlx::sqlite::SqliteRow;
use sqlx::{Row, Sqlite, Transaction};

use super::orchestration_gate_store::{
    PLAN_GATE_APPROVE, PLAN_GATE_REJECT, PLAN_GATE_REQUEST_CHANGES,
};
use super::orchestration_message_store::orchestration_id;
use super::orchestration_task_store::parse_string_array;
use super::run_event_store::{record_run_event, NewRunEvent, RunEventKind};
use super::run_plan::{workflow_digest, workflow_text};
use super::{OrchestrationGateStatus, RunActor, RunGateKind, RuntimeStore};

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct ResolveRunGate {
    pub request_id: String,
    pub gate_id: String,
    pub decision: String,
    #[serde(default)]
    pub reason: Option<String>,
    #[serde(default)]
    pub task_ids: Option<Vec<String>>,
    #[serde(default)]
    pub expected_evidence_digest: Option<String>,
    /// The Alera terminal the request came from, when a CLI runs inside one.
    #[serde(default)]
    pub caller_terminal: Option<String>,
}

/// A gate as clients see it (`runs.gates`, `runs.gate`).
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase")]
pub struct RunGate {
    pub id: String,
    pub run_id: Option<String>,
    pub task_id: Option<String>,
    pub kind: RunGateKind,
    pub scope: String,
    pub question: String,
    pub options: Vec<String>,
    pub status: OrchestrationGateStatus,
    /// A pending stage gate is due once its evidence is bound.
    pub due: bool,
    pub resolution: Option<String>,
    pub reason: Option<String>,
    pub plan_revision: Option<i64>,
    pub evidence_digest: Option<String>,
    pub integration_sha: Option<String>,
    pub actor_kind: Option<String>,
    pub actor_id: Option<String>,
    pub created_at: String,
    pub resolved_at: Option<String>,
}

pub(super) const RUN_GATE_COLUMNS: &str = "id, run_id, task_id, kind, scope, question, options, \
    status, resolution, reason, plan_revision, evidence_digest, integration_sha, actor_kind, \
    actor_id, created_at, resolved_at";

pub(super) fn run_gate_from_row(row: SqliteRow) -> Result<RunGate> {
    let kind = RunGateKind::parse(&row.try_get::<String, _>("kind")?)
        .ok_or_else(|| anyhow!("invalid gate kind"))?;
    let status = OrchestrationGateStatus::parse(&row.try_get::<String, _>("status")?)
        .ok_or_else(|| anyhow!("invalid gate status"))?;
    let evidence_digest: Option<String> = row.try_get("evidence_digest")?;
    Ok(RunGate {
        due: status == OrchestrationGateStatus::Pending
            && (kind != RunGateKind::Stage || evidence_digest.is_some()),
        id: row.try_get("id")?,
        run_id: row.try_get("run_id")?,
        task_id: row.try_get("task_id")?,
        kind,
        scope: row.try_get("scope")?,
        question: row.try_get("question")?,
        options: parse_string_array(&row.try_get::<String, _>("options")?),
        status,
        resolution: row.try_get("resolution")?,
        reason: row.try_get("reason")?,
        plan_revision: row.try_get("plan_revision")?,
        evidence_digest: evidence_digest.filter(|digest| !digest.is_empty()),
        integration_sha: row.try_get("integration_sha")?,
        actor_kind: row.try_get("actor_kind")?,
        actor_id: row.try_get("actor_id")?,
        created_at: row.try_get("created_at")?,
        resolved_at: row.try_get("resolved_at")?,
    })
}

/// The `runs.resolveGate` receipt.
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase")]
pub struct RunGateResolution {
    pub request_id: String,
    pub gate: RunGate,
    pub run_id: Option<String>,
    pub run_status: Option<String>,
    pub plan_revision: Option<i64>,
    /// The run went back to `planning`; its coordinator must replan.
    pub changes_requested: bool,
    /// This receipt answers a repeated request id; nothing changed now.
    #[serde(skip)]
    pub replayed: bool,
}

impl RuntimeStore {
    pub async fn run_gate(&self, gate_id: &str) -> Result<Option<RunGate>> {
        sqlx::query(sqlx::AssertSqlSafe(format!(
            "SELECT {RUN_GATE_COLUMNS} FROM runGates WHERE id = ?"
        )))
        .bind(gate_id)
        .fetch_optional(self.pool())
        .await?
        .map(run_gate_from_row)
        .transpose()
    }

    pub async fn resolve_run_gate(
        &self,
        request: &ResolveRunGate,
        actor: &RunActor,
    ) -> Result<RunGateResolution> {
        super::run_lifecycle::portable_request_id(&request.request_id)?;
        workflow_text(&request.gate_id, 160)?;
        workflow_text(&request.decision, 4096)?;
        if let Some(reason) = &request.reason {
            if reason.len() > 4096 {
                bail!("reason exceeds 4096 bytes");
            }
        }
        let digest = workflow_digest(&("runs.resolveGate", request))?;
        if let Some(receipt) = self
            .run_command_receipt(&request.request_id, &digest)
            .await?
        {
            return replayed(receipt);
        }
        let mut tx = self.pool().begin().await?;
        sqlx::query("UPDATE orchestrationBoardRevision SET revision = revision WHERE id = 1")
            .execute(&mut *tx)
            .await?;
        if let Some(row) = sqlx::query(
            "SELECT request_digest, receipt FROM runCommandReceipts WHERE request_id = ?",
        )
        .bind(&request.request_id)
        .fetch_optional(&mut *tx)
        .await?
        {
            if row.try_get::<String, _>("request_digest")? != digest {
                bail!("run_request_conflict: request id was already used for different contents");
            }
            return replayed(serde_json::from_str(&row.try_get::<String, _>("receipt")?)?);
        }
        let gate = sqlx::query(sqlx::AssertSqlSafe(format!(
            "SELECT {RUN_GATE_COLUMNS} FROM runGates WHERE id = ?"
        )))
        .bind(&request.gate_id)
        .fetch_optional(&mut *tx)
        .await?
        .map(run_gate_from_row)
        .transpose()?
        .ok_or_else(|| anyhow!("gate_not_found: no gate {}", request.gate_id))?;
        if gate.status != OrchestrationGateStatus::Pending {
            bail!(
                "gate_not_pending: gate {} is {}",
                gate.id,
                gate.status.as_str()
            );
        }
        if !gate.due {
            bail!("gate_not_due: the stage is not finished yet");
        }
        let decision = request.decision.trim();
        if !gate.options.is_empty() && !gate.options.iter().any(|option| option == decision) {
            bail!(
                "gate_invalid_resolution: resolve gate {} with one of: {}",
                gate.id,
                gate.options.join(", ")
            );
        }
        if decision.is_empty() {
            bail!("gate_invalid_resolution: a decision is required");
        }
        if let Some(terminal) = request.caller_terminal.as_deref() {
            let person_gate = matches!(
                gate.kind,
                RunGateKind::Plan | RunGateKind::Stage | RunGateKind::Stall
            );
            if person_gate && is_run_participant(&mut tx, gate.run_id.as_deref(), terminal).await? {
                bail!(
                    "gate_not_resolvable: a person decides {} gates; the run's own terminals \
                     cannot resolve them",
                    gate.kind.as_str()
                );
            }
        }
        if let Some(stored) = gate.evidence_digest.as_deref() {
            match request.expected_evidence_digest.as_deref() {
                Some(expected) if expected == stored => {}
                Some(_) => bail!("gate_stale: this gate changed; refresh before deciding"),
                None => bail!(
                    "gate_stale: send the gate's evidenceDigest as expectedEvidenceDigest so a \
                     gate that changed is not decided"
                ),
            }
        }
        if gate.kind == RunGateKind::Stage {
            let run_id = gate.run_id.as_deref().unwrap_or_default();
            let current =
                super::run_gate_evidence::stage_evidence(&mut tx, run_id, &gate.scope).await?;
            if current.map(|(digest, _)| digest) != gate.evidence_digest {
                bail!("gate_stale: the stage evidence changed; refresh before deciding");
            }
        }
        let reason = request
            .reason
            .as_deref()
            .map(str::trim)
            .filter(|reason| !reason.is_empty());
        let audit_id = orchestration_id("audit");
        sqlx::query(
            "INSERT INTO orchestrationAuditEvents
            (id, actor_handle, action, target_id, reason, payload, actor_kind, actor_id)
            VALUES (?, ?, 'gate.resolve', ?, ?, ?, ?, ?)",
        )
        .bind(&audit_id)
        .bind(actor.label())
        .bind(&gate.id)
        .bind(reason.unwrap_or(decision))
        .bind(serde_json::json!({ "decision": decision, "kind": gate.kind.as_str() }).to_string())
        .bind(actor.kind.as_str())
        .bind(&actor.id)
        .execute(&mut *tx)
        .await?;
        sqlx::query(
            "UPDATE runGates SET status = 'resolved', resolution = ?, reason = ?,
                actor_kind = ?, actor_id = ?, audit_id = ?, resolved_at = datetime('now')
            WHERE id = ? AND status = 'pending'",
        )
        .bind(decision)
        .bind(reason)
        .bind(actor.kind.as_str())
        .bind(&actor.id)
        .bind(&audit_id)
        .bind(&gate.id)
        .execute(&mut *tx)
        .await?;
        if let Some(run_id) = gate.run_id.as_deref() {
            let mut event = NewRunEvent::new(run_id, RunEventKind::GateResolved);
            event.task_id = gate.task_id.as_deref();
            event.gate_id = Some(&gate.id);
            event.actor_kind = Some(actor.kind);
            event.actor_id = actor.id.as_deref();
            event.summary = decision;
            event.payload = Some(serde_json::json!({
                "kind": gate.kind.as_str(),
                "scope": gate.scope,
                "resolution": decision,
                "reason": reason,
            }));
            record_run_event(&mut tx, &event).await?;
        }
        let changes_requested = apply(&mut tx, &gate, decision, reason, request, actor).await?;
        let resolved = sqlx::query(sqlx::AssertSqlSafe(format!(
            "SELECT {RUN_GATE_COLUMNS} FROM runGates WHERE id = ?"
        )))
        .bind(&gate.id)
        .fetch_one(&mut *tx)
        .await
        .map_err(anyhow::Error::from)
        .and_then(run_gate_from_row)?;
        let (run_status, plan_revision) = match gate.run_id.as_deref() {
            Some(run_id) => {
                let row = sqlx::query(
                    "SELECT status, plan_revision FROM orchestrationCoordinatorRuns WHERE id = ?",
                )
                .bind(run_id)
                .fetch_one(&mut *tx)
                .await?;
                (Some(row.try_get("status")?), row.try_get("plan_revision")?)
            }
            None => (None, None),
        };
        let receipt = RunGateResolution {
            request_id: request.request_id.clone(),
            gate: resolved,
            run_id: gate.run_id.clone(),
            run_status,
            plan_revision,
            changes_requested,
            replayed: false,
        };
        if let Some(run_id) = gate.run_id.as_deref() {
            sqlx::query(
                "INSERT INTO runCommandReceipts(request_id, request_digest, run_id, receipt)
                VALUES (?, ?, ?, ?)",
            )
            .bind(&request.request_id)
            .bind(&digest)
            .bind(run_id)
            .bind(serde_json::to_string(&receipt)?)
            .execute(&mut *tx)
            .await?;
        }
        tx.commit().await?;
        Ok(receipt)
    }
}

/// The effect of a resolution on its task or run. Returns whether the run
/// went back to planning.
async fn apply(
    tx: &mut Transaction<'_, Sqlite>,
    gate: &RunGate,
    decision: &str,
    reason: Option<&str>,
    request: &ResolveRunGate,
    actor: &RunActor,
) -> Result<bool> {
    let run_id = gate.run_id.as_deref().unwrap_or_default();
    match (gate.kind, decision) {
        (RunGateKind::Decision, _) => {
            sqlx::query(
                "UPDATE orchestrationTasks SET status = 'ready' WHERE id = ? AND status = 'blocked'",
            )
            .bind(&gate.task_id)
            .execute(&mut **tx)
            .await?;
            Ok(false)
        }
        // The lease sweep acts on resolved stall gates.
        (RunGateKind::Stall, _) => Ok(false),
        (RunGateKind::Plan, PLAN_GATE_APPROVE) => {
            sqlx::query(
                "UPDATE orchestrationCoordinatorRuns SET status = 'running', paused_by = NULL,
                    control_sequence = control_sequence + 1, last_activity_at = datetime('now')
                WHERE id = ? AND status = 'awaitingApproval'",
            )
            .bind(run_id)
            .execute(&mut **tx)
            .await?;
            run_event(tx, run_id, RunEventKind::PlanApproved, &gate.id, actor, "").await?;
            Ok(false)
        }
        (RunGateKind::Stage, PLAN_GATE_APPROVE) => {
            sqlx::query(
                "UPDATE orchestrationCoordinatorRuns SET status = 'running', paused_by = NULL,
                    control_sequence = control_sequence + 1, last_activity_at = datetime('now')
                WHERE id = ? AND status = 'paused' AND paused_by = 'runtime'
                  AND attention_reason IS NULL
                  AND NOT EXISTS(SELECT 1 FROM runGates g WHERE g.run_id = ? AND g.status = 'pending'
                      AND g.kind IN ('plan','stage') AND g.evidence_digest IS NOT NULL)",
            )
            .bind(run_id)
            .bind(run_id)
            .execute(&mut **tx)
            .await?;
            Ok(false)
        }
        (RunGateKind::Plan | RunGateKind::Stage, PLAN_GATE_REJECT) => {
            if gate.kind == RunGateKind::Plan {
                run_event(tx, run_id, RunEventKind::PlanRejected, &gate.id, actor, "").await?;
            }
            let reason = reason
                .map(str::to_string)
                .unwrap_or_else(|| format!("{} gate rejected", gate.kind.as_str()));
            super::run_cancellation::cancel(tx, run_id, &reason).await?;
            run_event(
                tx,
                run_id,
                RunEventKind::Cancelled,
                &gate.id,
                actor,
                &reason,
            )
            .await?;
            Ok(false)
        }
        (RunGateKind::Plan | RunGateKind::Stage, PLAN_GATE_REQUEST_CHANGES) => {
            super::run_changes::request_run_changes(
                tx,
                run_id,
                reason.unwrap_or_default(),
                request.task_ids.as_deref().unwrap_or_default(),
                actor,
                Some(&gate.id),
            )
            .await?;
            sqlx::query(
                "UPDATE orchestrationCoordinatorRuns SET control_sequence = control_sequence + 1
                WHERE id = ?",
            )
            .bind(run_id)
            .execute(&mut **tx)
            .await?;
            Ok(true)
        }
        _ => bail!("gate_invalid_resolution: unsupported decision {decision}"),
    }
}

async fn run_event(
    tx: &mut Transaction<'_, Sqlite>,
    run_id: &str,
    kind: RunEventKind,
    gate_id: &str,
    actor: &RunActor,
    summary: &str,
) -> Result<()> {
    let mut event = NewRunEvent::new(run_id, kind);
    event.gate_id = Some(gate_id);
    event.actor_kind = Some(actor.kind);
    event.actor_id = actor.id.as_deref();
    event.summary = summary;
    record_run_event(tx, &event).await?;
    Ok(())
}

fn replayed(receipt: serde_json::Value) -> Result<RunGateResolution> {
    let mut receipt: RunGateResolution = serde_json::from_value(receipt)?;
    receipt.replayed = true;
    Ok(receipt)
}

#[cfg(test)]
impl RuntimeStore {
    /// Resolves a gate as a CLI user would, for store tests.
    pub(crate) async fn resolve_gate(
        &self,
        gate_id: &str,
        resolution: &str,
        reason: Option<&str>,
    ) -> Result<super::OrchestrationDecisionGate> {
        let digest = self
            .run_gate(gate_id)
            .await?
            .and_then(|gate| gate.evidence_digest);
        self.resolve_run_gate(
            &ResolveRunGate {
                request_id: uuid::Uuid::new_v4().to_string(),
                gate_id: gate_id.into(),
                decision: resolution.into(),
                reason: reason.map(str::to_string),
                task_ids: None,
                expected_evidence_digest: digest,
                caller_terminal: None,
            },
            &RunActor::new(super::RunActorKind::Cli, None),
        )
        .await?;
        self.orchestration_gate_by_id(gate_id)
            .await?
            .ok_or_else(|| anyhow!("gate not found after resolution: {gate_id}"))
    }
}

/// Whether `terminal` coordinates, works for, or created tasks in the run.
async fn is_run_participant(
    tx: &mut sqlx::SqliteConnection,
    run_id: Option<&str>,
    terminal: &str,
) -> Result<bool> {
    let Some(run_id) = run_id else {
        return Ok(false);
    };
    Ok(sqlx::query_scalar(
        "SELECT EXISTS(
            SELECT 1 FROM orchestrationCoordinatorRuns WHERE id = ?1 AND coordinator_handle = ?2
            UNION ALL SELECT 1 FROM orchestrationDispatchContexts
                WHERE run_id = ?1 AND assignee_handle = ?2
            UNION ALL SELECT 1 FROM runLaunches WHERE run_id = ?1 AND terminal_handle = ?2
            UNION ALL SELECT 1 FROM orchestrationTasks
                WHERE run_id = ?1 AND created_by_terminal_handle = ?2)",
    )
    .bind(run_id)
    .bind(terminal)
    .fetch_one(&mut *tx)
    .await?)
}
