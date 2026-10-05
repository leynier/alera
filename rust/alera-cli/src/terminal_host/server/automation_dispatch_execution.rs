use alera_core::runtime::{
    prompt_value_map, render_prompt_template, AutomationActorKind, AutomationDefinition,
    AutomationOverlapPolicy, AutomationRun, AutomationRunStatus, AutomationTarget,
};
use chrono::Utc;
use serde_json::json;

use super::automation_run_lifecycle::is_non_retryable_dispatch_error;
use super::{automation_prompt, ServerActor};
pub(in crate::terminal_host::server) use automation_worktree_dispatch::AutomationWorktree;

impl ServerActor {
    pub(in crate::terminal_host::server) async fn start_automation_run(
        &mut self,
        definition: &AutomationDefinition,
        mut run: AutomationRun,
        run_precheck: bool,
    ) {
        if self.automation_precheck_jobs.contains(&run.id) {
            return;
        }
        if self
            .automation_target_is_reserved(definition, &run.id)
            .await
        {
            run.recovery = Some(alera_core::runtime::AutomationRecovery {
                status: "reconnecting".into(),
                attempt: run.attempt_count,
                max_attempts: definition.retry_max_attempts,
                interrupted_at: None,
                code: Some("waitingForPreviousOwner".into()),
            });
            run.retry_after = Some(Utc::now() + chrono::Duration::seconds(5));
            let _ = self.runtime_store.save_automation_run(&run).await;
            self.automation_run_event(&run);
            return;
        }
        run.recovery = None;
        let _ = self.runtime_store.save_automation_run(&run).await;
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
            .ensure_dispatch_policy(
                definition,
                &alera_core::runtime::AutomationActor {
                    kind: AutomationActorKind::ManagedAgent,
                    id: run.actor_id.clone(),
                    label: Some("Alera Automation Scheduler".to_string()),
                },
            )
            .await
        {
            self.block_run(&run, &error.wire_message()).await;
            return;
        }
        // Bind the durable target before a workspace or project lookup can
        // fail, so attention notifications still have a useful location.
        let target_identity = match self.target_identity(&definition.target).await {
            Ok(identity) => identity,
            Err(error) => {
                self.block_run(&run, &error).await;
                return;
            }
        };
        let mut target_identity = target_identity;
        if definition.target.direct_project_id().is_some() && run.owned_workspace {
            target_identity.workspace_id = run.workspace_id.clone();
        }
        run.target_identity = Some(target_identity.clone());
        if let Err(error) = self.runtime_store.save_automation_run(&run).await {
            tracing::warn!(run_id = %run.id, "could not persist automation target identity: {error}");
        }
        let location = match self.automation_target_location(definition).await {
            Ok(location) => location,
            Err(error) => {
                self.block_run(&run, &error.wire_message()).await;
                return;
            }
        };
        run.precheck = Some(run_precheck);
        run.actor_kind
            .get_or_insert(AutomationActorKind::ManagedAgent);
        if run.actor_id.is_none() {
            run.actor_id = target_identity.profile_id.clone();
        }
        if let Err(error) = self.runtime_store.save_automation_run(&run).await {
            self.fail_run(&run, error.to_string()).await;
            return;
        }
        if run_precheck && definition.precheck.is_some() {
            // Reserve concurrency while the command runs outside the actor.
            // A skipped precheck still consumes no dispatch attempt.
            run.status = AutomationRunStatus::Dispatching;
            run.started_at = None;
            run.last_heartbeat_at = None;
            run.retry_after = None;
            if let Err(error) = self.runtime_store.save_automation_run(&run).await {
                tracing::error!(run_id = %run.id, "could not reserve automation precheck: {error}");
                return;
            }
            self.start_automation_precheck(
                definition.clone(),
                run,
                location.host_id,
                location.path,
            );
            return;
        }
        Box::pin(self.dispatch_prechecked_automation(definition, run, location)).await;
    }

