use super::ServerActor;
use alera_core::runtime::{
    next_occurrence, AutomationActor, AutomationActorKind, AutomationDefinition,
    AutomationOccurrence, AutomationRunStatus, AutomationRunTrigger, AutomationSchedule,
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

impl ServerActor {
    pub(super) async fn handle_automation_tick(&mut self) {
        // Runtime mutations may delete a workspace on a worker while this
        // actor remains responsive. Do not create a new durable run or owner
        // after the mutation's ownership checks have started.
        if self.emulator_requests.has_runtime_mutations() {
            return;
        }
        let maintenance_now = Utc::now();
        if let Err(error) = self
            .runtime_store
            .prune_automation_history(maintenance_now)
            .await
        {
            tracing::warn!("automation history maintenance failed: {error}");
        }
        if let Err(error) = self
            .runtime_store
            .purge_trashed_automations_with_retention(
                maintenance_now,
                self.runtime_store
                    .automation_settings()
                    .await
                    .map(|settings| settings.trash_retention_days)
                    .unwrap_or(30),
            )
            .await
        {
            tracing::warn!("automation trash maintenance failed: {error}");
        }
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
        self.automations_active = active_definitions || !active_runs.is_empty();
        if active_definitions {
            let definitions = match self.runtime_store.list_automations(false).await {
                Ok(definitions) => definitions,
                Err(error) => {
                    tracing::error!("could not list automations: {error}");
                    return;
                }
            };
            for definition in definitions.into_iter().filter(|definition| {
                definition.state == AutomationState::Active && definition.is_approved()
            }) {
                self.evaluate_automation(definition).await;
            }
        }
        if self.automations_active {
            self.expire_inactive_automation_runs().await;
        }
        self.schedule_shutdown_if_idle();
    }

    async fn evaluate_automation(&mut self, definition: AutomationDefinition) {
        let now = Utc::now();
        let mut cursor = match &definition.schedule {
            AutomationSchedule::OneTime { .. } => chrono::DateTime::<Utc>::UNIX_EPOCH,
            AutomationSchedule::Recurring { start_at, .. } => self
                .runtime_store
                .latest_automation_occurrence(&definition.id)
                .await
                .ok()
                .flatten()
                .or(*start_at)
                .unwrap_or(definition.created_at),
        };
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
                    let _ = self
                        .runtime_store
                        .set_automation_state(
                            &definition.id,
                            AutomationState::Blocked,
                            managed_actor(),
                            Some(&error),
                        )
                        .await;
                    break;
                }
            };
            cursor = occurrence.scheduled_at;
            if !self
                .claim_and_start_scheduled(&definition, occurrence, now)
                .await
            {
                continue;
            }
            if started.elapsed() >= AUTOMATION_CATCH_UP_BUDGET {
                self.automation_wake.notify_one();
                break;
            }
        }
        self.resume_pending_runs(&definition).await;
    }

    async fn claim_and_start_scheduled(
        &mut self,
        definition: &AutomationDefinition,
        occurrence: AutomationOccurrence,
        now: chrono::DateTime<Utc>,
    ) -> bool {
        if let Some(maximum) = definition.schedule.max_scheduled_runs() {
            if self
                .runtime_store
                .count_scheduled_automation_executions(&definition.id)
                .await
                .unwrap_or(maximum)
                >= maximum
            {
                let _ = self
                    .runtime_store
                    .set_automation_state(
                        &definition.id,
                        AutomationState::Archived,
                        managed_actor(),
                        Some("maximum scheduled runs reached"),
                    )
                    .await;
                self.automations_active = false;
                return false;
            }
        }
        let claimed = match self
            .runtime_store
            .claim_automation_occurrence(&occurrence)
            .await
        {
            Ok(claimed) => claimed,
            Err(error) => {
                tracing::error!(automation_id = %definition.id, "could not claim automation occurrence: {error}");
                return false;
            }
        };
        if !claimed {
            return false;
        }
        let mut run = match self
            .runtime_store
            .create_automation_run(definition, &occurrence, AutomationRunTrigger::Scheduled)
            .await
        {
            Ok(run) => run,
            Err(error) => {
                tracing::error!(automation_id = %definition.id, "could not create automation run: {error}");
                return true;
            }
        };
        match self.target_identity(definition).await {
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
        let active_runs = self
            .runtime_store
            .list_active_automation_runs()
            .await
            .unwrap_or_default()
            .into_iter()
            .filter(|active| active.automation_id == definition.id && active.id != run.id)
            .collect::<Vec<_>>();
        match definition.overlap_policy {
            alera_core::runtime::AutomationOverlapPolicy::Skip if !active_runs.is_empty() => {
                let _ = self
                    .runtime_store
                    .update_automation_run_status(
                        &run.id,
                        AutomationRunStatus::OverlapSkipped,
                        Some("an automation run is already active".to_string()),
                    )
                    .await;
                return true;
            }
            alera_core::runtime::AutomationOverlapPolicy::RunLatestOnce
                if !active_runs.is_empty() =>
            {
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
            }
            alera_core::runtime::AutomationOverlapPolicy::Queue
                if active_runs
                    .iter()
                    .filter(|active| active.status == AutomationRunStatus::Pending)
                    .count()
                    >= definition.queue_cap.clamp(1, 10) as usize =>
            {
                let _ = self
                    .runtime_store
                    .update_automation_run_status(
                        &run.id,
                        AutomationRunStatus::QueueLimitSkipped,
                        Some("automation queue cap reached".to_string()),
                    )
                    .await;
                return true;
            }
            _ => {}
        }
        let is_misfire = now
            .signed_duration_since(occurrence.scheduled_at)
            .num_seconds()
            > definition.misfire_grace_seconds;
        let skip_misfire = match definition.misfire_policy {
            alera_core::runtime::AutomationMisfirePolicy::Skip => is_misfire,
            alera_core::runtime::AutomationMisfirePolicy::RunLatestOnce => {
                is_misfire && next_due_occurrence(definition, occurrence.scheduled_at, now)
            }
            alera_core::runtime::AutomationMisfirePolicy::Queue => false,
        };
        if skip_misfire {
            let _ = self
                .runtime_store
                .update_automation_run_status(
                    &run.id,
                    AutomationRunStatus::MisfireSkipped,
                    Some("scheduled occurrence exceeded its misfire grace window".to_string()),
                )
                .await;
            return true;
        }
        self.start_automation_run(definition, run, true).await;
        true
    }

    async fn resume_pending_runs(&mut self, definition: &AutomationDefinition) {
        let runs = match self
            .runtime_store
            .list_automation_runs(Some(&definition.id), 100)
            .await
        {
            Ok(runs) => runs,
            Err(_) => return,
        };
        for run in runs.into_iter().filter(|run| {
            run.status == AutomationRunStatus::Pending
                && run
                    .retry_after
                    .is_none_or(|retry_after| retry_after <= Utc::now())
        }) {
            self.start_automation_run(
                definition,
                run.clone(),
                run.precheck
                    .unwrap_or(run.trigger == AutomationRunTrigger::Scheduled),
            )
            .await;
        }
    }
}

#[path = "automation_dispatch_execution.rs"]
mod automation_dispatch_execution;
#[path = "automation_dispatch_helpers.rs"]
mod automation_dispatch_helpers;
#[path = "automation_manual_execution.rs"]
mod automation_manual_execution;
#[path = "automation_run_lifecycle.rs"]
mod automation_run_lifecycle;
pub(super) use automation_dispatch_helpers::{
    automation_prompt, render_workspace_name, run_precheck_command,
};
