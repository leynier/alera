use super::chat_orchestration_models::*;
use super::chat_orchestration_rows::{conflict, require_id, require_optional_id, require_task_in};
use super::chat_orchestration_wakes::{enqueue_wake_in, withdraw_pending_in};
use super::{format_timestamp, RuntimeStore};
use anyhow::Result;
use chrono::Utc;

impl RuntimeStore {
    /// Links the turn that actually started for a queued task without a
    /// Running-to-Running status transition or a new notification revision.
    pub async fn record_chat_orchestration_task_turn(
        &self,
        task_id: &str,
        chat_id: &str,
        turn_id: &str,
    ) -> Result<ChatOrchestrationTask> {
        require_id("taskId", task_id)?;
        require_id("chatId", chat_id)?;
        require_id("turnId", turn_id)?;
        let mut tx = self.pool().begin().await?;
        sqlx::query(
            "UPDATE chatOrchestrationTasks SET childTurnId = ?, updatedAt = ? \
             WHERE taskId = ? AND childChatId = ? AND childTurnId IS NULL",
        )
        .bind(turn_id)
        .bind(format_timestamp(Utc::now()))
        .bind(task_id)
        .bind(chat_id)
        .execute(&mut *tx)
        .await?;
        let task = require_task_in(&mut tx, task_id).await?;
        if task.child_chat_id.as_deref() != Some(chat_id)
            || task.child_turn_id.as_deref() != Some(turn_id)
        {
            return Err(conflict(
                "The owned task is already linked to a different chat or turn.",
            ));
        }
        tx.commit().await?;
        Ok(task)
    }

    /// Restores policy and acknowledges a settled result in one transaction,
    /// so completion at a wait deadline cannot create a duplicate wake.
    pub async fn finish_chat_orchestration_wait(
        &self,
        task_id: &str,
        notify: ChatOrchestrationNotify,
    ) -> Result<ChatOrchestrationTask> {
        require_id("taskId", task_id)?;
        let mut tx = self.pool().begin().await?;
        sqlx::query(
            "UPDATE chatOrchestrationTasks SET notify = ?, updatedAt = ?, \
             launchOptionsJson = json_remove(launchOptionsJson, '$.waitNotify'), \
             resultDelivery = CASE WHEN status IN ('completed', 'failed', 'interrupted', 'cancelled') \
                 THEN 'acknowledged' ELSE resultDelivery END WHERE taskId = ?",
        ).bind(notify.as_str()).bind(format_timestamp(Utc::now())).bind(task_id)
            .execute(&mut *tx).await?;
        let task = require_task_in(&mut tx, task_id).await?;
        if task.status.is_terminal() {
            withdraw_pending_in(&mut tx, task_id).await?;
        }
        tx.commit().await?;
        Ok(task)
    }

    /// Changes notification policy without changing the task's status revision.
    /// A timed-out wait also offers a status that settled during the wait.
    pub async fn set_chat_orchestration_notify(
        &self,
        task_id: &str,
        notify: ChatOrchestrationNotify,
    ) -> Result<ChatOrchestrationTask> {
        require_id("taskId", task_id)?;
        let mut tx = self.pool().begin().await?;
        sqlx::query(
            "UPDATE chatOrchestrationTasks SET notify = ?, updatedAt = ?, \
            launchOptionsJson = json_remove(launchOptionsJson, '$.waitNotify') WHERE taskId = ?",
        )
        .bind(notify.as_str())
        .bind(format_timestamp(Utc::now()))
        .bind(task_id)
        .execute(&mut *tx)
        .await?;
        let task = require_task_in(&mut tx, task_id).await?;
        enqueue_wake_in(&mut tx, &task).await?;
        tx.commit().await?;
        Ok(task)
    }

    /// Records externally prepared resources even if cancellation settled the
    /// task meanwhile. This does not change status or the status revision.
    pub async fn record_chat_orchestration_preparation(
        &self,
        task_id: &str,
        child_chat_id: Option<&str>,
        project_id: Option<&str>,
        workspace_id: Option<&str>,
        host_id: Option<&str>,
    ) -> Result<ChatOrchestrationTask> {
        require_id("taskId", task_id)?;
        for (label, value) in [
            ("childChatId", child_chat_id),
            ("projectId", project_id),
            ("workspaceId", workspace_id),
            ("hostId", host_id),
        ] {
            require_optional_id(label, value)?;
        }
        let mut tx = self.pool().begin().await?;
        sqlx::query(
            "UPDATE chatOrchestrationTasks SET childChatId = COALESCE(childChatId, ?), \
             projectId = COALESCE(projectId, ?), workspaceId = COALESCE(workspaceId, ?), \
             hostId = COALESCE(hostId, ?), updatedAt = ? WHERE taskId = ? \
             AND (? IS NULL OR childChatId IS NULL OR childChatId = ?) \
             AND (? IS NULL OR projectId IS NULL OR projectId = ?) \
             AND (? IS NULL OR workspaceId IS NULL OR workspaceId = ?) \
             AND (? IS NULL OR hostId IS NULL OR hostId = ?)",
        )
        .bind(child_chat_id)
        .bind(project_id)
        .bind(workspace_id)
        .bind(host_id)
        .bind(format_timestamp(Utc::now()))
        .bind(task_id)
        .bind(child_chat_id)
        .bind(child_chat_id)
        .bind(project_id)
        .bind(project_id)
        .bind(workspace_id)
        .bind(workspace_id)
        .bind(host_id)
        .bind(host_id)
        .execute(&mut *tx)
        .await?;
        let task = require_task_in(&mut tx, task_id).await?;
        for (stored, requested) in [
            (task.child_chat_id.as_deref(), child_chat_id),
            (task.project_id.as_deref(), project_id),
            (task.workspace_id.as_deref(), workspace_id),
            (task.host_id.as_deref(), host_id),
        ] {
            if requested.is_some() && stored != requested {
                return Err(conflict(
                    "A different preparation resource is already recorded.",
                ));
            }
        }
        tx.commit().await?;
        Ok(task)
    }
}
