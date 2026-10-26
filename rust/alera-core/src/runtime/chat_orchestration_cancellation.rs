use anyhow::Result;
use chrono::Utc;

use super::chat_orchestration_models::*;
use super::chat_orchestration_rows::{invalid, require_id, require_task_in};
use super::{format_timestamp, RuntimeStore};

impl RuntimeStore {
    pub async fn request_chat_orchestration_cancel(
        &self,
        task_id: &str,
    ) -> Result<ChatOrchestrationCancelOutcome> {
        self.request_chat_orchestration_cancel_with_authority(task_id, "runtime", None)
            .await
    }

    /// Stores cancellation authority with the recursive request so a restart
    /// cannot turn a bounded agent request into unbounded runtime cleanup.
    pub async fn request_chat_orchestration_cancel_with_authority(
        &self,
        task_id: &str,
        caller_scope: &str,
        runtime_mode_ceiling: Option<&str>,
    ) -> Result<ChatOrchestrationCancelOutcome> {
        require_id("taskId", task_id)?;
        require_id("callerScope", caller_scope)?;
        if runtime_mode_ceiling.is_some_and(|mode| {
            !matches!(
                mode,
                "approval-required" | "auto-accept-edits" | "auto" | "full-access"
            )
        }) {
            return Err(invalid("unknown cancellation runtime mode ceiling"));
        }
        let mut tx = self.pool().begin().await?;
        let now = format_timestamp(Utc::now());
        let policy = if runtime_mode_ceiling.is_some() {
            "bound"
        } else {
            "human"
        };
        let ids: Vec<String> = sqlx::query_scalar(
            "WITH RECURSIVE lineage(taskId) AS ( \
                 SELECT taskId FROM chatOrchestrationTasks WHERE taskId = ? \
                 UNION SELECT t.taskId FROM chatOrchestrationTasks t \
                 JOIN lineage l ON t.parentTaskId = l.taskId) \
             UPDATE chatOrchestrationTasks SET \
             revision = revision + CASE WHEN status = 'cancel_requested' THEN 0 ELSE 1 END, \
             launchOptionsJson = CASE WHEN status = 'cancel_requested' \
                 AND json_extract(launchOptionsJson, '$.cancellationPolicy') = 'human' \
                 THEN launchOptionsJson ELSE json_set(COALESCE(launchOptionsJson, '{}'), \
                     '$.cancellationRuntimeModeCeiling', ?, '$.cancellationCallerScope', ?, \
                     '$.cancellationPolicy', ?) END, \
             status = 'cancel_requested', cancelRequestedAt = COALESCE(cancelRequestedAt, ?), updatedAt = ? \
             WHERE taskId IN (SELECT taskId FROM lineage) \
             AND status IN ('preparing', 'running', 'needs_input', 'cancel_requested') RETURNING taskId",
        )
        .bind(task_id)
        .bind(runtime_mode_ceiling)
        .bind(caller_scope)
        .bind(policy)
        .bind(&now)
        .bind(&now)
        .fetch_all(&mut *tx)
        .await?;
        let task = require_task_in(&mut tx, task_id).await?;
        let mut descendants = Vec::with_capacity(ids.len());
        for id in ids.iter().filter(|id| id.as_str() != task_id) {
            descendants.push(require_task_in(&mut tx, id).await?);
        }
        descendants.sort_by_key(|task| (task.depth, task.sequence));
        let mut requested = Vec::with_capacity(ids.len());
        if ids.iter().any(|id| id == task_id) {
            requested.push(task.clone());
        }
        requested.extend(descendants);
        tx.commit().await?;
        Ok(ChatOrchestrationCancelOutcome { task, requested })
    }
}
