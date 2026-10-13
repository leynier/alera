//! Manual dispatch of a task to a terminal, its inspection and interruption,
//! and what happens to the worker terminal once the task completes.

use alera_core::runtime::{OrchestrationDispatchStatus, OrchestrationGateStatus};
use serde_json::{json, Value};

use crate::terminal_host::host_error::{HostError, HostResult};
use crate::terminal_host::orchestration::agent_registry::adapter_for;
use crate::terminal_host::orchestration::dispatch_preamble::{
    build_dispatch_bootstrap, build_dispatch_preamble, parse_allow_stale_base_from_spec,
    GateResolution, PreambleParams, WorkerKind,
};

use super::orchestration_validation::{optional_string, require_string, state_error};
use super::orchestration_worker_requests::context_token_hash;
use super::ServerActor;

impl ServerActor {
    pub(super) async fn orchestration_dispatch(&mut self, payload: &Value) -> HostResult<Value> {
        let task_id = require_string(payload, "task")?;
        self.runtime_store
            .ensure_terminal_dispatch_allowed(&task_id)
            .await
            .map_err(state_error)?;
        let to = require_string(payload, "to")?;
        let from = require_string(payload, "from")?;
        let inject = payload
            .get("inject")
            .and_then(Value::as_bool)
            .unwrap_or(false);
        let dry_run = payload
            .get("dryRun")
            .and_then(Value::as_bool)
            .unwrap_or(false);
        let return_preamble = payload
            .get("returnPreamble")
            .and_then(Value::as_bool)
            .unwrap_or(false);
        let assume_agent = optional_string(payload, "assumeAgent");
        let assumed_adapter = assume_agent
            .as_deref()
            .map(|agent| {
                adapter_for(agent)
                    .ok_or_else(|| HostError::format(format!("unsupported agent type: {agent}")))
            })
            .transpose()?;
        let allow_self_dispatch = payload
            .get("allowSelfDispatch")
            .and_then(Value::as_bool)
            .unwrap_or(false);
        if from == to && !allow_self_dispatch {
            return Err(HostError::state(format!(
                "self_dispatch_requires_opt_in: from and to both resolve to {to}; pass --allow-self-dispatch for a deliberate protocol test"
            )));
        }

        let task = self
            .runtime_store
            .orchestration_task_by_id(&task_id)
            .await
            .map_err(state_error)?
            .ok_or_else(|| HostError::state(format!("orchestration task not found: {task_id}")))?;
        let (_allow_stale, stripped_spec) = parse_allow_stale_base_from_spec(&task.spec);
        let (profile_name, effective_spec) = self
            .compose_orchestration_prompt(&task, &stripped_spec, payload)
            .await?;
        if from != task.coordinator_handle {
            return Err(HostError::state(format!(
                "coordinator ownership conflict: task is owned by {}, not {from}",
                task.coordinator_handle
            )));
        }
        let gate_resolution = self.latest_resolved_gate(&task_id).await?;

        if dry_run {
            // Builds the preamble without mutating any state; the dispatch id
            // is a placeholder that a real dispatch will replace.
            let preamble = build_dispatch_preamble(&PreambleParams {
                task_id: &task_id,
                dispatch_id: "ctx_dryrun",
                task_spec: &effective_spec,
                coordinator_handle: &from,
                base_drift: None,
                gate_resolution: gate_resolution.as_ref(),
                worker_kind: WorkerKind::BareShell,
            });
            return Ok(json!({ "dryRun": true, "preamble": preamble }));
        }

        if inject {
            // Refuse to dump a preamble into a bare shell: injection requires
            // a recognized agent to be running in the target terminal.
            // Stable `stale_terminal_handle:` prefix is matched by recovery docs
            // and agents re-listing terminals after PTY death.
            let Some(session) = self.sessions.get(&to) else {
                return Err(HostError::state(format!(
                    "stale_terminal_handle: terminal {to} not found; remint the PTY \
                     (reopen the tab) or dispatch to a live handle from `terminal list`"
                )));
            };
            if !session.running() {
                return Err(HostError::state(format!(
                    "stale_terminal_handle: terminal {to} is not running; remint the PTY \
                     (reopen the tab) or dispatch to a live handle from `terminal list`"
                )));
            }
            if session.workspace_id != task.workspace_id {
                return Err(HostError::state(format!(
                    "terminal {to} belongs to workspace {}, not task workspace {}",
                    session.workspace_id, task.workspace_id
                )));
            }
            if self.agent_presence.get(&to).is_none() && assumed_adapter.is_none() {
                return Err(HostError::state(format!(
                    "no agent detected in terminal {to}; use --assume-agent <agent> for an audited injection override or dispatch without --inject and submit the returned bootstrap manually"
                )));
            }
            if !self.agent_presence.is_injection_ready(&to) && assumed_adapter.is_none() {
                return Err(HostError::state(format!(
                    "agent in terminal {to} is not idle; cannot inject"
                )));
            }
        }

        let context_token = uuid::Uuid::new_v4().simple().to_string();
        let context_hash = context_token_hash(&context_token);
        let dispatch = self
            .runtime_store
            .create_scoped_orchestration_dispatch(
                &task_id,
                &to,
                task.run_id.as_deref(),
                &task.workspace_id,
                &task.coordinator_handle,
                Some(&context_hash),
                optional_string(payload, "terminalPolicy")
                    .as_deref()
                    .unwrap_or("keep-open"),
            )
            .await
            .map_err(state_error)?;
        // Recorded even when null so `task show` always reports how the worker
        // was launched, and so fallback selection can read the attempt history.
        self.runtime_store
            .set_orchestration_dispatch_profile(
                &dispatch.id,
                profile_name.as_deref(),
                optional_string(payload, "agentQuotaGroup").as_deref(),
            )
            .await
            .map_err(state_error)?;
        if let Some(adapter) = assumed_adapter {
            self.runtime_store
                .insert_orchestration_audit_event(
                    Some(&from),
                    "dispatch.inject.assume_agent",
                    &dispatch.id,
                    &format!(
                        "agent readiness bypassed with explicit adapter {}",
                        adapter.agent_type
                    ),
                )
                .await
                .map_err(state_error)?;
        }
        self.orchestration_activity_last_recorded.remove(&to);
        if let Err(error) = self.install_dispatch_context(&to, &dispatch.id, &context_token) {
            let _ = self
                .runtime_store
                .fail_orchestration_startup(&dispatch.id, "could not install worker context")
                .await;
            return Err(error);
        }
        let preamble = build_dispatch_preamble(&PreambleParams {
            task_id: &task_id,
            dispatch_id: &dispatch.id,
            task_spec: &effective_spec,
            coordinator_handle: &from,
            base_drift: None,
            gate_resolution: gate_resolution.as_ref(),
            worker_kind: WorkerKind::PromptReturningAgent,
        });

        if inject {
            if !self
                .sessions
                .get(&to)
                .is_some_and(|session| session.running())
            {
                self.remove_dispatch_context(&to);
                let _ = self
                    .runtime_store
                    .fail_orchestration_startup(&dispatch.id, "terminal session vanished")
                    .await;
                return Err(HostError::state(format!("terminal {to} vanished")));
            }
            let force_submit = payload
                .get("forceSubmit")
                .and_then(Value::as_bool)
                .unwrap_or_else(|| {
                    assumed_adapter
                        .map(|adapter| adapter.force_submit)
                        .unwrap_or(false)
                });
            if let Err(error) =
                self.queue_orchestration_paste(&to, &preamble, Vec::new(), force_submit)
            {
                self.remove_dispatch_context(&to);
                let _ = self
                    .runtime_store
                    .fail_orchestration_startup(&dispatch.id, "terminal input unavailable")
                    .await;
                return Err(error);
            }
        }

        let mut response = json!({
            "dispatch": dispatch,
            "taskId": task_id,
            "runId": task.run_id,
            "workspaceId": task.workspace_id,
            "coordinatorHandle": task.coordinator_handle,
            "assigneeHandle": to,
            "dispatchingTerminal": from,
            "startupState": if inject {
                self.presence_startup_state(&to)
            } else {
                "awaiting_manual_delivery"
            },
            "dispatchPreambleVersion": crate::terminal_host::protocol::DISPATCH_PREAMBLE_VERSION,
            "contextToken": context_token,
            "contextPath": self.dispatch_context_path(&to),
            "assumedAgent": assume_agent,
        });
        let bootstrap = build_dispatch_bootstrap();
        if return_preamble {
            response["preamble"] = Value::String(preamble);
        } else if !inject {
            response["preamble"] = Value::String(bootstrap.clone());
        }
        response["bootstrap"] = Value::String(bootstrap);
        Ok(response)
    }

