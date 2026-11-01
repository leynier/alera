//! Holds a task whose child turn completed while the child still works:
//! background work, a native sub-agent, an open request or queued message,
//! or tasks the child delegated that will wake it. A continuation turn moves
//! the task's head along; any other turn ends the chain. The task settles
//! from its head once the child stayed quiet for `SETTLE_QUIET`.

use std::time::Duration;

use alera_core::runtime::{
    ChatOrchestrationNotify, ChatOrchestrationTask, ChatOrchestrationTaskFilter,
    ChatOrchestrationTaskStatus,
};
use serde_json::Value;
use tokio::time::Instant;

use super::continuation::{child_leftover_work, is_continuation, next_turn_after};
use super::service::ChatOrchestrationService;

/// How long a child must stay without leftover work, with its cursor
/// unchanged, before a held task settles.
pub(super) const SETTLE_QUIET: Duration = Duration::from_millis(500);

pub(super) enum HoldStep {
    /// The head moved to a continuation turn.
    Advanced,
    Hold,
    Settle,
}

/// When the child went quiet, and at which cursor.
pub(super) type Quiet = Option<(Instant, Value)>;

/// Open requests of the head turn; while the task is held, requests with no
/// turn count too.
pub(super) fn pending_requests(snapshot: &Value, turn_id: &str, held: bool) -> usize {
    snapshot["pendingRequests"]
        .as_array()
        .map(|requests| {
            requests
                .iter()
                .filter(|request| {
                    request["turnId"] == turn_id
                        || (held && request.get("turnId").is_none_or(Value::is_null))
                })
                .count()
        })
        .unwrap_or(0)
}

impl ChatOrchestrationService {
    pub(super) async fn hold_completed_head(
        &self,
        task: &ChatOrchestrationTask,
        child_chat_id: &str,
        head: &str,
        snapshot: &Value,
        quiet: &mut Quiet,
    ) -> HoldStep {
        if let Some(next) = next_turn_after(snapshot, head) {
            *quiet = None;
            let Ok(Some(turn)) = self.runtime.child_turn(child_chat_id, &next, None).await else {
                return HoldStep::Hold;
            };
            if !is_continuation(&turn) {
                return HoldStep::Settle;
            }
            return match self
                .store
                .advance_chat_orchestration_task_turn(&task.task_id, head, &next)
                .await
            {
                Ok(Some(task)) => {
                    self.emit_change(&task).await;
                    HoldStep::Advanced
                }
                _ => HoldStep::Hold,
            };
        }
        if child_leftover_work(snapshot) || self.owes_child_wakes(child_chat_id).await {
            *quiet = None;
            return HoldStep::Hold;
        }
        let cursor = snapshot.get("cursor").cloned().unwrap_or(Value::Null);
        match quiet {
            Some((since, seen)) if *seen == cursor => {
                if since.elapsed() >= SETTLE_QUIET {
                    HoldStep::Settle
                } else {
                    HoldStep::Hold
                }
            }
            _ => {
                *quiet = Some((Instant::now(), cursor));
                HoldStep::Hold
            }
        }
    }

    /// Whether the child waits on tasks it delegated that will wake it, or
    /// on a wake it is owed; the pump is nudged to deliver such a wake.
    async fn owes_child_wakes(&self, child_chat_id: &str) -> bool {
        if self
            .store
            .list_chat_orchestration_wakes_awaiting_delivery(Some(child_chat_id))
            .await
            .is_ok_and(|wakes| !wakes.is_empty())
        {
            self.wake_pump.owe(child_chat_id);
            return true;
        }
        self.store
            .list_chat_orchestration_tasks(&ChatOrchestrationTaskFilter {
                parent_chat_id: Some(child_chat_id.to_owned()),
                statuses: vec![
                    ChatOrchestrationTaskStatus::Preparing,
                    ChatOrchestrationTaskStatus::Running,
                    ChatOrchestrationTaskStatus::NeedsInput,
                    ChatOrchestrationTaskStatus::CancelRequested,
                ],
                limit: Some(200),
                ..Default::default()
            })
            .await
            .is_ok_and(|page| {
                page.tasks
                    .iter()
                    .any(|task| task.notify != ChatOrchestrationNotify::Never)
            })
    }
}
