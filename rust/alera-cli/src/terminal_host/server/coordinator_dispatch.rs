//! How a coordinator tick hands ready tasks to idle or freshly spawned
//! worker terminals.

use alera_core::runtime::{
    OrchestrationCoordinatorStatus, OrchestrationGateStatus, OrchestrationTaskStatus,
};
use serde_json::Value;
use sha2::{Digest, Sha256};

use crate::terminal_host::orchestration::agent_presence::AgentPresenceState;
use crate::terminal_host::orchestration::agent_registry::adapter_for;
use crate::terminal_host::orchestration::coordinator_loop::{
    CoordinatorConfig, COORDINATOR_DISPATCH_STALE_THRESHOLD,
};
use crate::terminal_host::orchestration::dispatch_preamble::{
    build_dispatch_preamble, parse_allow_stale_base_from_spec, BaseDrift, GateResolution,
    PreambleParams, WorkerKind,
};
use crate::terminal_host::session::Session;

use super::orchestration_owned_spawn::is_pending_orchestration_worker;
use super::ServerActor;

const PENDING_WORKER_TAB_GRACE_SECONDS: i64 = 120;

impl ServerActor {
    pub(super) async fn coordinator_dispatch_ready_tasks(
        &mut self,
        config: &CoordinatorConfig,
    ) -> anyhow::Result<()> {
        // Planning, approval and pauses hold scheduling: the point of
        // requiring approval is that nothing starts before a person accepts.
        let running = self
            .runtime_store
            .orchestration_coordinator_run_by_id(&config.run_id)
            .await?
            .is_some_and(|run| run.status == OrchestrationCoordinatorStatus::Running);
        if !running {
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
                if !is_pending_orchestration_worker(&tab.payload, &config.agent_type) {
                    return None;
                }
                let fallback_id = tab.id;
                let created_at = tab.created_at;
                let payload = tab.payload.as_object()?;
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
            if presence.accepts_injection() {
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
        let (profile_name, profile_quota_group, effective_spec) = self
            .coordinator_profile_prompt_for_task(&task, &stripped_spec)
            .await?;
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
                "keep-open",
            )
            .await?;
        self.runtime_store
            .set_orchestration_dispatch_profile(
                &dispatch.id,
                profile_name.as_deref(),
                profile_quota_group.as_deref(),
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
            task_spec: &effective_spec,
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
        self.runtime_store
            .ensure_terminal_dispatch_allowed(&task.id)
            .await
            .ok()?;
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
}
