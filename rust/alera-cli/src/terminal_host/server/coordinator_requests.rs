use alera_core::runtime::{
    OrchestrationCoordinatorStatus, OrchestrationGateStatus, OrchestrationMessageType,
    OrchestrationTaskStatus,
};
use serde_json::{json, Value};
use sha2::{Digest, Sha256};

use crate::terminal_host::host_error::{HostError, HostResult};
use crate::terminal_host::orchestration::agent_presence::AgentPresenceState;
use crate::terminal_host::orchestration::agent_registry::adapter_for;
use crate::terminal_host::orchestration::coordinator_loop::{
    acceptance_timeout_threshold_iso, hung_dispatch_threshold_iso, CoordinatorConfig,
    CoordinatorHandle, COORDINATOR_DEFAULT_POLL_MS, COORDINATOR_DISPATCH_STALE_THRESHOLD,
    COORDINATOR_MAX_CONCURRENT_DEFAULT,
};
use crate::terminal_host::orchestration::dispatch_preamble::{
    build_dispatch_preamble, parse_allow_stale_base_from_spec, BaseDrift, GateResolution,
    PreambleParams, WorkerKind,
};
use crate::terminal_host::orchestration::lifecycle_reconciliation::{
    reconcile_lifecycle_message, LifecycleReconciliation,
};
use crate::terminal_host::protocol::event;
use crate::terminal_host::session::Session;

use super::{ServerActor, ServerCommand};

const PENDING_WORKER_TAB_GRACE_SECONDS: i64 = 120;

