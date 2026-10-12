//! `runs.timeline`: a run's events and the messages exchanged between its
//! terminals, newest first, a page at a time.

use anyhow::{bail, Result};
use serde::{Deserialize, Serialize};
use serde_json::Value;
use sqlx::{QueryBuilder, Row, Sqlite};

use super::RuntimeStore;

pub const RUN_TIMELINE_MAX_LIMIT: u32 = 200;
pub const RUN_TIMELINE_BODY_MAX_BYTES: usize = 4 * 1024;

#[derive(Debug, Clone, Deserialize, Default)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct RunTimelineQuery {
    pub run_id: String,
    #[serde(default)]
    pub cursor: Option<String>,
    #[serde(default)]
    pub limit: Option<u32>,
    /// Event kinds to keep; `message` selects messages.
    #[serde(default)]
    pub kinds: Option<Vec<String>>,
    #[serde(default)]
    pub task_id: Option<String>,
}

#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct RunTimelineEntry {
    pub id: String,
    /// `event` or `message`.
    pub source: String,
    /// The event kind, or `message`.
    pub kind: String,
    pub created_at: String,
    pub task_id: Option<String>,
    pub dispatch_id: Option<String>,
    pub gate_id: Option<String>,
    pub actor_kind: Option<String>,
    pub actor_id: Option<String>,
    pub summary: String,
    pub payload: Option<Value>,
    /// Messages, and escalation events: `status`, `handoff`, `merge_ready`,
    /// `decision_gate`, `escalation` or `question`.
    pub message_type: Option<String>,
    pub from: Option<String>,
    pub to: Option<String>,
    pub thread_id: Option<String>,
    pub body: Option<String>,
    pub truncated: bool,
    /// Task completion, integration and run completion events: the workspace
    /// holding the result and the commit range (`baseSha..sha`) to diff.
    pub workspace_id: Option<String>,
    pub sha: Option<String>,
    pub base_sha: Option<String>,
}

#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct RunTimelinePage {
    pub run_id: String,
    pub items: Vec<RunTimelineEntry>,
    pub next_cursor: Option<String>,
}

const MESSAGE_TYPES: &str =
    "('status','handoff','merge_ready','decision_gate','escalation','question')";

