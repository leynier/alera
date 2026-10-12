use alera_core::runtime::{NewRunPlan, OrchestrationCoordinatorStatus, OrchestrationTaskStatus};
use serde_json::{json, Value};

use crate::terminal_host::host_error::{HostError, HostResult};
use crate::terminal_host::orchestration::agent_registry::adapter_for;
use crate::terminal_host::orchestration::coordinator_loop::{
    CoordinatorConfig, CoordinatorHandle, COORDINATOR_DEFAULT_POLL_MS,
    COORDINATOR_MAX_CONCURRENT_DEFAULT,
};

use super::orchestration_validation::{optional_string, require_string};
use super::{ServerActor, ServerCommand};

fn state_error(error: impl std::fmt::Display) -> HostError {
    HostError::state(error.to_string())
}

impl ServerActor {
    pub(super) async fn orchestration_run(&mut self, payload: &Value) -> HostResult<Value> {
        let spec = payload
            .get("spec")
            .and_then(Value::as_str)
            .map(str::trim)
            .filter(|value| !value.is_empty())
            .ok_or_else(|| HostError::format("spec is required."))?;
        let coordinator_handle = payload
            .get("from")
            .and_then(Value::as_str)
            .map(str::trim)
            .filter(|value| !value.is_empty())
            .map(str::to_string)
            .ok_or_else(|| HostError::format("from is required."))?;
        let deliveries = &self.orchestration_delivery_in_flight;
        if deliveries.contains(&coordinator_handle) {
            return Err(HostError::state("prompt delivery in flight; retry"));
        }
        let poll_interval_ms = payload
            .get("pollIntervalMs")
            .and_then(Value::as_u64)
            .unwrap_or(COORDINATOR_DEFAULT_POLL_MS);
        let max_concurrent = payload
            .get("maxConcurrent")
            .and_then(Value::as_u64)
            .map(|value| value.max(1) as usize)
            .unwrap_or(COORDINATOR_MAX_CONCURRENT_DEFAULT);
        let workspace_id = payload
            .get("workspace")
            .and_then(Value::as_str)
            .filter(|value| !value.is_empty())
            .map(str::to_string)
            .unwrap_or_else(|| "global".to_string());
        let agent_type = payload
            .get("agent")
            .and_then(Value::as_str)
            .unwrap_or("claude")
            .to_string();
        if adapter_for(&agent_type).is_none() {
            return Err(HostError::format(format!(
                "unsupported agent type: {agent_type}"
            )));
        }
        if self
            .coordinators
            .values()
            .any(|handle| handle.config.workspace_id.as_deref() == Some(workspace_id.as_str()))
        {
            return Err(HostError::state(format!(
                "a coordinator run is already active for workspace {workspace_id}"
            )));
        }
        // Decomposition is the caller's responsibility in v1: the coordinator
        // manages the DAG, it does not invent it.
        let tasks = self
            .runtime_store
            .list_scoped_orchestration_tasks(None, None, None)
            .await
            .map_err(state_error)?;
        if tasks.is_empty() {
            return Err(HostError::state(
                "no orchestration tasks exist; delegate tasks before run",
            ));
        }
        let approval_required = payload
            .get("approvalRequired")
            .and_then(Value::as_bool)
            .unwrap_or(false);
        let policy_plan = match payload.get("policy") {
            None | Some(Value::Null) => None,
            Some(policy) => Some(Self::policy_plan(policy)?),
        };
        let stall_policy = policy_plan
            .as_ref()
            .and_then(|plan| plan.stall_policy.clone())
            .unwrap_or_else(|| "ask".to_string());
        let run = self
            .runtime_store
            .create_planned_orchestration_coordinator_run(
                spec,
                Some(&coordinator_handle),
                poll_interval_ms as i64,
                &workspace_id,
                max_concurrent as i64,
                NewRunPlan {
                    approval_required,
                    stall_policy: &stall_policy,
                },
            )
            .await
            .map_err(state_error)?;
        let bound = self
            .runtime_store
            .bind_manual_tasks_to_run(&run.id, &workspace_id, &coordinator_handle)
            .await
            .map_err(state_error)?;
        if bound == 0 {
            self.runtime_store
                .finish_orchestration_coordinator_run(
                    &run.id,
                    OrchestrationCoordinatorStatus::Failed,
                )
                .await
                .map_err(state_error)?;
            return Err(HostError::state(
                "no unowned tasks in this workspace belong to the coordinator",
            ));
        }
        let config_handle = Some(coordinator_handle.clone());
        let config = CoordinatorConfig {
            run_id: run.id.clone(),
            coordinator_handle: Some(coordinator_handle),
            poll_interval_ms,
            max_concurrent,
            workspace_id: Some(workspace_id),
            agent_type,
        };
        self.coordinators.insert(
            run.id.clone(),
            CoordinatorHandle::start(config, self.inbox.clone(), |run_id| {
                ServerCommand::CoordinatorTick { run_id }
            }),
        );
        self.cancel_shutdown_timer();
        let mut status = run.status.as_str().to_string();
        if let Some(plan) = policy_plan {
            let actor = alera_core::runtime::RunActor::new(
                alera_core::runtime::RunActorKind::Agent,
                config_handle.clone(),
            );
            let mut plan = plan;
            plan.stall_policy = Some(stall_policy.clone());
            let stages = std::mem::take(&mut plan.stages);
            plan.stages = self.normalized_plan_stages(stages).await?;
            let proposed = self
                .runtime_store
                .propose_run_plan(&run.id, plan, &actor)
                .await
                .map_err(super::orchestration_gate_requests::gate_error)?;
            status = proposed.status.clone();
            if let Some(gate_id) = proposed.plan_gate_id.as_deref() {
                if let Ok(Some(gate)) = self.runtime_store.orchestration_gate_by_id(gate_id).await {
                    self.queue_gate_push(&gate).await;
                }
            }
        }
        self.broadcast_orchestration_board_change().await;
        Ok(json!({
            "runId": run.id,
            "status": status,
            "approvalRequired": run.approval_required,
            "stallPolicy": stall_policy,
        }))
    }