fn state_error(error: impl std::fmt::Display) -> HostError {
    HostError::state(error.to_string())
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
                "no orchestration tasks exist; create tasks with task-create before run",
            ));
        }
        let run = self
            .runtime_store
            .create_scoped_orchestration_coordinator_run(
                spec,
                Some(&coordinator_handle),
                poll_interval_ms as i64,
                &workspace_id,
                max_concurrent as i64,
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
        Ok(json!({ "runId": run.id, "status": "running" }))
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
                ))
            }
        };
        let run_id = run_id.as_str();
        let run = self
            .runtime_store
            .orchestration_coordinator_run_by_id(run_id)
            .await
            .map_err(state_error)?
            .filter(|run| {
                matches!(
                    run.status,
                    OrchestrationCoordinatorStatus::Running
                        | OrchestrationCoordinatorStatus::Stopping
                )
            })
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

    // --- tick ---------------------------------------------------------------

    /// One coordinator tick, executed inside the actor. Order mirrors Orca:
    /// process messages -> re-assert gate blocks -> warn stale dispatches ->
    /// dispatch ready tasks -> check convergence.
    pub(super) async fn handle_coordinator_tick(&mut self, run_id: String) {
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
        if let Err(error) = self.coordinator_warn_stale_dispatches().await {
            self.coordinator_log(&format!("stale check failed: {error}"));
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

    /// Coordinator inbox: worker_done/heartbeat reconcile, escalations fail
    /// the dispatch (circuit breaker), decision_gate messages create gates.
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
                OrchestrationMessageType::WorkerDone | OrchestrationMessageType::Heartbeat => {
                    let mut sink = |line: String| logs.push(line);
                    let outcome =
                        reconcile_lifecycle_message(&self.runtime_store, message, &mut sink)
                            .await?;
                    match outcome {
                        LifecycleReconciliation::Completed { task_id, .. } => {
                            logs.push(format!("task {task_id} completed"));
                        }
                        LifecycleReconciliation::Failed { task_id, .. } => {
                            logs.push(format!("task {task_id} failed"));
                        }
                        _ => {}
                    }
                    true
                }
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
                                Ok(_) => logs.push(format!("gate created for task {task_id}")),
                                Err(error) => {
                                    logs.push(format!("gate for task {task_id} ignored: {error}"))
                                }
                            }
                        }
                        true
                    } else {
                        false
                    }
                    // Worker-side `ask` questions carry no taskId; they are
                    // answered by a human/agent via `reply`, not by gates.
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

    /// A dispatch with no runtime activity past the lease is stalled. It is
    /// never auto-retried, preventing two agents from doing the same work.
    async fn coordinator_warn_stale_dispatches(&mut self) -> anyhow::Result<()> {
        let acceptance_threshold = acceptance_timeout_threshold_iso(chrono::Utc::now());
        let unaccepted = self
            .runtime_store
            .expire_unaccepted_orchestration_dispatches(&acceptance_threshold)
            .await?;
        for dispatch in unaccepted {
            if let Some(handle) = dispatch.assignee_handle.as_deref() {
                self.remove_dispatch_context(handle);
                self.cleanup_failed_owned_spawn(handle).await;
            }
            self.coordinator_log(&format!(
                "dispatch {} did not accept before the startup deadline",
                dispatch.id
            ));
        }
        let threshold = hung_dispatch_threshold_iso(chrono::Utc::now());
        let stale = self
            .runtime_store
            .stall_expired_orchestration_dispatches(&threshold)
            .await?;
        for dispatch in stale {
            self.coordinator_log(&format!(
                "dispatch {} on {} exceeded its activity lease and is stalled since {}",
                dispatch.id,
                dispatch.assignee_handle.as_deref().unwrap_or("<unknown>"),
                dispatch
                    .last_heartbeat_at
                    .as_deref()
                    .or(dispatch.dispatched_at.as_deref())
                    .unwrap_or("dispatch")
            ));
            self.apply_stall_policy(&dispatch).await;
        }
        self.coordinator_process_stall_decisions().await?;
        Ok(())
    }

    async fn coordinator_policy_blocks_dispatch(&mut self, run_id: &str) -> anyhow::Result<bool> {
        let Some(run) = self
            .runtime_store
            .orchestration_coordinator_run_by_id(run_id)
            .await?
        else {
            return Ok(false);
        };
        Ok(run.execution_policy_status.blocks_dispatch())
    }

    async fn coordinator_dispatch_ready_tasks(
        &mut self,
        config: &CoordinatorConfig,
    ) -> anyhow::Result<()> {
        // A proposed but unresolved execution policy holds scheduling: the whole
        // point of the plan is that the user approves it before work starts. A
        // run with no policy is unaffected and schedules as it always did.
        if self
            .coordinator_policy_blocks_dispatch(&config.run_id)
            .await?
        {
            return Ok(());
        }
        let ready = self
            .runtime_store
            .list_scoped_orchestration_tasks(
                Some(OrchestrationTaskStatus::Ready),
                Some(&config.run_id),
                config.workspace_id.as_deref(),
            )
            .await?;
        if ready.is_empty() {
            return Ok(());
        }
        let occupied = self
            .runtime_store
            .list_scoped_orchestration_tasks(
                None,
                Some(&config.run_id),
                config.workspace_id.as_deref(),
            )
            .await?
            .into_iter()
            .filter(|task| {
                matches!(
                    task.status,
                    OrchestrationTaskStatus::Dispatched | OrchestrationTaskStatus::Stalled
                )
            })
            .count();
        let mut slots = config.max_concurrent.saturating_sub(occupied);
        if slots == 0 {
            return Ok(());
        }

        let mut idle_terminals = self.coordinator_available_terminals(config).await?;
        if idle_terminals.is_empty() {
            // One worker terminal per tick: the app spawns it eagerly and the
            // agent's presence appears before the next dispatch attempt.
            if self.coordinator_pending_worker_tabs(config).await? > 0 {
                self.coordinator_log("waiting for a spawned worker terminal to report presence");
                return Ok(());
            }
            self.coordinator_create_worker_terminal(config, &ready)
                .await?;
            return Ok(());
        }

        for task in ready {
            if slots == 0 || idle_terminals.is_empty() {
                break;
            }
            let handle = idle_terminals[0].clone();
            match self
                .coordinator_dispatch_task(config, &task.id, &handle)
                .await
            {
                Ok(true) => {
                    idle_terminals.remove(0);
                    slots -= 1;
                }
                Ok(false) => {}
                Err(error) => {
                    idle_terminals.remove(0);
                    self.coordinator_log(&format!("dispatch of {} failed: {error}", task.id));
                }
            }
        }
        Ok(())
    }

    /// Idle worker candidates: running sessions in the scoped workspace with
    /// injection-ready agent presence, no active dispatch, and not the
    /// coordinator's own terminal.
    async fn coordinator_available_terminals(
        &mut self,
        config: &CoordinatorConfig,
    ) -> anyhow::Result<Vec<String>> {
        let mut candidates = Vec::new();
        let session_ids: Vec<(String, String, bool)> = self
            .sessions
            .iter()
            .map(|(session_id, session)| {
                (
                    session_id.clone(),
                    session.workspace_id.clone(),
                    session.running(),
                )
            })
            .collect();
        for (session_id, workspace_id, running) in session_ids {
            if !running {
                continue;
            }
            if let Some(scope) = &config.workspace_id {
                if &workspace_id != scope {
                    continue;
                }
            }
            if config.coordinator_handle.as_deref() == Some(session_id.as_str()) {
                continue;
            }
            if !self.agent_presence.is_injection_ready(&session_id) {
                continue;
            }
            let busy = self
                .runtime_store
                .active_orchestration_dispatch_for_handle(&session_id)
                .await?
                .is_some();
            if !busy {
                candidates.push(session_id);
            }
        }
        Ok(candidates)
    }

    async fn coordinator_pending_worker_tabs(
        &self,
        config: &CoordinatorConfig,
    ) -> anyhow::Result<usize> {
        let Some(workspace_id) = &config.workspace_id else {
            return Ok(0);
        };
        let tabs = self.runtime_store.list_workspace_tabs(workspace_id).await?;
        let now = chrono::Utc::now();
        let mut pending = 0;
        for tab in tabs.into_iter().filter(|tab| tab.kind == "terminal") {
            let Some((handle, created_at)) = (|| {
                let fallback_id = tab.id;
                let created_at = tab.created_at;
                let payload = tab.payload.as_object()?;
                let is_spawned_worker = payload.get("spawnOnCreate").and_then(Value::as_bool)
                    == Some(true)
                    && payload.get("initialCommand").and_then(Value::as_str)
                        == adapter_for(&config.agent_type).map(|adapter| adapter.default_command);
                if !is_spawned_worker {
                    return None;
                }
                payload
                    .get("terminalSessionId")
                    .and_then(Value::as_str)
                    .filter(|handle| !handle.is_empty())
                    .map(str::to_string)
                    .or(Some(fallback_id))
                    .map(|handle| (handle, created_at))
            })() else {
                continue;
            };
            if now.signed_duration_since(created_at)
                > chrono::Duration::seconds(PENDING_WORKER_TAB_GRACE_SECONDS)
            {
                continue;
            }
            if !self
                .sessions
                .get(&handle)
                .is_some_and(|session| session.running())
            {
                pending += 1;
                continue;
            }
            let active_dispatch = self
                .runtime_store
                .active_orchestration_dispatch_for_handle(&handle)
                .await?
                .is_some();
            if active_dispatch {
                continue;
            }
            let Some(presence) = self.agent_presence.get(&handle) else {
                pending += 1;
                continue;
            };
            if presence.state.accepts_injection() {
                continue;
            }
            if presence.state == AgentPresenceState::Done {
                continue;
            }
            pending += 1;
        }
        Ok(pending)
    }

    /// Dispatch with the stale-base pre-flight: a drift beyond the threshold
    /// silently skips (task stays ready, retried next tick) so circuit budget
    /// is not burned on a recoverable fetch-and-retry situation.
    async fn coordinator_dispatch_task(
        &mut self,
        config: &CoordinatorConfig,
        task_id: &str,
        handle: &str,
    ) -> anyhow::Result<bool> {
        let Some(task) = self.runtime_store.orchestration_task_by_id(task_id).await? else {
            return Ok(false);
        };
        let Some((stripped_spec, drift)) = self.coordinator_dispatch_preflight(config, &task).await
        else {
            return Ok(false);
        };
        let gates = self
            .runtime_store
            .list_orchestration_gates(Some(task_id), Some(OrchestrationGateStatus::Resolved))
            .await?;
        let gate_resolution = gates.into_iter().last().map(|gate| GateResolution {
            question: gate.question,
            resolution: gate.resolution.unwrap_or_default(),
        });

        let context_token = uuid::Uuid::new_v4().simple().to_string();
        let context_hash = hex::encode(Sha256::digest(context_token.as_bytes()));
        let dispatch = self
            .runtime_store
            .create_scoped_orchestration_dispatch(
                task_id,
                handle,
                Some(&config.run_id),
                config.workspace_id.as_deref().unwrap_or("global"),
                config
                    .coordinator_handle
                    .as_deref()
                    .unwrap_or("coordinator"),
                Some(&context_hash),
                "return-immediately",
                "keep-open",
            )
            .await?;
        self.orchestration_activity_last_recorded.remove(handle);
        if let Err(error) = self.install_dispatch_context(handle, &dispatch.id, &context_token) {
            self.runtime_store
                .fail_orchestration_startup(&dispatch.id, "could not install worker context")
                .await?;
            return Err(anyhow::anyhow!(error.to_string()));
        }
        let preamble = build_dispatch_preamble(&PreambleParams {
            task_id,
            dispatch_id: &dispatch.id,
            task_spec: &stripped_spec,
            coordinator_handle: config
                .coordinator_handle
                .as_deref()
                .unwrap_or("coordinator"),
            base_drift: drift.as_ref(),
            gate_resolution: gate_resolution.as_ref(),
            worker_kind: WorkerKind::PromptReturningAgent,
        });
        if !self.sessions.get(handle).is_some_and(Session::running) {
            self.remove_dispatch_context(handle);
            self.runtime_store
                .fail_orchestration_startup(&dispatch.id, "terminal not writable")
                .await?;
            return Ok(false);
        }
        let force_submit =
            adapter_for(&config.agent_type).is_some_and(|adapter| adapter.force_submit);
        if let Err(error) =
            self.queue_orchestration_paste(handle, &preamble, Vec::new(), force_submit)
        {
            self.remove_dispatch_context(handle);
            self.runtime_store
                .fail_orchestration_startup(&dispatch.id, "terminal input unavailable")
                .await?;
            return Err(anyhow::anyhow!(error.wire_message()));
        }
        self.coordinator_log(&format!("dispatched {task_id} to {handle}"));
        Ok(true)
    }

    async fn coordinator_probe_drift(&self, config: &CoordinatorConfig) -> Option<BaseDrift> {
        let workspace_id = config.workspace_id.as_deref()?;
        let workspace = self
            .runtime_store
            .find_workspace(workspace_id)
            .await
            .ok()??;
        let path = workspace.path.clone();
        // git2 walks are blocking; run off the actor thread.
        let drift = tokio::task::spawn_blocking(move || {
            alera_core::git::probe_base_drift(&path).ok().flatten()
        })
        .await
        .ok()??;
        Some(BaseDrift {
            base: drift.base,
            behind: drift.behind,
            recent_subjects: drift.recent_subjects,
        })
    }

    pub(super) async fn coordinator_dispatch_preflight(
        &self,
        config: &CoordinatorConfig,
        task: &alera_core::runtime::OrchestrationTask,
    ) -> Option<(String, Option<BaseDrift>)> {
        let (allow_stale, stripped_spec) = parse_allow_stale_base_from_spec(&task.spec);
        let drift = self.coordinator_probe_drift(config).await;
        if let Some(drift) = &drift {
            if drift.behind > COORDINATOR_DISPATCH_STALE_THRESHOLD && !allow_stale {
                self.coordinator_log(&format!(
                    "worktree is {} commits behind {}; skipping dispatch of {} this tick",
                    drift.behind, drift.base, task.id
                ));
                return None;
            }
        }
        Some((stripped_spec, drift))
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
            return Ok(Some(OrchestrationCoordinatorStatus::Failed));
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
        eprintln!("[coordinator] {message}");
        self.broadcast_authenticated(event(
            "orchestrationCoordinatorLog",
            json!({ "message": message }),
        ));
    }
}
