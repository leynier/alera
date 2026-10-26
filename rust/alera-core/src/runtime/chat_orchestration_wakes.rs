//! Durable parent wakes. Completions that land while a parent's cohort is
//! still open merge into it; sealing closes the cohort for delivery and the
//! next completion opens the following generation. Generations come from a
//! per-parent counter, so they never repeat even after cohorts are withdrawn.

use anyhow::Result;
use chrono::Utc;
use sqlx::{Row, SqliteConnection};

use super::chat_orchestration_delivery::*;
use super::chat_orchestration_models::*;
use super::chat_orchestration_rows::{conflict, require_id};
use super::{format_timestamp, parse_timestamp, RuntimeStore};

fn client_message_id(parent_chat_id: &str, generation: i64) -> String {
    format!("chat-orchestration-wake:{parent_chat_id}:{generation}")
}

pub(super) async fn wake_in(
    connection: &mut SqliteConnection,
    parent_chat_id: &str,
    generation: i64,
) -> Result<Option<ChatOrchestrationWake>> {
    let Some(row) = sqlx::query(
        "SELECT clientMessageId, status, createdAt, updatedAt, sealedAt, deliveredAt \
         FROM chatOrchestrationWakes WHERE parentChatId = ? AND generation = ?",
    )
    .bind(parent_chat_id)
    .bind(generation)
    .fetch_optional(&mut *connection)
    .await?
    else {
        return Ok(None);
    };
    let entry_rows = sqlx::query(
        "SELECT taskId, taskStatus, taskRevision FROM chatOrchestrationWakeEntries \
         WHERE parentChatId = ? AND generation = ? ORDER BY rowid",
    )
    .bind(parent_chat_id)
    .bind(generation)
    .fetch_all(&mut *connection)
    .await?;
    let mut entries = Vec::with_capacity(entry_rows.len());
    for entry in entry_rows {
        let status: String = entry.try_get("taskStatus")?;
        entries.push(ChatOrchestrationWakeEntry {
            task_id: entry.try_get("taskId")?,
            task_status: ChatOrchestrationTaskStatus::parse(&status)
                .ok_or_else(|| anyhow::anyhow!("unknown wake task status: {status}"))?,
            task_revision: entry.try_get("taskRevision")?,
        });
    }
    let status: String = row.try_get("status")?;
    let optional = |column: &str| -> Result<_> {
        Ok(row
            .try_get::<Option<String>, _>(column)?
            .map(|value| parse_timestamp(&value)))
    };
    Ok(Some(ChatOrchestrationWake {
        parent_chat_id: parent_chat_id.to_string(),
        generation,
        client_message_id: row.try_get("clientMessageId")?,
        status: ChatOrchestrationWakeStatus::parse(&status)
            .ok_or_else(|| anyhow::anyhow!("unknown wake status: {status}"))?,
        entries,
        created_at: parse_timestamp(row.try_get("createdAt")?),
        updated_at: parse_timestamp(row.try_get("updatedAt")?),
        sealed_at: optional("sealedAt")?,
        delivered_at: optional("deliveredAt")?,
    }))
}

async fn next_generation_in(
    connection: &mut SqliteConnection,
    parent_chat_id: &str,
) -> Result<i64> {
    let generation: i64 = sqlx::query_scalar(
        "INSERT INTO chatOrchestrationWakeCounters (parentChatId, generation) \
         VALUES (?, 1 + (SELECT COALESCE(MAX(generation), 0) FROM chatOrchestrationWakes \
             WHERE parentChatId = ?)) \
         ON CONFLICT(parentChatId) DO UPDATE SET generation = generation + 1 \
         RETURNING generation",
    )
    .bind(parent_chat_id)
    .bind(parent_chat_id)
    .fetch_one(&mut *connection)
    .await?;
    Ok(generation)
}

