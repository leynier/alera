use std::collections::HashSet;

use alera_core::runtime::{
    chat_orchestration_request_digest, ChatOrchestrationTask, ChatOrchestrationTaskStatus,
    ChatOrchestrationTransitionOutcome,
};
use serde_json::{json, Value};

use crate::terminal_host::host_error::{HostError, HostResult};
use crate::terminal_host::server::agent_chat_runtime::commands::{CallerCtx, ChatOp};

use super::authorization::{require_lineage_for_task, OrchestrationCaller};
use super::queries::runtime_receipt_key;
use super::service::ChatOrchestrationService;
use super::tasks::{task_value, transition_status};

impl ChatOrchestrationService {
    pub(super) async fn cancel(
        &self,
        task_id: String,
        request_id: String,
        reason: Option<String>,
        payload: &Value,
        caller: &OrchestrationCaller,
    ) -> HostResult<Value> {
        if let Some(response) = self
            .check_receipt(caller, "cancel", &request_id, payload)
            .await?
        {
            return Ok(response);
        }
        require_lineage_for_task(caller, &self.store, &task_id).await?;
        let outcome = self
            .store
            .request_chat_orchestration_cancel_with_authority(
                &task_id,
                &caller.ctx.scope,
                caller
                    .bound
                    .as_ref()
                    .map(|bound| bound.runtime_mode.as_str()),
            )
            .await
            .map_err(|error| HostError::state(error.to_string()))?;
        let mut cancelled = Vec::new();
        let mut errors = Vec::new();
        let mut requested = outcome.requested;
        let mut known = requested
            .iter()
            .map(|task| task.task_id.clone())
            .collect::<HashSet<_>>();
        let mut pending = self
            .store
            .chat_orchestration_task_descendants(&task_id)
            .await
            .map_err(|error| HostError::state(error.to_string()))?;
        pending.push(outcome.task);
        for task in pending {
            if task.status == ChatOrchestrationTaskStatus::CancelRequested
                && known.insert(task.task_id.clone())
            {
                requested.push(task);
            }
        }
        for task in &requested {
            self.emit_change(task).await;
            if let Err(error) = self.cancel_task_input(task).await {
                errors.push(json!({"taskId":task.task_id, "error":error.wire_message()}));
            }
            cancelled.push(task.task_id.clone());
        }
        let task = self
            .store
            .chat_orchestration_task(&task_id)
            .await
            .map_err(|error| HostError::state(error.to_string()))?
            .ok_or_else(|| HostError::conflict("task_not_found", "Task not found.", json!({})))?;
        let response = json!({"task": task_value(&task), "cancelledTaskIds": cancelled, "reason": reason, "errors":errors});
        self.record_receipt(caller, "cancel", &request_id, payload, response.clone())
            .await?;
        Ok(response)
    }

    pub(super) async fn cancel_task_input(&self, task: &ChatOrchestrationTask) -> HostResult<()> {
        let pending = match self.stop_task_input(task).await {
            Ok(pending) => pending,
            Err(error) => {
                if let Some(chat_id) = &task.child_chat_id {
                    if !task.status.is_terminal() {
                        self.spawn_task_monitor(
                            task.task_id.clone(),
                            chat_id.clone(),
                            format!("chat-orchestration-task:{}", task.task_id),
                        );
                    }
                }
                return Err(error);
            }
        };
        if pending && !task.status.is_terminal() {
            self.spawn_task_monitor(
                task.task_id.clone(),
                task.child_chat_id.clone().expect("owned child"),
                format!("chat-orchestration-task:{}", task.task_id),
            );
            return Ok(());
        }
        self.settle_task_cancelled(task).await
    }

    pub(super) async fn stop_task_input(&self, task: &ChatOrchestrationTask) -> HostResult<bool> {
        let active_owned_turn = if let Some(chat_id) = &task.child_chat_id {
            let mut operation = ChatOp::CancelMessage {
                client_message_id: format!("chat-orchestration-task:{}", task.task_id),
            };
            let options = task.launch_options.as_ref();
            match options.and_then(|options| options["cancellationPolicy"].as_str()) {
                Some("bound") => {
                    let ceiling = options
                        .and_then(|options| options["cancellationRuntimeModeCeiling"].as_str())
                        .ok_or_else(|| {
                            HostError::state("The cancellation authority has no mode ceiling.")
                        })?;
                    operation = ChatOp::WithinCeiling {
                        runtime_mode_ceiling: ceiling.to_owned(),
                        operation: Box::new(operation),
                    };
                }
                Some("human") => {}
                _ => return Err(HostError::state("The cancellation authority is missing.")),
            }
            let scope = options
                .and_then(|options| options["cancellationCallerScope"].as_str())
                .unwrap_or("runtime");
            let identity = format!(
                "{}:{}",
                task.task_id,
                chat_orchestration_request_digest(
                    "cancel_authority",
                    &json!({"scope":scope, "operation":operation})
                )
            );
            let key = runtime_receipt_key(scope, "cancelInput", &identity, chat_id, &operation);
            let response = self
                .runtime
                .command(chat_id, operation, CallerCtx::runtime(), Some(key))
                .await?;
            response
                .get("turnId")
                .and_then(Value::as_str)
                .map(ToOwned::to_owned)
        } else {
            None
        };
        let recorded_turn = if let Some(chat_id) = &task.child_chat_id {
            self.runtime
                .turn_for_client_message(
                    chat_id,
                    &format!("chat-orchestration-task:{}", task.task_id),
                )
                .await?
        } else {
            None
        };
        Ok(active_owned_turn.is_some() || recorded_turn.is_some())
    }

    pub(super) async fn settle_task_cancelled(
        &self,
        task: &ChatOrchestrationTask,
    ) -> HostResult<()> {
        let transition = transition_status(
            ChatOrchestrationTaskStatus::CancelRequested,
            ChatOrchestrationTaskStatus::Cancelled,
            task.child_chat_id.clone(),
            task.child_turn_id.clone(),
            None,
            None,
            None,
        );
        if let ChatOrchestrationTransitionOutcome::Applied { task, .. } = self
            .store
            .transition_chat_orchestration_task(&task.task_id, &transition)
            .await
            .map_err(|error| HostError::state(error.to_string()))?
        {
            self.emit_change(&task).await;
            self.deliver_task_wake(&task).await;
        }
        Ok(())
    }
}
