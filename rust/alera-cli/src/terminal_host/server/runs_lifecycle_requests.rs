//! Run lifecycle mutations on the actor: create (with the coordinator
//! launch), gate resolution, control, and what every transition
//! must do afterwards (scheduling, coordinator loops, cancellation sweeps).

use alera_core::runtime::{
    AgentProfile, CreateRun, MessageDelivery, NewOrchestrationMessage,
    OrchestrationCoordinatorStatus, OrchestrationMessagePriority, OrchestrationMessageType,
    OrchestrationTaskStatus, ResolveRunGate, RetryRunCancellation, RunActor, RunControl,
    RunControlAction, RunCreated, RunIsolation, WorkflowCoordinatorReceipt,
};
use serde_json::{json, Value};

use crate::terminal_host::host_error::{HostError, HostResult};
use crate::terminal_host::orchestration::agent_registry::adapter_for;
use crate::terminal_host::orchestration::coordinator_loop::{CoordinatorConfig, CoordinatorHandle};
use crate::terminal_host::protocol::{error_response, ok_response};
use crate::terminal_host::session::Session;

use super::orchestration_gate_requests::gate_error;
use super::run_launch_requests::{WorkflowLaunchCommand, WorkflowLaunchPermit};
use super::runs_requests::parse;
use super::{ServerActor, ServerCommand};

/// The payload without the self-asserted MCP origin, which only picks the
/// actor and is never part of a stored request.
pub(super) fn request_payload(payload: &Value) -> Value {
    let mut payload = payload.clone();
    if let Some(map) = payload.as_object_mut() {
        map.remove("externalOrigin");
    }
    payload
}

pub(super) fn validate_profile(profile: &AgentProfile) -> anyhow::Result<()> {
    if adapter_for(&profile.agent_type).is_none() {
        anyhow::bail!("unsupported agent profile type: {}", profile.agent_type);
    }
    super::orchestration_profile_spawn::launch_for_profile(profile)
        .map_err(|_| anyhow::anyhow!("invalid agent profile launch configuration"))?;
    Ok(())
}

fn planning_prompt(run_id: &str, created: &RunCreated) -> String {
    let scope = match created.isolation {
        RunIsolation::Isolated => {
            "Follow the recipe's coordinator instructions and cover every recipe stage and role. Each task runs in its own worktree and its result integrates as a squash commit."
        }
        RunIsolation::Shared => {
            "Workers share this workspace. Declare the stages (with a profile each) and the tasks; after the plan is accepted, answer worker messages with `alera orchestration check` and `alera orchestration reply`."
        }
    };
    format!(
        "You coordinate Alera run {run_id}. Plan only: do not edit repository files and do not start workers yourself. Read the frozen run context with `alera orchestration --json plan context --run {run_id}`. Inspect the source without changing the checkout. {scope} Submit the plan as JSON with `alera orchestration plan propose --run {run_id} --stdin`, then end your turn."
    )
}

fn correction_prompt(run_id: &str) -> String {
    format!(
        "Changes were requested for Alera run {run_id}. Read the request and the prior results with `alera orchestration --json plan context --run {run_id}`, then submit a corrected plan with `alera orchestration plan propose --run {run_id} --stdin` and end your turn. Do not edit repository files and do not start workers yourself."
    )
}

impl ServerActor {
    pub(super) fn start_run_create(
        &mut self,
        client_id: u64,
        request_id: i64,
        payload: &Value,
        actor: RunActor,
    ) -> HostResult<()> {
        let request: CreateRun = parse(&request_payload(payload))?;
        if self.workflow_workspace_jobs >= 32 {
            return Err(HostError::state("runs are busy; retry shortly"));
        }
        self.workflow_workspace_jobs += 1;
        self.cancel_shutdown_timer();
        let store = self.runtime_store.clone();
        let inbox = self.inbox.clone();
        tokio::spawn(async move {
            let result = store
                .create_run(request, validate_profile, &actor)
                .await
                .map_err(gate_error);
            let _ = inbox
                .send_wait(ServerCommand::WorkflowLaunch(
                    WorkflowLaunchCommand::RunCreated {
                        client_id,
                        request_id,
                        result,
                    },
                ))
                .await;
        });
        Ok(())
    }

    pub(super) async fn handle_run_created(
        &mut self,
        client_id: u64,
        request_id: i64,
        result: HostResult<(RunCreated, bool)>,
    ) {
        self.workflow_workspace_jobs = self.workflow_workspace_jobs.saturating_sub(1);
        let response = match result {
            Ok((created, fresh)) => {
                let coordinator = if fresh {
                    let prompt = planning_prompt(&created.run_id, &created);
                    Some(self.launch_run_coordinator(&created.run_id, prompt).await)
                } else {
                    None
                };
                let coordinator = match coordinator {
                    Some(Err(error)) => {
                        tracing::warn!("run coordinator launch failed: {}", error.wire_message());
                        None
                    }
                    Some(Ok(receipt)) => Some(receipt),
                    None => self
                        .runtime_store
                        .workflow_coordinator(&created.run_id)
                        .await
                        .ok()
                        .flatten(),
                };
                ok_response(
                    request_id,
                    json!({ "run": created, "coordinator": coordinator }),
                )
            }
            Err(error) => error_response(request_id, &error),
        };
        self.client_write(client_id, response);
        self.broadcast_orchestration_board_change().await;
        self.schedule_shutdown_if_idle();
    }

