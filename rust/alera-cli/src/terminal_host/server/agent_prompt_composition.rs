use alera_core::runtime::OrchestrationTask;
use serde_json::Value;

use crate::terminal_host::host_error::{HostError, HostResult};

use super::ServerActor;

pub(super) fn append_role_contract(task: &OrchestrationTask, prompt: &str) -> HostResult<String> {
    match task.role_contract.as_ref() {
        None => Ok(prompt.to_string()),
        Some(contract) => Ok(format!(
            "{}\n\n{}",
            prompt,
            contract
                .worker_instructions()
                .map_err(|error| HostError::state(error.to_string()))?
        )),
    }
}

/// Combines the prompt supplied for one launch with profile and project
/// instructions while keeping each source in its configured order.
pub(super) fn compose_agent_prompt(
    prompt: &str,
    profile_prompt: &str,
    project_prompt: &str,
) -> String {
    [prompt, profile_prompt, project_prompt]
        .into_iter()
        .map(str::trim)
        .filter(|part| !part.is_empty())
        .collect::<Vec<_>>()
        .join("\n\n")
}

impl ServerActor {
    pub(super) async fn compose_profile_prompt_for_workspace(
        &self,
        workspace_id: &str,
        prompt: &str,
        profile_name: Option<&str>,
    ) -> HostResult<String> {
        let Some(profile_name) = profile_name else {
            return Ok(prompt.to_string());
        };
        let Some(profile) = self
            .runtime_store
            .agent_profile_by_name(profile_name)
            .await
            .map_err(|error| HostError::state(error.to_string()))?
        else {
            return Ok(prompt.to_string());
        };
        let project_prompt = match self
            .runtime_store
            .find_workspace(workspace_id)
            .await
            .map_err(|error| HostError::state(error.to_string()))?
        {
            Some(workspace) => {
                let effective_config = crate::project_management::effective_project_config(
                    &self.runtime_store,
                    &workspace.project_id,
                )
                .await
                .map_err(|error| HostError::state(error.to_string()))?;
                if let Some(error) = effective_config.error {
                    return Err(HostError::state(format!(
                        "Could not load project configuration: {error}"
                    )));
                }
                effective_config.config.new_workspace.prompt_append
            }
            None => String::new(),
        };
        Ok(compose_agent_prompt(
            prompt,
            &profile.custom_prompt,
            &project_prompt,
        ))
    }

    pub(super) async fn compose_orchestration_task_prompt(
        &self,
        task: &mut Option<OrchestrationTask>,
        profile_name: Option<&str>,
    ) -> HostResult<()> {
        if let Some(task) = task.as_mut() {
            let workspace_id = task.workspace_id.clone();
            let task_spec = task.spec.clone();
            task.spec = self
                .compose_profile_prompt_for_workspace(&workspace_id, &task_spec, profile_name)
                .await?;
        }
        Ok(())
    }

    pub(super) async fn compose_orchestration_prompt(
        &self,
        task: &OrchestrationTask,
        prompt: &str,
        payload: &Value,
    ) -> HostResult<(Option<String>, String)> {
        let profile_name =
            super::orchestration_validation::optional_string(payload, "agentProfile");
        let effective_prompt = self
            .compose_profile_prompt_for_workspace(
                &task.workspace_id,
                prompt,
                profile_name.as_deref(),
            )
            .await?;
        Ok((profile_name, append_role_contract(task, &effective_prompt)?))
    }
}

#[cfg(test)]
mod tests {
    use super::compose_agent_prompt;

    #[test]
    fn preserves_prompt_profile_project_order() {
        assert_eq!(
            compose_agent_prompt(
                "Build The Feature",
                "Use The Repository Style",
                "Run The Tests"
            ),
            "Build The Feature\n\nUse The Repository Style\n\nRun The Tests"
        );
    }

    #[test]
    fn skips_blank_sources_and_trims_boundaries() {
        assert_eq!(
            compose_agent_prompt("  Build The Feature  ", "  ", "  Run The Tests  "),
            "Build The Feature\n\nRun The Tests"
        );
    }
}
