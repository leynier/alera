use alera_core::runtime::{OrchestrationDispatchStatus, WorkspaceStatus, WorkspaceTabRecord};
use serde_json::{json, Value};

use crate::terminal_host::host_error::{HostError, HostResult};
use crate::terminal_host::orchestration::agent_profile_launch_snapshot::AGENT_PROFILE_LAUNCH_SNAPSHOT_KEY;
use crate::terminal_host::orchestration::agent_registry::{adapter_for, AgentStartupPrompt};
use crate::terminal_host::orchestration::coordinator_loop::CoordinatorConfig;
use crate::terminal_host::orchestration::dispatch_preamble::{build_dispatch_bootstrap, BaseDrift};

use super::orchestration_validation::{optional_string, require_string, state_error};
use super::ServerActor;

impl ServerActor {
    pub(super) async fn fail_active_dispatch_for_closed_session(
        &mut self,
        session_id: &str,
        reason: &str,
    ) {
        let dispatch = match self
            .runtime_store
            .active_orchestration_dispatch_for_handle(session_id)
            .await
        {
            Ok(dispatch) => dispatch,
            Err(error) => {
                tracing::error!(
                    "failed to inspect active orchestration dispatch for exited terminal {session_id}: {error}"
                );
                return;
            }
        };
        let Some(dispatch) = dispatch else {
            let Some(metadata) = self.owned_spawn_metadata(session_id).await else {
                return;
            };
            if !metadata.pending_readiness {
                return;
            }
            match self
                .runtime_store
                .record_orchestration_task_startup_failure(&metadata.task_id, reason)
                .await
            {
                Ok(_) => {
                    self.mark_owned_spawn_failure(session_id, reason).await;
                }
                Err(error) => {
                    tracing::error!(
                        "failed to record orchestration startup exit for task {}: {error}",
                        metadata.task_id
                    );
                }
            }
            return;
        };
        if self.is_workflow_terminal(session_id).await {
            return;
        }
        let result = if dispatch.status == OrchestrationDispatchStatus::AwaitingAcceptance
            && self
                .is_owned_orchestration_spawn(session_id, &dispatch.task_id)
                .await
        {
            let failed = self
                .runtime_store
                .fail_orchestration_startup(&dispatch.id, reason)
                .await;
            if failed.is_ok() {
                // The tab has to say a failure is already on the task's budget.
                // A spawn timeout arriving afterwards finds the dispatch no
                // longer active and would otherwise charge the task a second
                // time for the same dead terminal.
                self.mark_owned_spawn_failure(session_id, reason).await;
            }
            failed
        } else {
            self.runtime_store
                .fail_orchestration_dispatch(&dispatch.id, reason)
                .await
        };
        if let Err(error) = result {
            tracing::error!(
                "failed to mark orchestration dispatch {} failed after terminal close: {error}",
                dispatch.id
            );
        }
    }

    /// Mints and starts a terminal tab with the default agent command.
    pub(super) async fn coordinator_create_worker_terminal(
        &mut self,
        config: &CoordinatorConfig,
        ready: &[alera_core::runtime::OrchestrationTask],
    ) -> anyhow::Result<()> {
        let Some(workspace_id) = &config.workspace_id else {
            self.coordinator_log(
                "no idle worker terminals and no --workspace scope; cannot create workers",
            );
            return Ok(());
        };
        let Some(workspace) = self.runtime_store.find_workspace(workspace_id).await? else {
            self.coordinator_log(&format!(
                "workspace {workspace_id} not found; cannot create worker terminal"
            ));
            return Ok(());
        };
        if workspace.status != WorkspaceStatus::Active {
            self.coordinator_log(&format!(
                "workspace {workspace_id} is not active; cannot create worker terminal"
            ));
            return Ok(());
        }
        adapter_for(&config.agent_type)
            .ok_or_else(|| anyhow::anyhow!("unsupported agent type: {}", config.agent_type))?;
        // Every adapter is pre-dispatched. Waiting for the agent to announce
        // itself first is not an option any more, and never was a working one:
        // a worker that has been asked nothing never reports that it is idle,
        // so a bare terminal would sit there holding the task forever.
        for task in ready {
            let Some(preflight) = self.coordinator_dispatch_preflight(config, task).await else {
                continue;
            };
            let profile = self.coordinator_profile_for_task(task).await;
            let handle = self
                .coordinator_spawn_predispatched_worker(
                    workspace_id,
                    &config.agent_type,
                    &task.id,
                    config.coordinator_handle.as_deref(),
                    preflight,
                    profile.as_deref(),
                )
                .await?;
            self.coordinator_log(&format!(
                "created worker terminal {handle} with pre-dispatch for {}",
                task.id
            ));
            break;
        }
        Ok(())
    }

