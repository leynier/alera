use anyhow::Result;
use sqlx::sqlite::SqliteRow;
use sqlx::Row;
use uuid::Uuid;

use super::run_event_store::{record_run_event, NewRunEvent, RunActorKind, RunEventKind};
use super::{
    MessageDelivery, OrchestrationMessage, OrchestrationMessagePriority, OrchestrationMessageType,
    RuntimeStore,
};

pub const ORCHESTRATION_HANDLE_MAX_BYTES: usize = 512;
pub const ORCHESTRATION_SUBJECT_MAX_BYTES: usize = 256;
pub const ORCHESTRATION_BODY_MAX_BYTES: usize = 64 * 1024;
pub const ORCHESTRATION_THREAD_ID_MAX_BYTES: usize = 512;
pub const ORCHESTRATION_PAYLOAD_MAX_BYTES: usize = 64 * 1024;

#[derive(Default)]
pub struct NewOrchestrationMessage {
    pub from_handle: String,
    pub to_handle: String,
    pub subject: String,
    pub body: String,
    pub message_type: OrchestrationMessageType,
    pub priority: OrchestrationMessagePriority,
    pub thread_id: Option<String>,
    pub payload: Option<String>,
    pub run_id: Option<String>,
    pub workspace_id: Option<String>,
    pub task_id: Option<String>,
    pub dispatch_id: Option<String>,
    pub expires_at: Option<String>,
    pub reply_to_id: Option<String>,
    /// JSON text; only inbox questions carry it.
    pub external_meta: Option<String>,
    pub delivery: MessageDelivery,
}

fn validate_message_field(value: &str, field: &str, max_bytes: usize) -> Result<()> {
    if value.len() > max_bytes {
        anyhow::bail!("message_too_large: {field} exceeds {max_bytes} UTF-8 bytes");
    }
    Ok(())
}

fn validate_new_orchestration_message(message: &NewOrchestrationMessage) -> Result<()> {
    validate_message_field(
        &message.from_handle,
        "from handle",
        ORCHESTRATION_HANDLE_MAX_BYTES,
    )?;
    validate_message_field(
        &message.to_handle,
        "to handle",
        ORCHESTRATION_HANDLE_MAX_BYTES,
    )?;
    validate_message_field(&message.subject, "subject", ORCHESTRATION_SUBJECT_MAX_BYTES)?;
    validate_message_field(&message.body, "body", ORCHESTRATION_BODY_MAX_BYTES)?;
    if let Some(thread_id) = message.thread_id.as_deref() {
        validate_message_field(thread_id, "thread id", ORCHESTRATION_THREAD_ID_MAX_BYTES)?;
    }
    if let Some(payload) = message.payload.as_deref() {
        validate_message_field(payload, "payload", ORCHESTRATION_PAYLOAD_MAX_BYTES)?;
    }
    if let Some(reply_to_id) = message.reply_to_id.as_deref() {
        validate_message_field(reply_to_id, "reply id", ORCHESTRATION_THREAD_ID_MAX_BYTES)?;
    }
    Ok(())
}

pub(super) fn orchestration_id(prefix: &str) -> String {
    let hex = Uuid::new_v4().simple().to_string();
    format!("{prefix}_{}", &hex[..16])
}

pub(super) const MESSAGE_COLUMNS: &str = "id, from_handle, to_handle, subject, body, type, \
     priority, thread_id, payload, read, sequence, created_at, delivered_at, run_id, \
     workspace_id, task_id, dispatch_id, state, expires_at, obsolete_at, reply_to_id, \
     external_meta, delivery";