    /// Starts the run's reserved coordinator terminal. A failed launch is
    /// recorded as coordinator attention on the run.
    pub(super) async fn launch_run_coordinator(
        &mut self,
        run_id: &str,
        prompt: String,
    ) -> HostResult<WorkflowCoordinatorReceipt> {
        let (profile, receipt) = self
            .runtime_store
            .run_coordinator_launch(run_id)
            .await
            .map_err(|error| HostError::state(error.to_string()))?;
        if receipt.status != "reserved" {
            return Ok(receipt);
        }
        let payload = json!({
            "workspaceId": receipt.workspace_id,
            "profileId": profile.id,
            "prompt": prompt,
        });
        let permit = WorkflowLaunchPermit::coordinator(receipt.clone());
        let result = self
            .launch_agent_profile_snapshot(
                None,
                &payload,
                Some((profile, receipt.tab_id.clone())),
                Some(&permit),
            )
            .await;
        let error = result.err().map(|error| {
            format!(
                "Coordinator launch failed: {}. Inspect its terminal, then request changes or cancel the run.",
                error.wire_message()
            )
        });
        self.runtime_store
            .settle_workflow_coordinator(run_id, &receipt.tab_id, error.as_deref())
            .await
            .map_err(|error| HostError::state(error.to_string()))
    }

