use alera_core::runtime::{
    chat_orchestration_request_digest, ChatOrchestrationReceipt, ChatOrchestrationReceiptCheck,
};
use serde_json::{json, Value};

use crate::terminal_host::host_error::{HostError, HostResult};

use super::authorization::{require_lineage_for_task, OrchestrationCaller};
use super::service::ChatOrchestrationService;
use super::tasks::{task_value, task_value_for};

impl ChatOrchestrationService {
    pub(super) async fn task_request(
        &self,
        task_id: &str,
        acknowledge: bool,
        request_id: Option<&str>,
        caller: &OrchestrationCaller,
    ) -> HostResult<Value> {
        if !acknowledge {
            return task_value_for(&self.store, task_id).await;
        }
        require_lineage_for_task(caller, &self.store, task_id).await?;
        let payload = json!({"taskId": task_id, "acknowledge": true});
        if let Some(request_id) = request_id {
            if let Some(response) = self
                .check_receipt(caller, "task", request_id, &payload)
                .await?
            {
                return Ok(response);
            }
        }
        let before = self
            .store
            .chat_orchestration_task(task_id)
            .await
            .map_err(|error| HostError::state(error.to_string()))?
            .ok_or_else(|| HostError::conflict("task_not_found", "Task not found.", json!({})))?;
        if !before.status.is_terminal() {
            return Err(HostError::conflict(
                "task_not_settled",
                "Only a settled task result can be acknowledged.",
                json!({}),
            ));
        }
        let task = self
            .store
            .acknowledge_chat_orchestration_result(task_id)
            .await
            .map_err(|error| HostError::state(error.to_string()))?;
        let response = json!({"task": task_value(&task)});
        let response = if let Some(request_id) = request_id {
            let receipt = ChatOrchestrationReceipt {
                scope: caller.ctx.scope.clone(),
                verb: "task".into(),
                request_id: request_id.into(),
                digest: chat_orchestration_request_digest("task", &payload),
                response: response.clone(),
            };
            match self
                .store
                .record_chat_orchestration_receipt(Some(task_id), &receipt)
                .await
                .map_err(|error| HostError::state(error.to_string()))?
            {
                ChatOrchestrationReceiptCheck::New => response,
                ChatOrchestrationReceiptCheck::Replay(response) => response,
                ChatOrchestrationReceiptCheck::Conflict => {
                    return Err(HostError::conflict(
                        "request_conflict",
                        "This requestId was already used for a different request.",
                        json!({}),
                    ))
                }
            }
        } else {
            response
        };
        if task.result_delivery != before.result_delivery {
            self.emit_change(&task).await;
        }
        Ok(response)
    }
}
