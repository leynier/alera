use super::super::ServerCommand;
use super::{render_workspace_name, ServerActor};
use crate::terminal_host::host_error::{HostError, HostResult};
use alera_core::runtime::{
    AutomationDefinition, AutomationRun, AutomationRunStatus, AutomationTarget, Project, Workspace,
};

impl ServerActor {
    pub(in crate::terminal_host::server) fn start_automation_checkout_preparation(
        &mut self,
        definition: AutomationDefinition,
        run: AutomationRun,
        project: Project,
    ) {
        let store = self.runtime_store.clone();
        let AutomationTarget::ProjectCheckout {
            project_id,
            host_id,
            name_template,
            ..
        } = &definition.target
        else {
            return;
        };
        let request = crate::shared_workspace::SharedWorkspaceCreateRequest {
            project_id: project_id.clone(),
            host_id: Some(host_id.clone()),
            id: None,
            name: Some(render_workspace_name(name_template, &definition, &run)),
            parent_workspace_id: None,
        };
        self.defer_automation_checkout_preparation(definition, run, project, async move {
            crate::shared_workspace::prepare_fresh_shared_workspace(&store, request)
                .await
                .map_err(|error| HostError::state(error.to_string()))
        });
    }

    pub(in crate::terminal_host::server) fn defer_automation_checkout_preparation<F>(
        &mut self,
        definition: AutomationDefinition,
        run: AutomationRun,
        project: Project,
        preparation: F,
    ) where
        F: std::future::Future<Output = HostResult<Workspace>> + Send + 'static,
    {
        if !self.automation_checkout_jobs.insert(run.id.clone()) {
            return;
        }
        self.cancel_shutdown_timer();
        let inbox = self.inbox.clone();
        tokio::spawn(async move {
            let result = tokio::time::timeout(std::time::Duration::from_secs(60), preparation)
                .await
                .unwrap_or_else(|_| {
                    Err(HostError::state(
                        "SSH automation checkout preparation timed out",
                    ))
                });
            let _ = inbox.send(ServerCommand::AutomationCheckoutPrepared {
                definition: Box::new(definition),
                run: Box::new(run),
                project: Box::new(project),
                result,
            });
        });
    }

    pub(in crate::terminal_host::server) async fn finish_automation_checkout_preparation(
        &mut self,
        definition: AutomationDefinition,
        started: AutomationRun,
        project: Project,
        result: HostResult<Workspace>,
    ) {
        self.automation_checkout_jobs.remove(&started.id);
        self.complete_preparation_if_current(definition, started, project, result)
            .await;
        self.schedule_shutdown_if_idle();
    }

    async fn complete_preparation_if_current(
        &mut self,
        definition: AutomationDefinition,
        started: AutomationRun,
        project: Project,
        result: HostResult<Workspace>,
    ) {
        let Ok(Some(current)) = self.runtime_store.find_automation_run(&started.id).await else {
            return;
        };
        if current.status != AutomationRunStatus::Dispatching
            || current.attempt_count != started.attempt_count
        {
            return;
        }
        if current.cancel_requested_at.is_some() {
            let _ = self
                .runtime_store
                .update_automation_run_status(
                    &current.id,
                    AutomationRunStatus::Cancelled,
                    Some("Automation cancelled during checkout preparation".into()),
                )
                .await;
            return;
        }
        let Ok(Some(latest)) = self.runtime_store.find_automation(&definition.id).await else {
            self.block_run(
                &current,
                "Automation definition disappeared during checkout preparation",
            )
            .await;
            return;
        };
        if latest.revision != definition.revision
            || latest.state != definition.state
            || latest.target != definition.target
        {
            self.block_run(
                &current,
                "Automation definition changed during checkout preparation",
            )
            .await;
            return;
        }
        if let Err(error) = self
            .ensure_dispatch_policy(
                &latest,
                &alera_core::runtime::AutomationActor {
                    kind: alera_core::runtime::AutomationActorKind::ManagedAgent,
                    id: current.actor_id.clone(),
                    label: Some("Alera Automation Scheduler".into()),
                },
            )
            .await
        {
            self.block_run(&current, &error.wire_message()).await;
            return;
        }
        let candidate = match result {
            Ok(candidate) => candidate,
            Err(error) => {
                self.block_run(&current, &error.wire_message()).await;
                return;
            }
        };
        match self
            .runtime_store
            .allocate_automation_shared_workspace(&current, candidate)
            .await
        {
            Ok((run, workspace)) => {
                self.continue_automation_dispatch(&latest, run, workspace, &project)
                    .await
            }
            Err(error) => self.block_run(&current, &error.to_string()).await,
        }
    }
}
