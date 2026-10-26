use super::authorization::{enforce_mode_ceiling, OrchestrationCaller};
use super::delegation_options::delegation_effort;
use super::messages::task_message_origin;
use super::models::{DelegateInput, DelegateMode, ParsedTarget};
use super::native_operation_guard::task_creation_error;
use super::operations::{cancel_requested_task, task_launch_options};
use super::parent::task_parent_chat_id;
use super::service::ChatOrchestrationService;
use super::targets::ResolvedChatTarget;
use super::tasks::{task_value, transition_status};
use crate::terminal_host::host_error::{HostError, HostResult};
use crate::terminal_host::server::agent_chat_runtime::commands::{
    CallerCtx, SendInput as RuntimeSendInput,
};
use crate::terminal_host::server::agent_chat_runtime::CreateChatInput;
use alera_core::runtime::{
    chat_orchestration_request_digest, new_chat_orchestration_task_id,
    ChatOrchestrationCreateOutcome, ChatOrchestrationNotify, ChatOrchestrationReceipt,
    ChatOrchestrationTaskKind, ChatOrchestrationTaskStatus, NewChatOrchestrationTask,
};
use serde_json::{json, Value};

impl ChatOrchestrationService {
    pub(super) async fn delegate(
        &self,
        input: DelegateInput,
        caller: &OrchestrationCaller,
    ) -> HostResult<Value> {
        let mut payload = json!({
            "task": input.task,
            "title": input.title,
            "role": input.role,
            "notify": input.notify,
            "mode": match input.mode { DelegateMode::Async => "async", DelegateMode::Wait => "wait" },
            "waitSeconds": input.wait_seconds,
            "agent": {"providerInstanceId": input.agent.provider_instance_id, "model": input.agent.model, "options": input.agent.options},
            "runtimeMode": input.runtime_mode,
            "interactionMode": input.interaction_mode,
            "target": input.target.store_target(),
        });
        if let Some(parent) = &input.parent_chat_id {
            payload["parentChatId"] = json!(parent);
        }
        if let Some(response) = self
            .check_receipt(caller, "delegate", &input.request_id, &payload)
            .await?
        {
            return Ok(response);
        }
        let parent_chat_id = task_parent_chat_id(caller, input.parent_chat_id.as_deref())?;
        let destination = match &input.target {
            ParsedTarget::Chat { chat_id } => Some(chat_id.as_str()),
            _ => None,
        };
        super::native_operation_guard::require_unfrozen_admission(
            self.runtime.as_ref(),
            parent_chat_id.as_deref(),
            destination,
        )
        .await?;
        let mut runtime_mode = enforce_mode_ceiling(caller, input.runtime_mode.as_deref())?;
        let reasoning_effort = delegation_effort(input.agent.options.as_ref())?;
        let mut turn_model = None;
        if let ParsedTarget::Chat { chat_id } = &input.target {
            let snapshot = self.runtime.snapshot(chat_id).await?;
            let actual_mode = snapshot["session"]["runtimeMode"]
                .as_str()
                .unwrap_or("approval-required");
            runtime_mode = enforce_mode_ceiling(caller, Some(actual_mode))?;
            if input
                .runtime_mode
                .as_deref()
                .is_some_and(|mode| mode != actual_mode)
                || input
                    .agent
                    .provider_instance_id
                    .as_deref()
                    .is_some_and(|instance| {
                        snapshot["providerInstanceId"].as_str() != Some(instance)
                    })
            {
                return Err(HostError::conflict(
                    "unsupported",
                    "Configure the existing chat before delegating with a different provider or runtime mode.",
                    json!({}),
                ));
            }
            let different_model = input
                .agent
                .model
                .as_deref()
                .is_some_and(|model| snapshot["session"]["model"].as_str() != Some(model));
            if different_model
                && !snapshot["session"]["capabilities"]["modelSwitch"]
                    .as_bool()
                    .unwrap_or(false)
            {
                return Err(HostError::conflict(
                    "unsupported",
                    "This provider cannot select a different model for an existing chat turn.",
                    json!({}),
                ));
            }
            if different_model {
                turn_model = input.agent.model.clone();
            }
        }
        let parent_task_id = self
            .parent_task_id_for_chat(parent_chat_id.as_deref())
            .await?;
        let task_id = new_chat_orchestration_task_id();
        let launch_options = {
            let mut value = task_launch_options(&input);
            if let Value::Object(map) = &mut value {
                map.insert("runtimeMode".into(), json!(runtime_mode));
                if input.mode == DelegateMode::Wait {
                    map.insert("waitNotify".into(), json!(input.notify));
                }
            }
            value
        };
        let initial = json!({"taskId": task_id, "status": "preparing"});
        let receipt = ChatOrchestrationReceipt {
            scope: caller.ctx.scope.clone(),
            verb: "delegate".into(),
            request_id: input.request_id.clone(),
            digest: chat_orchestration_request_digest("delegate", &payload),
            response: initial.clone(),
        };
        let new_task = NewChatOrchestrationTask {
            task_id: task_id.clone(),
            kind: ChatOrchestrationTaskKind::Delegate,
            caller_scope: caller.ctx.scope.clone(),
            parent_task_id,
            parent_chat_id: parent_chat_id.clone(),
            child_chat_id: match &input.target {
                ParsedTarget::Chat { chat_id } => Some(chat_id.clone()),
                _ => None,
            },
            project_id: match &input.target {
                ParsedTarget::NewWorkspace(target) => Some(target.spec.project_id.clone()),
                _ => None,
            },
            workspace_id: match &input.target {
                ParsedTarget::Workspace { workspace_id } => Some(workspace_id.clone()),
                _ => None,
            },
            host_id: match &input.target {
                ParsedTarget::NewWorkspace(target) => Some(target.spec.host_id.clone()),
                _ => None,
            },
            target: input.target.store_target(),
            title: input.title.clone(),
            role: input.role.clone(),
            brief: input.task.clone(),
            notify: if input.mode == DelegateMode::Wait {
                ChatOrchestrationNotify::Never
            } else {
                input.notify
            },
            launch_options: Some(launch_options.clone()),
        };
        let created = self
            .store
            .create_chat_orchestration_task(new_task, Some(&receipt))
            .await
            .map_err(task_creation_error)?;
        let task = match created {
            ChatOrchestrationCreateOutcome::Replay(response) => return Ok(response),
            ChatOrchestrationCreateOutcome::Conflict => {
                return Err(HostError::conflict(
                    "request_conflict",
                    "This requestId was already used for a different request.",
                    json!({}),
                ));
            }
            ChatOrchestrationCreateOutcome::Created(task) => task,
        };
        self.emit_change(&task).await;
        if let Some(task) = cancel_requested_task(&self.store, &task_id).await? {
            return self
                .finalize_task_receipt(&receipt, &initial, task_value(&task))
                .await;
        }
        let resolved = match self.resolve_target(&input.target).await {
            Ok(resolved) => resolved,
            Err(error) => {
                self.fail_task(
                    &task_id,
                    None,
                    "workspace_preparation_failed",
                    error.wire_message(),
                )
                .await;
                let task = self
                    .store
                    .chat_orchestration_task(&task_id)
                    .await
                    .map_err(|error| HostError::state(error.to_string()))?
                    .expect("created task");
                self.finalize_task_receipt(&receipt, &initial, task_value(&task))
                    .await?;
                return Err(error);
            }
        };
        let task = self
            .store
            .record_chat_orchestration_preparation(
                &task_id,
                None,
                resolved.project_id.as_deref(),
                Some(&resolved.workspace_id),
                Some(&resolved.host_id),
            )
            .await
            .map_err(|error| HostError::state(error.to_string()))?;
        self.emit_change(&task).await;
        if let Some(task) = cancel_requested_task(&self.store, &task_id).await? {
            return self
                .finalize_task_receipt(&receipt, &initial, task_value(&task))
                .await;
        }
        let child_chat_id = match &input.target {
            ParsedTarget::Chat { chat_id } => chat_id.clone(),
            ParsedTarget::Workspace { .. } | ParsedTarget::NewWorkspace(_) => {
                match self
                    .create_child_chat(
                        &resolved,
                        &input,
                        &task_id,
                        &runtime_mode,
                        parent_chat_id.as_deref(),
                    )
                    .await
                {
                    Ok(chat_id) => chat_id,
                    Err(error) => {
                        self.fail_task(
                            &task_id,
                            None,
                            "chat_creation_failed",
                            error.wire_message(),
                        )
                        .await;
                        self.finalize_failed_task_receipt(&task_id, &receipt, &initial)
                            .await?;
                        return Err(error);
                    }
                }
            }
        };
        let task = self
            .store
            .record_chat_orchestration_preparation(&task_id, Some(&child_chat_id), None, None, None)
            .await
            .map_err(|error| HostError::state(error.to_string()))?;
        self.emit_change(&task).await;
        if let Some(task) = cancel_requested_task(&self.store, &task_id).await? {
            return self
                .finalize_task_receipt(&receipt, &initial, task_value(&task))
                .await;
        }
        let client_message_id = format!("chat-orchestration-task:{task_id}");
        let send_result = self
            .send_chat_input(
                &child_chat_id,
                RuntimeSendInput {
                    client_message_id: client_message_id.clone(),
                    text: input.task.clone(),
                    attachments: Vec::new(),
                    delivery: "auto".into(),
                    model: turn_model,
                    reasoning_effort,
                    interaction_mode: input.interaction_mode.clone(),
                    runtime_mode_ceiling: caller
                        .bound
                        .as_ref()
                        .map(|bound| bound.runtime_mode.clone()),
                    origin: Some(task_message_origin(caller, Some(&task_id))),
                },
                caller,
            )
            .await;
        let send_result = match send_result {
            Ok(result) => result,
            Err(error) => {
                self.fail_task(
                    &task_id,
                    Some(child_chat_id),
                    "sendFailed",
                    error.wire_message(),
                )
                .await;
                self.finalize_failed_task_receipt(&task_id, &receipt, &initial)
                    .await?;
                return Err(error);
            }
        };
        let turn_id = send_result
            .get("turnId")
            .and_then(Value::as_str)
            .map(ToOwned::to_owned);
        if let Some(parent) = parent_chat_id.as_deref() {
            super::transfers::record_delegated_brief(
                self.runtime.as_ref(),
                parent,
                &child_chat_id,
                &task_id,
                turn_id.as_deref(),
            )
            .await;
        }
        let transition = transition_status(
            ChatOrchestrationTaskStatus::Preparing,
            ChatOrchestrationTaskStatus::Running,
            Some(child_chat_id.clone()),
            turn_id.clone(),
            None,
            None,
            None,
        );
        let task = self
            .store
            .transition_chat_orchestration_task(&task_id, &transition)
            .await
            .map_err(|error| HostError::state(error.to_string()))?;
        let task = match task {
            alera_core::runtime::ChatOrchestrationTransitionOutcome::Applied { task, .. }
            | alera_core::runtime::ChatOrchestrationTransitionOutcome::Rejected { current: task } => {
                task
            }
        };
        if task.status == ChatOrchestrationTaskStatus::CancelRequested
            || task.status == ChatOrchestrationTaskStatus::Cancelled
        {
            self.cancel_task_input(&task).await?;
        }
        self.emit_change(&task).await;
        self.spawn_task_monitor(task_id.clone(), child_chat_id, client_message_id);
        let mut response = task_value(&task);
        response["taskId"] = json!(task_id);
        if input.mode == DelegateMode::Wait {
            let response = self
                .wait_for_delegate(&task_id, input.wait_seconds, input.notify)
                .await?;
            return self
                .finalize_task_receipt(&receipt, &initial, response)
                .await;
        }
        self.finalize_task_receipt(&receipt, &initial, response)
            .await
    }