    pub(super) async fn orchestration_dispatch_show(
        &mut self,
        payload: &Value,
    ) -> HostResult<Value> {
        let task_id = require_string(payload, "task")?;
        let active = self
            .runtime_store
            .active_orchestration_dispatch_for_task(&task_id)
            .await
            .map_err(state_error)?;
        let history = self
            .runtime_store
            .list_orchestration_dispatches_for_task(&task_id)
            .await
            .map_err(state_error)?;
        Ok(json!({ "active": active, "history": history }))
    }

    pub(super) async fn orchestration_dispatch_interrupt(
        &mut self,
        payload: &Value,
    ) -> HostResult<Value> {
        let id = require_string(payload, "id")?;
        let reason = require_string(payload, "reason")?;
        let dispatch = self
            .runtime_store
            .orchestration_dispatch_by_id(&id)
            .await
            .map_err(state_error)?
            .ok_or_else(|| HostError::state(format!("dispatch not found: {id}")))?;
        if !matches!(
            dispatch.status,
            OrchestrationDispatchStatus::Dispatched | OrchestrationDispatchStatus::Stalled
        ) {
            return Err(HostError::state("dispatch is not interruptible"));
        }
        let actor = optional_string(payload, "actor");
        let force = payload
            .get("force")
            .and_then(Value::as_bool)
            .unwrap_or(false);
        if !force && actor.as_deref() != Some(dispatch.coordinator_handle.as_str()) {
            return Err(HostError::state(format!(
                "only coordinator {} can interrupt dispatch {id}; use --force for audited recovery",
                dispatch.coordinator_handle
            )));
        }
        let handle = dispatch
            .assignee_handle
            .clone()
            .ok_or_else(|| HostError::state("dispatch has no assignee"))?;
        let agent_type = self.agent_presence.agent_type(&handle).unwrap_or("codex");
        let adapter = adapter_for(agent_type)
            .ok_or_else(|| HostError::state(format!("no interrupt adapter for {agent_type}")))?;
        self.queue_orchestration_control(&handle, adapter.interrupt_bytes)?;
        self.runtime_store
            .insert_orchestration_audit_event(
                actor.as_deref(),
                if force {
                    "dispatch.interrupt.force"
                } else {
                    "dispatch.interrupt"
                },
                &id,
                &reason,
            )
            .await
            .map_err(state_error)?;
        Ok(json!({ "dispatchId": id, "interrupted": true, "reason": reason }))
    }

