use super::{render_workspace_name, ServerActor};
use crate::terminal_host::host_error::{HostError, HostResult};
use alera_core::runtime::{AutomationDefinition, AutomationRun, AutomationTarget, Workspace};

impl ServerActor {
    pub(in crate::terminal_host::server) async fn allocate_project_checkout_automation_workspace(
        &self,
        definition: &AutomationDefinition,
        run: &AutomationRun,
    ) -> HostResult<(AutomationRun, Workspace)> {
        let AutomationTarget::ProjectCheckout {
            project_id,
            host_id,
            name_template,
            ..
        } = &definition.target
        else {
            return Err(HostError::state(
                "Automation target must be a project checkout",
            ));
        };
        let candidate = crate::shared_workspace::prepare_fresh_shared_workspace(
            &self.runtime_store,
            crate::shared_workspace::SharedWorkspaceCreateRequest {
                project_id: project_id.clone(),
                host_id: Some(host_id.clone()),
                id: None,
                name: Some(render_workspace_name(name_template, definition, run)),
                parent_workspace_id: None,
            },
        )
        .await
        .map_err(state_error)?;
        let current = self
            .runtime_store
            .find_automation_run(&run.id)
            .await
            .map_err(state_error)?
            .ok_or_else(|| HostError::state("Automation run no longer exists"))?;
        self.runtime_store
            .allocate_automation_shared_workspace(&current, candidate)
            .await
            .map_err(state_error)
    }
}

fn state_error(error: impl std::fmt::Display) -> HostError {
    HostError::state(error.to_string())
}
