use alera_core::runtime::{
    prompt_value_map, render_prompt_template, AutomationActorKind, AutomationDefinition,
    AutomationOverlapPolicy, AutomationRun, AutomationRunStatus, AutomationSetupPolicy,
    AutomationTarget, WorkspaceTabRecord,
};
use chrono::{Duration, Utc};
use serde_json::{json, Value};
use uuid::Uuid;

use super::automation_run_lifecycle::{is_non_retryable_dispatch_error, is_non_retryable_reason};
use super::{automation_prompt, render_workspace_name, run_precheck_command, ServerActor};
use crate::managed_workspace::ManagedWorkspaceCreateRequest;
use crate::terminal_host::host_error::{HostError, HostResult};

impl ServerActor {
    pub(super) async fn start_automation_run(
        &mut self,
        definition: &AutomationDefinition,
        mut run: AutomationRun,
        run_precheck: bool,
    ) {
        self.automations_active = true;
        self.cancel_shutdown_timer();
        let active_runs = self
            .runtime_store
            .list_active_automation_runs()
            .await
            .unwrap_or_default()
            .into_iter()
            .filter(|active| active.automation_id == definition.id && active.id != run.id)
            .collect::<Vec<_>>();
        let overlap = run.overlap_policy.unwrap_or(definition.overlap_policy);
        if !active_runs.is_empty() {
            match overlap {
                AutomationOverlapPolicy::Skip => {
                    let _ = self
                        .runtime_store
                        .update_automation_run_status(
                            &run.id,
                            AutomationRunStatus::OverlapSkipped,
                            Some("automation overlap policy skipped the run".to_string()),
                        )
                        .await;
                    return;
                }
                AutomationOverlapPolicy::RunLatestOnce => {
                    for active in active_runs
                        .iter()
                        .filter(|active| active.status == AutomationRunStatus::Pending)
                    {
                        let _ = self
                            .runtime_store
                            .update_automation_run_status(
                                &active.id,
                                AutomationRunStatus::OverlapSkipped,
                                Some("a newer occurrence replaced this queued run".to_string()),
                            )
                            .await;
                    }
                    return;
                }
                AutomationOverlapPolicy::Queue => {
                    let pending = active_runs
                        .iter()
                        .filter(|active| active.status == AutomationRunStatus::Pending)
                        .count();
                    if pending >= definition.queue_cap.clamp(1, 10) as usize {
                        let _ = self
                            .runtime_store
                            .update_automation_run_status(
                                &run.id,
                                AutomationRunStatus::QueueLimitSkipped,
                                Some("automation queue cap reached".to_string()),
                            )
                            .await;
                        return;
                    }
                    if active_runs
                        .iter()
                        .any(|active| active.status != AutomationRunStatus::Pending)
                    {
                        return;
                    }
                }
                AutomationOverlapPolicy::ForceParallel => {}
            }
        }
        if let Err(error) = self
            .ensure_agent_policy(
                definition,
                &alera_core::runtime::AutomationActor {
                    kind: AutomationActorKind::ManagedAgent,
                    id: run.actor_id.clone(),
                    label: Some("Alera Automation Scheduler".to_string()),
                },
                true,
            )
            .await
        {
            self.block_run(&run, &error.wire_message()).await;
            return;
        }
        // Bind the durable target before a workspace or project lookup can
        // fail, so attention notifications still have a useful location.
        let target_identity = match self.target_identity(definition).await {
            Ok(identity) => identity,
            Err(error) => {
                self.block_run(&run, &error).await;
                return;
            }
        };
        run.target_identity = Some(target_identity.clone());
        if let Err(error) = self.runtime_store.save_automation_run(&run).await {
            tracing::warn!(run_id = %run.id, "could not persist automation target identity: {error}");
        }
        let target_workspace_id = match &definition.target {
            AutomationTarget::ExistingTab { workspace_id, .. }
            | AutomationTarget::FreshTab { workspace_id, .. } => workspace_id.clone(),
            AutomationTarget::ManagedWorkspace {
                source_workspace_id,
                ..
            } => source_workspace_id.clone(),
        };
        let source_workspace = match self
            .runtime_store
            .find_workspace(&target_workspace_id)
            .await
        {
            Ok(Some(workspace)) => workspace,
            Ok(None) => {
                self.block_run(&run, "automation target workspace is missing")
                    .await;
                return;
            }
            Err(error) => {
                self.fail_run(&run, error.to_string()).await;
                return;
            }
        };
        let project = match self
            .runtime_store
            .find_project(&source_workspace.project_id)
            .await
        {
            Ok(Some(project)) => project,
            Ok(None) => {
                self.block_run(&run, "automation target project is missing")
                    .await;
                return;
            }
            Err(error) => {
                self.fail_run(&run, error.to_string()).await;
                return;
            }
        };
        run.precheck = Some(run_precheck);
        run.actor_kind
            .get_or_insert(AutomationActorKind::ManagedAgent);
        if run.actor_id.is_none() {
            run.actor_id = target_identity.profile_id.clone();
        }
        if run_precheck {
            if let Some(precheck) = &definition.precheck {
                match run_precheck_command(
                    &self.runtime_store,
                    &source_workspace.host_id,
                    precheck,
                    &source_workspace.path,
                )
                .await
                {
                    Ok(true) => {}
                    Ok(false) => {
                        let _ = self
                            .runtime_store
                            .update_automation_run_status(
                                &run.id,
                                AutomationRunStatus::PrecheckSkipped,
                                Some("automation precheck did not pass".to_string()),
                            )
                            .await;
                        return;
                    }
                    Err(error) => {
                        if is_non_retryable_reason(&error) {
                            self.block_run(&run, &error).await;
                        } else {
                            let _ = self
                                .runtime_store
                                .update_automation_run_status(
                                    &run.id,
                                    AutomationRunStatus::PrecheckSkipped,
                                    Some(error),
                                )
                                .await;
                        }
                        return;
                    }
                }
            }
        }
        let workspace_values = (
            source_workspace.id.as_str(),
            source_workspace.name.as_str(),
            source_workspace.path.as_str(),
        );
        let project_values = (project.id.as_str(), project.name.as_str());
        let values = prompt_value_map(
            definition,
            &run,
            Some(workspace_values),
            Some(project_values),
        );
        let rendered = match render_prompt_template(definition, &run, &values) {
            Ok(value) => value,
            Err(error) => {
                self.block_run(&run, &error).await;
                return;
            }
        };
        let prompt = automation_prompt(&rendered, &run.id, definition.heartbeat_interval_seconds);
        run.rendered_prompt = Some(rendered);
        run.status = AutomationRunStatus::Dispatching;
        run.retry_after = None;
        run.started_at = Some(Utc::now());
        run.last_heartbeat_at = run.started_at;
        run.absolute_deadline_at = run.started_at.map(|started| started + Duration::hours(24));
        run.attempt_count += 1;
        if let Err(error) = self.runtime_store.save_automation_run(&run).await {
            tracing::error!(run_id = %run.id, "could not mark automation dispatching: {error}");
            return;
        }
        let _ = self
            .runtime_store
            .insert_automation_attempt(&run.id, AutomationRunStatus::Dispatching, None)
            .await;
        let result = match &definition.target {
            AutomationTarget::ExistingTab {
                workspace_id,
                tab_id,
                conversation_id,
            } => {
                self.dispatch_existing_tab(
                    &mut run,
                    workspace_id,
                    tab_id,
                    conversation_id.as_deref(),
                    &prompt,
                )
                .await
            }
            AutomationTarget::FreshTab {
                workspace_id,
                agent_profile_id,
            } => {
                self.dispatch_fresh_tab(&mut run, workspace_id, agent_profile_id, &prompt, false)
                    .await
            }
            AutomationTarget::ManagedWorkspace {
                source_branch,
                name_template,
                agent_profile_id,
                ..
            } => {
                if source_workspace.host_id != alera_core::runtime::LOCAL_HOST_ID {
                    self.block_run(
                        &run,
                        "managed workspace automation requires a local execution host",
                    )
                    .await;
                    return;
                }
                let name = render_workspace_name(name_template, definition, &run);
                let branch = format!("automation/{}/{}", definition.slug, &run.id[..8]);
                let request = ManagedWorkspaceCreateRequest {
                    id: None,
                    project_id: project.id.clone(),
                    name: Some(name),
                    branch,
                    source_branch: Some(source_branch.clone()),
                    reuse_existing_branch: false,
                    workspace_root: None,
                    path: None,
                    parent_workspace_id: Some(source_workspace.id.clone()),
                    defer_setup: definition.setup_policy != AutomationSetupPolicy::Wait,
                    skip_setup: definition.setup_policy == AutomationSetupPolicy::Skip,
                    setup_script_directory: (definition.setup_policy
                        != AutomationSetupPolicy::Wait)
                        .then(|| self.runtime_dir.join("automation-setup")),
                };
                match crate::managed_workspace::create_managed_workspace(
                    &self.runtime_store,
                    request,
                )
                .await
                {
                    Ok(result) => {
                        run.workspace_id = Some(result.workspace.id.clone());
                        run.workspace_branch = result.workspace.branch.clone();
                        run.owned_workspace = true;
                        if definition.setup_policy == AutomationSetupPolicy::Wait
                            && result.setup_report.steps.iter().any(|step| !step.succeeded)
                        {
                            let reason = result
                                .setup_report
                                .steps
                                .iter()
                                .find(|step| !step.succeeded)
                                .and_then(|step| step.message.as_deref())
                                .unwrap_or("managed workspace setup failed");
                            let _ = self.runtime_store.save_automation_run(&run).await;
                            self.block_run(&run, reason).await;
                            return;
                        }
                        if definition.setup_policy == AutomationSetupPolicy::Parallel
                            && result.deferred_setup_command.is_none()
                            && result.setup_report.steps.iter().any(|step| !step.succeeded)
                        {
                            let reason = result
                                .setup_report
                                .steps
                                .iter()
                                .find(|step| !step.succeeded)
                                .and_then(|step| step.message.as_deref())
                                .unwrap_or("managed workspace setup could not be prepared");
                            let _ = self.runtime_store.save_automation_run(&run).await;
                            self.block_run(&run, reason).await;
                            return;
                        }
                        if definition.setup_policy == AutomationSetupPolicy::Parallel {
                            if let Some(command) = result.deferred_setup_command.as_deref() {
                                let setup_id = Uuid::new_v4().to_string();
                                let now = Utc::now();
                                let setup_tab = WorkspaceTabRecord {
                                    id: setup_id.clone(),
                                    workspace_id: result.workspace.id.clone(),
                                    kind: "terminal".to_string(),
                                    title: "Setup".to_string(),
                                    created_at: now,
                                    updated_at: now,
                                    payload: json!({
                                        "terminalSessionId": setup_id,
                                        "initialCommand": command,
                                        "initialCommandOnce": true,
                                        "spawnOnCreate": true,
                                        "autoCloseOnSuccess": true,
                                        "automationRunId": run.id,
                                        "automationOwned": true,
                                    }),
                                };
                                if let Err(error) =
                                    self.upsert_workspace_tab_and_spawn(setup_tab).await
                                {
                                    tracing::warn!(
                                        run_id = %run.id,
                                        "could not start managed workspace setup terminal: {}",
                                        error.wire_message()
                                    );
                                } else {
                                    run.setup_tab_id = Some(setup_id);
                                }
                            }
                        }
                        self.dispatch_fresh_tab(
                            &mut run,
                            &result.workspace.id,
                            agent_profile_id,
                            &prompt,
                            true,
                        )
                        .await
                    }
                    Err(error) => Err(HostError::state(error.to_string())),
                }
            }
        };
        match result {
            Ok(()) => {
                // Keep the first-attachment marker until a user client really
                // attaches. The agent runs inside the PTY and is not a host
                // client, so clearing it here would classify the user's first
                // view of a fresh tab as a takeover.
                if run.status != AutomationRunStatus::Pending {
                    if let Some(identity) = run.target_identity.as_mut() {
                        identity.workspace_id =
                            run.workspace_id.clone().or(identity.workspace_id.clone());
                        identity.tab_id = run.tab_id.clone().or(identity.tab_id.clone());
                        identity.session_id =
                            run.session_id.clone().or(identity.session_id.clone());
                        identity.terminal_handle =
                            run.session_id.clone().or(identity.terminal_handle.clone());
                    }
                    run.status = AutomationRunStatus::Dispatched;
                    run.updated_at = Utc::now();
                    let _ = self.runtime_store.save_automation_run(&run).await;
                }
                self.broadcast_authenticated(crate::terminal_host::protocol::event(
                    "automationRunChanged",
                    json!({ "automationId": definition.id, "runId": run.id }),
                ));
            }
            Err(error) if is_non_retryable_dispatch_error(&error) => {
                self.block_run(&run, &error.wire_message()).await
            }
            Err(error) => self.fail_run(&run, error.wire_message()).await,
        }
    }

