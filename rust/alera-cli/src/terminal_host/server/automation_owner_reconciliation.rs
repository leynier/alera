use super::ServerActor;
use crate::process_identity::{ProcessIdentityProbe, ProcessLookup, SystemProcessIdentityProbe};
use alera_core::runtime::{
    AutomationDefinition, AutomationRecovery, AutomationRun, AutomationRunStatus, LOCAL_HOST_ID,
};
use chrono::Utc;
use serde_json::json;

impl ServerActor {
    pub(super) async fn reconcile_automation_runs(&mut self) {
        let mut runs = self
            .runtime_store
            .list_active_automation_runs()
            .await
            .unwrap_or_default();
        for reserved in self
            .runtime_store
            .reserved_automation_runs()
            .await
            .unwrap_or_default()
        {
            if !runs.iter().any(|run| run.id == reserved.id) {
                runs.push(reserved);
            }
        }
        for mut run in runs {
            if run.taken_over
                || (!run.owner_reserved
                    && matches!(
                        run.status,
                        AutomationRunStatus::Pending | AutomationRunStatus::WaitingForUser
                    ))
            {
                continue;
            }
            if run.status == AutomationRunStatus::Dispatching && run.started_at.is_none() {
                continue;
            }
            if self.automation_checkout_jobs.contains(&run.id)
                || self.automation_precheck_jobs.contains(&run.id)
            {
                continue;
            }
            let Some(definition) = run.definition_snapshot.clone().or(self
                .runtime_store
                .find_automation(&run.automation_id)
                .await
                .ok()
                .flatten())
            else {
                continue;
            };
            let host_id = if let Some(workspace_id) = run.workspace_id.as_deref() {
                self.runtime_store
                    .find_workspace(workspace_id)
                    .await
                    .ok()
                    .flatten()
                    .map(|w| w.host_id)
            } else {
                self.automation_target_location(&definition)
                    .await
                    .ok()
                    .map(|loc| loc.host_id)
            };
            if run
                .recovery
                .as_ref()
                .is_some_and(|recovery| recovery.status == "resuming")
                && run.status != AutomationRunStatus::WaitingForUser
            {
                let attempts = self
                    .runtime_store
                    .automation_attempts(&run.id)
                    .await
                    .unwrap_or_default();
                if attempts.last().is_some_and(|attempt| {
                    Utc::now()
                        .signed_duration_since(attempt.started_at)
                        .num_seconds()
                        >= (definition.heartbeat_interval_seconds * 2).max(120)
                }) && host_id.as_deref() == Some(LOCAL_HOST_ID)
                {
                    if let Some(session) = run
                        .session_id
                        .as_deref()
                        .and_then(|id| self.sessions.get_mut(id))
                    {
                        session.terminate(false, &self.store).await;
                    }
                    run.recovery.as_mut().expect("checked recovery").status = "resumeFailed".into();
                    let _ = self.runtime_store.save_automation_run(&run).await;
                    self.fail_run(
                        &run,
                        "Native conversation did not acknowledge recovery; continuing with context"
                            .into(),
                    )
                    .await;
                    continue;
                }
            }
            let remote_host = host_id.as_deref().filter(|id| *id != LOCAL_HOST_ID);
            let remote_state = if let Some(host) = remote_host {
                let links = self.host_links.clone();
                let owner = json!({"sessionId":run.session_id,"workspaceId":run.workspace_id,"tabId":run.tab_id});
                tokio::time::timeout(std::time::Duration::from_millis(250), async {
                    let link = links.link(host).await?;
                    link.request_with_timeout(
                        "automation.ownerStatus",
                        owner,
                        std::time::Duration::from_millis(200),
                    )
                    .await
                })
                .await
                .ok()
                .and_then(Result::ok)
                .and_then(|value| value["state"].as_str().map(str::to_string))
            } else {
                None
            };
            if let Some(host) = remote_host.filter(|_| remote_state.as_deref() == Some("running")) {
                let resume_expired = run
                    .recovery
                    .as_ref()
                    .is_some_and(|r| r.status == "resuming")
                    && self
                        .runtime_store
                        .automation_attempts(&run.id)
                        .await
                        .unwrap_or_default()
                        .last()
                        .is_some_and(|attempt| {
                            Utc::now()
                                .signed_duration_since(attempt.started_at)
                                .num_seconds()
                                >= (definition.heartbeat_interval_seconds * 2).max(120)
                        });
                if resume_expired {
                    let links = self.host_links.clone();
                    let payload = json!({"sessionId":run.session_id});
                    let _ = tokio::time::timeout(std::time::Duration::from_millis(250), async {
                        links
                            .link(host)
                            .await?
                            .request_with_timeout(
                                "terminate",
                                payload,
                                std::time::Duration::from_millis(200),
                            )
                            .await
                    })
                    .await;
                    // Retry only after a subsequent owner-status response proves closure.
                    continue;
                }
                let attached = run
                    .session_id
                    .as_deref()
                    .and_then(|id| self.sessions.get(id))
                    .is_some_and(|s| s.running())
                    || self
                        .reconnect_automation_remote_terminal(&run)
                        .await
                        .is_ok();
                if attached {
                    if run.owner_reserved
                        || run
                            .recovery
                            .as_ref()
                            .is_some_and(|r| r.status == "reconnecting")
                    {
                        run.owner_reserved = false;
                        if run
                            .recovery
                            .as_ref()
                            .is_some_and(|r| r.status == "reconnecting")
                        {
                            run.recovery = None;
                        }
                        let _ = self.runtime_store.save_automation_run(&run).await;
                        self.automation_run_event(&run);
                    }
                    continue;
                }
            }
            if remote_host.is_some() && remote_state.as_deref() != Some("exited") {
                self.mark_automation_reconnecting(
                    &mut run,
                    &definition,
                    if remote_state.as_deref() == Some("running") {
                        "ownerRunning"
                    } else {
                        "hostUnreachable"
                    },
                )
                .await;
                continue;
            }
            let live_session = run
                .session_id
                .as_deref()
                .and_then(|id| self.sessions.get(id));
            if remote_host.is_none() && live_session.is_some_and(|session| session.running()) {
                if run.owner_reserved {
                    run.owner_reserved = false;
                    let _ = self.runtime_store.save_automation_run(&run).await;
                }
                self.record_automation_process(&run).await;
                continue;
            }
            let owner = run.owner_process.clone();
            let owner_boot = run.owner_boot_id.clone();
            let durable_state = if owner.is_none() && remote_host.is_none() {
                self.automation_owner_status(&json!({"sessionId":run.session_id,"workspaceId":run.workspace_id,"tabId":run.tab_id})).await.ok().and_then(|v| v["state"].as_str().map(str::to_string))
            } else {
                None
            };
            let state = if remote_state.as_deref() == Some("exited")
                || durable_state.as_deref() == Some("exited")
            {
                ProcessLookup::Exited
            } else {
                tokio::task::spawn_blocking(move || {
                    let boot = crate::relocation_setup_process::current_boot_id()
                        .ok()
                        .flatten();
                    if owner_boot
                        .as_deref()
                        .zip(boot.as_deref())
                        .is_some_and(|(old, new)| old != new)
                    {
                        return ProcessLookup::Exited;
                    }
                    let Some(owner) = owner else {
                        return ProcessLookup::Unknown("Owner identity was not recorded".into());
                    };
                    if owner.boot_id.is_some() && boot.is_some() && boot != owner.boot_id {
                        return ProcessLookup::Exited;
                    }
                    match SystemProcessIdentityProbe.lookup(owner.pid) {
                        ProcessLookup::Live(identity)
                            if identity.start_marker != owner.start_marker =>
                        {
                            ProcessLookup::Exited
                        }
                        state => state,
                    }
                })
                .await
                .unwrap_or_else(|e| ProcessLookup::Unknown(e.to_string()))
            };
            match state {
                ProcessLookup::Live(_) | ProcessLookup::Unknown(_) => {
                    self.mark_automation_reconnecting(&mut run, &definition, "ownerUnreachable")
                        .await;
                }
                ProcessLookup::Exited => {
                    if run.owner_reserved {
                        run.owner_reserved = false;
                        let _ = self.runtime_store.save_automation_run(&run).await;
                    }
                    if remote_state.as_deref() == Some("exited") {
                        if let Some(session) = run
                            .session_id
                            .as_deref()
                            .and_then(|id| self.sessions.get_mut(id))
                        {
                            session.terminate(false, &self.store).await;
                        }
                    }
                    if run.status.is_final() {
                        continue;
                    }
                    run.recovery = Some(AutomationRecovery {
                        status: if run
                            .recovery
                            .as_ref()
                            .is_some_and(|r| r.status == "resuming")
                        {
                            "resumeFailed"
                        } else {
                            "retryingWithContext"
                        }
                        .into(),
                        attempt: run.attempt_count,
                        max_attempts: definition.retry_max_attempts,
                        interrupted_at: Some(Utc::now()),
                        code: Some("runtimeRestart".into()),
                    });
                    let _ = self.runtime_store.save_automation_run(&run).await;
                    self.fail_run(
                        &run,
                        "Automation agent interrupted; continuing the persisted run".into(),
                    )
                    .await;
                }
            }
        }
    }

