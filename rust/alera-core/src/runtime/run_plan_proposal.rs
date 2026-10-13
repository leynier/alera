//! `orchestration.planPropose`: a coordinator submits a plan (v2) for its
//! run. Validation reuses the plan compilation of isolated runs; tasks and
//! stage gates are materialized in the same transaction as the revision.
//! Then the plan either waits behind a `plan` gate (`awaitingApproval`) or
//! the run starts at once.

use anyhow::{anyhow, bail, Result};
use serde::Serialize;
use sqlx::{Row, Sqlite, Transaction};

use super::run_event_store::{record_run_event, NewRunEvent, RunActorKind, RunEventKind};
use super::run_lifecycle::RUN_STALL_POLICIES;
use super::run_plan::{workflow_digest, workflow_text};
use super::run_plan_gate_store::open_plan_gate;
use super::run_plan_inputs::compile;
use super::run_plan_materialization::{execution_policy, materialize};
use super::{
    RunActor, RunIsolation, RunPlanInput, RuntimeStore, SharedRunPlanSnapshot,
    WorkflowPlanSnapshot, WORKFLOW_PLAN_MAX_TASKS,
};

/// What `orchestration.planPropose` answers.
#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct RunPlanProposed {
    pub run_id: String,
    pub revision: i64,
    pub status: String,
    pub isolation: RunIsolation,
    pub approval_required: bool,
    pub plan_gate_id: Option<String>,
    pub digest: String,
    pub task_count: usize,
}

pub(super) struct RunRow {
    pub isolation: RunIsolation,
    pub status: String,
    pub plan_revision: Option<i64>,
    pub approval_required: bool,
    pub objective: String,
    pub max_concurrent: i64,
    pub stall_policy: String,
    pub coordinator_handle: Option<String>,
    pub workspace_id: String,
    pub coordinator_profile_id: Option<String>,
    pub profiles_snapshot: Option<String>,
    pub source_snapshot: Option<String>,
    pub plan_approved: bool,
}

pub(super) async fn load_run(conn: &mut sqlx::SqliteConnection, run_id: &str) -> Result<RunRow> {
    let row = sqlx::query(
        "SELECT isolation, status, plan_revision, approval_required, spec, max_concurrent,
            stall_policy, coordinator_handle, workspace_id, coordinator_profile_id,
            profiles_snapshot, source_snapshot,
            EXISTS(SELECT 1 FROM runGates g WHERE g.run_id = r.id AND g.kind = 'plan'
              AND g.status = 'resolved' AND g.resolution = 'approve') AS plan_approved
        FROM orchestrationCoordinatorRuns r WHERE id = ?",
    )
    .bind(run_id)
    .fetch_optional(&mut *conn)
    .await?
    .ok_or_else(|| anyhow!("run_not_found: no run {run_id}"))?;
    Ok(RunRow {
        isolation: match row.try_get::<String, _>("isolation")?.as_str() {
            "isolated" => RunIsolation::Isolated,
            _ => RunIsolation::Shared,
        },
        status: row.try_get("status")?,
        plan_revision: row.try_get("plan_revision")?,
        approval_required: row.try_get("approval_required")?,
        objective: row.try_get("spec")?,
        max_concurrent: row.try_get("max_concurrent")?,
        stall_policy: row.try_get("stall_policy")?,
        coordinator_handle: row.try_get("coordinator_handle")?,
        workspace_id: row.try_get("workspace_id")?,
        coordinator_profile_id: row.try_get("coordinator_profile_id")?,
        profiles_snapshot: row.try_get("profiles_snapshot")?,
        source_snapshot: row.try_get("source_snapshot")?,
        plan_approved: row.try_get("plan_approved")?,
    })
}

/// A compiled plan ready to persist.
pub(super) enum CompiledPlan {
    Isolated(Box<WorkflowPlanSnapshot>),
    Shared(SharedRunPlanSnapshot),
}

impl CompiledPlan {
    pub(super) fn digest(&self) -> &str {
        match self {
            CompiledPlan::Isolated(plan) => &plan.digest,
            CompiledPlan::Shared(plan) => &plan.digest,
        }
    }

    fn snapshot(&self) -> Result<String> {
        Ok(match self {
            CompiledPlan::Isolated(plan) => serde_json::to_string(plan)?,
            CompiledPlan::Shared(plan) => serde_json::to_string(plan)?,
        })
    }

    fn max_concurrent(&self) -> u32 {
        match self {
            CompiledPlan::Isolated(plan) => plan.max_concurrent,
            CompiledPlan::Shared(plan) => plan.max_concurrent,
        }
    }
}