    async fn dispatch_fresh_tab(
        &mut self,
        run: &mut AutomationRun,
        workspace_id: &str,
        profile_id: &str,
        prompt: &str,
        owned_workspace: bool,
    ) -> HostResult<()> {
        let response = self
            .launch_agent_profile(&json!({
                "workspaceId": workspace_id,
                "profileId": profile_id,
                "prompt": prompt,
                "automationRunId": run.id,
                "automationOwned": true,
            }))
            .await?;
        let tab = response
            .get("tab")
            .ok_or_else(|| HostError::state("agent profile launch returned no tab"))?;
        let tab_id = tab
            .get("id")
            .and_then(Value::as_str)
            .ok_or_else(|| HostError::state("agent profile launch returned no tab id"))?;
        let session_id = tab
            .get("payload")
            .and_then(|value| value.get("terminalSessionId"))
            .and_then(Value::as_str)
            .unwrap_or(tab_id)
            .to_string();
        if let Ok(Some(mut record)) = self.runtime_store.find_workspace_tab(tab_id).await {
            record.payload["automationRunId"] = Value::String(run.id.clone());
            record.payload["automationOwned"] = Value::Bool(true);
            record.updated_at = Utc::now();
            let _ = self.runtime_store.upsert_workspace_tab(record).await;
        }
        run.workspace_id = Some(workspace_id.to_string());
        run.tab_id = Some(tab_id.to_string());
        run.session_id = Some(session_id);
        run.owned_tab = true;
        run.owned_workspace = owned_workspace;
        Ok(())
    }
}
