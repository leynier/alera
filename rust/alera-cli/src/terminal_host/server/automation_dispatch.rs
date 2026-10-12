use super::ServerActor;
use alera_core::runtime::{
    next_occurrence, AutomationActor, AutomationActorKind, AutomationDefinition,
    AutomationMisfirePolicy, AutomationOccurrence, AutomationRunStatus, AutomationRunTrigger,
    AutomationState,
};
use chrono::Utc;
use std::time::{Duration as StdDuration, Instant};

const AUTOMATION_PRECHECK_OUTPUT_BYTES: usize = 16 * 1024;
const AUTOMATION_CATCH_UP_BUDGET: StdDuration = StdDuration::from_millis(100);

fn managed_actor() -> AutomationActor {
    AutomationActor {
        kind: AutomationActorKind::ManagedAgent,
        id: None,
        label: Some("Alera Automation Scheduler".to_string()),
    }
}

fn next_due_occurrence(
    definition: &AutomationDefinition,
    after: chrono::DateTime<Utc>,
    now: chrono::DateTime<Utc>,
) -> bool {
    next_occurrence(&definition.id, &definition.schedule, after)
        .ok()
        .flatten()
        .is_some_and(|next| next.scheduled_at <= now)
}

/// Whether the misfire policy drops this occurrence instead of running it.
/// `queue` runs every missed occurrence; `runLatestOnce` runs only the last
/// one that is due.
fn skips_misfire(
    definition: &AutomationDefinition,
    occurrence: &AutomationOccurrence,
    now: chrono::DateTime<Utc>,
    runtime_started_at: Option<chrono::DateTime<Utc>>,
) -> bool {
    let is_misfire = runtime_started_at.is_some_and(|at| occurrence.scheduled_at < at)
        || now
            .signed_duration_since(occurrence.scheduled_at)
            .num_seconds()
            > definition.misfire_grace_seconds;
    match definition.misfire_policy {
        AutomationMisfirePolicy::Skip => is_misfire,
        AutomationMisfirePolicy::RunLatestOnce => {
            is_misfire && next_due_occurrence(definition, occurrence.scheduled_at, now)
        }
        AutomationMisfirePolicy::Queue => false,
    }
}

impl ServerActor {
    pub(super) async fn handle_automation_tick(&mut self) {
        // Runtime mutations may delete a workspace on a worker while this
        // actor remains responsive. Do not create a new durable run or owner
        // after the mutation's ownership checks have started.
        if self.mutation_queue.has_runtime_mutations() {
            return;
        }
        self.recover_automation_shared_cleanups().await;
        let maintenance_now = Utc::now();
        if let Err(error) = self
            .runtime_store
            .prune_automation_history(maintenance_now)
            .await
        {
            tracing::warn!("automation history maintenance failed: {error}");
        }
        match self
            .runtime_store
            .purge_trashed_automations(maintenance_now)
            .await
        {
            Ok(0) => {}
            Ok(_) => self.broadcast_automation_changed(None),
            Err(error) => tracing::warn!("automation trash maintenance failed: {error}"),
        }
        match self
            .runtime_store
            .reset_expired_automation_circuits(maintenance_now, managed_actor())
            .await
        {
            Ok((reset, errors)) => {
                for error in errors {
                    tracing::warn!("automation circuit reset failed: {error}");
                }
                if reset > 0 {
                    self.automation_wake.notify_one();
                    self.broadcast_automation_changed(None);
                }
            }
            Err(error) => tracing::warn!("automation circuit reset failed: {error}"),
        }
        self.reconcile_automation_runs().await;
        let previous_active = self.automations_active;
        let active_definitions = match self.runtime_store.has_active_automations().await {
            Ok(active) => active,
            Err(error) => {
                tracing::error!("could not inspect active automations: {error}");
                false
            }
        };
        let active_runs = self
            .runtime_store
            .list_active_automation_runs()
            .await
            .unwrap_or_default();
        let pending_circuits = match self.runtime_store.has_pending_automation_work().await {
            Ok(pending) => pending,
            Err(error) => {
                tracing::error!("could not inspect pending automation work: {error}");
                previous_active || active_definitions || !active_runs.is_empty()
            }
        };
        self.automations_active = pending_circuits;
        if active_definitions {
            match self.runtime_store.list_automations(false).await {
                Ok(definitions) => {
                    for definition in definitions
                        .into_iter()
                        .filter(|definition| definition.state == AutomationState::Active)
                    {
                        self.evaluate_automation(definition).await;
                    }
                }
                Err(error) => tracing::error!("could not list automations: {error}"),
            }
        }
        for definition in self
            .runtime_store
            .list_automations(false)
            .await
            .unwrap_or_default()
        {
            if definition.state != AutomationState::Active
                && definition.state != AutomationState::Trashed
            {
                self.resume_pending_runs(&definition).await;
            }
        }
        if self.automations_active {
            self.expire_inactive_automation_runs().await;
        }
        self.automations_active = self
            .runtime_store
            .has_pending_automation_work()
            .await
            .unwrap_or(self.automations_active);
        self.schedule_shutdown_if_idle();
    }

