use alera_core::runtime::{
    AutomationActor, AutomationActorKind, AutomationDefinition, AutomationRun, AutomationRunStatus,
};

use super::super::ServerCommand;
use super::automation_run_lifecycle::is_non_retryable_reason;
use super::{run_precheck_command, ServerActor};

impl ServerActor {
    pub(in crate::terminal_host::server) async fn resume_remote_automation_precheck(
        &mut self,
        run: &AutomationRun,
    ) -> bool {
        if !matches!(
            run.status,
            AutomationRunStatus::Dispatching | AutomationRunStatus::WaitingForUser
        ) || run.precheck != Some(true)
            || run.started_at.is_some()
        {
            return false;
        }
        let Ok(records) = self
            .runtime_store
            .automation_precheck_processes(&run.id)
            .await
        else {
            return false;
        };
        let [intent] = records.as_slice() else {
            return false;
        };
        if intent.host_id == alera_core::runtime::LOCAL_HOST_ID {
            return false;
        }
        let Ok(Some(definition)) = self.runtime_store.find_automation(&run.automation_id).await
        else {
            return false;
        };
        self.start_automation_precheck(
            definition,
            run.clone(),
            intent.host_id.clone(),
            intent.path.clone(),
        );
        true
    }

    pub(in crate::terminal_host::server) async fn retain_unverified_precheck(
        &mut self,
        run: &AutomationRun,
    ) -> bool {
        use alera_core::runtime::WorkspaceProcessJobPhase::{ClosureVerified, SpawnFailed};
        let unresolved = match self
            .runtime_store
            .automation_precheck_processes(&run.id)
            .await
        {
            Ok(records) => {
                let mut unresolved = false;
                let open: Vec<_> = records
                    .into_iter()
                    .filter(|record| !matches!(record.phase, ClosureVerified | SpawnFailed))
                    .collect();
                let boot = if open.is_empty() {
                    None
                } else {
                    tokio::task::spawn_blocking(crate::relocation_setup_process::current_boot_id)
                        .await
                        .ok()
                        .and_then(Result::ok)
                        .flatten()
                };
                for record in open {
                    let closed = if let Some(boot) = &boot {
                        self.runtime_store
                            .close_automation_precheck_from_previous_boot(&record, boot)
                            .await
                            .is_ok()
                    } else {
                        false
                    };
                    unresolved |= !closed;
                }
                unresolved
            }
            Err(_) => true,
        };
        if unresolved && run.status != AutomationRunStatus::WaitingForUser {
            let _ = self.runtime_store.update_automation_run_status(
                &run.id, AutomationRunStatus::WaitingForUser,
                Some("Automation precheck process closure is unverified; its run and dependencies are retained".into()),
            ).await;
        }
        unresolved
    }

    pub(in crate::terminal_host::server) async fn recover_interrupted_automation_precheck(
        &mut self,
        run: &AutomationRun,
    ) -> bool {
        // Only a reserved precheck has Dispatching without a started attempt.
        // Never repeat a command whose completion was lost across restart.
        if matches!(
            run.status,
            AutomationRunStatus::Dispatching | AutomationRunStatus::WaitingForUser
        ) && run.precheck == Some(true)
            && run.started_at.is_none()
            && !self.automation_precheck_jobs.contains(&run.id)
        {
            if self.retain_unverified_precheck(run).await {
                return true;
            }
            self.block_run(
                run,
                "Runtime restarted during automation precheck; command completion is unverified",
            )
            .await;
            return true;
        }
        false
    }

