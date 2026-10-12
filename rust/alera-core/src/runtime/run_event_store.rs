//! The run timeline. Each event is written in the same transaction as the
//! mutation it describes, so the timeline never shows a change that rolled
//! back or misses one that committed.

use anyhow::Result;
use serde::{Deserialize, Serialize};
use sqlx::sqlite::SqliteRow;
use sqlx::{Row, SqliteConnection};

use super::orchestration_message_store::orchestration_id;
use super::RuntimeStore;

pub const RUN_EVENT_SUMMARY_MAX_BYTES: usize = 512;
pub const RUN_EVENT_PAYLOAD_MAX_BYTES: usize = 8 * 1024;

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub enum RunEventKind {
    Created,
    CoordinatorStarted,
    PlanProposed,
    PlanApproved,
    PlanRejected,
    ChangesRequested,
    TaskCreated,
    AttemptPrepared,
    Dispatched,
    Accepted,
    Escalation,
    TaskCompleted,
    TaskFailed,
    TaskStalled,
    TaskCancelled,
    GateOpened,
    GateResolved,
    IntegrationStarted,
    Integrated,
    Conflict,
    Attention,
    Retried,
    Paused,
    Resumed,
    Cancelled,
    Completed,
    Failed,
    CleanupPrepared,
    CleanupApplied,
    CleanupAbandoned,
}

impl RunEventKind {
    pub fn as_str(self) -> &'static str {
        match self {
            RunEventKind::Created => "created",
            RunEventKind::CoordinatorStarted => "coordinatorStarted",
            RunEventKind::PlanProposed => "planProposed",
            RunEventKind::PlanApproved => "planApproved",
            RunEventKind::PlanRejected => "planRejected",
            RunEventKind::ChangesRequested => "changesRequested",
            RunEventKind::TaskCreated => "taskCreated",
            RunEventKind::AttemptPrepared => "attemptPrepared",
            RunEventKind::Dispatched => "dispatched",
            RunEventKind::Accepted => "accepted",
            RunEventKind::Escalation => "escalation",
            RunEventKind::TaskCompleted => "taskCompleted",
            RunEventKind::TaskFailed => "taskFailed",
            RunEventKind::TaskStalled => "taskStalled",
            RunEventKind::TaskCancelled => "taskCancelled",
            RunEventKind::GateOpened => "gateOpened",
            RunEventKind::GateResolved => "gateResolved",
            RunEventKind::IntegrationStarted => "integrationStarted",
            RunEventKind::Integrated => "integrated",
            RunEventKind::Conflict => "conflict",
            RunEventKind::Attention => "attention",
            RunEventKind::Retried => "retried",
            RunEventKind::Paused => "paused",
            RunEventKind::Resumed => "resumed",
            RunEventKind::Cancelled => "cancelled",
            RunEventKind::Completed => "completed",
            RunEventKind::Failed => "failed",
            RunEventKind::CleanupPrepared => "cleanupPrepared",
            RunEventKind::CleanupApplied => "cleanupApplied",
            RunEventKind::CleanupAbandoned => "cleanupAbandoned",
        }
    }
}

/// Who caused an event or resolved a gate.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub enum RunActorKind {
    Desktop,
    Mobile,
    Cli,
    Mcp,
    Agent,
    Runtime,
}

impl RunActorKind {
    pub fn as_str(self) -> &'static str {
        match self {
            RunActorKind::Desktop => "desktop",
            RunActorKind::Mobile => "mobile",
            RunActorKind::Cli => "cli",
            RunActorKind::Mcp => "mcp",
            RunActorKind::Agent => "agent",
            RunActorKind::Runtime => "runtime",
        }
    }
}

#[derive(Debug, Clone)]
pub struct NewRunEvent<'a> {
    pub run_id: &'a str,
    pub kind: RunEventKind,
    pub task_id: Option<&'a str>,
    pub dispatch_id: Option<&'a str>,
    pub gate_id: Option<&'a str>,
    pub actor_kind: Option<RunActorKind>,
    pub actor_id: Option<&'a str>,
    pub summary: &'a str,
    pub payload: Option<serde_json::Value>,
}