    async fn evaluate_automation(&mut self, definition: AutomationDefinition) {
        let now = Utc::now();
        let mut cursor = alera_core::runtime::automation_cursor(
            &definition,
            self.runtime_store
                .latest_automation_occurrence(&definition.id)
                .await
                .ok()
                .flatten(),
        );
        let runtime_started_at = self
            .runtime_store
            .get_metadata("automations.runtimeStartedAt")
            .await
            .ok()
            .flatten()
            .and_then(|at| chrono::DateTime::parse_from_rfc3339(&at).ok())
            .map(|at| at.with_timezone(&Utc));
        let mut missed = Vec::new();
        let started = Instant::now();
        loop {
            if started.elapsed() >= AUTOMATION_CATCH_UP_BUDGET {
                self.automation_wake.notify_one();
                break;
            }
            let occurrence = match next_occurrence(&definition.id, &definition.schedule, cursor) {
                Ok(Some(value)) if value.scheduled_at <= now => value,
                Ok(Some(_)) | Ok(None) => break,
                Err(error) => {
                    tracing::warn!(automation_id = %definition.id, "invalid automation occurrence: {error}");
                    if self
                        .runtime_store
                        .set_automation_state(
                            &definition.id,
                            AutomationState::Blocked,
                            managed_actor(),
                            Some(&error),
                        )
                        .await
                        .is_ok()
                    {
                        self.broadcast_automation_changed(Some(&definition.id));
                    }
                    break;
                }
            };
            cursor = occurrence.scheduled_at;
            if skips_misfire(&definition, &occurrence, now, runtime_started_at) {
                missed.push(occurrence);
                continue;
            }
            if !self
                .claim_and_start_scheduled(&definition, occurrence)
                .await
            {
                continue;
            }
            if started.elapsed() >= AUTOMATION_CATCH_UP_BUDGET {
                self.automation_wake.notify_one();
                break;
            }
        }
        self.record_skipped_misfires(&definition, &missed).await;
        self.resume_pending_runs(&definition).await;
    }

    /// Claims occurrences the misfire policy drops without creating a run for
    /// each one, and leaves one audit entry for the whole batch.
    async fn record_skipped_misfires(
        &self,
        definition: &AutomationDefinition,
        missed: &[AutomationOccurrence],
    ) {
        let (Some(first), Some(last)) = (missed.first(), missed.last()) else {
            return;
        };
        let count = match self
            .runtime_store
            .claim_skipped_automation_occurrences(&definition.id, missed)
            .await
        {
            Ok(0) => return,
            Ok(count) => count,
            Err(error) => {
                tracing::error!(automation_id = %definition.id, "could not claim missed automation occurrences: {error}");
                return;
            }
        };
        if let Err(error) = self
            .runtime_store
            .insert_automation_audit_event(
                Some(&definition.id),
                None,
                "misfiresSkipped",
                managed_actor(),
                Some(definition.revision),
                serde_json::json!({
                    "count": count,
                    "from": first.scheduled_at,
                    "to": last.scheduled_at,
                }),
            )
            .await
        {
            tracing::warn!(automation_id = %definition.id, "could not audit missed automation occurrences: {error}");
        }
        self.broadcast_automation_changed(Some(&definition.id));
    }