pub(super) fn message_from_row(row: SqliteRow) -> Result<OrchestrationMessage> {
    let type_raw: String = row.try_get("type")?;
    let priority_raw: String = row.try_get("priority")?;
    Ok(OrchestrationMessage {
        id: row.try_get("id")?,
        from_handle: row.try_get("from_handle")?,
        to_handle: row.try_get("to_handle")?,
        subject: row.try_get("subject")?,
        body: row.try_get("body")?,
        message_type: OrchestrationMessageType::parse(&type_raw)
            .unwrap_or(OrchestrationMessageType::Status),
        priority: OrchestrationMessagePriority::parse(&priority_raw).unwrap_or_default(),
        thread_id: row.try_get("thread_id")?,
        payload: row.try_get("payload")?,
        read: row.try_get::<i64, _>("read")? != 0,
        sequence: row.try_get("sequence")?,
        created_at: row.try_get("created_at")?,
        delivered_at: row.try_get("delivered_at")?,
        run_id: row.try_get("run_id")?,
        workspace_id: row.try_get("workspace_id")?,
        task_id: row.try_get("task_id")?,
        dispatch_id: row.try_get("dispatch_id")?,
        state: row.try_get("state")?,
        expires_at: row.try_get("expires_at")?,
        obsolete_at: row.try_get("obsolete_at")?,
        reply_to_id: row.try_get("reply_to_id")?,
        external_meta: row
            .try_get::<Option<String>, _>("external_meta")?
            .and_then(|raw| serde_json::from_str(&raw).ok()),
        delivery: MessageDelivery::parse(&row.try_get::<String, _>("delivery")?)
            .unwrap_or_default(),
    })
}

fn id_placeholders(count: usize) -> String {
    let mut placeholders = "?,".repeat(count);
    placeholders.pop();
    placeholders
}

impl RuntimeStore {
    /// An inbox question only expires before it reaches the agent; once pasted
    /// it keeps waiting for its reply.
    pub(super) async fn expire_orchestration_messages(&self) -> Result<()> {
        sqlx::query(
            "UPDATE orchestrationMessages SET state = 'expired' \
             WHERE expires_at IS NOT NULL AND expires_at <= datetime('now') \
             AND (state = 'queued' OR (state = 'delivered' AND substr(from_handle, 1, 4) != 'ext:'))",
        )
        .execute(self.pool())
        .await?;
        Ok(())
    }

    pub async fn insert_orchestration_message(
        &self,
        message: NewOrchestrationMessage,
    ) -> Result<OrchestrationMessage> {
        validate_new_orchestration_message(&message)?;
        let id = orchestration_id("msg");
        let mut tx = self.pool().begin().await?;
        sqlx::query(
            "INSERT INTO orchestrationMessages \
             (id, from_handle, to_handle, subject, body, type, priority, thread_id, payload, \
              run_id, workspace_id, task_id, dispatch_id, expires_at, reply_to_id, external_meta, \
              delivery) \
             VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)",
        )
        .bind(&id)
        .bind(&message.from_handle)
        .bind(&message.to_handle)
        .bind(&message.subject)
        .bind(&message.body)
        .bind(message.message_type.as_str())
        .bind(message.priority.as_str())
        .bind(&message.thread_id)
        .bind(&message.payload)
        .bind(&message.run_id)
        .bind(&message.workspace_id)
        .bind(&message.task_id)
        .bind(&message.dispatch_id)
        .bind(&message.expires_at)
        .bind(&message.reply_to_id)
        .bind(&message.external_meta)
        .bind(message.delivery.as_str())
        .execute(&mut *tx)
        .await?;
        if let (OrchestrationMessageType::Escalation, Some(run_id)) =
            (message.message_type, message.run_id.as_deref())
        {
            // The timeline shows the escalation once, as this event; it joins
            // the message for the route and body.
            let mut event = NewRunEvent::new(run_id, RunEventKind::Escalation);
            event.task_id = message.task_id.as_deref();
            event.dispatch_id = message.dispatch_id.as_deref();
            event.actor_kind = Some(RunActorKind::Agent);
            event.actor_id = Some(&message.from_handle);
            event.summary = &message.subject;
            event.payload = Some(serde_json::json!({ "messageId": id }));
            record_run_event(&mut tx, &event).await?;
        }
        tx.commit().await?;
        self.orchestration_message_by_id(&id)
            .await?
            .ok_or_else(|| anyhow::anyhow!("inserted orchestration message not found"))
    }