    pub(super) async fn orchestration_agent_spawn(&mut self, payload: &Value) -> HostResult<Value> {
        self.orchestration_agent_spawn_with_preflight(payload, None)
            .await
    }

    async fn orchestration_agent_spawn_with_preflight(
        &mut self,
        payload: &Value,
        preflight: Option<(String, Option<BaseDrift>)>,
    ) -> HostResult<Value> {
        let workspace_id = require_string(payload, "workspace")?;
        let task_id = require_string(payload, "task")?;
        self.runtime_store
            .ensure_legacy_workflow_dispatch_allowed(&task_id)
            .await
            .map_err(state_error)?;
        let from = require_string(payload, "from")?;
        // A profile is the single source of truth for the adapter and the
        // launch command, so it replaces --agent/--command rather than layering
        // on top of them.
        let resolved = self.resolve_spawn_profile(payload).await?;
        let agent_type = resolved.agent_type.clone();
        let adapter = adapter_for(&agent_type)
            .ok_or_else(|| HostError::format(format!("unsupported agent type: {agent_type}")))?;
        let task = self
            .runtime_store
            .orchestration_task_by_id(&task_id)
            .await
            .map_err(state_error)?
            .ok_or_else(|| HostError::state(format!("orchestration task not found: {task_id}")))?;
        if task.workspace_id != workspace_id {
            return Err(HostError::state(format!(
                "task belongs to workspace {}, not {workspace_id}",
                task.workspace_id
            )));
        }
        if task.coordinator_handle != from {
            return Err(HostError::state(format!(
                "coordinator ownership conflict: task is owned by {}",
                task.coordinator_handle
            )));
        }
        if let Some(terminal) = optional_string(payload, "terminal") {
            let response = self
                .orchestration_dispatch(&json!({
                    "task": task_id,
                    "to": terminal,
                    "from": from,
                    "inject": true,
                    "forceSubmit": adapter.force_submit,
                    "completionPolicy": "return-immediately",
                    "terminalPolicy": "keep-open",
                    "agentProfile": resolved.profile_name,
                    "agentQuotaGroup": resolved.quota_group,
                }))
                .await?;
            return Ok(response);
        }
        let workspace = self
            .runtime_store
            .find_workspace(&workspace_id)
            .await
            .map_err(state_error)?
            .ok_or_else(|| HostError::state(format!("workspace not found: {workspace_id}")))?;
        if workspace.status != WorkspaceStatus::Active {
            return Err(HostError::state(format!(
                "workspace is not active: {workspace_id}"
            )));
        }
        let id = uuid::Uuid::new_v4().to_string();
        let command = resolved.command.clone().unwrap_or_else(|| {
            if resolved.managed_launch.is_some() {
                String::new()
            } else {
                adapter.default_command.to_string()
            }
        });
        let keep_on_failure = payload
            .get("keepOnFailure")
            .and_then(Value::as_bool)
            .unwrap_or(false);
        let bootstrap = build_dispatch_bootstrap();
        let prompt_after_ready = adapter.startup_prompt == AgentStartupPrompt::TerminalAfterReady;
        let mut dispatch_response = Some(
            self.orchestration_dispatch(&json!({
                "task": task_id,
                "to": id,
                "from": from,
                "inject": false,
                "completionPolicy": "return-immediately",
                "terminalPolicy": "keep-open",
                "agentProfile": resolved.profile_name,
                "agentQuotaGroup": resolved.quota_group,
            }))
            .await?,
        );
        let now = chrono::Utc::now();
        let orchestration_preflight = preflight.as_ref().and_then(|(task_spec, base_drift)| {
            dispatch_response.as_ref().and_then(|response| {
                let dispatch_id = response.pointer("/dispatch/id")?.as_str()?;
                Some(json!({
                    "taskId": task_id,
                    "dispatchId": dispatch_id,
                    "taskSpec": task_spec,
                    "baseDrift": base_drift.as_ref().map(|drift| json!({
                        "base": drift.base,
                        "behind": drift.behind,
                        "recentSubjects": drift.recent_subjects,
                    })),
                }))
            })
        });
        let mut tab_payload = json!({
            "terminalSessionId": id,
            // OnRestart keeps the durable prompt even when delivery waits for
            // a ready event. Each new PTY gets a fresh pending copy.
            "initialPrompt": bootstrap.clone(),
            "pendingAgentPrompt": prompt_after_ready.then(|| json!({
                "agent": adapter.agent_type,
                "prompt": bootstrap.clone(),
            })),
            "spawnOnCreate": true,
            "orchestrationPreflight": orchestration_preflight,
            "orchestrationSpawn": {
                "task": task_id,
                "from": from,
                "agent": agent_type,
                "owned": true,
                "keepOnFailure": keep_on_failure,
            }
        });
        if let Some(snapshot) = resolved.launch_snapshot {
            tab_payload[AGENT_PROFILE_LAUNCH_SNAPSHOT_KEY] = serde_json::to_value(snapshot)
                .map_err(|error| {
                    HostError::state(format!(
                        "could not encode agent profile launch snapshot: {error}"
                    ))
                })?;
        } else {
            tab_payload["initialCommand"] = json!(command);
            tab_payload["initialManagedAgentLaunch"] = json!(resolved.managed_launch);
            tab_payload["agentType"] = json!(agent_type);
        }
        let tab = WorkspaceTabRecord {
            id: id.clone(),
            workspace_id: workspace_id.clone(),
            kind: "terminal".to_string(),
            title: optional_string(payload, "title")
                .unwrap_or_else(|| format!("{} Worker", agent_type)),
            created_at: now,
            updated_at: now,
            payload: tab_payload,
        };
        if let Err(error) = self.upsert_workspace_tab_and_spawn(tab).await {
            if let Some(dispatch_id) = dispatch_response
                .as_ref()
                .and_then(|value| value.pointer("/dispatch/id"))
                .and_then(Value::as_str)
            {
                let _ = self
                    .runtime_store
                    .fail_orchestration_startup(dispatch_id, "terminal process failed to start")
                    .await;
                self.remove_dispatch_context(&id);
            }
            return Err(error);
        }
        let mut response = json!({
            "terminalHandle": id,
            "agentType": adapter.agent_type,
            "taskId": task.id,
            "runId": task.run_id,
            "workspaceId": workspace_id,
            "coordinatorHandle": task.coordinator_handle,
            "assigneeHandle": id,
            "startupState": "terminal_started",
            "acceptanceState": "awaiting_acceptance",
        });
        if let Some(dispatch) = dispatch_response.take() {
            response["dispatch"] = dispatch["dispatch"].clone();
            response["contextPath"] = dispatch["contextPath"].clone();
        }
        Ok(response)
    }