    pub(super) async fn apply_terminal_completion_policy(
        &mut self,
        handle: &str,
        policy: &str,
    ) -> HostResult<()> {
        match policy {
            "return-to-shell" => {
                let _ = self.queue_orchestration_control(handle, b"\x04");
            }
            "close-on-success" => {
                if let Some(tab_id) = self
                    .sessions
                    .get(handle)
                    .map(|session| session.tab_id.clone())
                {
                    self.runtime_store
                        .remove_workspace_tab(&tab_id)
                        .await
                        .map_err(state_error)?;
                    self.terminate_sessions_for_tab(&tab_id).await;
                    self.broadcast_authenticated(crate::terminal_host::protocol::event(
                        "workspaceTabsChanged",
                        json!({}),
                    ));
                } else {
                    self.agent_presence.remove(handle);
                    self.schedule_shutdown_if_idle();
                }
            }
            _ => {}
        }
        Ok(())
    }

    pub(super) async fn latest_resolved_gate(
        &self,
        task_id: &str,
    ) -> HostResult<Option<GateResolution>> {
        let gates = self
            .runtime_store
            .list_orchestration_gates(Some(task_id), Some(OrchestrationGateStatus::Resolved))
            .await
            .map_err(state_error)?;
        Ok(gates.into_iter().last().map(|gate| GateResolution {
            question: gate.question,
            resolution: gate.resolution.unwrap_or_default(),
        }))
    }
}