    async fn claim_and_start_scheduled(
        &mut self,
        definition: &AutomationDefinition,
        occurrence: AutomationOccurrence,
    ) -> bool {
        if let Some(maximum) = definition.schedule.max_scheduled_runs() {
            if self
                .runtime_store
                .count_scheduled_automation_executions(&definition.id)
                .await
                .unwrap_or(maximum)
                >= maximum
            {
                if self
                    .runtime_store
                    .set_automation_state(
                        &definition.id,
                        AutomationState::Archived,
                        managed_actor(),
                        Some("maximum scheduled runs reached"),
                    )
                    .await
                    .is_ok()
                {
                    self.broadcast_automation_changed(Some(&definition.id));
                }
                return false;
            }
        }
        let mut run = match self
            .runtime_store
            .admit_automation_run(
                definition,
                &occurrence,
                AutomationRunTrigger::Scheduled,
                true,
            )
            .await
        {
            Ok(Some(run)) => run,
            Ok(None) => return false,
            Err(error) => {
                tracing::error!(automation_id = %definition.id, "could not admit automation run: {error}");
                return false;
            }
        };
        self.broadcast_automation_run_changed(&run);
        match self
            .target_identity(&definition.target, definition.reuse_policy)
            .await
        {
            Ok(identity) => {
                run.target_identity = Some(identity);
                if let Err(error) = self.runtime_store.save_automation_run(&run).await {
                    tracing::error!(
                        automation_id = %definition.id,
                        run_id = %run.id,
                        "could not bind scheduled automation target: {error}"
                    );
                    return false;
                }
            }
            Err(reason) => {
                self.block_run(&run, &reason).await;
                return true;
            }
        }
        Box::pin(self.start_automation_run(definition, run, true)).await;
        true
    }

    async fn resume_pending_runs(&mut self, definition: &AutomationDefinition) {
        let runs = match self.runtime_store.list_active_automation_runs().await {
            Ok(runs) => runs,
            Err(_) => return,
        };
        for run in runs.into_iter().filter(|run| {
            run.automation_id == definition.id
                && run.status == AutomationRunStatus::Pending
                && run
                    .retry_after
                    .is_none_or(|retry_after| retry_after <= Utc::now())
        }) {
            let frozen = run
                .definition_snapshot
                .clone()
                .unwrap_or_else(|| definition.clone());
            // A run parked behind a busy bound target was never interrupted.
            if run
                .recovery
                .as_ref()
                .is_some_and(|recovery| recovery.status != "waiting")
                && run.attempt_count > 0
                && (run.tab_id.is_some() || run.session_id.is_some())
            {
                Box::pin(self.resume_interrupted_automation_run(&frozen, run)).await;
                continue;
            }
            Box::pin(
                self.start_automation_run(
                    &frozen,
                    run.clone(),
                    run.precheck
                        .unwrap_or(run.trigger == AutomationRunTrigger::Scheduled),
                ),
            )
            .await;
        }
    }
}

#[path = "automation_checkout_preparation.rs"]
mod automation_checkout_preparation;
#[path = "automation_local_precheck.rs"]
pub(super) mod automation_local_precheck;
#[path = "automation_owner_precheck_requests.rs"]
mod automation_owner_precheck_requests;
#[path = "automation_precheck_authorization.rs"]
pub(super) mod automation_precheck_authorization;
#[path = "automation_precheck_command_owner.rs"]
mod automation_precheck_command_owner;
#[path = "automation_precheck_execution.rs"]
mod automation_precheck_execution;
#[path = "automation_project_checkout_dispatch.rs"]
mod automation_project_checkout_dispatch;

#[path = "automation_dispatch_execution.rs"]
mod automation_dispatch_execution;
#[path = "automation_dispatch_helpers.rs"]
mod automation_dispatch_helpers;
#[path = "automation_manual_execution.rs"]
mod automation_manual_execution;
#[path = "automation_run_lifecycle.rs"]
mod automation_run_lifecycle;
#[cfg(test)]
pub(super) use automation_dispatch_execution::AutomationWorktree;
pub(super) use automation_dispatch_helpers::{
    automation_prompt, render_workspace_name, run_precheck_command,
};