    pub(super) async fn orchestration_run_stop(&mut self, payload: &Value) -> HostResult<Value> {
        let requested_run_id = payload
            .get("id")
            .and_then(Value::as_str)
            .filter(|value| !value.is_empty())
            .map(str::to_string);
        let run_id = match requested_run_id {
            Some(id) => id,
            None if self.coordinators.len() == 1 => {
                self.coordinators.keys().next().cloned().unwrap()
            }
            None => {
                return Err(HostError::format(
                    "id is required when zero or multiple runs are active.",
                ));
            }
        };
        let run_id = run_id.as_str();
        let run = self
            .runtime_store
            .orchestration_coordinator_run_by_id(run_id)
            .await
            .map_err(state_error)?
            .filter(|run| run.holds_workspace())
            .ok_or_else(|| HostError::state(format!("coordinator run is not active: {run_id}")))?;
        let actor = payload
            .get("actor")
            .and_then(Value::as_str)
            .filter(|value| !value.is_empty());
        let force = payload
            .get("force")
            .and_then(Value::as_bool)
            .unwrap_or(false);
        if !force && actor != run.coordinator_handle.as_deref() {
            return Err(HostError::state(format!(
                "only coordinator {} can stop run {run_id}; use --force for audited recovery",
                run.coordinator_handle.as_deref().unwrap_or("<unassigned>")
            )));
        }
        let handle = self.coordinators.remove(run_id);
        if let Some(handle) = handle.as_ref() {
            handle.stop();
        }
        let config_workspace = Some(run.workspace_id.clone());
        let reason = payload
            .get("reason")
            .and_then(Value::as_str)
            .unwrap_or("coordinator stopped");
        if payload
            .get("cancelActive")
            .and_then(Value::as_bool)
            .unwrap_or(false)
        {
            let tasks = self
                .runtime_store
                .list_scoped_orchestration_tasks(None, Some(run_id), config_workspace.as_deref())
                .await
                .map_err(state_error)?;
            for task in tasks.into_iter().filter(|task| {
                matches!(
                    task.status,
                    OrchestrationTaskStatus::Dispatched | OrchestrationTaskStatus::Stalled
                )
            }) {
                self.orchestration_task_cancel(&json!({
                    "id": task.id,
                    "reason": reason,
                    "actor": actor,
                    "force": force,
                }))
                .await?;
            }
        }
        self.runtime_store
            .stop_orchestration_coordinator_run(run_id, reason)
            .await
            .map_err(state_error)?;
        self.runtime_store
            .insert_orchestration_audit_event(
                actor,
                if force { "run.stop.force" } else { "run.stop" },
                run_id,
                reason,
            )
            .await
            .map_err(state_error)?;
        self.schedule_shutdown_if_idle();
        Ok(json!({ "runId": run_id, "status": "stopped" }))
    }

