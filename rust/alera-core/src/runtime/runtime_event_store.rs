//! The runtime event journal: one row per domain event, in order.
//!
//! Clients read it with a cursor (`seq`), so a reader that reconnects or loses
//! a response reads the same events again instead of missing them. Events
//! carry identifiers and states only; details stay behind the tools that read
//! them. Rows older than [`RUNTIME_EVENT_RETENTION_DAYS`] are pruned.

use anyhow::Result;
use chrono::{Duration, Utc};
use serde::Serialize;
use serde_json::Value;
use sqlx::Row;

use super::RuntimeStore;

pub(super) const RUNTIME_EVENT_SCHEMA: &[&str] = &[
    "CREATE TABLE IF NOT EXISTS runtimeEvents (
        seq INTEGER PRIMARY KEY AUTOINCREMENT,
        id TEXT NOT NULL UNIQUE,
        kind TEXT NOT NULL,
        workspaceId TEXT,
        projectId TEXT,
        dataJson TEXT NOT NULL,
        occurredAt TEXT NOT NULL,
        forwardedAt TEXT
    );",
    "CREATE INDEX IF NOT EXISTS runtimeEventsKindIdx ON runtimeEvents(kind, seq);",
    "CREATE INDEX IF NOT EXISTS runtimeEventsWorkspaceIdx ON runtimeEvents(workspaceId, seq);",
];

/// A version-4 UUID in SQL, for events the triggers below record.
const SQL_EVENT_ID: &str = "lower(hex(randomblob(4)) || '-' || hex(randomblob(2)) || '-4' || \
     substr(hex(randomblob(2)), 2) || '-' || substr('89ab', 1 + (abs(random()) % 4), 1) || \
     substr(hex(randomblob(2)), 2) || '-' || hex(randomblob(6)))";
const SQL_NOW: &str = "strftime('%Y-%m-%dT%H:%M:%f+00:00', 'now')";

/// Task and external question states change in many places; triggers record
/// every transition without each writer having to remember it. They run
/// after every orchestration migration, which may rebuild those tables.
fn trigger_statements() -> Vec<String> {
    let task_event = format!(
        "INSERT INTO runtimeEvents (id, kind, workspaceId, dataJson, occurredAt) VALUES \
         ({SQL_EVENT_ID}, 'orchestration.task.state', NEW.workspace_id, \
         json_object('taskId', NEW.id, 'runId', NEW.run_id, 'state', NEW.status), {SQL_NOW});"
    );
    // `inbox_queries::question_status` precedence: cancelled, answered,
    // expired, delivered, received, pending.
    let question_status = "CASE WHEN NEW.state = 'obsolete' THEN 'cancelled' \
         WHEN EXISTS (SELECT 1 FROM orchestrationMessages r WHERE r.reply_to_id = NEW.id \
         AND r.from_handle = NEW.to_handle) THEN 'answered' \
         WHEN NEW.state = 'expired' AND NEW.delivered_at IS NULL THEN 'expired' \
         WHEN NEW.delivered_at IS NOT NULL THEN 'delivered' \
         WHEN NEW.read = 1 THEN 'received' ELSE 'pending' END";
    vec![
        format!(
            "CREATE TRIGGER IF NOT EXISTS runtimeEventsTaskCreated AFTER INSERT ON orchestrationTasks \
             BEGIN {task_event} END;"
        ),
        format!(
            "CREATE TRIGGER IF NOT EXISTS runtimeEventsTaskState AFTER UPDATE OF status ON orchestrationTasks \
             WHEN OLD.status IS NOT NEW.status BEGIN {task_event} END;"
        ),
        format!(
            "CREATE TRIGGER IF NOT EXISTS runtimeEventsQuestionState AFTER UPDATE OF state, delivered_at, read \
             ON orchestrationMessages WHEN NEW.from_handle LIKE 'ext:%' \
             AND (OLD.state IS NOT NEW.state OR OLD.delivered_at IS NOT NEW.delivered_at OR OLD.read IS NOT NEW.read) \
             BEGIN INSERT INTO runtimeEvents (id, kind, workspaceId, dataJson, occurredAt) VALUES \
             ({SQL_EVENT_ID}, 'inbox.question.status', NEW.workspace_id, json_object('inbox', NEW.from_handle, \
             'threadId', COALESCE(NEW.thread_id, NEW.id), 'questionId', NEW.id, 'status', {question_status}), \
             {SQL_NOW}); END;"
        ),
        // A reply answers its question without updating it, so the answer is
        // recorded when the correlated reply is inserted.
        format!(
            "CREATE TRIGGER IF NOT EXISTS runtimeEventsQuestionAnswered AFTER INSERT ON orchestrationMessages \
             WHEN NEW.reply_to_id IS NOT NULL AND NEW.to_handle LIKE 'ext:%' BEGIN \
             INSERT INTO runtimeEvents (id, kind, workspaceId, dataJson, occurredAt) \
             SELECT {SQL_EVENT_ID}, 'inbox.question.status', q.workspace_id, json_object('inbox', q.from_handle, \
             'threadId', COALESCE(q.thread_id, q.id), 'questionId', q.id, 'status', 'answered'), {SQL_NOW} \
             FROM orchestrationMessages q WHERE q.id = NEW.reply_to_id AND q.from_handle = NEW.to_handle \
             AND q.to_handle = NEW.from_handle AND q.state <> 'obsolete' \
             AND NOT EXISTS (SELECT 1 FROM orchestrationMessages r WHERE r.reply_to_id = q.id \
             AND r.from_handle = q.to_handle AND r.id <> NEW.id); END;"
        ),
    ]
}