    pub(super) async fn finalize_task_receipt(
        &self,
        receipt: &ChatOrchestrationReceipt,
        initial: &Value,
        response: Value,
    ) -> HostResult<Value> {
        let mut receipt = receipt.clone();
        receipt.response = response;
        match self
            .store
            .finalize_chat_orchestration_receipt(&receipt, initial)
            .await
            .map_err(|error| HostError::state(error.to_string()))?
        {
            alera_core::runtime::ChatOrchestrationReceiptCheck::Replay(response) => Ok(response),
            _ => Err(HostError::conflict(
                "request_conflict",
                "The admission receipt changed during preparation.",
                json!({}),
            )),
        }
    }

    pub(super) async fn finalize_failed_task_receipt(
        &self,
        task_id: &str,
        receipt: &ChatOrchestrationReceipt,
        initial: &Value,
    ) -> HostResult<()> {
        if let Some(task) = self
            .store
            .chat_orchestration_task(task_id)
            .await
            .map_err(|error| HostError::state(error.to_string()))?
        {
            self.finalize_task_receipt(receipt, initial, task_value(&task))
                .await?;
        }
        Ok(())
    }

    async fn resolve_target(&self, target: &ParsedTarget) -> HostResult<ResolvedChatTarget> {
        match target {
            ParsedTarget::Chat { chat_id } => self.targets.resolve_existing_chat(chat_id).await,
            ParsedTarget::Workspace { workspace_id } => {
                self.targets.resolve_existing_workspace(workspace_id).await
            }
            ParsedTarget::NewWorkspace(target) => self.targets.create_workspace(&target.spec).await,
        }
    }

