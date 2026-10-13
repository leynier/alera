//! Startup reconciliation. Provider processes do not survive the runtime, so
//! every local task left unsettled is settled from what its child chat
//! recorded, or marked interrupted (cancelled when a cancel was pending).
//! Nothing is sent to a model again. Credentials are all revoked, because
//! each one belonged to a provider launch that no longer exists.

use anyhow::Result;
use sqlx::{Row, SqliteConnection};

use super::chat_orchestration_delivery::*;
use super::chat_orchestration_models::*;
use super::chat_orchestration_rows::{require_id, task_from_row, TASK_COLUMNS};
use super::chat_orchestration_store::transition_in;
use super::{RuntimeStore, LOCAL_HOST_ID};

use ChatOrchestrationTaskStatus as Status;

pub(super) async fn child_turn_in(
    connection: &mut SqliteConnection,
    chat_id: &str,
    turn_id: &str,
) -> Result<Option<ChatOrchestrationChildTurn>> {
    let session = sqlx::query(
        "SELECT (SELECT status FROM agentChatTurns t \
             WHERE t.chatId = agentChatSessions.chatId AND t.turnId = ?) AS turnStatus \
         FROM agentChatSessions WHERE chatId = ?",
    )
    .bind(turn_id)
    .bind(chat_id)
    .fetch_optional(&mut *connection)
    .await?;
    let Some(session) = session else {
        return Ok(None);
    };
    let final_assistant_text: Option<String> = sqlx::query_scalar(
        "SELECT json_extract(itemJson, '$.text') FROM agentChatItems \
         WHERE chatId = ? AND turnId = ? AND json_extract(itemJson, '$.type') = 'assistant_message' \
         ORDER BY seq DESC LIMIT 1",
    )
    .bind(chat_id)
    .bind(turn_id)
    .fetch_optional(&mut *connection)
    .await?
    .flatten();
    Ok(Some(ChatOrchestrationChildTurn {
        turn_status: session.try_get("turnStatus")?,
        final_assistant_text,
    }))
}

fn is_local(task: &ChatOrchestrationTask) -> bool {
    task.host_id
        .as_deref()
        .is_none_or(|host| host == LOCAL_HOST_ID)
}

fn restarted(transition: &mut ChatOrchestrationTaskTransition) {
    transition.error_code = Some(CHAT_ORCHESTRATION_INTERRUPT_RUNTIME_RESTARTED.into());
    transition.error = Some("The runtime restarted before the task settled.".into());
}

/// What a task left unsettled by a restart becomes.
fn settle(
    task: &ChatOrchestrationTask,
    child: Option<Option<ChatOrchestrationChildTurn>>,
) -> ChatOrchestrationTaskTransition {
    let cancelling = task.status == Status::CancelRequested;
    let stopped = if cancelling {
        Status::Cancelled
    } else {
        Status::Interrupted
    };
    let mut transition = ChatOrchestrationTaskTransition::new([task.status], stopped);
    transition.expected_revision = Some(task.revision);
    match child {
        Some(None) => {
            transition.error_code = Some(CHAT_ORCHESTRATION_INTERRUPT_CHILD_CHAT_MISSING.into());
            transition.error = Some("The child chat no longer exists.".into());
        }
        Some(Some(turn)) => match turn.turn_status.as_deref() {
            Some("completed") => {
                transition.to = Status::Completed;
                transition.result_text = turn.final_assistant_text;
            }
            Some("failed") => {
                transition.to = Status::Failed;
                transition.result_text = turn.final_assistant_text;
            }
            Some("cancelled") if cancelling => {}
            _ => restarted(&mut transition),
        },
        None => restarted(&mut transition),
    }
    transition
}

impl RuntimeStore {
    /// The recorded state of a child chat's turn: `None` when the chat no
    /// longer exists (deleted with its workspace).
    pub async fn chat_orchestration_child_turn(
        &self,
        chat_id: &str,
        turn_id: &str,
    ) -> Result<Option<ChatOrchestrationChildTurn>> {
        require_id("chatId", chat_id)?;
        require_id("turnId", turn_id)?;
        let mut connection = self.pool().acquire().await?;
        child_turn_in(&mut connection, chat_id, turn_id).await
    }

    /// Run once by the runtime owner after `recover_agent_chats` and before
    /// it accepts chat orchestration requests. Each task settles in its own
    /// transaction, together with any wake it owes its parent.
    pub async fn recover_chat_orchestration(&self) -> Result<ChatOrchestrationRecovery> {
        let mut recovery = ChatOrchestrationRecovery {
            revoked_credentials: self
                .revoke_all_chat_orchestration_credentials(
                    CHAT_ORCHESTRATION_INTERRUPT_RUNTIME_RESTARTED,
                )
                .await?,
            ..ChatOrchestrationRecovery::default()
        };
        let rows = sqlx::query(sqlx::AssertSqlSafe(format!(
            "SELECT {TASK_COLUMNS} FROM chatOrchestrationTasks \
             WHERE status IN ('preparing', 'running', 'needs_input', 'cancel_requested') \
             OR json_extract(launchOptionsJson, '$.waitNotify') IS NOT NULL \
             ORDER BY depth DESC, sequence"
        )))
        .fetch_all(self.pool())
        .await?;
        for row in &rows {
            let mut task = task_from_row(row)?;
            if let Some(notify) = task
                .launch_options
                .as_ref()
                .and_then(|options| options.get("waitNotify"))
                .and_then(serde_json::Value::as_str)
                .and_then(ChatOrchestrationNotify::parse)
            {
                task = self
                    .set_chat_orchestration_notify(&task.task_id, notify)
                    .await?;
            }
            if task.status.is_terminal() {
                continue;
            }
            if !is_local(&task) {
                recovery.remote.push(task);
                continue;
            }
            let mut connection = self.pool().acquire().await?;
            let child = match (&task.child_chat_id, &task.child_turn_id) {
                (Some(chat_id), Some(turn_id)) => {
                    Some(child_turn_in(&mut connection, chat_id, turn_id).await?)
                }
                (Some(chat_id), None) => {
                    let exists: Option<i64> =
                        sqlx::query_scalar("SELECT 1 FROM agentChatSessions WHERE chatId = ?")
                            .bind(chat_id)
                            .fetch_optional(&mut *connection)
                            .await?;
                    exists.is_none().then_some(None)
                }
                _ => None,
            };
            drop(connection);
            let transition = settle(&task, child);
            // The revision guard leaves a task alone if anything moved it
            // between this read and the write.
            let mut tx = self.pool().begin().await?;
            match transition_in(&mut tx, &task.task_id, &transition).await? {
                ChatOrchestrationTransitionOutcome::Applied { task, .. } => {
                    recovery.settled.push(task);
                }
                ChatOrchestrationTransitionOutcome::Rejected { .. } => {}
            }
            tx.commit().await?;
        }
        recovery.wakes = self
            .list_chat_orchestration_wakes_awaiting_delivery(None)
            .await?;
        Ok(recovery)
    }
}
