use alera_core::runtime::{
    decide_overlap, prompt_value_map, render_prompt_template, AutomationActorKind,
    AutomationDefinition, AutomationOverlapDecision, AutomationRun, AutomationRunStatus,
    AUTOMATION_OVERLAP_SUPERSEDED_REASON, AUTOMATION_QUEUE_LIMIT_REASON,
};
use chrono::Utc;
use std::future::Future;
use std::pin::Pin;

use super::super::automation_bound_target_resolution::BoundTargetPlan;
use super::automation_run_lifecycle::is_non_retryable_dispatch_error;
use super::{automation_prompt, ServerActor};
pub(in crate::terminal_host::server) use automation_worktree_dispatch::AutomationWorktree;

impl ServerActor {
    /// Starts a pending run unless its overlap policy keeps it waiting or
    /// skips it. This is the only place overlap is decided, for scheduled,
    /// manual and resumed runs alike.
    pub(in crate::terminal_host::server) async fn start_automation_run(
        &mut self,
        definition: &AutomationDefinition,
        mut run: AutomationRun,
        run_precheck: bool,
    ) -> AutomationOverlapDecision {
        if self.automation_precheck_jobs.contains(&run.id) {
            return AutomationOverlapDecision::Proceed;
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
            self.broadcast_automation_run_changed(&run);
            return AutomationOverlapDecision::Wait;
        }
        run.recovery = None;
        let _ = self.runtime_store.save_automation_run(&run).await;
        self.automations_active = true;
        self.cancel_shutdown_timer();
        let decision = self.apply_overlap_policy(definition, &run).await;
        if decision != AutomationOverlapDecision::Proceed {
            return decision;
        }
        self.dispatch_admitted_automation_run(definition, run, run_precheck)
            .await;
        AutomationOverlapDecision::Proceed
    }

    async fn apply_overlap_policy(
        &self,
        definition: &AutomationDefinition,
        run: &AutomationRun,
    ) -> AutomationOverlapDecision {
        let active = self
            .runtime_store
            .list_active_automation_runs()
            .await
            .unwrap_or_default()
            .into_iter()
            .filter(|active| active.automation_id == definition.id)
            .collect::<Vec<_>>();
        let policy = run.overlap_policy.unwrap_or(definition.overlap_policy);
        let (decision, superseded) = decide_overlap(policy, definition.queue_cap, &run.id, &active);
        for id in superseded {
            let _ = self
                .set_automation_run_status(
                    &id,
                    AutomationRunStatus::OverlapSkipped,
                    Some(AUTOMATION_OVERLAP_SUPERSEDED_REASON.to_string()),
                )
                .await;
        }
        let skipped = match decision {
            AutomationOverlapDecision::Skip(reason) => {
                Some((AutomationRunStatus::OverlapSkipped, reason))
            }
            AutomationOverlapDecision::QueueLimit => Some((
                AutomationRunStatus::QueueLimitSkipped,
                AUTOMATION_QUEUE_LIMIT_REASON,
            )),
            AutomationOverlapDecision::Proceed | AutomationOverlapDecision::Wait => None,
        };
        if let Some((status, reason)) = skipped {
            let _ = self
                .set_automation_run_status(&run.id, status, Some(reason.to_string()))
                .await;
        }
        decision
    }

    async fn dispatch_admitted_automation_run(
        &mut self,
        definition: &AutomationDefinition,
        mut run: AutomationRun,
        run_precheck: bool,
    ) {
        if let Err(error) = self.ensure_target_valid(definition).await {
            self.block_run(&run, &error.wire_message()).await;
            return;
        }
        // Bind the durable target before a workspace or project lookup can
        // fail, so attention notifications still have a useful location.
        let target_identity = match self
            .target_identity(&definition.target, definition.reuse_policy)
            .await
        {
            Ok(identity) => identity,
            Err(error) => {
                self.block_run(&run, &error).await;
                return;
            }
        };
        let mut target_identity = target_identity;
        let creates_workspace = definition.target.project_checkout().is_some()
            || definition.target.worktree().is_some();
        if creates_workspace && run.owned_workspace {
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
            self.broadcast_automation_run_changed(&run);
            self.start_automation_precheck(
                definition.clone(),
                run,
                location.host_id,
                location.path,
            );
            return;
        }
        self.dispatch_prechecked_automation(definition, run, location)
            .await;
    }

