use super::ServerActor;
use crate::terminal_host::host_error::{HostError, HostResult};
use alera_core::runtime::{AutomationDefinition, Project, Workspace};

#[derive(Debug)]
pub(super) struct AutomationTargetLocation {
    pub project: Project,
    pub host_id: String,
    pub path: String,
    pub workspace: Option<Workspace>,
}

impl ServerActor {
    pub(super) async fn automation_definition_project(
        &self,
        definition: &AutomationDefinition,
    ) -> HostResult<Option<String>> {
        if let Some(project_id) = &definition.project_id {
            return Ok(Some(project_id.clone()));
        }
        if let Some((project_id, _)) = definition.target.project_checkout() {
            return Ok(Some(project_id.into()));
        }
        let Some(workspace_id) = definition.target.source_workspace_id() else {
            return Ok(None);
        };
        Ok(self
            .runtime_store
            .find_workspace(workspace_id)
            .await
            .map_err(state_error)?
            .map(|workspace| workspace.project_id))
    }

    pub(super) async fn automation_target_location(
        &self,
        definition: &AutomationDefinition,
    ) -> HostResult<AutomationTargetLocation> {
        if let Some((project_id, host_id)) = definition.target.project_checkout() {
            let project = self
                .runtime_store
                .find_project(project_id)
                .await
                .map_err(state_error)?
                .ok_or_else(|| HostError::state("automation target project is missing"))?;
            let checkout = self
                .runtime_store
                .find_project_checkout(project_id, host_id)
                .await
                .map_err(state_error)?
                .ok_or_else(|| {
                    HostError::state("Register a project checkout on the automation execution host")
                })?;
            return Ok(AutomationTargetLocation {
                project,
                host_id: host_id.into(),
                path: checkout.path,
                workspace: None,
            });
        }
        let workspace_id = definition
            .target
            .source_workspace_id()
            .ok_or_else(|| HostError::state("automation target workspace is missing"))?;
        let workspace = self
            .runtime_store
            .find_workspace(workspace_id)
            .await
            .map_err(state_error)?
            .ok_or_else(|| HostError::state("automation target workspace is missing"))?;
        let project = self
            .runtime_store
            .find_project(&workspace.project_id)
            .await
            .map_err(state_error)?
            .ok_or_else(|| HostError::state("automation target project is missing"))?;
        Ok(AutomationTargetLocation {
            project,
            host_id: workspace.host_id.clone(),
            path: workspace.path.clone(),
            workspace: Some(workspace),
        })
    }
}

fn state_error(error: impl std::fmt::Display) -> HostError {
    HostError::state(error.to_string())
}