/// Records that `task`'s latest status change owes its parent a wake, merging
/// into the open cohort. Idempotent per `(taskId, revision)`.
pub(super) async fn enqueue_wake_in(
    connection: &mut SqliteConnection,
    task: &ChatOrchestrationTask,
) -> Result<Option<ChatOrchestrationWake>> {
    let Some(parent) = task.parent_chat_id.as_deref() else {
        return Ok(None);
    };
    if !task.notify.wakes_on(task.status)
        || task.result_delivery == ChatOrchestrationResultDelivery::Acknowledged
    {
        return Ok(None);
    }
    let existing: Option<i64> = sqlx::query_scalar(
        "SELECT generation FROM chatOrchestrationWakeEntries WHERE taskId = ? AND taskRevision = ?",
    )
    .bind(&task.task_id)
    .bind(task.revision)
    .fetch_optional(&mut *connection)
    .await?;
    if let Some(generation) = existing {
        return wake_in(connection, parent, generation).await;
    }
    let now = format_timestamp(Utc::now());
    let open: Option<i64> = sqlx::query_scalar(
        "SELECT generation FROM chatOrchestrationWakes WHERE parentChatId = ? \
         AND status = 'pending' ORDER BY generation DESC LIMIT 1",
    )
    .bind(parent)
    .fetch_optional(&mut *connection)
    .await?;
    let generation = match open {
        Some(generation) => {
            sqlx::query(
                "UPDATE chatOrchestrationWakes SET updatedAt = ? \
                 WHERE parentChatId = ? AND generation = ?",
            )
            .bind(&now)
            .bind(parent)
            .bind(generation)
            .execute(&mut *connection)
            .await?;
            generation
        }
        None => {
            let generation = next_generation_in(connection, parent).await?;
            sqlx::query(
                "INSERT INTO chatOrchestrationWakes \
                 (parentChatId, generation, clientMessageId, status, createdAt, updatedAt) \
                 VALUES (?, ?, ?, 'pending', ?, ?)",
            )
            .bind(parent)
            .bind(generation)
            .bind(client_message_id(parent, generation))
            .bind(&now)
            .bind(&now)
            .execute(&mut *connection)
            .await?;
            generation
        }
    };
    sqlx::query(
        "DELETE FROM chatOrchestrationWakeEntries WHERE parentChatId = ? \
         AND generation = ? AND taskId = ?",
    )
    .bind(parent)
    .bind(generation)
    .bind(&task.task_id)
    .execute(&mut *connection)
    .await?;
    sqlx::query(
        "INSERT INTO chatOrchestrationWakeEntries \
         (parentChatId, generation, taskId, taskStatus, taskRevision) VALUES (?, ?, ?, ?, ?)",
    )
    .bind(parent)
    .bind(generation)
    .bind(&task.task_id)
    .bind(task.status.as_str())
    .bind(task.revision)
    .execute(&mut *connection)
    .await?;
    wake_in(connection, parent, generation).await
}

/// Drops `task_id` from cohorts that are still open, and any cohort that
/// leaves empty. Sealed cohorts are already on their way and stay intact.
pub(super) async fn withdraw_pending_in(
    connection: &mut SqliteConnection,
    task_id: &str,
) -> Result<()> {
    sqlx::query(
        "DELETE FROM chatOrchestrationWakeEntries WHERE taskId = ? AND EXISTS ( \
             SELECT 1 FROM chatOrchestrationWakes w WHERE w.status = 'pending' \
             AND w.parentChatId = chatOrchestrationWakeEntries.parentChatId \
             AND w.generation = chatOrchestrationWakeEntries.generation)",
    )
    .bind(task_id)
    .execute(&mut *connection)
    .await?;
    sqlx::query(
        "DELETE FROM chatOrchestrationWakes WHERE status = 'pending' AND NOT EXISTS ( \
             SELECT 1 FROM chatOrchestrationWakeEntries e \
             WHERE e.parentChatId = chatOrchestrationWakes.parentChatId \
             AND e.generation = chatOrchestrationWakes.generation)",
    )
    .execute(&mut *connection)
    .await?;
    Ok(())
}

impl RuntimeStore {
    pub async fn chat_orchestration_wake(
        &self,
        parent_chat_id: &str,
        generation: i64,
    ) -> Result<Option<ChatOrchestrationWake>> {
        let mut connection = self.pool().acquire().await?;
        wake_in(&mut connection, parent_chat_id, generation).await
    }

    /// Pending and sealed cohorts, oldest generation first per parent; with
    /// `parent_chat_id` only that parent's.
    pub async fn list_chat_orchestration_wakes_awaiting_delivery(
        &self,
        parent_chat_id: Option<&str>,
    ) -> Result<Vec<ChatOrchestrationWake>> {
        let mut connection = self.pool().acquire().await?;
        let keys: Vec<(String, i64)> = sqlx::query_as(
            "SELECT parentChatId, generation FROM chatOrchestrationWakes \
             WHERE status IN ('pending', 'sealed') AND (? IS NULL OR parentChatId = ?) \
             ORDER BY parentChatId, generation",
        )
        .bind(parent_chat_id)
        .bind(parent_chat_id)
        .fetch_all(&mut *connection)
        .await?;
        let mut wakes = Vec::with_capacity(keys.len());
        for (parent, generation) in keys {
            if let Some(wake) = wake_in(&mut connection, &parent, generation).await? {
                wakes.push(wake);
            }
        }
        Ok(wakes)
    }

