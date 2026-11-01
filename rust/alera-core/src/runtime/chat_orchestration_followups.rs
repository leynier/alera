//! Work a child chat does after its task settled. A settled result stays as
//! it is; a later turn the child runs on its own (a background continuation,
//! a sub-agent's or delegated task's wake, a person's message) becomes a
//! `followup` task, whose own settle wakes the parent again. A task's chain
//! also moves its head along continuation turns while it is still running.

use anyhow::Result;
use chrono::Utc;
use serde_json::{json, Value};

use super::chat_orchestration_models::*;
use super::chat_orchestration_rows::{require_id, require_task_in, task_from_row, TASK_COLUMNS};
use super::chat_orchestration_store::{insert_task_in, transition_in, validate_new_task};
use super::{format_timestamp, RuntimeStore};

const UNSETTLED: &str = "('preparing', 'running', 'needs_input', 'cancel_requested')";

/// A child turn that may open a follow-up of the child's latest task.
#[derive(Debug, Clone)]
pub struct ChatOrchestrationFollowup {
    pub task_id: String,
    pub followup_of: String,
    pub child_chat_id: String,
    pub child_turn_id: String,
    /// What started the turn, for the follow-up's brief.
    pub origin: String,
}

#[derive(Debug, Clone)]
pub enum ChatOrchestrationFollowupOutcome {
    Created(Box<ChatOrchestrationTask>),
    /// A task already owns the turn.
    Exists,
    /// The task it would follow is unsettled, has no parent, was stopped by
    /// its parent's person, or the child already works on another task.
    Refused,
}

fn parent_stopped(task: &ChatOrchestrationTask) -> bool {
    task.launch_options
        .as_ref()
        .and_then(|options| options.get("parentStopped"))
        == Some(&Value::Bool(true))
}

impl RuntimeStore {
    /// The child chat's newest task, settled or not.
    pub async fn latest_chat_orchestration_task_for_child(
        &self,
        child_chat_id: &str,
    ) -> Result<Option<ChatOrchestrationTask>> {
        require_id("childChatId", child_chat_id)?;
        let row = sqlx::query(sqlx::AssertSqlSafe(format!(
            "SELECT {TASK_COLUMNS} FROM chatOrchestrationTasks WHERE childChatId = ? \
             ORDER BY sequence DESC LIMIT 1"
        )))
        .bind(child_chat_id)
        .fetch_optional(self.pool())
        .await?;
        row.as_ref().map(task_from_row).transpose()
    }

    /// Moves a running task's head turn from `from_turn_id` to the
    /// continuation `to_turn_id`, recording where its chain started once. A
    /// compare-and-set with no revision bump: `None` when the head moved.
    pub async fn advance_chat_orchestration_task_turn(
        &self,
        task_id: &str,
        from_turn_id: &str,
        to_turn_id: &str,
    ) -> Result<Option<ChatOrchestrationTask>> {
        require_id("taskId", task_id)?;
        require_id("fromTurnId", from_turn_id)?;
        require_id("toTurnId", to_turn_id)?;
        let mut tx = self.pool().begin().await?;
        let updated = sqlx::query(
            "UPDATE chatOrchestrationTasks SET childTurnId = ?, updatedAt = ?, \
             launchOptionsJson = CASE \
                 WHEN json_extract(COALESCE(launchOptionsJson, '{}'), '$.chainStartTurnId') IS NULL \
                 THEN json_set(COALESCE(launchOptionsJson, '{}'), '$.chainStartTurnId', ?) \
                 ELSE launchOptionsJson END \
             WHERE taskId = ? AND childTurnId = ? AND status IN ('running', 'needs_input')",
        )
        .bind(to_turn_id)
        .bind(format_timestamp(Utc::now()))
        .bind(from_turn_id)
        .bind(task_id)
        .bind(from_turn_id)
        .execute(&mut *tx)
        .await?
        .rows_affected();
        let task = require_task_in(&mut tx, task_id).await?;
        tx.commit().await?;
        Ok((updated > 0).then_some(task))
    }