    async fn create_child_chat(
        &self,
        target: &ResolvedChatTarget,
        input: &DelegateInput,
        task_id: &str,
        runtime_mode: &str,
        parent_chat_id: Option<&str>,
    ) -> HostResult<String> {
        let instance = input.agent.provider_instance_id.clone().ok_or_else(|| {
            HostError::conflict(
                "providerUnavailable",
                "A providerInstanceId is required for a new chat target.",
                json!({}),
            )
        })?;
        let metadata = json!({
            "originKind": "orchestration",
            "taskId": task_id,
            "parentChatId": parent_chat_id,
            "role": input.role,
        });
        let response = self
            .runtime
            .create(
                CreateChatInput {
                    workspace_id: target.workspace_id.clone(),
                    provider: None,
                    provider_instance_id: Some(instance),
                    model: input.agent.model.clone(),
                    reasoning_effort: delegation_effort(input.agent.options.as_ref())?,
                    runtime_mode: Some(runtime_mode.to_owned()),
                    interaction_mode: input.interaction_mode.clone(),
                    title: input.title.clone(),
                    metadata: Some(metadata),
                },
                CallerCtx::runtime(),
                None,
            )
            .await?;
        response
            .get("chatId")
            .and_then(Value::as_str)
            .map(ToOwned::to_owned)
            .ok_or_else(|| HostError::state("The chat runtime did not return a child chat id."))
    }
}
