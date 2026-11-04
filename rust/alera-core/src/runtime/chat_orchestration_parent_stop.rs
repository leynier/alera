//! Stopping a parent chat stops the delegated work under it. Its unsettled
//! delegated tasks and their descendants no longer wake anyone, and its open
//! and sealed wake cohorts are dropped, so neither the stopped children nor
//! results gathered before the stop start the chat again.

use anyhow::Result;
use chrono::Utc;

use super::chat_orchestration_rows::require_id;
use super::chat_orchestration_wakes::wake_in;
use super::{format_timestamp, RuntimeStore};

#[cfg(test)]
#[path = "chat_orchestration_parent_stop_tests.rs"]
mod tests;

/// The launch option that keeps a task from waking its parent.
pub(super) const PARENT_STOPPED_KEY: &str = "parentStopped";

/// What a parent stop leaves for the host to do.
#[derive(Debug, Clone, Default, PartialEq, Eq)]
pub struct ChatOrchestrationParentStop {
    /// The unsettled delegated tasks the chat owns directly, oldest first.
    /// Cancelling each also cancels its descendants.
    pub task_ids: Vec<String>,
    /// The client message ids of dropped sealed cohorts, whose wake message
    /// may already wait in the chat's queue.
    pub sealed_wake_message_ids: Vec<String>,
}

impl RuntimeStore {
    pub async fn stop_chat_orchestration_parent(
        &self,
        parent_chat_id: &str,
    ) -> Result<ChatOrchestrationParentStop> {
        require_id("parentChatId", parent_chat_id)?;
        let mut tx = self.pool().begin_with("BEGIN IMMEDIATE").await?;
        let now = format_timestamp(Utc::now());
        let task_ids: Vec<String> = sqlx::query_scalar(
            "SELECT taskId FROM chatOrchestrationTasks WHERE parentChatId = ? \
             AND kind IN ('delegate', 'followup') \
             AND status IN ('preparing', 'running', 'needs_input', 'cancel_requested') \
             ORDER BY sequence",
        )
        .bind(parent_chat_id)
        .fetch_all(&mut *tx)
        .await?;
        // `$.parentStopped` is PARENT_STOPPED_KEY.
        sqlx::query(
            "WITH RECURSIVE lineage(taskId) AS ( \
                 SELECT taskId FROM chatOrchestrationTasks WHERE parentChatId = ? \
                 AND kind IN ('delegate', 'followup') \
                 UNION SELECT t.taskId FROM chatOrchestrationTasks t \
                 JOIN lineage l ON t.parentTaskId = l.taskId) \
             UPDATE chatOrchestrationTasks SET updatedAt = ?, launchOptionsJson = \
                 json_set(COALESCE(launchOptionsJson, '{}'), '$.parentStopped', json('true')) \
             WHERE taskId IN (SELECT taskId FROM lineage) \
             AND status IN ('preparing', 'running', 'needs_input', 'cancel_requested')",
        )
        .bind(parent_chat_id)
        .bind(&now)
        .execute(&mut *tx)
        .await?;
        let generations: Vec<i64> = sqlx::query_scalar(
            "SELECT generation FROM chatOrchestrationWakes WHERE parentChatId = ? \
             AND status = 'sealed' ORDER BY generation",
        )
        .bind(parent_chat_id)
        .fetch_all(&mut *tx)
        .await?;
        let mut sealed_wake_message_ids = Vec::with_capacity(generations.len());
        for generation in generations {
            if let Some(wake) = wake_in(&mut tx, parent_chat_id, generation).await? {
                sealed_wake_message_ids.push(wake.client_message_id);
            }
        }
        sqlx::query(
            "DELETE FROM chatOrchestrationWakeEntries WHERE parentChatId = ? AND generation IN ( \
                 SELECT generation FROM chatOrchestrationWakes WHERE parentChatId = ? \
                 AND status IN ('pending', 'sealed'))",
        )
        .bind(parent_chat_id)
        .bind(parent_chat_id)
        .execute(&mut *tx)
        .await?;
        sqlx::query(
            "DELETE FROM chatOrchestrationWakes WHERE parentChatId = ? \
             AND status IN ('pending', 'sealed')",
        )
        .bind(parent_chat_id)
        .execute(&mut *tx)
        .await?;
        tx.commit().await?;
        Ok(ChatOrchestrationParentStop {
            task_ids,
            sealed_wake_message_ids,
        })
    }
}
