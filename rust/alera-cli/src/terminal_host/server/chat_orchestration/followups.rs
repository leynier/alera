//! Follow-ups: a child that runs another turn after its task settled, on
//! its own or because a person wrote to it, reports that work to its parent
//! as a `followup` task. Stateless: each turn start the pump sees is checked
//! against the child's latest task, and the store dedupes on the turn.

use alera_core::runtime::{
    new_chat_orchestration_task_id, ChatOrchestrationFollowup, ChatOrchestrationFollowupOutcome,
    ChatOrchestrationNotify, ChatOrchestrationTaskKind, ChatOrchestrationTaskStatus,
};
use serde_json::Value;

use super::continuation::followup_origin;
use super::service::ChatOrchestrationService;

impl ChatOrchestrationService {
    /// Called for each chat change whose session names an active turn.
    pub(super) async fn open_followup(&self, child_chat_id: &str, turn_id: &str) {
        let Ok(Some(latest)) = self
            .store
            .latest_chat_orchestration_task_for_child(child_chat_id)
            .await
        else {
            return;
        };
        let stopped = latest
            .launch_options
            .as_ref()
            .and_then(|options| options.get("parentStopped"))
            == Some(&Value::Bool(true));
        let Some(parent) = latest.parent_chat_id.as_deref() else {
            return;
        };
        if !matches!(
            latest.status,
            ChatOrchestrationTaskStatus::Completed | ChatOrchestrationTaskStatus::Failed
        ) || !matches!(
            latest.kind,
            ChatOrchestrationTaskKind::Delegate | ChatOrchestrationTaskKind::Followup
        ) || latest.notify == ChatOrchestrationNotify::Never
            || stopped
            || latest.child_turn_id.as_deref() == Some(turn_id)
        {
            return;
        }
        let Ok(Some(turn)) = self.runtime.child_turn(child_chat_id, turn_id, None).await else {
            return;
        };
        let Some(origin) = followup_origin(&turn, parent) else {
            return;
        };
        let input = ChatOrchestrationFollowup {
            task_id: new_chat_orchestration_task_id(),
            followup_of: latest.task_id.clone(),
            child_chat_id: child_chat_id.to_owned(),
            child_turn_id: turn_id.to_owned(),
            origin: origin.to_owned(),
        };
        match self.store.create_chat_orchestration_followup(&input).await {
            Ok(ChatOrchestrationFollowupOutcome::Created(task)) => {
                self.emit_change(&task).await;
                self.spawn_task_monitor(
                    task.task_id.clone(),
                    child_chat_id.to_owned(),
                    format!("chat-orchestration-task:{}", task.task_id),
                );
            }
            Ok(_) => {}
            // A native operation freezes the chats; the next change retries.
            Err(error) => tracing::debug!(%child_chat_id, "follow-up not opened: {error}"),
        }
    }
}