    pub(super) async fn orchestration_run_list(&mut self, payload: &Value) -> HostResult<Value> {
        let runs = self
            .runtime_store
            .list_orchestration_coordinator_runs(optional_string(payload, "workspace").as_deref())
            .await
            .map_err(state_error)?;
        Ok(
            json!({ "kind": "runs", "items": runs, "runs": runs, "filters": { "workspace": optional_string(payload, "workspace") } }),
        )
    }

    pub(super) async fn orchestration_run_show(&mut self, payload: &Value) -> HostResult<Value> {
        let id = require_string(payload, "id")?;
        let run = self
            .runtime_store
            .orchestration_coordinator_run_by_id(&id)
            .await
            .map_err(state_error)?
            .ok_or_else(|| HostError::state(format!("coordinator run not found: {id}")))?;
        let tasks = self
            .runtime_store
            .list_scoped_orchestration_tasks(None, Some(&id), Some(&run.workspace_id))
            .await
            .map_err(state_error)?;
        Ok(json!({ "run": run, "tasks": tasks }))
    }

    pub(super) async fn orchestration_status(&mut self, payload: &Value) -> HostResult<Value> {
        let id = require_string(payload, "id")?;
        let run = self
            .runtime_store
            .orchestration_coordinator_run_by_id(&id)
            .await
            .map_err(state_error)?
            .ok_or_else(|| HostError::state(format!("coordinator run not found: {id}")))?;
        let tasks = self
            .runtime_store
            .list_scoped_orchestration_tasks(None, Some(&id), Some(&run.workspace_id))
            .await
            .map_err(state_error)?;
        let mut run_handles = tasks
            .iter()
            .filter_map(|task| task.assignee_handle.as_deref())
            .collect::<std::collections::HashSet<_>>();
        if let Some(coordinator_handle) = run.coordinator_handle.as_deref() {
            run_handles.insert(coordinator_handle);
        }
        let terminals = self.orchestration_terminals(&json!({}))["items"]
            .as_array()
            .into_iter()
            .flatten()
            .filter(|terminal| {
                terminal.get("workspaceId").and_then(Value::as_str)
                    == Some(run.workspace_id.as_str())
                    && terminal
                        .get("handle")
                        .and_then(Value::as_str)
                        .is_some_and(|handle| run_handles.contains(handle))
            })
            .cloned()
            .collect::<Vec<_>>();
        let active = tasks
            .iter()
            .filter(|task| {
                matches!(
                    task.status,
                    OrchestrationTaskStatus::Dispatched | OrchestrationTaskStatus::Stalled
                )
            })
            .count();
        Ok(json!({
            "run": run,
            "tasks": tasks,
            "terminals": terminals,
            "activeTaskCount": active,
            "lastActivityAt": run.last_activity_at,
        }))
    }
}
