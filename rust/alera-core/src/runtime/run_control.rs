//! `runs.control` and `runs.retryCancellation`: a person pauses, resumes,
//! cancels or replans a run. Every command names the `control_sequence` it
//! observed, so a stale screen cannot act on a run that changed, and a
//! replayed request id returns its original receipt.

use anyhow::{anyhow, bail, Result};
use serde::{Deserialize, Serialize};
use sqlx::{Row, Sqlite, Transaction};

use super::run_event_store::{record_run_event, NewRunEvent, RunEventKind};
use super::run_plan::{workflow_digest, workflow_text};
use super::{RunActor, RuntimeStore};

#[derive(Clone, Copy, Debug, Deserialize, Serialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase")]
pub enum RunControlAction {
    Cancel,
    Pause,
    Resume,
    Replan,
}

impl RunControlAction {
    pub fn as_str(self) -> &'static str {
        match self {
            RunControlAction::Cancel => "cancel",
            RunControlAction::Pause => "pause",
            RunControlAction::Resume => "resume",
            RunControlAction::Replan => "replan",
        }
    }
}

#[derive(Clone, Debug, Deserialize, Serialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct RunControl {
    pub request_id: String,
    pub run_id: String,
    pub expected_sequence: i64,
    pub action: RunControlAction,
    #[serde(default)]
    pub reason: Option<String>,
    #[serde(default)]
    pub task_ids: Option<Vec<String>>,
}

#[derive(Clone, Debug, Deserialize, Serialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct RetryRunCancellation {
    pub request_id: String,
    pub run_id: String,
    pub expected_sequence: i64,
}

/// The `runs.control` / `runs.retryCancellation` receipt.
#[derive(Clone, Debug, Deserialize, Serialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase")]
pub struct RunControlReceipt {
    pub request_id: String,
    pub run_id: String,
    pub action: String,
    pub sequence: i64,
    pub status: String,
    pub plan_revision: Option<i64>,
    /// The run went back to `planning`; its coordinator must replan.
    pub changes_requested: bool,
    /// This receipt answers a repeated request id; nothing changed now.
    #[serde(skip)]
    pub replayed: bool,
}

enum Command<'a> {
    Control(&'a RunControl, Option<&'a str>),
    RetryCancellation,
}

impl RuntimeStore {
    pub async fn control_run(
        &self,
        request: &RunControl,
        actor: &RunActor,
    ) -> Result<RunControlReceipt> {
        let digest = workflow_digest(&("runs.control", request))?;
        let reason = request
            .reason
            .as_deref()
            .map(str::trim)
            .filter(|reason| !reason.is_empty());
        self.run_command(
            &request.request_id,
            &request.run_id,
            request.expected_sequence,
            &digest,
            request.action.as_str(),
            Command::Control(request, reason),
            actor,
        )
        .await
    }

    /// Retries the cancellation targets and integrations of a cancelled run
    /// that need a person. Automatic recovery never selects them.
    pub async fn retry_run_cancellation(
        &self,
        request: &RetryRunCancellation,
        actor: &RunActor,
    ) -> Result<RunControlReceipt> {
        let digest = workflow_digest(&("runs.retryCancellation", request))?;
        self.run_command(
            &request.request_id,
            &request.run_id,
            request.expected_sequence,
            &digest,
            "retryCancellation",
            Command::RetryCancellation,
            actor,
        )
        .await
    }

    /// Runs one sequence-checked command with its receipt.
    #[allow(clippy::too_many_arguments)]
    async fn run_command(
        &self,
        request_id: &str,
        run_id: &str,
        expected_sequence: i64,
        digest: &str,
        action: &str,
        command: Command<'_>,
        actor: &RunActor,
    ) -> Result<RunControlReceipt> {
        super::run_lifecycle::portable_request_id(request_id)?;
        workflow_text(run_id, 160)?;
        if expected_sequence < 0 {
            bail!("expectedSequence must not be negative");
        }
        if let Some(receipt) = self.run_command_receipt(request_id, digest).await? {
            let mut receipt: RunControlReceipt = serde_json::from_value(receipt)?;
            receipt.replayed = true;
            return Ok(receipt);
        }
        let mut tx = self.pool().begin().await?;
        sqlx::query("UPDATE orchestrationCoordinatorRuns SET control_sequence = control_sequence WHERE id = ?")
            .bind(run_id)
            .execute(&mut *tx)
            .await?;
        if let Some(row) = sqlx::query(
            "SELECT request_digest, receipt FROM runCommandReceipts WHERE request_id = ?",
        )
        .bind(request_id)
        .fetch_optional(&mut *tx)
        .await?
        {
            if row.try_get::<String, _>("request_digest")? != digest {
                bail!("run_request_conflict: request id was already used for different contents");
            }
            let mut receipt: RunControlReceipt =
                serde_json::from_str(&row.try_get::<String, _>("receipt")?)?;
            receipt.replayed = true;
            return Ok(receipt);
        }
        let row = sqlx::query(
            "SELECT status, control_sequence FROM orchestrationCoordinatorRuns WHERE id = ?",
        )
        .bind(run_id)
        .fetch_optional(&mut *tx)
        .await?
        .ok_or_else(|| anyhow!("run_not_found: no run {run_id}"))?;
        let sequence: i64 = row.try_get("control_sequence")?;
        if sequence != expected_sequence {
            bail!("run_sequence_stale: the run changed; refresh before acting on it");
        }
        let status: String = row.try_get("status")?;
        let changes_requested = match command {
            Command::Control(request, reason) => {
                control(&mut tx, request, status, reason, actor).await?
            }
            Command::RetryCancellation => {
                retry_cancellation(&mut tx, run_id, &status, actor).await?
            }
        };
        sqlx::query(
            "UPDATE orchestrationCoordinatorRuns SET control_sequence = ?,
                last_activity_at = datetime('now') WHERE id = ?",
        )
        .bind(sequence + 1)
        .bind(run_id)
        .execute(&mut *tx)
        .await?;
        let row = sqlx::query(
            "SELECT status, plan_revision FROM orchestrationCoordinatorRuns WHERE id = ?",
        )
        .bind(run_id)
        .fetch_one(&mut *tx)
        .await?;
        let receipt = RunControlReceipt {
            request_id: request_id.into(),
            run_id: run_id.into(),
            action: action.into(),
            sequence: sequence + 1,
            status: row.try_get("status")?,
            plan_revision: row.try_get("plan_revision")?,
            changes_requested,
            replayed: false,
        };
        sqlx::query(
            "INSERT INTO runCommandReceipts(request_id, request_digest, run_id, receipt)
            VALUES (?, ?, ?, ?)",
        )
        .bind(request_id)
        .bind(digest)
        .bind(run_id)
        .bind(serde_json::to_string(&receipt)?)
        .execute(&mut *tx)
        .await?;
        tx.commit().await?;
        Ok(receipt)
    }
}