    /// Hands a change request to the run's coordinator: a message when its
    /// terminal is running, otherwise a relaunch with the correction prompt.
    /// Returns `message`, `relaunch` or `none`.
    async fn nudge_run_coordinator(&mut self, run_id: &str) -> &'static str {
        let Ok(Some(run)) = self
            .runtime_store
            .orchestration_coordinator_run_by_id(run_id)
            .await
        else {
            return "none";
        };
        let handle = run
            .coordinator_tab_id
            .clone()
            .or(run.coordinator_handle.clone());
        let Some(handle) = handle else {
            return "none";
        };
        if self.sessions.get(&handle).is_some_and(Session::running) {
            let message = NewOrchestrationMessage {
                from_handle: "alera".into(),
                to_handle: handle.clone(),
                subject: "Changes requested".into(),
                body: correction_prompt(run_id),
                message_type: OrchestrationMessageType::Status,
                priority: OrchestrationMessagePriority::High,
                thread_id: None,
                payload: None,
                run_id: Some(run_id.into()),
                workspace_id: Some(run.workspace_id.clone()),
                task_id: None,
                dispatch_id: None,
                expires_at: None,
                reply_to_id: None,
                external_meta: None,
                delivery: MessageDelivery::TurnEnd,
            };
            if self
                .runtime_store
                .insert_orchestration_message(message)
                .await
                .is_ok()
            {
                self.deliver_after_send(&handle).await;
                return "message";
            }
            return "none";
        }
        if run.coordinator_tab_id.is_none() {
            return "none";
        }
        if self
            .runtime_store
            .reserve_run_coordinator_relaunch(run_id)
            .await
            .is_err()
        {
            return "none";
        }
        match self
            .launch_run_coordinator(run_id, correction_prompt(run_id))
            .await
        {
            Ok(_) => "relaunch",
            Err(_) => "none",
        }
    }

    pub(super) async fn runs_resolve_gate(
        &mut self,
        payload: &Value,
        actor: &RunActor,
    ) -> HostResult<Value> {
        let request: ResolveRunGate = parse(&request_payload(payload))?;
        let receipt = self
            .runtime_store
            .resolve_run_gate(&request, actor)
            .await
            .map_err(gate_error)?;
        let mut coordinator = "none";
        if let Some(run_id) = receipt.run_id.clone() {
            if receipt.changes_requested && !receipt.replayed {
                coordinator = self.nudge_run_coordinator(&run_id).await;
            }
            self.after_run_transition(&run_id).await;
        }
        let mut value =
            serde_json::to_value(&receipt).map_err(|error| HostError::state(error.to_string()))?;
        value["coordinatorAction"] = json!(coordinator);
        Ok(value)
    }

    pub(super) async fn runs_control(
        &mut self,
        payload: &Value,
        actor: &RunActor,
    ) -> HostResult<Value> {
        let request: RunControl = parse(&request_payload(payload))?;
        if request.action == RunControlAction::Cancel {
            self.interrupt_shared_run_tasks(&request.run_id, actor)
                .await?;
        }
        let receipt = self
            .runtime_store
            .control_run(&request, actor)
            .await
            .map_err(gate_error)?;
        let mut coordinator = "none";
        if receipt.changes_requested && !receipt.replayed {
            coordinator = self.nudge_run_coordinator(&request.run_id).await;
        }
        self.after_run_transition(&request.run_id).await;
        let mut value =
            serde_json::to_value(&receipt).map_err(|error| HostError::state(error.to_string()))?;
        value["coordinatorAction"] = json!(coordinator);
        Ok(value)
    }

    pub(super) async fn runs_retry_cancellation(
        &mut self,
        payload: &Value,
        actor: &RunActor,
    ) -> HostResult<Value> {
        let request: RetryRunCancellation = parse(&request_payload(payload))?;
        let receipt = self
            .runtime_store
            .retry_run_cancellation(&request, actor)
            .await
            .map_err(gate_error)?;
        self.after_run_transition(&request.run_id).await;
        serde_json::to_value(receipt).map_err(|error| HostError::state(error.to_string()))
    }

    /// Workers of a shared run are interrupted before the run is cancelled,
    /// the same way a coordinator's `runStop --cancel-active` does.
    async fn interrupt_shared_run_tasks(
        &mut self,
        run_id: &str,
        actor: &RunActor,
    ) -> HostResult<()> {
        let Some(run) = self
            .runtime_store
            .orchestration_coordinator_run_by_id(run_id)
            .await
            .map_err(|error| HostError::state(error.to_string()))?
        else {
            return Ok(());
        };
        if run.isolation == "isolated" {
            return Ok(());
        }
        let tasks = self
            .runtime_store
            .list_scoped_orchestration_tasks(None, Some(run_id), Some(&run.workspace_id))
            .await
            .map_err(|error| HostError::state(error.to_string()))?;
        for task in tasks.into_iter().filter(|task| {
            matches!(
                task.status,
                OrchestrationTaskStatus::Dispatched | OrchestrationTaskStatus::Stalled
            )
        }) {
            self.orchestration_task_cancel(&json!({
                "id": task.id,
                "reason": "The run was cancelled.",
                "actor": actor.label(),
                "force": true,
            }))
            .await?;
        }
        Ok(())
    }

    /// Brings the host in line with a run's new state: stops or starts its
    /// coordinator loop, wakes the isolated scheduler and the cancellation
    /// sweep, and tells every client.
    pub(super) async fn after_run_transition(&mut self, run_id: &str) {
        self.stop_coordinator_if_run_finished(run_id).await;
        let run = self
            .runtime_store
            .orchestration_coordinator_run_by_id(run_id)
            .await
            .ok()
            .flatten();
        if let Some(run) = run {
            let active = matches!(
                run.status,
                OrchestrationCoordinatorStatus::Running | OrchestrationCoordinatorStatus::Paused
            );
            if run.isolation == "isolated" {
                self.wake_workflow_execution();
            } else if active
                && run.coordinator_tab_id.is_some()
                && !self.coordinators.contains_key(run_id)
            {
                // Only runs whose coordinator the runtime launched get a loop
                // here; delegated runs schedule through their own dispatches.
                if let Some(handle) = run.coordinator_handle.clone() {
                    let agent_type = self
                        .runtime_store
                        .run_worker_agent_type(run_id)
                        .await
                        .ok()
                        .flatten()
                        .unwrap_or_else(|| "claude".to_string());
                    let config = CoordinatorConfig {
                        run_id: run.id.clone(),
                        coordinator_handle: Some(handle),
                        poll_interval_ms: run.poll_interval_ms.max(250) as u64,
                        max_concurrent: run.max_concurrent.max(1) as usize,
                        workspace_id: Some(run.workspace_id.clone()),
                        agent_type,
                    };
                    self.coordinators.insert(
                        run.id.clone(),
                        CoordinatorHandle::start(config, self.inbox.clone(), |run_id| {
                            ServerCommand::CoordinatorTick { run_id }
                        }),
                    );
                    self.cancel_shutdown_timer();
                }
            }
            if run.status == OrchestrationCoordinatorStatus::Cancelled {
                self.wake_workflow_cancellation();
            }
        }
        self.broadcast_orchestration_board_change().await;
    }

    /// One scheduling step for a run. An isolated run is advanced by the
    /// attempt scheduler; a shared run is scheduled by its coordinator tick,
    /// which proceeds only when this returns true.
    pub(super) async fn schedule_run(&mut self, run_id: &str) -> bool {
        let Ok(Some(run)) = self
            .runtime_store
            .orchestration_coordinator_run_by_id(run_id)
            .await
        else {
            return false;
        };
        if run.isolation == "isolated" {
            self.wake_workflow_execution();
            return false;
        }
        if run.status != OrchestrationCoordinatorStatus::Running {
            return false;
        }
        match self.runtime_store.open_due_stage_gates(run_id).await {
            Ok(opened) if !opened.is_empty() => {
                for gate_id in opened {
                    if let Ok(Some(gate)) =
                        self.runtime_store.orchestration_gate_by_id(&gate_id).await
                    {
                        self.queue_gate_push(&gate).await;
                    }
                }
                self.broadcast_orchestration_board_change().await;
                false
            }
            Ok(_) => true,
            Err(error) => {
                self.coordinator_log(&format!("stage gate check failed: {error}"));
                true
            }
        }
    }
}
