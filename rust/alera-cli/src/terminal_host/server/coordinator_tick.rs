//! The coordinator loop tick: inbound messages, gate blocks and convergence.

use alera_core::runtime::{
    OrchestrationCoordinatorStatus, OrchestrationGateStatus, OrchestrationMessageType,
    OrchestrationTaskStatus,
};
use serde_json::{json, Value};

use crate::terminal_host::orchestration::coordinator_loop::CoordinatorConfig;
use crate::terminal_host::protocol::event;

use super::ServerActor;

impl ServerActor {
    /// One coordinator tick, executed inside the actor. Order mirrors Orca:
    /// process messages -> re-assert gate blocks -> dispatch ready tasks ->
    /// check convergence. Startup deadlines and activity leases run on the
    /// host-wide lease sweep, not here.
    pub(super) async fn handle_coordinator_tick(&mut self, run_id: String) {
        if self.mutation_queue.has_runtime_mutations() {
            return;
        }
        self.stop_coordinator_if_run_finished(&run_id).await;
        let Some(handle) = self.coordinators.get(&run_id) else {
            return;
        };
        let config = handle.config.clone();

        if let Err(error) = self.coordinator_process_messages(&config).await {
            self.coordinator_log(&format!("message processing failed: {error}"));
        }
        if let Err(error) = self.coordinator_assert_gate_blocks().await {
            self.coordinator_log(&format!("gate check failed: {error}"));
        }
        // Only a running run schedules work or converges; planning, approval
        // and pauses hold it with its tasks untouched.
        if !self.schedule_run(&run_id).await {
            return;
        }
        if let Err(error) = self.coordinator_dispatch_ready_tasks(&config).await {
            self.coordinator_log(&format!("dispatch failed: {error}"));
        }
        match self.coordinator_check_convergence(&config).await {
            Ok(Some(final_status)) => {
                let _ = self
                    .runtime_store
                    .finish_orchestration_coordinator_run(&run_id, final_status)
                    .await;
                if let Some(handle) = self.coordinators.remove(&run_id) {
                    handle.stop();
                }
                self.coordinator_log(&format!(
                    "coordinator run {run_id} finished: {}",
                    final_status.as_str()
                ));
                self.schedule_shutdown_if_idle();
            }
            Ok(None) => {}
            Err(error) => self.coordinator_log(&format!("convergence check failed: {error}")),
        }
    }

    /// Coordinator inbox: escalations fail the dispatch (circuit breaker), and
    /// explicit `send --type decision_gate` messages naming a task create
    /// gates. Questions (`ask`) are left for the coordinator to answer.
    async fn coordinator_process_messages(
        &mut self,
        config: &CoordinatorConfig,
    ) -> anyhow::Result<()> {
        let Some(coordinator_handle) = &config.coordinator_handle else {
            return Ok(());
        };
        let messages = self
            .runtime_store
            .unread_orchestration_coordinator_messages(coordinator_handle)
            .await?;
        if messages.is_empty() {
            return Ok(());
        }
        let mut logs = Vec::new();
        let mut read_ids = Vec::new();
        for message in &messages {
            let mark_read = match message.message_type {
                OrchestrationMessageType::Escalation => {
                    logs.push(format!(
                        "escalation from {}: {}",
                        message.from_handle, message.subject
                    ));
                    let payload = payload_value(message);
                    let task_id = message
                        .task_id
                        .clone()
                        .or_else(|| payload_string(payload.as_ref(), "taskId"));
                    let dispatch_id = message
                        .dispatch_id
                        .clone()
                        .or_else(|| payload_string(payload.as_ref(), "dispatchId"));
                    if let Some(task_id) = task_id {
                        if let Some(dispatch) = self
                            .runtime_store
                            .active_orchestration_dispatch_for_task(&task_id)
                            .await?
                        {
                            let assignee_matches = dispatch.assignee_handle.as_deref()
                                == Some(message.from_handle.as_str());
                            let dispatch_matches =
                                dispatch_id.as_deref() == Some(dispatch.id.as_str());
                            if !assignee_matches || !dispatch_matches {
                                logs.push(format!("stale escalation for task {task_id} ignored"));
                            } else {
                                let failed = self
                                    .runtime_store
                                    .fail_orchestration_dispatch(&dispatch.id, &message.subject)
                                    .await?;
                                logs.push(format!(
                                    "dispatch {} failed ({} failures)",
                                    failed.id, failed.failure_count
                                ));
                            }
                        }
                    }
                    true
                }
                OrchestrationMessageType::DecisionGate => {
                    let payload = payload_value(message);
                    let task_id = message
                        .task_id
                        .clone()
                        .or_else(|| payload_string(payload.as_ref(), "taskId"));
                    let dispatch_id = message
                        .dispatch_id
                        .clone()
                        .or_else(|| payload_string(payload.as_ref(), "dispatchId"));
                    if let Some(task_id) = task_id {
                        let question = payload
                            .as_ref()
                            .and_then(|value| value.get("question").and_then(Value::as_str))
                            .unwrap_or(&message.subject)
                            .to_string();
                        let active = self
                            .runtime_store
                            .active_orchestration_dispatch_for_task(&task_id)
                            .await?;
                        let sender_owns_active_dispatch = active.as_ref().is_some_and(|dispatch| {
                            dispatch.assignee_handle.as_deref()
                                == Some(message.from_handle.as_str())
                                && dispatch_id.as_deref() == Some(dispatch.id.as_str())
                        });
                        if !sender_owns_active_dispatch {
                            logs.push(format!("stale decision gate for task {task_id} ignored"));
                        } else {
                            match self
                                .runtime_store
                                .create_orchestration_gate(&task_id, &question, &[])
                                .await
                            {
                                Ok(gate) => {
                                    logs.push(format!("gate created for task {task_id}"));
                                    self.queue_gate_push(&gate).await;
                                }
                                Err(error) => {
                                    logs.push(format!("gate for task {task_id} ignored: {error}"))
                                }
                            }
                        }
                        true
                    } else {
                        false
                    }
                }
                _ => false,
            };
            if mark_read {
                read_ids.push(message.id.clone());
            }
        }
        if !read_ids.is_empty() {
            self.runtime_store
                .mark_orchestration_messages_read(&read_ids)
                .await?;
        }
        for line in logs {
            self.coordinator_log(&line);
        }
        Ok(())
    }

