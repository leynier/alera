use alera_core::runtime::ChatOrchestrationTaskStatus;
use serde_json::Map;
use serde_json::{json, Value};

use crate::terminal_host::host_error::{HostError, HostResult};
use crate::terminal_host::server::agent_chat_runtime::commands::{ChatOp, ConfigureInput};

use super::authorization::{enforce_mode_ceiling, require_lineage_for_chat, OrchestrationCaller};
use super::models::{DelegateInput, WaitInput};
use super::queries::runtime_receipt_key;
use super::service::ChatOrchestrationService;
use super::tasks::wait_for_tasks;

impl ChatOrchestrationService {
    pub(super) async fn wait(
        &self,
        input: WaitInput,
        _caller: &OrchestrationCaller,
    ) -> HostResult<Value> {
        wait_for_tasks(&self.store, &input).await
    }

    pub(super) async fn interrupt(
        &self,
        chat_id: String,
        turn_id: Option<String>,
        request_id: String,
        payload: &Value,
        caller: &OrchestrationCaller,
    ) -> HostResult<Value> {
        if let Some(response) = self
            .check_receipt(caller, "interrupt", &request_id, payload)
            .await?
        {
            return Ok(response);
        }
        require_lineage_for_chat(caller, &self.store, &chat_id).await?;
        let operation = bound_control_operation(caller, ChatOp::Interrupt { turn_id });
        let key = runtime_receipt_key(
            &caller.ctx.scope,
            "interrupt",
            &request_id,
            &chat_id,
            &operation,
        );
        let response = self
            .runtime
            .command(&chat_id, operation, caller.ctx.clone(), Some(key))
            .await?;
        self.record_receipt(caller, "interrupt", &request_id, payload, response.clone())
            .await?;
        Ok(response)
    }

    pub(super) async fn requests(
        &self,
        task_id: Option<String>,
        chat_id: Option<String>,
        _caller: &OrchestrationCaller,
    ) -> HostResult<Value> {
        let (chat_id, task_id) = match (chat_id, task_id) {
            (Some(chat_id), task_id) => (chat_id, task_id),
            (None, Some(task_id)) => {
                let task = self
                    .store
                    .chat_orchestration_task(&task_id)
                    .await
                    .map_err(|error| HostError::state(error.to_string()))?
                    .ok_or_else(|| {
                        HostError::conflict("task_not_found", "Task not found.", json!({}))
                    })?;
                (
                    task.child_chat_id
                        .ok_or_else(|| HostError::state("Task has no child chat yet."))?,
                    Some(task_id),
                )
            }
            (None, None) => return Err(HostError::format("taskId or chatId is required")),
        };
        let snapshot = self.runtime.snapshot(&chat_id).await?;
        let requests = snapshot
            .get("pendingRequests")
            .cloned()
            .unwrap_or_else(|| json!([]));
        Ok(json!({
            "requests": requests
                .as_array()
                .into_iter()
                .flatten()
                .map(|request| json!({"chatId": chat_id, "taskId": task_id, "request": request}))
                .collect::<Vec<_>>(),
        }))
    }

    pub(super) async fn respond(
        &self,
        chat_id: String,
        runtime_request_id: String,
        response: Value,
        request_id: String,
        payload: &Value,
        caller: &OrchestrationCaller,
    ) -> HostResult<Value> {
        if let Some(response) = self
            .check_receipt(caller, "respond", &request_id, payload)
            .await?
        {
            return Ok(response);
        }
        require_lineage_for_chat(caller, &self.store, &chat_id).await?;
        let operation = bound_control_operation(
            caller,
            ChatOp::Respond {
                runtime_request_id,
                response,
            },
        );
        let key = runtime_receipt_key(
            &caller.ctx.scope,
            "respond",
            &request_id,
            &chat_id,
            &operation,
        );
        let result = self
            .runtime
            .command(&chat_id, operation, caller.ctx.clone(), Some(key))
            .await?;
        self.record_receipt(caller, "respond", &request_id, payload, result.clone())
            .await?;
        Ok(result)
    }

    pub(super) async fn configure(
        &self,
        chat_id: String,
        request_id: String,
        input: ConfigureInput,
        payload: &Value,
        caller: &OrchestrationCaller,
    ) -> HostResult<Value> {
        if let Some(response) = self
            .check_receipt(caller, "configure", &request_id, payload)
            .await?
        {
            return Ok(response);
        }
        require_lineage_for_chat(caller, &self.store, &chat_id).await?;
        let _ = enforce_mode_ceiling(caller, input.runtime_mode.as_deref())?;
        let operation = bound_control_operation(caller, ChatOp::Configure(input));
        let key = runtime_receipt_key(
            &caller.ctx.scope,
            "configure",
            &request_id,
            &chat_id,
            &operation,
        );
        let result = self
            .runtime
            .command(&chat_id, operation, caller.ctx.clone(), Some(key))
            .await?;
        self.record_receipt(caller, "configure", &request_id, payload, result.clone())
            .await?;
        Ok(result)
    }
}

fn bound_control_operation(caller: &OrchestrationCaller, operation: ChatOp) -> ChatOp {
    if let Some(bound) = &caller.bound {
        ChatOp::WithinCeiling {
            runtime_mode_ceiling: bound.runtime_mode.clone(),
            operation: Box::new(operation),
        }
    } else {
        operation
    }
}

pub(super) fn task_launch_options(input: &DelegateInput) -> Value {
    let mut options = Map::new();
    if let Some(provider_instance_id) = &input.agent.provider_instance_id {
        options.insert("providerInstanceId".into(), json!(provider_instance_id));
    }
    if let Some(model) = &input.agent.model {
        options.insert("model".into(), json!(model));
    }
    if let Some(value) = &input.agent.options {
        options.insert("options".into(), value.clone());
    }
    if let Some(mode) = &input.runtime_mode {
        options.insert("runtimeMode".into(), json!(mode));
    }
    if let Some(mode) = &input.interaction_mode {
        options.insert("interactionMode".into(), json!(mode));
    }
    Value::Object(options)
}

pub(super) async fn cancel_requested_task(
    store: &alera_core::runtime::RuntimeStore,
    task_id: &str,
) -> HostResult<Option<alera_core::runtime::ChatOrchestrationTask>> {
    let task = store
        .chat_orchestration_task(task_id)
        .await
        .map_err(|error| HostError::state(error.to_string()))?;
    Ok(task.filter(|task| {
        task.status == ChatOrchestrationTaskStatus::CancelRequested
            || task.status == ChatOrchestrationTaskStatus::Cancelled
    }))
}