    pub(super) async fn orchestration_agent_spawn_timeout(
        &mut self,
        payload: &Value,
    ) -> HostResult<Value> {
        let handle = require_string(payload, "terminal")?;
        if let Some(dispatch) = self
            .runtime_store
            .active_orchestration_dispatch_for_handle(&handle)
            .await
            .map_err(state_error)?
        {
            if dispatch.status == OrchestrationDispatchStatus::AwaitingAcceptance {
                let failed = self
                    .runtime_store
                    .fail_orchestration_startup(&dispatch.id, "acceptance timeout")
                    .await
                    .map_err(state_error)?;
                self.remove_dispatch_context(&handle);
                let terminal_removed = self.cleanup_failed_owned_spawn(&handle).await;
                return Ok(json!({
                    "outcome": "startup_failed",
                    "dispatch": failed,
                    "terminalRemoved": terminal_removed,
                }));
            }
        }
        let tab = self
            .runtime_store
            .find_workspace_tab(&handle)
            .await
            .map_err(state_error)?;
        let task_id = tab
            .as_ref()
            .and_then(|tab| tab.payload.get("pendingOrchestration"))
            .or_else(|| {
                tab.as_ref()
                    .and_then(|tab| tab.payload.get("orchestrationSpawn"))
            })
            .and_then(|pending| pending.get("task"))
            .and_then(Value::as_str)
            .map(str::to_string)
            .ok_or_else(|| HostError::state("no pending spawn or acceptance for terminal"))?;
        let failure_recorded = tab
            .as_ref()
            .and_then(|tab| {
                tab.payload
                    .pointer("/orchestrationSpawn/startupFailureRecorded")
            })
            .and_then(Value::as_bool)
            .unwrap_or(false);
        let task = if failure_recorded {
            self.runtime_store
                .orchestration_task_by_id(&task_id)
                .await
                .map_err(state_error)?
                .ok_or_else(|| {
                    HostError::state(format!("orchestration task not found: {task_id}"))
                })?
        } else {
            let task = self
                .runtime_store
                .record_orchestration_task_startup_failure(&task_id, "agent readiness timeout")
                .await
                .map_err(state_error)?;
            self.mark_owned_spawn_failure(&handle, "agent readiness timeout")
                .await;
            task
        };
        let terminal_removed = self.cleanup_failed_owned_spawn(&handle).await;
        Ok(json!({
            "outcome": "startup_failed",
            "task": task,
            "terminalRemoved": terminal_removed,
        }))
    }