    pub(in crate::terminal_host::server) async fn dispatch_prechecked_automation(
        &mut self,
        definition: &AutomationDefinition,
        mut run: AutomationRun,
        location: super::super::automation_target_location::AutomationTargetLocation,
    ) {
        if let AutomationTarget::ExistingTab { tab_id, .. } = &definition.target {
            let session = self
                .runtime_store
                .find_workspace_tab(tab_id)
                .await
                .ok()
                .flatten()
                .and_then(|tab| super::super::requests::terminal_session_id_from_tab(&tab));
            if session.as_deref().is_some_and(|id| {
                self.sessions.get(id).is_some_and(|s| s.running())
                    && !self.agent_presence.is_injection_ready(id)
            }) {
                run.retry_after = Some(Utc::now() + chrono::Duration::seconds(5));
                let _ = self.runtime_store.save_automation_run(&run).await;
                return;
            }
        }
        let project = &location.project;
        run = match self
            .runtime_store
            .begin_automation_attempt(&run.id, definition.retry_max_attempts)
            .await
        {
            Ok(run) => run,
            Err(error) => {
                self.fail_run(&run, error.to_string()).await;
                return;
            }
        };
        if definition.target.project_checkout().is_some()
            && location.host_id != alera_core::runtime::LOCAL_HOST_ID
        {
            self.start_automation_checkout_preparation(definition.clone(), run, project.clone());
            return;
        }
        let source_workspace = if let AutomationTarget::ProjectWorktree {
            project_id,
            source_branch,
            name_template,
            ..
        } = &definition.target
        {
            let target = AutomationWorktree {
                project_id,
                source_branch,
                name_template,
                parent_workspace_id: None,
            };
            match self
                .project_worktree_automation_workspace(definition, &mut run, target)
                .await
            {
                Ok(Some(workspace)) => workspace,
                Ok(None) => return,
                Err(error) if is_non_retryable_dispatch_error(&error) => {
                    self.block_run(&run, &error.wire_message()).await;
                    return;
                }
                Err(error) => {
                    self.fail_run(&run, error.wire_message()).await;
                    return;
                }
            }
        } else if definition.target.project_checkout().is_some() {
            match self
                .allocate_project_checkout_automation_workspace(definition, &run)
                .await
            {
                Ok((bound, workspace)) => {
                    run = bound;
                    workspace
                }
                Err(error) => {
                    self.block_run(&run, &error.wire_message()).await;
                    return;
                }
            }
        } else {
            let Some(workspace) = location.workspace else {
                self.block_run(&run, "automation target workspace is missing")
                    .await;
                return;
            };
            workspace
        };
        // Dispatch includes workspace setup and profile launch. Keep that large
        // future off the actor's stack, including deferred precheck completions.
        Box::pin(self.continue_automation_dispatch(definition, run, source_workspace, project))
            .await;
    }

    pub(in crate::terminal_host::server) async fn continue_automation_dispatch(
        &mut self,
        definition: &AutomationDefinition,
        mut run: AutomationRun,
        source_workspace: alera_core::runtime::Workspace,
        project: &alera_core::runtime::Project,
    ) {
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
        let prompt = super::super::automation_run_recovery::automation_attempt_prompt(
            automation_prompt(&rendered, &run.id, definition.heartbeat_interval_seconds),
            &run,
        );
        run.rendered_prompt = Some(rendered);
        if let Err(error) = self.runtime_store.save_automation_run(&run).await {
            self.fail_run(&run, error.to_string()).await;
            return;
        }
        let result = match &definition.target {
            AutomationTarget::ProjectCheckout {
                agent_profile_id, ..
            } => {
                self.dispatch_fresh_tab(
                    &mut run,
                    &source_workspace.id,
                    agent_profile_id,
                    &prompt,
                    true,
                )
                .await
            }

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
            AutomationTarget::ProjectWorktree {
                agent_profile_id, ..
            } => {
                self.dispatch_fresh_tab(
                    &mut run,
                    &source_workspace.id,
                    agent_profile_id,
                    &prompt,
                    true,
                )
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
                let target = AutomationWorktree {
                    project_id: &project.id,
                    source_branch,
                    name_template,
                    parent_workspace_id: Some(&source_workspace.id),
                };
                match self
                    .create_automation_worktree(definition, &mut run, target)
                    .await
                {
                    Ok(Some(workspace)) => {
                        self.dispatch_fresh_tab(
                            &mut run,
                            &workspace.id,
                            agent_profile_id,
                            &prompt,
                            true,
                        )
                        .await
                    }
                    Ok(None) => return,
                    Err(error) => Err(error),
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
                    self.record_automation_process(&run).await;
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
}

#[path = "automation_fresh_tab_dispatch.rs"]
mod automation_fresh_tab_dispatch;
#[path = "automation_workspace_placement.rs"]
mod automation_workspace_placement;
#[path = "automation_worktree_dispatch.rs"]
mod automation_worktree_dispatch;