async fn retry_cancellation(
    tx: &mut Transaction<'_, Sqlite>,
    run_id: &str,
    status: &str,
    actor: &RunActor,
) -> Result<bool> {
    if status != "cancelled" {
        bail!("run_not_cancelled: only a cancelled run retries its cancellation");
    }
    let attention: bool = sqlx::query_scalar(
        "SELECT EXISTS(SELECT 1 FROM runCancellationTargets
            WHERE run_id = ? AND state = 'attention')
        OR EXISTS(SELECT 1 FROM runIntegrations
            WHERE run_id = ? AND cancelled = 0 AND state = 'attention')",
    )
    .bind(run_id)
    .bind(run_id)
    .fetch_one(&mut **tx)
    .await?;
    if !attention {
        bail!("run_nothing_to_retry: the cancellation needs no retry");
    }
    super::run_cancellation::cancel(tx, run_id, "Run cancelled.").await?;
    let mut event = NewRunEvent::new(run_id, RunEventKind::Retried);
    event.actor_kind = Some(actor.kind);
    event.actor_id = actor.id.as_deref();
    event.summary = "Cancellation retried.";
    record_run_event(tx, &event).await?;
    Ok(false)
}

async fn control(
    tx: &mut Transaction<'_, Sqlite>,
    request: &RunControl,
    status: String,
    reason: Option<&str>,
    actor: &RunActor,
) -> Result<bool> {
    let run_id = request.run_id.as_str();
    let event = |kind, summary: &'static str| {
        let mut event = NewRunEvent::new(run_id, kind);
        event.actor_kind = Some(actor.kind);
        event.actor_id = actor.id.as_deref();
        event.summary = summary;
        event
    };
    match request.action {
        super::RunControlAction::Pause => {
            if status != "running" {
                bail!("run_not_running: only a running run can be paused");
            }
            sqlx::query(
                "UPDATE orchestrationCoordinatorRuns SET status = 'paused', paused_by = 'user'
                WHERE id = ?",
            )
            .bind(run_id)
            .execute(&mut **tx)
            .await?;
            record_run_event(tx, &event(RunEventKind::Paused, "Paused.")).await?;
            Ok(false)
        }
        super::RunControlAction::Resume => {
            if status != "paused" {
                bail!("run_not_paused: only a paused run can be resumed");
            }
            let gated: bool = sqlx::query_scalar(
                "SELECT EXISTS(SELECT 1 FROM runGates WHERE run_id = ? AND status = 'pending'
                    AND kind IN ('plan','stage') AND evidence_digest IS NOT NULL)",
            )
            .bind(run_id)
            .fetch_one(&mut **tx)
            .await?;
            if gated {
                bail!("run_gate_pending: resolve the pending gate to continue");
            }
            sqlx::query(
                "UPDATE orchestrationCoordinatorRuns SET status = 'running', paused_by = NULL,
                    attention_reason = NULL WHERE id = ?",
            )
            .bind(run_id)
            .execute(&mut **tx)
            .await?;
            record_run_event(tx, &event(RunEventKind::Resumed, "Resumed.")).await?;
            Ok(false)
        }
        super::RunControlAction::Cancel => {
            if matches!(status.as_str(), "completed" | "failed" | "cancelled") {
                bail!("run_finished: the run is already {status}");
            }
            let summary = reason.unwrap_or("Cancelled.");
            super::run_cancellation::cancel(tx, run_id, summary).await?;
            let mut cancelled = event(RunEventKind::Cancelled, "");
            cancelled.summary = summary;
            record_run_event(tx, &cancelled).await?;
            Ok(false)
        }
        super::RunControlAction::Replan => {
            if !matches!(
                status.as_str(),
                "planning" | "awaitingApproval" | "running" | "paused"
            ) {
                bail!("run_finished: a {status} run cannot be replanned");
            }
            let reason =
                reason.ok_or_else(|| anyhow!("run_reason_required: explain the changes"))?;
            super::run_changes::request_run_changes(
                tx,
                run_id,
                reason,
                request.task_ids.as_deref().unwrap_or_default(),
                actor,
                None,
            )
            .await?;
            Ok(true)
        }
    }
}
