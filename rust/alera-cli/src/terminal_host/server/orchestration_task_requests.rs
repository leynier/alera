//! Task reads and task-level control: list, show, cancel, recover and
//! coordinator transfer.

use alera_core::runtime::{
    MessageDelivery, NewOrchestrationMessage, OrchestrationMessagePriority,
    OrchestrationMessageType, OrchestrationTaskStatus,
};
use serde_json::{json, Value};

use crate::terminal_host::host_error::{HostError, HostResult};
use crate::terminal_host::orchestration::agent_registry::adapter_for;

use super::orchestration_validation::{optional_string, require_string, state_error};
use super::ServerActor;

impl ServerActor {
    pub(super) async fn orchestration_task_list(&mut self, payload: &Value) -> HostResult<Value> {
        let status = match optional_string(payload, "status") {
            None => None,
            Some(raw) => Some(
                OrchestrationTaskStatus::parse(&raw)
                    .ok_or_else(|| HostError::format(format!("unknown task status: {raw}")))?,
            ),
        };
        let tasks = self
            .runtime_store
            .list_scoped_orchestration_tasks(
                status,
                optional_string(payload, "run").as_deref(),
                optional_string(payload, "workspace").as_deref(),
            )
            .await
            .map_err(state_error)?;
        Ok(json!({
            "kind": "tasks",
            "items": tasks,
            "tasks": tasks,
            "filters": {
                "status": optional_string(payload, "status"),
                "run": optional_string(payload, "run"),
                "workspace": optional_string(payload, "workspace"),
            }
        }))
    }

    pub(super) async fn orchestration_task_show(&mut self, payload: &Value) -> HostResult<Value> {
        let id = require_string(payload, "id")?;
        let task = self
            .runtime_store
            .orchestration_task_by_id(&id)
            .await
            .map_err(state_error)?
            .ok_or_else(|| HostError::state(format!("orchestration task not found: {id}")))?;
        let dispatch = self
            .runtime_store
            .active_orchestration_dispatch_for_task(&id)
            .await
            .map_err(state_error)?;
        Ok(json!({ "task": task, "activeDispatch": dispatch }))
    }

    pub(super) async fn orchestration_task_cancel(&mut self, payload: &Value) -> HostResult<Value> {
        let id = require_string(payload, "id")?;
        let reason = require_string(payload, "reason")?;
        let actor = optional_string(payload, "actor");
        let force = payload
            .get("force")
            .and_then(Value::as_bool)
            .unwrap_or(false);
        let existing_task = self
            .runtime_store
            .orchestration_task_by_id(&id)
            .await
            .map_err(state_error)?
            .ok_or_else(|| HostError::state(format!("orchestration task not found: {id}")))?;
        if !force && actor.as_deref() != Some(existing_task.coordinator_handle.as_str()) {
            return Err(HostError::state(format!(
                "only coordinator {} can cancel task {id}; use --force for audited recovery",
                existing_task.coordinator_handle
            )));
        }
        let active = self
            .runtime_store
            .active_orchestration_dispatch_for_task(&id)
            .await
            .map_err(state_error)?;
        let task = self
            .runtime_store
            .cancel_orchestration_task(&id, &reason)
            .await
            .map_err(state_error)?;
        self.runtime_store
            .insert_orchestration_audit_event(
                actor.as_deref(),
                if force {
                    "task.cancel.force"
                } else {
                    "task.cancel"
                },
                &id,
                &reason,
            )
            .await
            .map_err(state_error)?;
        if let Some(dispatch) = active {
            if let Some(assignee) = dispatch.assignee_handle {
                self.remove_dispatch_context(&assignee);
                let message = self
                    .runtime_store
                    .insert_orchestration_message(NewOrchestrationMessage {
                        from_handle: task.coordinator_handle.clone(),
                        to_handle: assignee.clone(),
                        subject: "Task Cancelled".to_string(),
                        body: reason.clone(),
                        message_type: OrchestrationMessageType::Status,
                        priority: OrchestrationMessagePriority::Urgent,
                        thread_id: None,
                        payload: None,
                        run_id: task.run_id.clone(),
                        workspace_id: Some(task.workspace_id.clone()),
                        task_id: Some(task.id.clone()),
                        dispatch_id: Some(dispatch.id),
                        expires_at: None,
                        reply_to_id: None,
                        external_meta: None,
                        delivery: MessageDelivery::TurnEnd,
                    })
                    .await
                    .map_err(state_error)?;
                if self.agent_presence.is_injection_ready(&assignee) {
                    self.deliver_pending_messages(&assignee).await;
                } else if let Some(agent_type) = self.agent_presence.agent_type(&assignee) {
                    if let Some(adapter) = adapter_for(agent_type) {
                        let _ =
                            self.queue_orchestration_control(&assignee, adapter.interrupt_bytes);
                    }
                }
                return Ok(json!({ "task": task, "cancellationMessage": message }));
            }
        }
        Ok(json!({ "task": task }))
    }

