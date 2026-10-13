use alera_core::runtime::{
    chat_orchestration_request_digest, new_chat_orchestration_task_id,
    ChatOrchestrationCreateOutcome, ChatOrchestrationNotify, ChatOrchestrationReceipt,
    ChatOrchestrationTarget, ChatOrchestrationTaskKind, ChatOrchestrationTaskStatus,
    ChatOrchestrationTransitionOutcome, NewChatOrchestrationTask,
};
use serde_json::{json, Value};

use crate::terminal_host::host_error::{HostError, HostResult};
use crate::terminal_host::server::agent_chat_runtime::commands::{
    ChatOp, SendInput as RuntimeSendInput,
};

use super::authorization::OrchestrationCaller;
use super::models::SendInput;
use super::operations::cancel_requested_task;
use super::service::{ChatOrchestrationService, TASK_ORIGIN};
use super::tasks::{task_value, transition_status};

impl ChatOrchestrationService {
    pub(super) async fn send_chat_input(
        &self,
        chat_id: &str,
        input: RuntimeSendInput,
        caller: &OrchestrationCaller,
    ) -> HostResult<Value> {
        if let Some(bound) = &caller.bound {
            self.runtime
                .command(
                    chat_id,
                    ChatOp::SendWithinCeiling {
                        input,
                        runtime_mode_ceiling: bound.runtime_mode.clone(),
                    },
                    caller.ctx.clone(),
                    None,
                )
                .await
        } else {
            self.runtime.send(chat_id, input, caller.ctx.clone()).await
        }
    }

    pub(super) async fn send(
        &self,
        input: SendInput,
        caller: &OrchestrationCaller,
    ) -> HostResult<Value> {
        if input.delivery != "auto" && input.delivery != "queue" {
            return Err(HostError::format("delivery must be auto or queue"));
        }
        let payload = json!({"chatId": input.chat_id, "message": input.message,
            "delivery": input.delivery, "expectReply": input.expect_reply});
        if let Some(response) = self
            .check_receipt(caller, "send", &input.request_id, &payload)
            .await?
        {
            return Ok(response);
        }
        let sender = caller.bound.as_ref().map(|bound| bound.chat_id.clone());
        let (task_id, receipt) = if input.expect_reply {
            let task_id = new_chat_orchestration_task_id();
            let receipt = ChatOrchestrationReceipt {
                scope: caller.ctx.scope.clone(),
                verb: "send".into(),
                request_id: input.request_id.clone(),
                digest: chat_orchestration_request_digest("send", &payload),
                response: json!({"chatId": input.chat_id, "taskId": task_id, "delivery": "preparing"}),
            };
            let resolved = self.targets.resolve_existing_chat(&input.chat_id).await?;
            let created = self
                .store
                .create_chat_orchestration_task(
                    NewChatOrchestrationTask {
                        task_id: task_id.clone(),
                        kind: ChatOrchestrationTaskKind::Message,
                        caller_scope: caller.ctx.scope.clone(),
                        parent_task_id: self.caller_parent_task_id(caller).await?,
                        parent_chat_id: sender.clone(),
                        child_chat_id: Some(input.chat_id.clone()),
                        project_id: resolved.project_id,
                        workspace_id: Some(resolved.workspace_id),
                        host_id: Some(resolved.host_id),
                        target: ChatOrchestrationTarget::Chat {
                            chat_id: input.chat_id.clone(),
                        },
                        title: None,
                        role: None,
                        brief: input.message.clone(),
                        notify: ChatOrchestrationNotify::Always,
                        launch_options: None,
                    },
                    Some(&receipt),
                )
                .await
                .map_err(|error| HostError::state(error.to_string()))?;
            match created {
                ChatOrchestrationCreateOutcome::Replay(response) => return Ok(response),
                ChatOrchestrationCreateOutcome::Conflict => {
                    return Err(HostError::conflict(
                        "request_conflict",
                        "This requestId was already used for a different request.",
                        json!({}),
                    ))
                }
                ChatOrchestrationCreateOutcome::Created(task) => self.emit_change(&task).await,
            }
            if let Some(task) = cancel_requested_task(&self.store, &task_id).await? {
                return self
                    .finalize_task_receipt(
                        &receipt,
                        &receipt.response,
                        json!({"chatId":input.chat_id, "taskId":task_id, "task":task_value(&task)}),
                    )
                    .await;
            }
            (Some(task_id), Some(receipt))
        } else {
            (None, None)
        };
        let client_message_id = task_id
            .as_ref()
            .map(|task_id| format!("chat-orchestration-task:{task_id}"))
            .unwrap_or_else(|| {
                format!(
                    "chat-orchestration-send:{}",
                    chat_orchestration_request_digest(
                        "send_identity",
                        &json!({"scope":caller.ctx.scope, "id":input.request_id})
                    )
                )
            });
        let response = self.send_chat_input(&input.chat_id, RuntimeSendInput {
            client_message_id: client_message_id.clone(), text: input.message, attachments: Vec::new(),
            delivery: input.delivery, model: None, interaction_mode: None,
            runtime_mode_ceiling: caller.bound.as_ref().map(|bound| bound.runtime_mode.clone()),
            origin: Some(json!({"kind":TASK_ORIGIN, "senderChatId":sender, "taskIds":task_id.as_ref().map(|id| vec![id])})),
        }, caller).await;
        let response = match response {
            Ok(response) => response,
            Err(error) => {
                if let Some(task_id) = &task_id {
                    self.fail_task(
                        task_id,
                        Some(input.chat_id.clone()),
                        "send_failed",
                        error.wire_message(),
                    )
                    .await;
                    if let Some(receipt) = &receipt {
                        self.finalize_failed_task_receipt(task_id, receipt, &receipt.response)
                            .await?;
                    }
                }
                return Err(error);
            }
        };
        if let Some(task_id) = &task_id {
            let transition = transition_status(
                ChatOrchestrationTaskStatus::Preparing,
                ChatOrchestrationTaskStatus::Running,
                Some(input.chat_id.clone()),
                response["turnId"].as_str().map(ToOwned::to_owned),
                None,
                None,
                None,
            );
            let task = match self
                .store
                .transition_chat_orchestration_task(task_id, &transition)
                .await
                .map_err(|error| HostError::state(error.to_string()))?
            {
                ChatOrchestrationTransitionOutcome::Applied { task, .. }
                | ChatOrchestrationTransitionOutcome::Rejected { current: task } => task,
            };
            if task.status == ChatOrchestrationTaskStatus::CancelRequested
                || task.status == ChatOrchestrationTaskStatus::Cancelled
            {
                self.cancel_task_input(&task).await?;
            }
            self.emit_change(&task).await;
            self.spawn_task_monitor(task_id.clone(), input.chat_id.clone(), client_message_id);
        }
        let mut result = response;
        result["chatId"] = json!(input.chat_id);
        if let Some(task_id) = task_id {
            result["taskId"] = json!(task_id);
        }
        if let Some(receipt) = receipt {
            self.finalize_task_receipt(&receipt, &receipt.response, result)
                .await
        } else {
            self.record_receipt(caller, "send", &input.request_id, &payload, result.clone())
                .await?;
            Ok(result)
        }
    }
}