    pub async fn orchestration_message_by_id(
        &self,
        id: &str,
    ) -> Result<Option<OrchestrationMessage>> {
        let row = sqlx::query(sqlx::AssertSqlSafe(format!(
            "SELECT {MESSAGE_COLUMNS} FROM orchestrationMessages WHERE id = ?"
        )))
        .bind(id)
        .fetch_optional(self.pool())
        .await?;
        row.map(message_from_row).transpose()
    }

    pub async fn unread_orchestration_messages(
        &self,
        to_handle: &str,
        types: Option<&[OrchestrationMessageType]>,
    ) -> Result<Vec<OrchestrationMessage>> {
        self.expire_orchestration_messages().await?;
        let mut sql = format!(
            "SELECT {MESSAGE_COLUMNS} FROM orchestrationMessages \
             WHERE to_handle = ? AND read = 0 AND state NOT IN ('expired','obsolete')"
        );
        if let Some(types) = types {
            if !types.is_empty() {
                sql.push_str(&format!(" AND type IN ({})", id_placeholders(types.len())));
            }
        }
        sql.push_str(" ORDER BY sequence ASC");
        let mut query = sqlx::query(sqlx::AssertSqlSafe(sql)).bind(to_handle);
        if let Some(types) = types {
            for message_type in types {
                query = query.bind(message_type.as_str());
            }
        }
        let rows = query.fetch_all(self.pool()).await?;
        rows.into_iter().map(message_from_row).collect()
    }

    pub async fn unread_orchestration_coordinator_messages(
        &self,
        to_handle: &str,
    ) -> Result<Vec<OrchestrationMessage>> {
        self.expire_orchestration_messages().await?;
        let rows = sqlx::query(sqlx::AssertSqlSafe(format!(
            "SELECT {MESSAGE_COLUMNS} FROM orchestrationMessages \
             WHERE to_handle = ? AND read = 0 AND state NOT IN ('expired','obsolete') AND ( \
               type = 'escalation' \
               OR ( \
                 type = 'decision_gate' \
                 AND CASE \
                   WHEN payload IS NOT NULL AND json_valid(payload) \
                   THEN COALESCE(json_extract(payload, '$.taskId'), '') != '' \
                   ELSE 0 \
                 END \
               ) \
             ) \
             ORDER BY sequence ASC"
        )))
        .bind(to_handle)
        .fetch_all(self.pool())
        .await?;
        rows.into_iter().map(message_from_row).collect()
    }

    pub async fn undelivered_unread_orchestration_messages(
        &self,
        to_handle: &str,
    ) -> Result<Vec<OrchestrationMessage>> {
        self.undelivered_messages(to_handle, false).await
    }

    /// Queued messages sent with `delivery = now`: the ones that may be pasted
    /// while the recipient is still working.
    pub async fn undelivered_now_orchestration_messages(
        &self,
        to_handle: &str,
    ) -> Result<Vec<OrchestrationMessage>> {
        self.undelivered_messages(to_handle, true).await
    }

    async fn undelivered_messages(
        &self,
        to_handle: &str,
        now_only: bool,
    ) -> Result<Vec<OrchestrationMessage>> {
        self.expire_orchestration_messages().await?;
        let rows = sqlx::query(sqlx::AssertSqlSafe(format!(
            "SELECT {MESSAGE_COLUMNS} FROM orchestrationMessages \
             WHERE to_handle = ? AND read = 0 AND delivered_at IS NULL AND state = 'queued' \
             AND (? = 0 OR delivery = 'now') \
             ORDER BY sequence ASC"
        )))
        .bind(to_handle)
        .bind(now_only)
        .fetch_all(self.pool())
        .await?;
        rows.into_iter().map(message_from_row).collect()
    }

