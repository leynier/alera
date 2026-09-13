use alera_core::runtime::{OwnerAutomationPrecheckOutcome, OwnerAutomationPrecheckRequest};
use serde_json::{json, Value};

use super::super::{ClientKind, ServerActor, ServerCommand};
use crate::terminal_host::host_error::{HostError, HostResult};

impl ServerActor {
    pub(in crate::terminal_host::server) async fn owner_precheck_request(
        &mut self,
        client_id: u64,
        verb: &str,
        payload: &Value,
    ) -> HostResult<Value> {
        self.require_request_allowed(client_id, verb)?;
        if self
            .clients
            .get(&client_id)
            .is_none_or(|client| client.kind != ClientKind::Local)
        {
            return Err(HostError::state(
                "Owner prechecks require a local runtime client",
            ));
        }
        let request: OwnerAutomationPrecheckRequest =
            super::super::requests::parse_payload(payload)?;
        if verb == "automation.ownerPrecheck.start" {
            let job = self
                .runtime_store
                .register_owner_automation_precheck(&request)
                .await
                .map_err(host_error)?;
            if job.outcome.is_none() && job.process_id.is_none() && !job.cancel_requested {
                let key = format!("owner:{}", request.operation_id);
                if self.automation_precheck_jobs.insert(key) {
                    self.cancel_shutdown_timer();
                    let store = self.runtime_store.clone();
                    let inbox = self.inbox.clone();
                    let operation = request.clone();
                    tokio::spawn(async move {
                        let result = async {
                            store
                                .set_owner_precheck_attention(&operation, None)
                                .await
                                .map_err(|error| error.to_string())?;
                            tokio::time::timeout(
                                std::time::Duration::from_secs(60),
                                authorize(&store, &operation),
                            )
                            .await
                            .map_err(|_| "Owner precheck authorization timed out".to_string())??;
                            super::automation_local_precheck::run_owner_precheck(
                                &store, &operation,
                            )
                            .await?;
                            Ok::<(), String>(())
                        }
                        .await;
                        if let Err(error) = result {
                            if let Err(persistence) = store
                                .set_owner_precheck_attention(&operation, Some(&error))
                                .await
                            {
                                tracing::warn!(
                                    "Owner precheck attention could not be recorded: {persistence}"
                                );
                            }
                        }
                        let _ = inbox.send(ServerCommand::OwnerAutomationPrecheckFinished {
                            operation_id: operation.operation_id,
                        });
                    });
                }
            }
        } else if verb == "automation.ownerPrecheck.cancel" {
            self.runtime_store
                .cancel_owner_automation_precheck(&request)
                .await
                .map_err(host_error)?;
            if self
                .runtime_store
                .find_owner_automation_precheck(&request.operation_id)
                .await
                .map_err(host_error)?
                .is_some_and(|job| job.process_id.is_none() && job.outcome.is_none())
            {
                self.runtime_store
                    .finish_owner_automation_precheck(
                        &request,
                        &OwnerAutomationPrecheckOutcome::Cancelled,
                    )
                    .await
                    .map_err(host_error)?;
            }
        } else if verb != "automation.ownerPrecheck.status" {
            return Err(HostError::state("Unknown owner precheck operation"));
        }
        self.reconcile_owner_precheck(&request).await?;
        let job = self
            .runtime_store
            .find_owner_automation_precheck(&request.operation_id)
            .await
            .map_err(host_error)?
            .ok_or_else(|| HostError::state("Owner precheck reservation is missing"))?;
        if job.request != request {
            return Err(HostError::state("Owner precheck request identity changed"));
        }
        let processes = match &job.process_id {
            Some(id) => self
                .runtime_store
                .automation_precheck_processes(id)
                .await
                .map_err(host_error)?,
            None => Vec::new(),
        };
        Ok(json!({"version":1,"job":job,"processes":processes}))
    }

    async fn reconcile_owner_precheck(
        &self,
        request: &OwnerAutomationPrecheckRequest,
    ) -> HostResult<()> {
        use alera_core::runtime::WorkspaceProcessJobPhase::{ClosureVerified, SpawnFailed};
        if self
            .automation_precheck_jobs
            .contains(&format!("owner:{}", request.operation_id))
        {
            return Ok(());
        }
        let job = self
            .runtime_store
            .find_owner_automation_precheck(&request.operation_id)
            .await
            .map_err(host_error)?
            .ok_or_else(|| HostError::state("Owner precheck reservation is missing"))?;
        if job.request != *request {
            return Err(HostError::state("Owner precheck request identity changed"));
        }
        if job.outcome.is_some() {
            return Ok(());
        }
        let Some(process_id) = &job.process_id else {
            return Ok(());
        };
        let mut processes = self
            .runtime_store
            .automation_precheck_processes(process_id)
            .await
            .map_err(host_error)?;
        if processes.len() != 1 {
            return Err(HostError::state(
                "Owner precheck process evidence is missing or ambiguous",
            ));
        }
        let process = &mut processes[0];
        if !matches!(process.phase, ClosureVerified | SpawnFailed) {
            let boot =
                tokio::task::spawn_blocking(crate::relocation_setup_process::current_boot_id)
                    .await
                    .ok()
                    .and_then(Result::ok)
                    .flatten();
            if let Some(boot) = boot {
                if let Ok(closed) = self
                    .runtime_store
                    .close_automation_precheck_from_previous_boot(process, &boot)
                    .await
                {
                    *process = closed;
                }
            }
        }
        if !matches!(process.phase, ClosureVerified | SpawnFailed) {
            return self.runtime_store.set_owner_precheck_attention(request,
                Some("The owner runtime lost native process ownership; closure is unverified. The command will not be repeated and its checkout remains protected."))
                .await.map_err(host_error);
        }
        let outcome = if job.cancel_requested {
            OwnerAutomationPrecheckOutcome::Cancelled
        } else {
            OwnerAutomationPrecheckOutcome::Failed("The owner runtime was interrupted; process closure is verified but the command result is unavailable".into())
        };
        self.runtime_store
            .finish_owner_automation_precheck(request, &outcome)
            .await
            .map_err(host_error)
    }

    pub(in crate::terminal_host::server) fn finish_owner_precheck(&mut self, operation_id: &str) {
        self.automation_precheck_jobs
            .remove(&format!("owner:{operation_id}"));
        self.schedule_shutdown_if_idle();
    }
}

async fn authorize(
    store: &alera_core::runtime::RuntimeStore,
    request: &OwnerAutomationPrecheckRequest,
) -> Result<(), String> {
    let project = store
        .find_project(&request.project_id)
        .await
        .map_err(|error| error.to_string())?
        .ok_or("Owner precheck project is missing")?;
    crate::owner_precheck_checkout::inspect(request, project.kind)
        .await
        .map_err(|error| error.to_string())?;
    let policy = store
        .automation_project_policy(&project.id)
        .await
        .map_err(|error| error.to_string())?;
    if policy.restrictive && !policy.local_approved {
        return Err("Owner precheck project requires local approval".into());
    }
    Ok(())
}

fn host_error(error: impl std::fmt::Display) -> HostError {
    HostError::state(error.to_string())
}
