//! Request Changes on a run: from a plan or stage gate, or `runs.control
//! replan`. The current plan is copied into a placeholder revision that
//! carries the reason, unfinished tasks are cancelled, completed evidence is
//! kept, and the run returns to `planning` for its coordinator.

use anyhow::{bail, Result};
use sqlx::{Row, Sqlite, Transaction};

use super::run_event_store::{record_run_event, NewRunEvent, RunEventKind};
use super::RunActor;

pub(super) async fn ensure_no_active_work(
    tx: &mut Transaction<'_, Sqlite>,
    run_id: &str,
) -> Result<()> {
    let active: bool = sqlx::query_scalar(
        "SELECT EXISTS(SELECT 1 FROM orchestrationTasks WHERE run_id = ?
            AND status IN ('dispatched','stalled'))",
    )
    .bind(run_id)
    .fetch_one(&mut **tx)
    .await?;
    if active {
        bail!("run_has_active_work: stop or finish active attempts before requesting changes");
    }
    let unsettled: bool = sqlx::query_scalar(
        "SELECT EXISTS(SELECT 1 FROM runIntegrations
        WHERE run_id = ? AND cancelled=0 AND state IN ('pending','prepared','attention'))",
    )
    .bind(run_id)
    .fetch_one(&mut **tx)
    .await?;
    if unsettled {
        bail!(
            "run_integration_pending: reconcile the pending integration before requesting changes"
        );
    }
    Ok(())
}

/// Returns the placeholder revision, or `None` when the run had no plan yet.
pub(super) async fn request_run_changes(
    tx: &mut Transaction<'_, Sqlite>,
    run_id: &str,
    reason: &str,
    task_ids: &[String],
    actor: &RunActor,
    gate_id: Option<&str>,
) -> Result<Option<i64>> {
    if reason.trim().is_empty() {
        bail!("run_reason_required: explain the changes you request");
    }
    ensure_no_active_work(tx, run_id).await?;
    for task in task_ids {
        let member: bool = sqlx::query_scalar(
            "SELECT EXISTS(SELECT 1 FROM orchestrationTasks WHERE run_id = ? AND id = ?)",
        )
        .bind(run_id)
        .bind(task)
        .fetch_one(&mut **tx)
        .await?;
        if !member {
            bail!("run_task_not_found: task {task} does not belong to this run");
        }
    }
    let current = sqlx::query(
        "SELECT p.revision, p.snapshot, p.digest FROM orchestrationCoordinatorRuns r
        JOIN runPlanRevisions p ON p.run_id = r.id AND p.revision = r.plan_revision
        WHERE r.id = ?",
    )
    .bind(run_id)
    .fetch_optional(&mut **tx)
    .await?;
    let placeholder = match current {
        Some(row) => {
            let revision: i64 = row.try_get("revision")?;
            let next = revision + 1;
            sqlx::query(
                "INSERT INTO runPlanRevisions
                (run_id, revision, request_id, request_digest, snapshot, digest,
                 previous_revision, change_reason, change_task_ids)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)",
            )
            .bind(run_id)
            .bind(next)
            .bind(format!("changes:{}", uuid::Uuid::new_v4()))
            .bind(super::run_plan::workflow_digest(&(reason, task_ids))?)
            .bind(row.try_get::<String, _>("snapshot")?)
            .bind(row.try_get::<String, _>("digest")?)
            .bind(revision)
            .bind(reason)
            .bind(serde_json::to_string(task_ids)?)
            .execute(&mut **tx)
            .await?;
            Some(next)
        }
        None => None,
    };
    // Completed evidence stays immutable and inspectable for the next plan.
    sqlx::query(
        "UPDATE orchestrationTasks SET status = 'cancelled', cancelled_at = datetime('now'),
            completed_at = COALESCE(completed_at, datetime('now'))
        WHERE run_id = ? AND status IN ('pending','ready','blocked','failed')",
    )
    .bind(run_id)
    .execute(&mut **tx)
    .await?;
    sqlx::query(
        "UPDATE runGates SET status = 'invalidated', resolved_at = datetime('now')
        WHERE run_id = ? AND status = 'pending' AND (? IS NULL OR id <> ?)",
    )
    .bind(run_id)
    .bind(gate_id)
    .bind(gate_id)
    .execute(&mut **tx)
    .await?;
    sqlx::query(
        "UPDATE orchestrationCoordinatorRuns SET status = 'planning', paused_by = NULL,
            attention_reason = NULL, plan_revision = COALESCE(?, plan_revision),
            last_activity_at = datetime('now')
        WHERE id = ?",
    )
    .bind(placeholder)
    .bind(run_id)
    .execute(&mut **tx)
    .await?;
    let mut event = NewRunEvent::new(run_id, RunEventKind::ChangesRequested);
    event.gate_id = gate_id;
    event.actor_kind = Some(actor.kind);
    event.actor_id = actor.id.as_deref();
    event.summary = reason;
    event.payload = Some(serde_json::json!({ "taskIds": task_ids, "revision": placeholder }));
    record_run_event(tx, &event).await?;
    Ok(placeholder)
}