impl RuntimeStore {
    /// Stores a proposed plan as the run's next revision. Shared stages must
    /// already be normalized by the host, which owns the profile catalog.
    pub async fn propose_run_plan(
        &self,
        run_id: &str,
        input: RunPlanInput,
        actor: &RunActor,
    ) -> Result<RunPlanProposed> {
        workflow_text(run_id, 160)?;
        if let Some(id) = &input.request_id {
            super::run_lifecycle::portable_request_id(id)?;
        }
        if let Some(policy) = &input.stall_policy {
            if !RUN_STALL_POLICIES.contains(&policy.as_str()) {
                bail!(
                    "plan.stallPolicy must be one of {}",
                    RUN_STALL_POLICIES.join(", ")
                );
            }
        }
        if input.tasks.len() > WORKFLOW_PLAN_MAX_TASKS {
            bail!("a plan holds at most {WORKFLOW_PLAN_MAX_TASKS} tasks");
        }
        let request_digest = workflow_digest(&("planPropose", run_id, &input))?;
        if let Some(id) = &input.request_id {
            if let Some(row) = sqlx::query(
                "SELECT run_id, revision, request_digest FROM runPlanRevisions WHERE request_id = ?",
            )
            .bind(id)
            .fetch_optional(self.pool())
            .await?
            {
                if row.try_get::<String, _>("request_digest")? != request_digest
                    || row.try_get::<String, _>("run_id")? != run_id
                {
                    bail!("run_request_conflict: plan request id was already used");
                }
                return self
                    .run_plan_proposed(run_id, row.try_get("revision")?)
                    .await;
            }
        }
        let run = {
            let mut conn = self.pool().acquire().await?;
            load_run(&mut conn, run_id).await?
        };
        require_proposable(&run)?;
        let compiled = compile(&run, input.clone()).await?;
        let mut tx = self.pool().begin().await?;
        sqlx::query("UPDATE orchestrationBoardRevision SET revision = revision WHERE id = 1")
            .execute(&mut *tx)
            .await?;
        if let Some(id) = &input.request_id {
            let existing: Option<i64> = sqlx::query_scalar(
                "SELECT revision FROM runPlanRevisions WHERE request_id = ? AND run_id = ?
                    AND request_digest = ?",
            )
            .bind(id)
            .bind(run_id)
            .bind(&request_digest)
            .fetch_optional(&mut *tx)
            .await?;
            if let Some(revision) = existing {
                tx.commit().await?;
                return self.run_plan_proposed(run_id, revision).await;
            }
        }
        let run = load_run(&mut tx, run_id).await?;
        require_proposable(&run)?;
        if let CompiledPlan::Isolated(plan) = &compiled {
            super::run_source_identity::require_source_workspace(&mut tx, &plan.source_workspace)
                .await?;
        }
        let revision = run.plan_revision.unwrap_or(0) + 1;
        supersede_unstarted_plan(&mut tx, run_id).await?;
        for corrects in input
            .tasks
            .iter()
            .filter_map(|task| task.corrects_task_id.as_ref())
        {
            let member: bool = sqlx::query_scalar(
                "SELECT EXISTS(SELECT 1 FROM orchestrationTasks WHERE run_id = ? AND id = ?
                    AND plan_revision IS NOT NULL)",
            )
            .bind(run_id)
            .bind(corrects)
            .fetch_one(&mut *tx)
            .await?;
            if !member {
                bail!("a correction references a task outside this run");
            }
        }
        let request_id = input
            .request_id
            .clone()
            .unwrap_or_else(|| format!("plan:{run_id}:{revision}:{}", uuid::Uuid::new_v4()));
        sqlx::query(
            "INSERT INTO runPlanRevisions
            (run_id, revision, request_id, request_digest, snapshot, digest, previous_revision)
            VALUES (?, ?, ?, ?, ?, ?, ?)",
        )
        .bind(run_id)
        .bind(revision)
        .bind(&request_id)
        .bind(&request_digest)
        .bind(compiled.snapshot()?)
        .bind(compiled.digest())
        .bind(run.plan_revision)
        .execute(&mut *tx)
        .await?;
        let mut proposed = NewRunEvent::new(run_id, RunEventKind::PlanProposed);
        proposed.actor_kind = Some(actor.kind);
        proposed.actor_id = actor.id.as_deref();
        let summary = format!("Revision {revision}");
        proposed.summary = &summary;
        proposed.payload =
            Some(serde_json::json!({ "revision": revision, "digest": compiled.digest() }));
        record_run_event(&mut tx, &proposed).await?;
        let task_count = materialize(&mut tx, run_id, &run, revision, &compiled).await?;
        let stall_policy = input
            .stall_policy
            .clone()
            .unwrap_or_else(|| run.stall_policy.clone());
        let execution_policy = match &compiled {
            CompiledPlan::Shared(plan) => Some(execution_policy(plan)?),
            CompiledPlan::Isolated(_) => None,
        };
        let needs_gate = run.approval_required
            && (run.isolation == RunIsolation::Isolated || !run.plan_approved);
        let plan_gate_id = if needs_gate {
            Some(open_plan_gate(&mut tx, run_id, revision, compiled.digest()).await?)
        } else {
            let mut approved = NewRunEvent::new(run_id, RunEventKind::PlanApproved);
            approved.actor_kind = Some(RunActorKind::Runtime);
            approved.summary = &summary;
            record_run_event(&mut tx, &approved).await?;
            None
        };
        let status = if needs_gate {
            "awaitingApproval"
        } else if run.status == "paused" {
            "paused"
        } else {
            "running"
        };
        sqlx::query(
            "UPDATE orchestrationCoordinatorRuns SET plan_revision = ?, status = ?,
                execution_policy = COALESCE(?, execution_policy), stall_policy = ?,
                max_concurrent = ?, last_activity_at = datetime('now')
            WHERE id = ?",
        )
        .bind(revision)
        .bind(status)
        .bind(execution_policy)
        .bind(&stall_policy)
        .bind(compiled.max_concurrent())
        .bind(run_id)
        .execute(&mut *tx)
        .await?;
        tx.commit().await?;
        Ok(RunPlanProposed {
            run_id: run_id.into(),
            revision,
            status: status.into(),
            isolation: run.isolation,
            approval_required: run.approval_required,
            plan_gate_id,
            digest: compiled.digest().into(),
            task_count,
        })
    }

    async fn run_plan_proposed(&self, run_id: &str, revision: i64) -> Result<RunPlanProposed> {
        let row = sqlx::query(
            "SELECT r.status, r.isolation, r.approval_required, p.digest,
                (SELECT id FROM runGates g WHERE g.run_id = r.id AND g.kind = 'plan'
                   AND g.plan_revision = p.revision ORDER BY rowid DESC LIMIT 1) AS gate_id,
                (SELECT COUNT(*) FROM orchestrationTasks t WHERE t.run_id = r.id
                   AND t.plan_revision = p.revision) AS task_count
            FROM orchestrationCoordinatorRuns r JOIN runPlanRevisions p ON p.run_id = r.id
            WHERE r.id = ? AND p.revision = ?",
        )
        .bind(run_id)
        .bind(revision)
        .fetch_one(self.pool())
        .await?;
        Ok(RunPlanProposed {
            run_id: run_id.into(),
            revision,
            status: row.try_get("status")?,
            isolation: if row.try_get::<String, _>("isolation")? == "isolated" {
                RunIsolation::Isolated
            } else {
                RunIsolation::Shared
            },
            approval_required: row.try_get("approval_required")?,
            plan_gate_id: row.try_get("gate_id")?,
            digest: row.try_get("digest")?,
            task_count: row.try_get::<i64, _>("task_count")? as usize,
        })
    }
}