    async fn mark_automation_reconnecting(
        &self,
        run: &mut AutomationRun,
        definition: &AutomationDefinition,
        code: &str,
    ) {
        let changed = !run.owner_reserved
            || run
                .recovery
                .as_ref()
                .is_none_or(|r| r.status != "reconnecting" || r.code.as_deref() != Some(code));
        run.owner_reserved = true;
        run.recovery = Some(AutomationRecovery {
            status: "reconnecting".into(),
            attempt: run.attempt_count,
            max_attempts: definition.retry_max_attempts,
            interrupted_at: run
                .recovery
                .as_ref()
                .and_then(|r| r.interrupted_at)
                .or(Some(Utc::now())),
            code: Some(code.into()),
        });
        if changed {
            let _ = self.runtime_store.save_automation_run(run).await;
            self.automation_run_event(run);
        }
    }

    async fn reconnect_automation_remote_terminal(
        &mut self,
        run: &AutomationRun,
    ) -> crate::terminal_host::host_error::HostResult<()> {
        let tab = self.automation_recovery_tab(run).await.ok_or_else(|| {
            crate::terminal_host::host_error::HostError::state("Automation terminal is missing")
        })?;
        let workspace = self
            .runtime_store
            .find_workspace(&tab.workspace_id)
            .await
            .map_err(|e| crate::terminal_host::host_error::HostError::state(e.to_string()))?
            .ok_or_else(|| {
                crate::terminal_host::host_error::HostError::state("Workspace is missing")
            })?;
        let session = run.session_id.clone().ok_or_else(|| {
            crate::terminal_host::host_error::HostError::state("Session is missing")
        })?;
        let (bytes, range) = self
            .take_terminal_restart_state(
                &session,
                &workspace.id,
                &tab.id,
                self.config.scrollback_bytes as usize,
            )
            .await?;
        let launch = super::terminal_launch_defaults::default_terminal_launch(
            &workspace.path,
            self.config.login_shell,
        )
        .await;
        // Reconnect the SSH transport to the proven live owner without injecting a startup command.
        self.start_new_terminal_session(
            session,
            workspace.id,
            tab.id,
            workspace.path,
            launch.launch,
            80,
            24,
            bytes,
            range,
            None,
        )
        .await
    }
}