    // The two dispatch steps return their futures already boxed: the chain
    // down to the PTY spawn is deep, and an unoptimized build keeps a future
    // in the poll frame of whatever function constructs it.
    pub(in crate::terminal_host::server) fn dispatch_prechecked_automation<'a>(
        &'a mut self,
        definition: &'a AutomationDefinition,
        run: AutomationRun,
        location: super::super::automation_target_location::AutomationTargetLocation,
    ) -> Pin<Box<impl Future<Output = ()> + 'a>> {
        Box::pin(self.dispatch_prechecked_inner(definition, run, location))
    }

    async fn dispatch_prechecked_inner(
        &mut self,
        definition: &AutomationDefinition,
        mut run: AutomationRun,
        location: super::super::automation_target_location::AutomationTargetLocation,
    ) {
        let plan = match self.plan_bound_target_task(definition, &run).await {
            Ok(BoundTargetPlan::Busy { code, session_id }) => {
                tracing::debug!(run_id = %run.id, ?session_id, code, "automation bound target is busy");
                match self.park_task(definition, &mut run, code).await {
                    Some(plan) => plan,
                    None => return,
                }
            }
            Ok(plan) => plan,
            Err(error) if is_non_retryable_dispatch_error(&error) => {
                self.block_run(&run, &error.wire_message()).await;
                return;
            }
            Err(error) => {
                self.fail_run(&run, error.wire_message()).await;
                return;
            }
        };
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
        self.broadcast_automation_run_changed(&run);
        let reused = plan.reused_workspace().cloned();
        if reused.is_none()
            && definition.target.project_checkout().is_some()
            && location.host_id != alera_core::runtime::LOCAL_HOST_ID
        {
            self.start_automation_checkout_preparation(definition.clone(), run, project.clone());
            return;
        }
        let source_workspace = if let Some(workspace) = reused {
            workspace
        } else if let Some(spec) = definition.target.worktree() {
            if spec.parent_workspace_id.is_some()
                && location.host_id != alera_core::runtime::LOCAL_HOST_ID
            {
                self.block_run(&run, "worktree automation requires a local execution host")
                    .await;
                return;
            }
            let target = AutomationWorktree {
                project_id: &project.id,
                source_branch: spec.source_branch,
                name_template: spec.name_template,
                parent_workspace_id: spec.parent_workspace_id,
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
        self.continue_automation_dispatch(definition, run, source_workspace, project, plan)
            .await;
    }

    pub(in crate::terminal_host::server) fn continue_automation_dispatch<'a>(
        &'a mut self,
        definition: &'a AutomationDefinition,
        run: AutomationRun,
        source_workspace: alera_core::runtime::Workspace,
        project: &'a alera_core::runtime::Project,
        plan: BoundTargetPlan,
    ) -> Pin<Box<impl Future<Output = ()> + 'a>> {
        Box::pin(self.continue_dispatch_inner(definition, run, source_workspace, project, plan))
    }

    async fn continue_dispatch_inner(
        &mut self,
        definition: &AutomationDefinition,
        mut run: AutomationRun,
        source_workspace: alera_core::runtime::Workspace,
        project: &alera_core::runtime::Project,
        plan: BoundTargetPlan,
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
        let rendered = match render_prompt_template(definition, &values) {
            Ok(value) => value,
            Err(error) => {
                self.block_run(&run, &error).await;
                return;
            }
        };
        let rendered = self
            .reuse_preface_task(definition, &run, &plan, rendered)
            .await;
        let prompt = super::super::automation_run_recovery::automation_attempt_prompt(
            automation_prompt(&rendered, &run.id, definition.heartbeat_interval_seconds),
            &run,
        );
        run.rendered_prompt = Some(rendered);
        if let Err(error) = self.runtime_store.save_automation_run(&run).await {
            self.fail_run(&run, error.to_string()).await;
            return;
        }
        run.reuse = super::super::automation_bound_target_dispatch::run_reuse(definition, &plan);
        let result = self
            .dispatch_plan_task(definition, &mut run, &plan, &source_workspace, &prompt)
            .await;
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
                    self.record_bound_target_task(definition, &run, &plan).await;
                }
                self.broadcast_automation_run_changed(&run);
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
