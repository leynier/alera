use alera_core::runtime::{
    AutomationDefinition, AutomationRun, AutomationSetupPolicy, Workspace, WorkspaceStatus,
    WorkspaceTabRecord,
};
use chrono::Utc;
use serde_json::json;
use uuid::Uuid;

use super::super::{render_workspace_name, ServerActor};
use crate::managed_workspace::ManagedWorkspaceCreateRequest;
use crate::terminal_host::host_error::{HostError, HostResult};

/// Where a run's own worktree comes from.
pub(in crate::terminal_host::server) struct AutomationWorktree<'a> {
    pub project_id: &'a str,
    pub source_branch: &'a str,
    pub name_template: &'a str,
    pub parent_workspace_id: Option<&'a str>,
}

impl ServerActor {
    /// The workspace a project worktree run executes in. A retried attempt
    /// reuses the worktree its run already owns instead of creating another.
    pub(in crate::terminal_host::server) async fn project_worktree_automation_workspace(
        &mut self,
        definition: &AutomationDefinition,
        run: &mut AutomationRun,
        target: AutomationWorktree<'_>,
    ) -> HostResult<Option<Workspace>> {
        if let Some(workspace) = self.owned_project_worktree(run, target.project_id).await {
            return Ok(Some(workspace));
        }
        self.create_automation_worktree(definition, run, target)
            .await
    }

    async fn owned_project_worktree(
        &self,
        run: &AutomationRun,
        project_id: &str,
    ) -> Option<Workspace> {
        if !run.owned_workspace {
            return None;
        }
        let workspace = self
            .runtime_store
            .find_workspace(run.workspace_id.as_deref()?)
            .await
            .ok()
            .flatten()?;
        (workspace.project_id == project_id
            && workspace.parent_workspace_id.is_none()
            && workspace.status == WorkspaceStatus::Active
            && !workspace.is_archived
            && workspace.branch.is_some()
            && workspace.branch == run.workspace_branch)
            .then_some(workspace)
    }

    /// Creates the run's own worktree and branch from the source branch. Returns
    /// `None` after blocking the run when setup failed under its policy.
    pub(super) async fn create_automation_worktree(
        &mut self,
        definition: &AutomationDefinition,
        run: &mut AutomationRun,
        target: AutomationWorktree<'_>,
    ) -> HostResult<Option<Workspace>> {
        let AutomationWorktree {
            project_id,
            source_branch,
            name_template,
            parent_workspace_id,
        } = target;
        let request = ManagedWorkspaceCreateRequest {
            id: None,
            project_id: project_id.to_string(),
            name: Some(render_workspace_name(name_template, definition, run)),
            branch: format!("automation/{}/{}", definition.slug, &run.id[..8]),
            source_branch: Some(source_branch.to_string()),
            reuse_existing_branch: false,
            workspace_root: None,
            path: None,
            parent_workspace_id: parent_workspace_id.map(str::to_string),
            host_id: None,
            defer_setup: definition.setup_policy != AutomationSetupPolicy::Wait,
            skip_setup: definition.setup_policy == AutomationSetupPolicy::Skip,
            setup_script_directory: (definition.setup_policy != AutomationSetupPolicy::Wait)
                .then(|| self.runtime_dir.join("automation-setup")),
        };
        let result =
            crate::managed_workspace::create_managed_workspace(&self.runtime_store, request)
                .await
                .map_err(|error| HostError::state(error.to_string()))?;
        run.workspace_id = Some(result.workspace.id.clone());
        run.workspace_branch = result.workspace.branch.clone();
        run.owned_workspace = true;
        // Persist ownership before anything else can fail, so a retry finds
        // and reuses this worktree instead of colliding with its branch.
        let _ = self.runtime_store.save_automation_run(run).await;
        self.apply_automation_workspace_placement(definition, &result.workspace)
            .await;
        let failed_step = || {
            result
                .setup_report
                .steps
                .iter()
                .find(|step| !step.succeeded)
        };
        if definition.setup_policy == AutomationSetupPolicy::Wait {
            if let Some(step) = failed_step() {
                let reason = step
                    .message
                    .as_deref()
                    .unwrap_or("managed workspace setup failed")
                    .to_string();
                self.block_run(run, &reason).await;
                return Ok(None);
            }
        }
        if definition.setup_policy == AutomationSetupPolicy::Parallel {
            match result.deferred_setup_command.as_deref() {
                None => {
                    if let Some(step) = failed_step() {
                        let reason = step
                            .message
                            .as_deref()
                            .unwrap_or("managed workspace setup could not be prepared")
                            .to_string();
                        self.block_run(run, &reason).await;
                        return Ok(None);
                    }
                }
                Some(command) => {
                    self.start_automation_setup_tab(run, &result.workspace.id, command)
                        .await
                }
            }
        }
        Ok(Some(result.workspace))
    }

    async fn start_automation_setup_tab(
        &mut self,
        run: &mut AutomationRun,
        workspace_id: &str,
        command: &str,
    ) {
        let setup_id = Uuid::new_v4().to_string();
        let now = Utc::now();
        let setup_tab = WorkspaceTabRecord {
            id: setup_id.clone(),
            workspace_id: workspace_id.to_string(),
            kind: "terminal".to_string(),
            title: "Setup".to_string(),
            created_at: now,
            updated_at: now,
            payload: json!({
                "terminalSessionId": setup_id,
                "initialCommand": command,
                "initialCommandOnce": true,
                "spawnOnCreate": true,
                "autoCloseOnSuccess": true,
                "automationRunId": run.id,
                "automationAttemptId": run.attempt_id,
                "automationOwned": true,
            }),
        };
        if let Err(error) = self.upsert_workspace_tab_and_spawn(setup_tab).await {
            tracing::warn!(
                run_id = %run.id,
                "could not start managed workspace setup terminal: {}",
                error.wire_message()
            );
        } else {
            run.setup_tab_id = Some(setup_id);
        }
    }
}