    /// Returns the cohort to deliver to an idle parent next. A sealed cohort
    /// left by an earlier attempt comes back first (its stable client message
    /// id makes the resend idempotent); otherwise the open cohort is sealed so
    /// later completions start a new generation. `None` when nothing waits.
    pub async fn seal_chat_orchestration_wake(
        &self,
        parent_chat_id: &str,
    ) -> Result<Option<ChatOrchestrationWake>> {
        require_id("parentChatId", parent_chat_id)?;
        let mut tx = self.pool().begin_with("BEGIN IMMEDIATE").await?;
        if super::agent_chat_native_operations::active_operation_in(&mut tx, parent_chat_id)
            .await?
            .is_some()
        {
            tx.commit().await?;
            return Ok(None);
        }
        let now = format_timestamp(Utc::now());
        sqlx::query(
            "UPDATE chatOrchestrationWakes SET status = 'sealed', sealedAt = ?, updatedAt = ? \
             WHERE parentChatId = ? AND status = 'pending' AND NOT EXISTS ( \
                 SELECT 1 FROM chatOrchestrationWakes s \
                 WHERE s.parentChatId = ? AND s.status = 'sealed')",
        )
        .bind(&now)
        .bind(&now)
        .bind(parent_chat_id)
        .bind(parent_chat_id)
        .execute(&mut *tx)
        .await?;
        let generation: Option<i64> = sqlx::query_scalar(
            "SELECT generation FROM chatOrchestrationWakes WHERE parentChatId = ? \
             AND status = 'sealed' ORDER BY generation LIMIT 1",
        )
        .bind(parent_chat_id)
        .fetch_optional(&mut *tx)
        .await?;
        let wake = match generation {
            Some(generation) => wake_in(&mut tx, parent_chat_id, generation).await?,
            None => None,
        };
        tx.commit().await?;
        Ok(wake)
    }

    /// Records that the parent chat accepted the sealed cohort's message and
    /// marks its settled tasks `notified`. Repeating it is harmless; acking a
    /// cohort that was never sealed is a conflict.
    pub async fn ack_chat_orchestration_wake(
        &self,
        parent_chat_id: &str,
        generation: i64,
    ) -> Result<ChatOrchestrationWake> {
        require_id("parentChatId", parent_chat_id)?;
        let mut tx = self.pool().begin().await?;
        let now = format_timestamp(Utc::now());
        let delivered = sqlx::query(
            "UPDATE chatOrchestrationWakes SET status = 'delivered', deliveredAt = ?, \
             updatedAt = ? WHERE parentChatId = ? AND generation = ? AND status = 'sealed'",
        )
        .bind(&now)
        .bind(&now)
        .bind(parent_chat_id)
        .bind(generation)
        .execute(&mut *tx)
        .await?
        .rows_affected();
        let wake = wake_in(&mut tx, parent_chat_id, generation)
            .await?
            .ok_or_else(|| {
                ChatOrchestrationStoreError::NotFound(client_message_id(parent_chat_id, generation))
            })?;
        if wake.status == ChatOrchestrationWakeStatus::Pending {
            return Err(conflict(format!(
                "wake {} has not been sealed",
                wake.client_message_id
            )));
        }
        if delivered > 0 {
            sqlx::query(
                "UPDATE chatOrchestrationTasks SET resultDelivery = 'notified', updatedAt = ? \
                 WHERE resultDelivery = 'pending' \
                 AND status IN ('completed', 'failed', 'interrupted', 'cancelled') \
                 AND EXISTS (SELECT 1 FROM chatOrchestrationWakeEntries e \
                     WHERE e.parentChatId = ? AND e.generation = ? \
                     AND e.taskId = chatOrchestrationTasks.taskId \
                     AND e.taskRevision = chatOrchestrationTasks.revision \
                     AND e.taskStatus = chatOrchestrationTasks.status)",
            )
            .bind(&now)
            .bind(parent_chat_id)
            .bind(generation)
            .execute(&mut *tx)
            .await?;
        }
        tx.commit().await?;
        Ok(wake)
    }
}