pub const RUNTIME_EVENT_RETENTION_DAYS: i64 = 7;
const MAX_PAGE: i64 = 500;

#[derive(Debug, Clone, PartialEq, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct RuntimeEvent {
    pub seq: i64,
    pub event_id: String,
    pub kind: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub workspace_id: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub project_id: Option<String>,
    pub data: Value,
    pub occurred_at: String,
}

#[derive(Debug, Clone, Default)]
pub struct RuntimeEventFilter {
    pub after: i64,
    pub kinds: Vec<String>,
    pub workspace_id: Option<String>,
    pub limit: i64,
}

/// A page of events and where the next read starts. `truncated` means the
/// cursor points before the oldest retained event, so some were pruned.
#[derive(Debug, Clone, PartialEq, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct RuntimeEventPage {
    pub events: Vec<RuntimeEvent>,
    pub cursor: i64,
    pub truncated: bool,
}

impl RuntimeStore {
    pub(super) async fn install_runtime_event_triggers(&self) -> Result<()> {
        // The statements are built only from constants above, never from input.
        for statement in trigger_statements() {
            sqlx::query(sqlx::AssertSqlSafe(statement))
                .execute(self.pool())
                .await?;
        }
        Ok(())
    }

    pub async fn append_runtime_event(
        &self,
        kind: &str,
        workspace_id: Option<&str>,
        project_id: Option<&str>,
        data: &Value,
    ) -> Result<i64> {
        let result = sqlx::query(
            "INSERT INTO runtimeEvents (id, kind, workspaceId, projectId, dataJson, occurredAt) \
             VALUES (?, ?, ?, ?, ?, ?)",
        )
        .bind(uuid::Uuid::new_v4().to_string())
        .bind(kind)
        .bind(workspace_id)
        .bind(project_id)
        .bind(serde_json::to_string(data)?)
        .bind(Utc::now().to_rfc3339())
        .execute(self.pool())
        .await?;
        Ok(result.last_insert_rowid())
    }

    pub async fn list_runtime_events(
        &self,
        filter: &RuntimeEventFilter,
    ) -> Result<RuntimeEventPage> {
        let limit = if filter.limit <= 0 {
            100
        } else {
            filter.limit.min(MAX_PAGE)
        };
        let rows = sqlx::query(
            "SELECT seq, id, kind, workspaceId, projectId, dataJson, occurredAt FROM runtimeEvents \
             WHERE seq > ? ORDER BY seq ASC LIMIT ?",
        )
        .bind(filter.after)
        // Filters run after the read so the cursor still advances past
        // events a reader does not want.
        .bind(MAX_PAGE)
        .fetch_all(self.pool())
        .await?;
        let mut cursor = filter.after;
        let mut events = Vec::new();
        for row in rows {
            let event = event_from_row(row)?;
            cursor = event.seq;
            let kind_matches = filter.kinds.is_empty() || filter.kinds.contains(&event.kind);
            let workspace_matches = filter
                .workspace_id
                .as_deref()
                .is_none_or(|workspace| event.workspace_id.as_deref() == Some(workspace));
            if kind_matches && workspace_matches {
                events.push(event);
                if events.len() as i64 >= limit {
                    break;
                }
            }
        }
        let oldest: Option<i64> = sqlx::query_scalar("SELECT MIN(seq) FROM runtimeEvents")
            .fetch_one(self.pool())
            .await?;
        let truncated = filter.after > 0 && oldest.is_some_and(|oldest| oldest > filter.after + 1);
        Ok(RuntimeEventPage {
            events,
            cursor,
            truncated,
        })
    }