    pub(super) async fn orchestration_task_recover(
        &mut self,
        payload: &Value,
    ) -> HostResult<Value> {
        let id = require_string(payload, "id")?;
        let status_raw = require_string(payload, "status")?;
        let status = OrchestrationTaskStatus::parse(&status_raw)
            .ok_or_else(|| HostError::format(format!("unknown task status: {status_raw}")))?;
        let reason = require_string(payload, "reason")?;
        let actor = optional_string(payload, "actor");
        let force = payload
            .get("force")
            .and_then(Value::as_bool)
            .unwrap_or(false);
        let existing_task = self
            .runtime_store
            .orchestration_task_by_id(&id)
            .await
            .map_err(state_error)?
            .ok_or_else(|| HostError::state(format!("orchestration task not found: {id}")))?;
        if !force && actor.as_deref() != Some(existing_task.coordinator_handle.as_str()) {
            return Err(HostError::state(format!(
                "only coordinator {} can recover task {id}; use --force for audited recovery",
                existing_task.coordinator_handle
            )));
        }
        let task = self
            .runtime_store
            .recover_stalled_orchestration_task(&id, status, actor.as_deref(), &reason, force)
            .await
            .map_err(state_error)?;
        Ok(json!({ "task": task }))
    }

    pub(super) async fn orchestration_transfer_coordinator(
        &mut self,
        payload: &Value,
    ) -> HostResult<Value> {
        let actor = optional_string(payload, "actor")
            .ok_or_else(|| HostError::format("actor is required."))?;
        let to = require_string(payload, "to")?;
        let reason = require_string(payload, "reason")?;
        let force = payload
            .get("force")
            .and_then(Value::as_bool)
            .unwrap_or(false);
        match (
            optional_string(payload, "task"),
            optional_string(payload, "run"),
        ) {
            (Some(task_id), None) => {
                let task = self
                    .runtime_store
                    .orchestration_task_by_id(&task_id)
                    .await
                    .map_err(state_error)?
                    .ok_or_else(|| {
                        HostError::state(format!("orchestration task not found: {task_id}"))
                    })?;
                if let Some(run_id) = task.run_id {
                    return Err(HostError::state(format!(
                        "task {task_id} belongs to run {run_id}; transfer the run instead"
                    )));
                }
                let task = self
                    .runtime_store
                    .transfer_orchestration_task_coordinator(&task_id, &actor, &to, &reason, force)
                    .await
                    .map_err(state_error)?;
                Ok(json!({ "task": task }))
            }
            (None, Some(run_id)) => {
                let run = self
                    .runtime_store
                    .transfer_orchestration_run_coordinator(&run_id, &actor, &to, &reason, force)
                    .await
                    .map_err(state_error)?;
                if let Some(handle) = self.coordinators.get_mut(&run_id) {
                    handle.config.coordinator_handle = Some(to);
                }
                Ok(json!({ "run": run }))
            }
            _ => Err(HostError::format("exactly one of task or run is required.")),
        }
    }
}