    /// Invariant: a task with a pending gate stays blocked.
    async fn coordinator_assert_gate_blocks(&mut self) -> anyhow::Result<()> {
        let pending_gates = self
            .runtime_store
            .list_orchestration_gates(None, Some(OrchestrationGateStatus::Pending))
            .await?;
        for gate in pending_gates {
            if let Some(task) = self
                .runtime_store
                .orchestration_task_by_id(&gate.task_id)
                .await?
            {
                // A stalled task keeps its status while its stall gate is
                // pending. Flipping it to blocked would close the dispatch and
                // claim the worker stopped, which is exactly what a stall
                // cannot assert.
                if task.status != OrchestrationTaskStatus::Blocked
                    && task.status != OrchestrationTaskStatus::Completed
                    && task.status != OrchestrationTaskStatus::Failed
                    && task.status != OrchestrationTaskStatus::Cancelled
                    && task.status != OrchestrationTaskStatus::Stalled
                {
                    let _ = self
                        .runtime_store
                        .update_orchestration_task_status(
                            &task.id,
                            OrchestrationTaskStatus::Blocked,
                            None,
                        )
                        .await;
                }
            }
        }
        Ok(())
    }

    /// Done when every task is completed or failed. Stuck (only blocked left)
    /// keeps the loop alive but logs the situation.
    async fn coordinator_check_convergence(
        &mut self,
        config: &CoordinatorConfig,
    ) -> anyhow::Result<Option<OrchestrationCoordinatorStatus>> {
        let tasks = self
            .runtime_store
            .list_scoped_orchestration_tasks(
                None,
                Some(&config.run_id),
                config.workspace_id.as_deref(),
            )
            .await?;
        if tasks.is_empty() {
            // A run whose coordinator the runtime launched may still be
            // adding tasks to a stage-only plan.
            let launched = self
                .runtime_store
                .orchestration_coordinator_run_by_id(&config.run_id)
                .await?
                .is_some_and(|run| run.coordinator_tab_id.is_some());
            return Ok((!launched).then_some(OrchestrationCoordinatorStatus::Failed));
        }
        let all_terminal = tasks.iter().all(|task| {
            matches!(
                task.status,
                OrchestrationTaskStatus::Completed
                    | OrchestrationTaskStatus::Failed
                    | OrchestrationTaskStatus::Cancelled
            )
        });
        if all_terminal {
            let any_failed = tasks
                .iter()
                .any(|task| task.status == OrchestrationTaskStatus::Failed);
            return Ok(Some(if any_failed {
                OrchestrationCoordinatorStatus::Failed
            } else {
                OrchestrationCoordinatorStatus::Completed
            }));
        }
        let has_actionable = tasks.iter().any(|task| {
            matches!(
                task.status,
                OrchestrationTaskStatus::Ready | OrchestrationTaskStatus::Dispatched
            )
        });
        if !has_actionable {
            if tasks
                .iter()
                .any(|task| task.status == OrchestrationTaskStatus::Blocked)
            {
                self.coordinator_log(
                    "coordinator stuck: blocked tasks remain; resolve decision gates to continue",
                );
            } else if tasks
                .iter()
                .any(|task| task.status == OrchestrationTaskStatus::Stalled)
            {
                self.coordinator_log(
                    "coordinator waiting: stalled tasks require explicit recovery",
                );
            } else {
                self.coordinator_log(
                    "coordinator run failed: pending tasks have no active dependencies",
                );
                return Ok(Some(OrchestrationCoordinatorStatus::Failed));
            }
        }
        Ok(None)
    }

    pub(super) fn coordinator_log(&self, message: &str) {
        tracing::info!("[coordinator] {message}");
        self.broadcast_authenticated(event(
            "orchestrationCoordinatorLog",
            json!({ "message": message }),
        ));
    }
}

fn payload_value(message: &alera_core::runtime::OrchestrationMessage) -> Option<Value> {
    message
        .payload
        .as_deref()
        .and_then(|payload| serde_json::from_str::<Value>(payload).ok())
}

fn payload_string(payload: Option<&Value>, key: &str) -> Option<String> {
    payload?
        .get(key)
        .and_then(Value::as_str)
        .filter(|value| !value.is_empty())
        .map(str::to_string)
}