    /// Events not yet sent to the cloud, oldest first.
    pub async fn list_unforwarded_runtime_events(&self, limit: i64) -> Result<Vec<RuntimeEvent>> {
        let rows = sqlx::query(
            "SELECT seq, id, kind, workspaceId, projectId, dataJson, occurredAt FROM runtimeEvents \
             WHERE forwardedAt IS NULL ORDER BY seq ASC LIMIT ?",
        )
        .bind(limit.clamp(1, MAX_PAGE))
        .fetch_all(self.pool())
        .await?;
        rows.into_iter().map(event_from_row).collect()
    }

    pub async fn mark_runtime_events_forwarded(&self, up_to_seq: i64) -> Result<()> {
        sqlx::query(
            "UPDATE runtimeEvents SET forwardedAt = ? WHERE forwardedAt IS NULL AND seq <= ?",
        )
        .bind(Utc::now().to_rfc3339())
        .bind(up_to_seq)
        .execute(self.pool())
        .await?;
        Ok(())
    }

    pub async fn prune_runtime_events(&self) -> Result<u64> {
        let cutoff = Utc::now() - Duration::days(RUNTIME_EVENT_RETENTION_DAYS);
        let result = sqlx::query("DELETE FROM runtimeEvents WHERE occurredAt < ?")
            .bind(cutoff.to_rfc3339())
            .execute(self.pool())
            .await?;
        Ok(result.rows_affected())
    }
}

fn event_from_row(row: sqlx::sqlite::SqliteRow) -> Result<RuntimeEvent> {
    let data: String = row.try_get("dataJson")?;
    Ok(RuntimeEvent {
        seq: row.try_get("seq")?,
        event_id: row.try_get("id")?,
        kind: row.try_get("kind")?,
        workspace_id: row.try_get("workspaceId")?,
        project_id: row.try_get("projectId")?,
        data: serde_json::from_str(&data)?,
        occurred_at: row.try_get("occurredAt")?,
    })
}

#[cfg(test)]
mod tests {
    use serde_json::json;

    use super::RuntimeEventFilter;
    use crate::runtime::RuntimeStore;

    #[tokio::test]
    async fn readers_page_by_cursor_and_filter_without_losing_their_place() {
        let directory = tempfile::tempdir().unwrap();
        let store = RuntimeStore::open(directory.path()).await.unwrap();
        let first = store
            .append_runtime_event(
                "inbox.reply",
                Some("w-1"),
                None,
                &json!({ "questionId": "q" }),
            )
            .await
            .unwrap();
        store
            .append_runtime_event(
                "agent.status",
                Some("w-2"),
                None,
                &json!({ "state": "done" }),
            )
            .await
            .unwrap();
        let third = store
            .append_runtime_event(
                "inbox.reply",
                Some("w-2"),
                None,
                &json!({ "questionId": "r" }),
            )
            .await
            .unwrap();
        let replies = store
            .list_runtime_events(&RuntimeEventFilter {
                kinds: vec!["inbox.reply".to_owned()],
                ..Default::default()
            })
            .await
            .unwrap();
        assert_eq!(replies.events.len(), 2);
        assert_eq!(replies.cursor, third);
        assert!(!replies.truncated);
        let after_first = store
            .list_runtime_events(&RuntimeEventFilter {
                after: first,
                workspace_id: Some("w-2".to_owned()),
                ..Default::default()
            })
            .await
            .unwrap();
        assert_eq!(after_first.events.len(), 2);
        assert!(after_first
            .events
            .iter()
            .all(|event| event.workspace_id.as_deref() == Some("w-2")));
        let nothing_new = store
            .list_runtime_events(&RuntimeEventFilter {
                after: third,
                ..Default::default()
            })
            .await
            .unwrap();
        assert!(nothing_new.events.is_empty());
        assert_eq!(nothing_new.cursor, third);
    }

