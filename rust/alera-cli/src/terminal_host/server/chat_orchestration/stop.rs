//! A person's stop of a chat reaches the delegated work under it. Once the
//! chat's own turn, or the background work earlier turns left, is
//! interrupted, every delegated task the chat owns is cancelled with its
//! descendants, and the chat's pending wakes are dropped, so stopped children
//! cannot start it again. Each task gets [CHILD_STOP_DEADLINE] to stop; one
//! that hangs is recorded as `stopTimedOut` and the next one still stops.

use std::time::Duration;

use serde_json::{json, Value};

use crate::terminal_host::host_error::{HostError, HostResult};
use crate::terminal_host::server::agent_chat_runtime::commands::{CallerCtx, ChatOp, ReceiptKey};

use super::service::ChatOrchestrationService;

/// How long one delegated task, with its descendants, may take to stop.
pub(crate) const CHILD_STOP_DEADLINE: Duration = Duration::from_secs(30);

impl ChatOrchestrationService {
    /// Interrupts `chat_id`, then stops the delegated tasks under it with
    /// the person's authority unless `stop_delegated_tasks` is false, as for a
    /// caller that stops those itself. The tasks stop even when the interrupt
    /// fails; the interrupt's own result is returned.
    pub(crate) async fn stop_chat(
        &self,
        chat_id: &str,
        operation: ChatOp,
        ctx: CallerCtx,
        receipt: Option<ReceiptKey>,
        stop_delegated_tasks: bool,
    ) -> HostResult<Value> {
        let scope = ctx.scope.clone();
        let interrupted = self.runtime.command(chat_id, operation, ctx, receipt).await;
        if stop_delegated_tasks {
            self.stop_delegated_tasks_logged(chat_id, &scope).await;
        }
        interrupted
    }

    pub(crate) async fn stop_delegated_tasks_logged(&self, chat_id: &str, caller_scope: &str) {
        match self.stop_delegated_tasks(chat_id, caller_scope).await {
            Ok(stopped)
                if stopped["errors"]
                    .as_array()
                    .is_some_and(|errors| !errors.is_empty()) =>
            {
                tracing::warn!(chat_id, errors = %stopped["errors"], "some delegated tasks did not stop");
            }
            Ok(_) => {}
            Err(error) => {
                tracing::warn!(chat_id, error = %error, "stopping the delegated tasks failed");
            }
        }
    }

    /// Cancels every unsettled delegated task `chat_id` owns, with its
    /// descendants, as `caller_scope` (a person), after dropping the chat's
    /// open and sealed wakes and the sealed wake's queued message.
    pub(crate) async fn stop_delegated_tasks(
        &self,
        chat_id: &str,
        caller_scope: &str,
    ) -> HostResult<Value> {
        let stop = self
            .store
            .stop_chat_orchestration_parent(chat_id)
            .await
            .map_err(|error| HostError::state(error.to_string()))?;
        for client_message_id in stop.sealed_wake_message_ids {
            // The sealed cohort's message may already wait in the queue.
            if let Err(error) = self
                .runtime
                .command(
                    chat_id,
                    ChatOp::CancelMessage { client_message_id },
                    CallerCtx::runtime(),
                    None,
                )
                .await
            {
                tracing::warn!(chat_id, error = %error, "dropping a sealed wake message failed");
            }
        }
        let mut cancelled = Vec::new();
        let mut errors = Vec::new();
        for task_id in stop.task_ids {
            let stopped = tokio::time::timeout(
                self.child_stop_deadline,
                self.cancel_lineage(&task_id, caller_scope, None),
            )
            .await;
            match stopped {
                Ok(Ok((task_ids, task_errors))) => {
                    cancelled.extend(task_ids);
                    errors.extend(task_errors);
                }
                Ok(Err(error)) => {
                    errors.push(json!({"taskId": task_id, "error": error.wire_message()}));
                }
                Err(_) => {
                    tracing::warn!(chat_id, task_id, "a delegated task did not stop in time");
                    errors.push(json!({
                        "taskId": task_id,
                        "code": "stopTimedOut",
                        "error": format!(
                            "The task did not stop within {} seconds.",
                            self.child_stop_deadline.as_secs()
                        ),
                    }));
                }
            }
        }
        Ok(json!({"cancelledTaskIds": cancelled, "errors": errors}))
    }
}

/// The delegated tasks a person's `agentChat.interrupt` stops once the chat's
/// own stop returns.
pub(crate) struct DelegatedTasksStop {
    service: ChatOrchestrationService,
    chat_id: String,
    caller_scope: String,
}

impl DelegatedTasksStop {
    /// Some for an `agentChat.interrupt` or `agentChat.forceStop` of a chat
    /// by a person.
    pub(crate) fn for_request(
        service: Option<&ChatOrchestrationService>,
        verb: &str,
        payload: &Value,
        ctx: &CallerCtx,
    ) -> Option<Self> {
        if !matches!(verb, "agentChat.interrupt" | "agentChat.forceStop") || ctx.scope == "runtime"
        {
            return None;
        }
        Some(Self {
            service: service?.clone(),
            chat_id: payload.get("chatId")?.as_str()?.to_owned(),
            caller_scope: ctx.scope.clone(),
        })
    }

    pub(crate) async fn run(self) {
        self.service
            .stop_delegated_tasks_logged(&self.chat_id, &self.caller_scope)
            .await;
    }
}