    pub(super) async fn cleanup_failed_owned_spawn(&mut self, handle: &str) -> bool {
        let Ok(Some(tab)) = self.runtime_store.find_workspace_tab(handle).await else {
            return false;
        };
        let spawn = tab.payload.get("orchestrationSpawn");
        let owned = spawn
            .and_then(|value| value.get("owned"))
            .and_then(Value::as_bool)
            .unwrap_or(false);
        let keep = spawn
            .and_then(|value| value.get("keepOnFailure"))
            .and_then(Value::as_bool)
            .unwrap_or(false);
        if !owned {
            return false;
        }
        if keep && self.make_failed_owned_spawn_inert(handle).await {
            return false;
        }
        if self
            .runtime_store
            .remove_workspace_tab(&tab.id)
            .await
            .is_err()
        {
            return false;
        }
        self.terminate_sessions_for_tab(&tab.id).await;
        self.broadcast_workspace_tabs_changed(Some(&tab.workspace_id));
        true
    }

    pub(super) async fn coordinator_spawn_predispatched_worker(
        &mut self,
        workspace_id: &str,
        agent_type: &str,
        task_id: &str,
        coordinator_handle: Option<&str>,
        preflight: (String, Option<BaseDrift>),
        profile: Option<&str>,
    ) -> anyhow::Result<String> {
        // A profile supersedes the run-level agent type, so send only one of
        // them: the host rejects both together.
        let response = self
            .orchestration_agent_spawn_with_preflight(
                &json!({
                    "workspace": workspace_id,
                    "agent": profile.is_none().then_some(agent_type),
                    "profile": profile,
                    "task": task_id,
                    "from": coordinator_handle,
                }),
                Some(preflight),
            )
            .await
            .map_err(|error| anyhow::anyhow!(error.wire_message()))?;
        Ok(response
            .get("terminalHandle")
            .and_then(Value::as_str)
            .unwrap_or("unknown")
            .to_string())
    }
}