    #[tokio::test]
    async fn task_and_external_question_transitions_are_journaled_by_triggers() {
        let directory = tempfile::tempdir().unwrap();
        let store = RuntimeStore::open(directory.path()).await.unwrap();
        sqlx::query(
            "INSERT INTO orchestrationTasks (id, spec, workspace_id, coordinator_handle, run_id) \
             VALUES ('t-1', 'spec', 'w-1', 'c-1', 'r-1')",
        )
        .execute(store.pool())
        .await
        .unwrap();
        sqlx::query("UPDATE orchestrationTasks SET status = 'ready' WHERE id = 't-1'")
            .execute(store.pool())
            .await
            .unwrap();
        sqlx::query("UPDATE orchestrationTasks SET status = 'ready' WHERE id = 't-1'")
            .execute(store.pool())
            .await
            .unwrap();
        sqlx::query(
            "INSERT INTO orchestrationMessages (id, from_handle, to_handle, subject) \
             VALUES ('q-1', 'ext:mcp', 'agent-1', 'Question')",
        )
        .execute(store.pool())
        .await
        .unwrap();
        sqlx::query(
            "UPDATE orchestrationMessages SET state = 'delivered', delivered_at = datetime('now') \
             WHERE id = 'q-1'",
        )
        .execute(store.pool())
        .await
        .unwrap();
        let page = store
            .list_runtime_events(&RuntimeEventFilter::default())
            .await
            .unwrap();
        let states = page
            .events
            .iter()
            .filter(|event| event.kind == "orchestration.task.state")
            .map(|event| event.data["state"].as_str().unwrap().to_owned())
            .collect::<Vec<_>>();
        assert_eq!(states, ["pending", "ready"]);
        let question = page
            .events
            .iter()
            .find(|event| event.kind == "inbox.question.status")
            .unwrap();
        assert_eq!(question.data["status"], "delivered");
        assert_eq!(question.data["questionId"], "q-1");
        assert_eq!(question.event_id.len(), 36);
    }

    #[tokio::test]
    async fn the_first_answer_and_later_updates_journal_answered() {
        let directory = tempfile::tempdir().unwrap();
        let store = RuntimeStore::open(directory.path()).await.unwrap();
        for statement in [
            "INSERT INTO orchestrationMessages (id, from_handle, to_handle, subject, workspace_id) \
             VALUES ('q-1', 'ext:mcp', 'agent-1', 'Question', 'w-1')",
            "INSERT INTO orchestrationMessages (id, from_handle, to_handle, subject, reply_to_id, thread_id, workspace_id) \
             VALUES ('a-1', 'agent-1', 'ext:mcp', 'Re: Question', 'q-1', 'q-1', 'w-1')",
            "INSERT INTO orchestrationMessages (id, from_handle, to_handle, subject, reply_to_id, thread_id) \
             VALUES ('a-2', 'agent-1', 'ext:mcp', 'Re: Question', 'q-1', 'q-1')",
            "UPDATE orchestrationMessages SET read = 1 WHERE id = 'q-1'",
        ] {
            sqlx::query(statement).execute(store.pool()).await.unwrap();
        }
        let page = store
            .list_runtime_events(&RuntimeEventFilter::default())
            .await
            .unwrap();
        let statuses = page
            .events
            .iter()
            .filter(|event| event.kind == "inbox.question.status")
            .map(|event| {
                assert_eq!(event.workspace_id.as_deref(), Some("w-1"));
                event.data["status"].as_str().unwrap().to_owned()
            })
            .collect::<Vec<_>>();
        assert_eq!(statuses, ["answered", "answered"]);
    }

    #[tokio::test]
    async fn forwarding_marks_events_up_to_a_sequence() {
        let directory = tempfile::tempdir().unwrap();
        let store = RuntimeStore::open(directory.path()).await.unwrap();
        let first = store
            .append_runtime_event("agent.status", None, None, &json!({}))
            .await
            .unwrap();
        store
            .append_runtime_event("agent.status", None, None, &json!({}))
            .await
            .unwrap();
        store.mark_runtime_events_forwarded(first).await.unwrap();
        let pending = store.list_unforwarded_runtime_events(10).await.unwrap();
        assert_eq!(pending.len(), 1);
        assert!(pending[0].seq > first);
        assert_eq!(store.prune_runtime_events().await.unwrap(), 0);
    }
}