fn require_proposable(run: &RunRow) -> Result<()> {
    let allowed = match run.isolation {
        RunIsolation::Isolated => matches!(run.status.as_str(), "planning" | "awaitingApproval"),
        RunIsolation::Shared => matches!(
            run.status.as_str(),
            "planning" | "awaitingApproval" | "running" | "paused"
        ),
    };
    if !allowed {
        bail!(
            "run_not_planning: the run does not accept a plan while {}",
            run.status
        );
    }
    Ok(())
}

/// A new plan replaces the tasks of an earlier one that never started, and
/// any stage gates that were waiting on them.
async fn supersede_unstarted_plan(tx: &mut Transaction<'_, Sqlite>, run_id: &str) -> Result<()> {
    sqlx::query(
        "UPDATE orchestrationTasks SET status = 'cancelled', cancelled_at = datetime('now'),
            completed_at = datetime('now')
        WHERE run_id = ? AND plan_revision IS NOT NULL AND status IN ('pending','ready')
          AND NOT EXISTS(SELECT 1 FROM orchestrationDispatchContexts d WHERE d.task_id = orchestrationTasks.id)",
    )
    .bind(run_id)
    .execute(&mut **tx)
    .await?;
    sqlx::query(
        "UPDATE runGates SET status = 'invalidated', resolved_at = datetime('now')
        WHERE run_id = ? AND kind IN ('plan','stage') AND status = 'pending'",
    )
    .bind(run_id)
    .execute(&mut **tx)
    .await?;
    Ok(())
}