    pub async fn all_orchestration_messages_for_handle(
        &self,
        to_handle: &str,
        types: Option<&[OrchestrationMessageType]>,
        limit: i64,
    ) -> Result<Vec<OrchestrationMessage>> {
        self.expire_orchestration_messages().await?;
        let mut sql = format!(
            "SELECT {MESSAGE_COLUMNS} FROM orchestrationMessages \
             WHERE to_handle = ?"
        );
        if let Some(types) = types {
            if !types.is_empty() {
                sql.push_str(&format!(" AND type IN ({})", id_placeholders(types.len())));
            }
        }
        sql.push_str(" ORDER BY sequence DESC LIMIT ?");
        let mut query = sqlx::query(sqlx::AssertSqlSafe(sql)).bind(to_handle);
        if let Some(types) = types {
            for message_type in types {
                query = query.bind(message_type.as_str());
            }
        }
        let rows = query.bind(limit).fetch_all(self.pool()).await?;
        rows.into_iter().map(message_from_row).collect()
    }

    pub async fn all_orchestration_messages_from_handle(
        &self,
        from_handle: &str,
        limit: i64,
    ) -> Result<Vec<OrchestrationMessage>> {
        self.expire_orchestration_messages().await?;
        let rows = sqlx::query(sqlx::AssertSqlSafe(format!(
            "SELECT {MESSAGE_COLUMNS} FROM orchestrationMessages \
             WHERE from_handle = ? ORDER BY sequence DESC LIMIT ?"
        )))
        .bind(from_handle)
        .bind(limit)
        .fetch_all(self.pool())
        .await?;
        rows.into_iter().map(message_from_row).collect()
    }

    pub async fn recent_orchestration_messages(
        &self,
        limit: i64,
    ) -> Result<Vec<OrchestrationMessage>> {
        self.expire_orchestration_messages().await?;
        let rows = sqlx::query(sqlx::AssertSqlSafe(format!(
            "SELECT {MESSAGE_COLUMNS} FROM orchestrationMessages \
             ORDER BY sequence DESC LIMIT ?"
        )))
        .bind(limit)
        .fetch_all(self.pool())
        .await?;
        rows.into_iter().map(message_from_row).collect()
    }

    pub async fn mark_orchestration_messages_read(&self, ids: &[String]) -> Result<()> {
        if ids.is_empty() {
            return Ok(());
        }
        let sql = format!(
            "UPDATE orchestrationMessages SET read = 1, state = CASE WHEN state = 'obsolete' THEN state ELSE 'read' END WHERE id IN ({})",
            id_placeholders(ids.len())
        );
        let mut query = sqlx::query(sqlx::AssertSqlSafe(sql));
        for id in ids {
            query = query.bind(id);
        }
        query.execute(self.pool()).await?;
        Ok(())
    }

    pub async fn mark_orchestration_messages_delivered(&self, ids: &[String]) -> Result<()> {
        if ids.is_empty() {
            return Ok(());
        }
        let sql = format!(
            "UPDATE orchestrationMessages SET delivered_at = datetime('now'), \
             state = CASE WHEN state = 'queued' OR (state = 'expired' AND substr(from_handle, 1, 4) = 'ext:') \
               THEN 'delivered' ELSE state END WHERE id IN ({})",
            id_placeholders(ids.len())
        );
        let mut query = sqlx::query(sqlx::AssertSqlSafe(sql));
        for id in ids {
            query = query.bind(id);
        }
        query.execute(self.pool()).await?;
        Ok(())
    }

    /// Replies addressed to `to_handle` in a thread, strictly after `after_sequence`.
    /// Powers the blocking `ask` loop.
    pub async fn orchestration_thread_messages_for(
        &self,
        thread_id: &str,
        to_handle: &str,
        after_sequence: i64,
    ) -> Result<Vec<OrchestrationMessage>> {
        let rows = sqlx::query(sqlx::AssertSqlSafe(format!(
            "SELECT {MESSAGE_COLUMNS} FROM orchestrationMessages \
             WHERE thread_id = ? AND to_handle = ? AND sequence > ? \
             ORDER BY sequence ASC"
        )))
        .bind(thread_id)
        .bind(to_handle)
        .bind(after_sequence)
        .fetch_all(self.pool())
        .await?;
        rows.into_iter().map(message_from_row).collect()
    }

    pub async fn reset_orchestration_messages(&self) -> Result<()> {
        sqlx::query("DELETE FROM orchestrationMessages")
            .execute(self.pool())
            .await?;
        Ok(())
    }
}
