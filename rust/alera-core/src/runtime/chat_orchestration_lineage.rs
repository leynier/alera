//! Lineage queries. Tasks form a tree through `parentTaskId`, and chats form
//! a graph through tasks (`parentChatId` delegated to `childChatId`). A bound
//! agent may only steer work in its own descendant lineage, which these
//! queries decide.

use anyhow::Result;

use super::chat_orchestration_models::*;
use super::chat_orchestration_rows::{require_id, task_from_row, TASK_COLUMNS};
use super::RuntimeStore;

impl RuntimeStore {
    /// Every task below `task_id`, shallowest first.
    pub async fn chat_orchestration_task_descendants(
        &self,
        task_id: &str,
    ) -> Result<Vec<ChatOrchestrationTask>> {
        require_id("taskId", task_id)?;
        let rows = sqlx::query(sqlx::AssertSqlSafe(format!(
            "WITH RECURSIVE lineage(taskId) AS ( \
                 SELECT taskId FROM chatOrchestrationTasks WHERE parentTaskId = ? \
                 UNION SELECT t.taskId FROM chatOrchestrationTasks t \
                 JOIN lineage l ON t.parentTaskId = l.taskId) \
             SELECT {TASK_COLUMNS} FROM chatOrchestrationTasks \
             WHERE taskId IN (SELECT taskId FROM lineage) ORDER BY depth, sequence"
        )))
        .bind(task_id)
        .fetch_all(self.pool())
        .await?;
        rows.iter().map(task_from_row).collect()
    }

    /// The tasks above `task_id`, nearest first.
    pub async fn chat_orchestration_task_ancestors(
        &self,
        task_id: &str,
    ) -> Result<Vec<ChatOrchestrationTask>> {
        require_id("taskId", task_id)?;
        let rows = sqlx::query(sqlx::AssertSqlSafe(format!(
            "WITH RECURSIVE lineage(taskId) AS ( \
                 SELECT parentTaskId FROM chatOrchestrationTasks \
                 WHERE taskId = ? AND parentTaskId IS NOT NULL \
                 UNION SELECT t.parentTaskId FROM chatOrchestrationTasks t \
                 JOIN lineage l ON t.taskId = l.taskId WHERE t.parentTaskId IS NOT NULL) \
             SELECT {TASK_COLUMNS} FROM chatOrchestrationTasks \
             WHERE taskId IN (SELECT taskId FROM lineage) ORDER BY depth DESC"
        )))
        .bind(task_id)
        .fetch_all(self.pool())
        .await?;
        rows.iter().map(task_from_row).collect()
    }

    /// Whether `chat_id` was reached from `ancestor_chat_id` through one or
    /// more delegations. A chat is not its own descendant.
    pub async fn is_chat_orchestration_descendant_chat(
        &self,
        ancestor_chat_id: &str,
        chat_id: &str,
    ) -> Result<bool> {
        require_id("ancestorChatId", ancestor_chat_id)?;
        require_id("chatId", chat_id)?;
        if ancestor_chat_id == chat_id {
            return Ok(false);
        }
        let found: Option<i64> = sqlx::query_scalar(
            "WITH RECURSIVE reached(chatId) AS ( \
                 SELECT childChatId FROM chatOrchestrationTasks \
                 WHERE parentChatId = ? AND childChatId IS NOT NULL \
                 UNION SELECT t.childChatId FROM chatOrchestrationTasks t \
                 JOIN reached r ON t.parentChatId = r.chatId WHERE t.childChatId IS NOT NULL) \
             SELECT 1 FROM reached WHERE chatId = ? LIMIT 1",
        )
        .bind(ancestor_chat_id)
        .bind(chat_id)
        .fetch_optional(self.pool())
        .await?;
        Ok(found.is_some())
    }

    /// Whether `task_id` was created by `chat_id` or by one of its descendant
    /// chats: the tasks a bound agent may cancel, interrupt or answer for.
    pub async fn is_chat_orchestration_task_in_lineage(
        &self,
        chat_id: &str,
        task_id: &str,
    ) -> Result<bool> {
        require_id("chatId", chat_id)?;
        let Some(task) = self.chat_orchestration_task(task_id).await? else {
            return Ok(false);
        };

        // A delegated task can carry a different parent chat once its child
        // session is created. Walk the durable task ancestry as well as the
        // chat graph so the original caller still owns the whole subtree.
        let mut candidates = vec![task];
        candidates.extend(self.chat_orchestration_task_ancestors(task_id).await?);
        for candidate in candidates {
            let Some(parent_chat) = candidate.parent_chat_id.as_deref() else {
                continue;
            };
            if parent_chat == chat_id
                || self
                    .is_chat_orchestration_descendant_chat(chat_id, parent_chat)
                    .await?
            {
                return Ok(true);
            }
        }
        Ok(false)
    }
}