impl RuntimeStore {
    pub async fn run_timeline(&self, query: &RunTimelineQuery) -> Result<RunTimelinePage> {
        let limit = query.limit.unwrap_or(50);
        if !(1..=RUN_TIMELINE_MAX_LIMIT).contains(&limit) {
            bail!("timeline limit must be between 1 and {RUN_TIMELINE_MAX_LIMIT}");
        }
        if query.run_id.is_empty() || query.run_id.len() > 256 {
            bail!("invalid run id");
        }
        let cursor = match query.cursor.as_deref() {
            Some(raw) => {
                let (at, key) = raw
                    .split_once('|')
                    .filter(|(at, key)| at.len() <= 64 && key.len() <= 64)
                    .ok_or_else(|| anyhow::anyhow!("invalid timeline cursor"))?;
                Some((at.to_string(), key.to_string()))
            }
            None => None,
        };
        let kinds = query.kinds.clone().unwrap_or_default();
        if kinds.len() > 40 || kinds.iter().any(|kind| kind.len() > 64) {
            bail!("invalid timeline kinds");
        }
        let exists: bool = sqlx::query_scalar(
            "SELECT EXISTS(SELECT 1 FROM orchestrationCoordinatorRuns WHERE id = ?)",
        )
        .bind(&query.run_id)
        .fetch_one(self.pool())
        .await?;
        if !exists {
            bail!("run_not_found: no run {}", query.run_id);
        }
        let want_messages = kinds.is_empty() || kinds.iter().any(|kind| kind == "message");
        let event_kinds = kinds
            .iter()
            .filter(|kind| kind.as_str() != "message")
            .cloned()
            .collect::<Vec<_>>();
        let want_events = kinds.is_empty() || !event_kinds.is_empty();
        let mut sql: QueryBuilder<Sqlite> = QueryBuilder::new("SELECT * FROM (");
        let mut first = true;
        if want_events {
            first = false;
            // An escalation event carries its message's route and body.
            sql.push(format!(
                "SELECT e.id, 'event' AS source, e.kind, e.created_at, e.task_id, e.dispatch_id,
                    e.gate_id, e.actor_kind, e.actor_id, e.summary, e.payload,
                    m.type AS message_type, m.from_handle, m.to_handle, m.thread_id,
                    substr(m.body, 1, {RUN_TIMELINE_BODY_MAX_BYTES}) AS body,
                    COALESCE(length(CAST(m.body AS BLOB)) > {RUN_TIMELINE_BODY_MAX_BYTES}, 0)
                        AS body_truncated,
                    'e' || printf('%020d', e.sequence) AS ord
                FROM runEvents e
                LEFT JOIN orchestrationMessages m ON e.kind = 'escalation'
                    AND m.id = json_extract(e.payload, '$.messageId')
                WHERE e.run_id = "
            ))
            .push_bind(&query.run_id);
            if !event_kinds.is_empty() {
                sql.push(" AND e.kind IN (");
                let mut separated = sql.separated(", ");
                for kind in &event_kinds {
                    separated.push_bind(kind);
                }
                sql.push(")");
            }
            if let Some(task) = &query.task_id {
                sql.push(" AND e.task_id = ").push_bind(task);
            }
        }
        if want_messages {
            if !first {
                sql.push(" UNION ALL ");
            }
            // A run's messages: those stamped with the run, and those between
            // its coordinator and the terminals of its dispatches.
            sql.push(format!(
                "SELECT m.id, 'message' AS source, 'message' AS kind, m.created_at, m.task_id,
                    m.dispatch_id, NULL AS gate_id, NULL AS actor_kind, NULL AS actor_id,
                    substr(m.subject, 1, 512) AS summary, NULL AS payload, m.type AS message_type,
                    m.from_handle, m.to_handle, m.thread_id,
                    substr(m.body, 1, {RUN_TIMELINE_BODY_MAX_BYTES}) AS body,
                    length(CAST(m.body AS BLOB)) > {RUN_TIMELINE_BODY_MAX_BYTES} AS body_truncated,
                    'm' || printf('%020d', m.sequence) AS ord
                FROM orchestrationMessages m
                WHERE m.type IN {MESSAGE_TYPES}
                  AND m.from_handle NOT LIKE 'ext:%' AND m.to_handle NOT LIKE 'ext:%'
                  AND (m.type <> 'escalation' OR NOT EXISTS(SELECT 1 FROM runEvents e
                      WHERE e.run_id = m.run_id AND e.kind = 'escalation'
                      AND json_extract(e.payload, '$.messageId') = m.id))
                  AND (m.run_id = "
            ))
            .push_bind(&query.run_id)
            .push(
                " OR (m.run_id IS NULL AND EXISTS(WITH handles(h) AS (
                    SELECT coordinator_handle FROM orchestrationCoordinatorRuns WHERE id = ",
            )
            .push_bind(&query.run_id)
            .push(" UNION SELECT coordinator_tab_id FROM orchestrationCoordinatorRuns WHERE id = ")
            .push_bind(&query.run_id)
            .push(
                " UNION SELECT assignee_handle FROM orchestrationDispatchContexts WHERE run_id = ",
            )
            .push_bind(&query.run_id)
            .push(" UNION SELECT terminal_handle FROM runLaunches WHERE run_id = ")
            .push_bind(&query.run_id)
            .push(
                ") SELECT 1 FROM handles a, handles b
                    WHERE a.h = m.from_handle AND b.h = m.to_handle)))",
            );
            if let Some(task) = &query.task_id {
                sql.push(" AND m.task_id = ").push_bind(task);
            }
        }
        if first && !want_messages {
            bail!("timeline kinds select nothing");
        }
        sql.push(") timeline");
        if let Some((at, key)) = &cursor {
            sql.push(" WHERE (created_at < ")
                .push_bind(at)
                .push(" OR (created_at = ")
                .push_bind(at)
                .push(" AND ord < ")
                .push_bind(key)
                .push("))");
        }
        sql.push(" ORDER BY created_at DESC, ord DESC LIMIT ")
            .push_bind(i64::from(limit) + 1);
        let rows = sql.build().fetch_all(self.pool()).await?;
        let mut items = Vec::new();
        let mut keys = Vec::new();
        for row in rows {
            keys.push((
                row.try_get::<String, _>("created_at")?,
                row.try_get::<String, _>("ord")?,
            ));
            let payload: Option<Value> = row
                .try_get::<Option<String>, _>("payload")?
                .and_then(|raw| serde_json::from_str(&raw).ok());
            let payload_text = |key: &str| {
                payload
                    .as_ref()
                    .and_then(|payload| payload.get(key))
                    .and_then(Value::as_str)
                    .filter(|value| !value.is_empty())
                    .map(str::to_string)
            };
            let (workspace_id, sha, base_sha) = (
                payload_text("workspaceId"),
                payload_text("sha"),
                payload_text("baseSha"),
            );
            items.push(RunTimelineEntry {
                id: row.try_get("id")?,
                source: row.try_get("source")?,
                kind: row.try_get("kind")?,
                created_at: row.try_get("created_at")?,
                task_id: row.try_get("task_id")?,
                dispatch_id: row.try_get("dispatch_id")?,
                gate_id: row.try_get("gate_id")?,
                actor_kind: row.try_get("actor_kind")?,
                actor_id: row.try_get("actor_id")?,
                summary: row
                    .try_get::<Option<String>, _>("summary")?
                    .unwrap_or_default(),
                payload,
                message_type: row.try_get("message_type")?,
                from: row.try_get("from_handle")?,
                to: row.try_get("to_handle")?,
                thread_id: row.try_get("thread_id")?,
                truncated: row.try_get::<bool, _>("body_truncated")?,
                body: row.try_get("body")?,
                workspace_id,
                sha,
                base_sha,
            });
            if let Some(entry) = items.last_mut() {
                if let Some(body) = entry.body.as_mut() {
                    if body.len() > RUN_TIMELINE_BODY_MAX_BYTES {
                        let mut end = RUN_TIMELINE_BODY_MAX_BYTES;
                        while !body.is_char_boundary(end) {
                            end -= 1;
                        }
                        body.truncate(end);
                        entry.truncated = true;
                    }
                }
            }
        }
        let has_more = items.len() > limit as usize;
        items.truncate(limit as usize);
        let next_cursor = has_more
            .then(|| keys.get(limit as usize - 1))
            .flatten()
            .map(|(at, key)| format!("{at}|{key}"));
        Ok(RunTimelinePage {
            run_id: query.run_id.clone(),
            items,
            next_cursor,
        })
    }
}