    pub(in crate::terminal_host::server) fn start_automation_precheck(
        &mut self,
        definition: AutomationDefinition,
        run: AutomationRun,
        host_id: String,
        path: String,
    ) {
        if !self.automation_precheck_jobs.insert(run.id.clone()) {
            return;
        }
        self.cancel_shutdown_timer();
        let store = self.runtime_store.clone();
        let inbox = self.inbox.clone();
        tokio::spawn(async move {
            let retained = store.automation_precheck_processes(&run.id).await;
            let result = match retained {
                Err(error) => Err(error.to_string()),
                Ok(records)
                    if records
                        .iter()
                        .any(|record| record.host_id != alera_core::runtime::LOCAL_HOST_ID) =>
                {
                    // Recovery may query/cancel the pinned owner operation,
                    // but cannot authorize a new dispatch from a changed definition.
                    run_precheck_command(&store, &host_id, &definition, &run, &path).await.and_then(|_| {
                        Err("Runtime restarted during automation precheck; command closure is verified but dispatch requires a new run".into())
                    })
                }
                Ok(_) => {
                    super::automation_precheck_authorization::execute_authorized_precheck(
                        &store,
                        &definition,
                        &run,
                        &host_id,
                        &path,
                        &crate::ssh_remote::LiveSshRemoteHost,
                        run_precheck_command(&store, &host_id, &definition, &run, &path),
                    )
                    .await
                }
            };
            let _ = inbox.send(ServerCommand::AutomationPrecheckFinished {
                definition: Box::new(definition),
                run: Box::new(run),
                host_id,
                path,
                result,
            });
        });
    }

    pub(in crate::terminal_host::server) async fn finish_automation_precheck(
        &mut self,
        definition: AutomationDefinition,
        started: AutomationRun,
        host_id: String,
        path: String,
        result: Result<bool, String>,
    ) {
        self.automation_precheck_jobs.remove(&started.id);
        self.complete_precheck_if_current(definition, started, host_id, path, result)
            .await;
        self.schedule_shutdown_if_idle();
    }

    async fn complete_precheck_if_current(
        &mut self,
        definition: AutomationDefinition,
        started: AutomationRun,
        host_id: String,
        path: String,
        result: Result<bool, String>,
    ) {
        let Ok(Some(current)) = self.runtime_store.find_automation_run(&started.id).await else {
            return;
        };
        if self.retain_unverified_precheck(&current).await {
            return;
        }
        if !matches!(
            current.status,
            AutomationRunStatus::Dispatching | AutomationRunStatus::WaitingForUser
        ) || current.attempt_count != started.attempt_count
        {
            return;
        }
        if current.cancel_requested_at.is_some() {
            let _ = self
                .runtime_store
                .update_automation_run_status(
                    &current.id,
                    AutomationRunStatus::Cancelled,
                    Some("Automation cancelled during precheck".into()),
                )
                .await;
            return;
        }
        let Ok(Some(latest)) = self.runtime_store.find_automation(&definition.id).await else {
            self.block_run(
                &current,
                "Automation definition disappeared during precheck",
            )
            .await;
            return;
        };
        if latest.revision != definition.revision
            || latest.state != definition.state
            || latest.target != definition.target
        {
            self.block_run(&current, "Automation definition changed during precheck")
                .await;
            return;
        }
        if let Err(error) = self
            .ensure_dispatch_policy(
                &latest,
                &AutomationActor {
                    kind: AutomationActorKind::ManagedAgent,
                    id: current.actor_id.clone(),
                    label: Some("Alera Automation Scheduler".into()),
                },
            )
            .await
        {
            self.block_run(&current, &error.wire_message()).await;
            return;
        }
        let location = match self.automation_target_location(&latest).await {
            Ok(location) => location,
            Err(error) => {
                self.block_run(&current, &error.wire_message()).await;
                return;
            }
        };
        if location.host_id != host_id || location.path != path {
            self.block_run(
                &current,
                "Automation target location changed during precheck",
            )
            .await;
            return;
        }
        let error = match result {
            Ok(true) => {
                self.dispatch_prechecked_automation(&latest, current, location)
                    .await;
                return;
            }
            Ok(false) => "automation precheck did not pass".to_string(),
            Err(error) => error,
        };
        if is_non_retryable_reason(&error) {
            self.block_run(&current, &error).await;
        } else {
            let _ = self
                .runtime_store
                .update_automation_run_status(
                    &current.id,
                    AutomationRunStatus::PrecheckSkipped,
                    Some(error),
                )
                .await;
        }
    }
}