impl<'a> NewRunEvent<'a> {
    pub fn new(run_id: &'a str, kind: RunEventKind) -> Self {
        Self {
            run_id,
            kind,
            task_id: None,
            dispatch_id: None,
            gate_id: None,
            actor_kind: None,
            actor_id: None,
            summary: "",
            payload: None,
        }
    }
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct RunEvent {
    pub sequence: i64,
    pub id: String,
    pub run_id: String,
    pub task_id: Option<String>,
    pub dispatch_id: Option<String>,
    pub gate_id: Option<String>,
    pub kind: String,
    pub actor_kind: Option<String>,
    pub actor_id: Option<String>,
    pub summary: String,
    pub payload: Option<serde_json::Value>,
    pub created_at: String,
}

fn truncate_to_boundary(value: &str, max_bytes: usize) -> &str {
    if value.len() <= max_bytes {
        return value;
    }
    let mut end = max_bytes;
    while !value.is_char_boundary(end) {
        end -= 1;
    }
    &value[..end]
}

/// Appends one timeline event. Call it on the transaction that performs the
/// mutation. An oversized payload is replaced by a marker instead of failing
/// the mutation it describes.
pub async fn record_run_event(
    conn: &mut SqliteConnection,
    event: &NewRunEvent<'_>,
) -> Result<String> {
    let id = orchestration_id("evt");
    let payload = event.payload.as_ref().map(|payload| {
        let encoded = payload.to_string();
        if encoded.len() > RUN_EVENT_PAYLOAD_MAX_BYTES {
            serde_json::json!({ "truncated": true }).to_string()
        } else {
            encoded
        }
    });
    sqlx::query(
        "INSERT INTO runEvents \
         (id, run_id, task_id, dispatch_id, gate_id, kind, actor_kind, actor_id, summary, payload) \
         VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)",
    )
    .bind(&id)
    .bind(event.run_id)
    .bind(event.task_id)
    .bind(event.dispatch_id)
    .bind(event.gate_id)
    .bind(event.kind.as_str())
    .bind(event.actor_kind.map(RunActorKind::as_str))
    .bind(event.actor_id)
    .bind(truncate_to_boundary(
        event.summary,
        RUN_EVENT_SUMMARY_MAX_BYTES,
    ))
    .bind(payload)
    .execute(conn)
    .await?;
    Ok(id)
}

/// Records `kind` on the run a dispatch belongs to, naming its task. A
/// dispatch outside a run has no timeline, so nothing is written.
pub(crate) async fn record_dispatch_run_event(
    conn: &mut SqliteConnection,
    dispatch_id: &str,
    kind: RunEventKind,
    summary: &str,
    payload: Option<serde_json::Value>,
) -> Result<()> {
    let owner: Option<(Option<String>, String, Option<String>)> = sqlx::query_as(
        "SELECT run_id, task_id, assignee_handle FROM orchestrationDispatchContexts WHERE id = ?",
    )
    .bind(dispatch_id)
    .fetch_optional(&mut *conn)
    .await?;
    let Some((Some(run_id), task_id, assignee)) = owner else {
        return Ok(());
    };
    let mut event = NewRunEvent::new(&run_id, kind);
    event.task_id = Some(&task_id);
    event.dispatch_id = Some(dispatch_id);
    if kind == RunEventKind::Accepted {
        event.actor_kind = Some(RunActorKind::Agent);
        event.actor_id = assignee.as_deref();
    } else {
        event.actor_kind = Some(RunActorKind::Runtime);
    }
    event.summary = summary;
    event.payload = payload;
    record_run_event(conn, &event).await?;
    Ok(())
}

/// Records `kind` on the run a task belongs to. A task outside a run has no
/// timeline, so nothing is written.
pub(crate) async fn record_task_run_event(
    conn: &mut SqliteConnection,
    task_id: &str,
    kind: RunEventKind,
    summary: &str,
    payload: Option<serde_json::Value>,
) -> Result<()> {
    let run_id: Option<Option<String>> =
        sqlx::query_scalar("SELECT run_id FROM orchestrationTasks WHERE id = ?")
            .bind(task_id)
            .fetch_optional(&mut *conn)
            .await?;
    let Some(Some(run_id)) = run_id else {
        return Ok(());
    };
    let mut event = NewRunEvent::new(&run_id, kind);
    event.task_id = Some(task_id);
    event.summary = summary;
    event.payload = payload;
    record_run_event(conn, &event).await?;
    Ok(())
}

fn run_event_from_row(row: SqliteRow) -> Result<RunEvent> {
    Ok(RunEvent {
        sequence: row.try_get("sequence")?,
        id: row.try_get("id")?,
        run_id: row.try_get("run_id")?,
        task_id: row.try_get("task_id")?,
        dispatch_id: row.try_get("dispatch_id")?,
        gate_id: row.try_get("gate_id")?,
        kind: row.try_get("kind")?,
        actor_kind: row.try_get("actor_kind")?,
        actor_id: row.try_get("actor_id")?,
        summary: row.try_get("summary")?,
        payload: row
            .try_get::<Option<String>, _>("payload")?
            .and_then(|raw| serde_json::from_str(&raw).ok()),
        created_at: row.try_get("created_at")?,
    })
}

impl RuntimeStore {
    /// A run's timeline, oldest first.
    pub async fn run_events(&self, run_id: &str, limit: i64) -> Result<Vec<RunEvent>> {
        sqlx::query(
            "SELECT sequence, id, run_id, task_id, dispatch_id, gate_id, kind, actor_kind, \
             actor_id, summary, payload, created_at FROM runEvents \
             WHERE run_id = ? ORDER BY sequence ASC LIMIT ?",
        )
        .bind(run_id)
        .bind(limit.clamp(1, 1000))
        .fetch_all(self.pool())
        .await?
        .into_iter()
        .map(run_event_from_row)
        .collect()
    }
}