    /// Opens a `followup` of `input.followup_of` for the child turn, linked
    /// to that turn and running, in one transaction.
    pub async fn create_chat_orchestration_followup(
        &self,
        input: &ChatOrchestrationFollowup,
    ) -> Result<ChatOrchestrationFollowupOutcome> {
        require_id("childTurnId", &input.child_turn_id)?;
        let mut tx = self.pool().begin_with("BEGIN IMMEDIATE").await?;
        let owned: Option<i64> = sqlx::query_scalar(
            "SELECT 1 FROM chatOrchestrationTasks WHERE childChatId = ? AND childTurnId = ? LIMIT 1",
        )
        .bind(&input.child_chat_id)
        .bind(&input.child_turn_id)
        .fetch_optional(&mut *tx)
        .await?;
        if owned.is_some() {
            tx.commit().await?;
            return Ok(ChatOrchestrationFollowupOutcome::Exists);
        }
        let original = require_task_in(&mut tx, &input.followup_of).await?;
        let busy: Option<i64> = sqlx::query_scalar(sqlx::AssertSqlSafe(format!(
            "SELECT 1 FROM chatOrchestrationTasks WHERE childChatId = ? AND status IN {UNSETTLED} \
             LIMIT 1"
        )))
        .bind(&input.child_chat_id)
        .fetch_optional(&mut *tx)
        .await?;
        if !original.status.is_terminal()
            || original.parent_chat_id.is_none()
            || original.child_chat_id.as_deref() != Some(input.child_chat_id.as_str())
            || parent_stopped(&original)
            || busy.is_some()
        {
            tx.commit().await?;
            return Ok(ChatOrchestrationFollowupOutcome::Refused);
        }
        // Every follow-up hangs under the chain's original task, so lineage
        // stays shallow and cancelling the original still reaches it.
        let root = match original.kind {
            ChatOrchestrationTaskKind::Followup => original
                .parent_task_id
                .clone()
                .unwrap_or_else(|| original.task_id.clone()),
            _ => original.task_id.clone(),
        };
        let mut options = original.launch_options.clone().unwrap_or_else(|| json!({}));
        if let Some(options) = options.as_object_mut() {
            options.remove("waitNotify");
            options.remove(CHAIN_START_TURN_KEY);
            options.insert(FOLLOWUP_OF_KEY.into(), json!(original.task_id));
        }
        let task = NewChatOrchestrationTask {
            task_id: input.task_id.clone(),
            kind: ChatOrchestrationTaskKind::Followup,
            caller_scope: original.caller_scope.clone(),
            parent_task_id: Some(root),
            parent_chat_id: original.parent_chat_id.clone(),
            child_chat_id: Some(input.child_chat_id.clone()),
            project_id: original.project_id.clone(),
            workspace_id: original.workspace_id.clone(),
            host_id: original.host_id.clone(),
            target: original.target.clone(),
            title: original.title.clone(),
            role: original.role.clone(),
            brief: format!(
                "Continuation of task {} after {}",
                original.task_id, input.origin
            ),
            notify: original.notify,
            launch_options: Some(options),
        };
        validate_new_task(&task)?;
        insert_task_in(&mut tx, &task).await?;
        let mut running = ChatOrchestrationTaskTransition::new(
            [ChatOrchestrationTaskStatus::Preparing],
            ChatOrchestrationTaskStatus::Running,
        );
        running.child_chat_id = Some(input.child_chat_id.clone());
        running.child_turn_id = Some(input.child_turn_id.clone());
        let created = match transition_in(&mut tx, &task.task_id, &running).await? {
            ChatOrchestrationTransitionOutcome::Applied { task, .. } => task,
            ChatOrchestrationTransitionOutcome::Rejected { current } => current,
        };
        tx.commit().await?;
        Ok(ChatOrchestrationFollowupOutcome::Created(Box::new(created)))
    }
}
