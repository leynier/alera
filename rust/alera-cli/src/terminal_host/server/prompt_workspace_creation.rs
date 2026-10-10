//! Creating the workspace of a From Prompt operation: its identity, a branch
//! nobody uses yet, the worktree or project folder, and its section.

use std::time::Duration;

use alera_core::git as core_git;
use alera_core::runtime::{Project, ProjectKind, WorkspaceStatus, LOCAL_HOST_ID};
use serde_json::{json, Value};

use super::prompt_workspace_operation::{SectionPolicy, StartMode};
use super::prompt_workspace_pipeline::{state, PromptWorkspaceRun, Step, Stop};
use crate::terminal_host::host_error::HostError;

const CREATE_DEADLINE: Duration = Duration::from_secs(10 * 60);
const SECTION_DEADLINE: Duration = Duration::from_secs(60);
/// The same retry hint the app's form adds when a generated branch is taken.
const RETRY_IDENTITY_HINT: &str = "\n\nThe previous generated workspace identity was unavailable. Generate a different workspace name and branch.";
/// Numbered branches tried after a second generated identity is also taken.
const NUMBERED_SUFFIXES: std::ops::RangeInclusive<u32> = 2..=9;

/// Whether the workspace gets its own worktree. Auto follows the app: a
/// worktree for Git projects, the project folder for plain folders.
pub(super) fn uses_worktree(mode: StartMode, kind: ProjectKind) -> Result<bool, HostError> {
    match (mode, kind) {
        (StartMode::ProjectCheckout, _) => Ok(false),
        (StartMode::Worktree, ProjectKind::GitRepository) => Ok(true),
        (StartMode::Worktree, ProjectKind::Folder) => Err(HostError::state(
            "This project is not a Git repository, so it cannot have a worktree. Use mode projectCheckout.",
        )),
        (StartMode::Auto, kind) => Ok(kind == ProjectKind::GitRepository),
    }
}

pub(super) fn numbered_branch(branch: &str, number: u32) -> String {
    format!("{}-{number}", branch.trim_end_matches('/'))
}

fn looks_like_collision(error: &HostError) -> bool {
    let message = error.to_string().to_lowercase();
    message.contains("already exists") || message.contains("workspace for branch")
}

impl PromptWorkspaceRun {
    pub(super) async fn create_workspace(
        &mut self,
        project: &Project,
        prompt: &str,
        inferred: Option<Value>,
    ) -> Step<()> {
        let worktree = uses_worktree(self.operation.request.mode, project.kind)?;
        let host_id = self
            .operation
            .request
            .host_id
            .clone()
            .unwrap_or_else(|| LOCAL_HOST_ID.to_owned());
        let local = crate::project_hosts::project_folder_is_local(&self.store, project).await
            && !crate::ssh_remote::is_remote_host_id(Some(&host_id));
        let source_branch = if worktree {
            self.source_branch(project, local).await
        } else {
            None
        };
        let mut identity = match inferred {
            Some(identity) => {
                self.operation.identity = Some(identity.clone());
                identity
            }
            None => self.project_identity(project, prompt).await?,
        };
        for attempt in 0..2 {
            let branch = identity_field(&identity, "branchName")?;
            if worktree && self.branch_taken(project, &host_id, &branch, local).await {
                if attempt == 0 {
                    identity = self
                        .project_identity(project, &format!("{prompt}{RETRY_IDENTITY_HINT}"))
                        .await?;
                }
                continue;
            }
            match self
                .create(
                    project,
                    &identity,
                    &branch,
                    worktree,
                    source_branch.as_deref(),
                )
                .await
            {
                Ok(()) => return Ok(()),
                Err(Stop::Failed(error)) if attempt == 0 && looks_like_collision(&error) => {
                    identity = self
                        .project_identity(project, &format!("{prompt}{RETRY_IDENTITY_HINT}"))
                        .await?;
                }
                Err(stop) => return Err(stop),
            }
        }
        let base = identity_field(&identity, "branchName")?;
        for number in NUMBERED_SUFFIXES {
            let branch = numbered_branch(&base, number);
            if self.branch_taken(project, &host_id, &branch, local).await {
                continue;
            }
            match self
                .create(
                    project,
                    &identity,
                    &branch,
                    worktree,
                    source_branch.as_deref(),
                )
                .await
            {
                Ok(()) => return Ok(()),
                Err(Stop::Failed(error)) if looks_like_collision(&error) => continue,
                Err(stop) => return Err(stop),
            }
        }
        Err(
            HostError::state("AI Assist could not generate an available workspace identity.")
                .into(),
        )
    }

    async fn project_identity(&mut self, project: &Project, prompt: &str) -> Step<Value> {
        self.set_phase("generatingIdentity").await?;
        let identity = self
            .generate_identity(json!({
                "projectId": project.id,
                "prompt": prompt,
                "autoAssignSection": self.auto_section(),
            }))
            .await?;
        self.operation.identity = Some(identity.clone());
        Ok(identity)
    }

    /// The requested branch, else the project's preferred source branch, else
    /// the repository's default or current branch.
    async fn source_branch(&self, project: &Project, local: bool) -> Option<String> {
        if let Some(branch) = self.operation.request.source_branch.clone() {
            return Some(branch);
        }
        if let Some(branch) =
            crate::worktree_setup::preferred_source_branch(&self.store, project).await
        {
            return Some(branch);
        }
        if !local {
            return None;
        }
        core_git::default_branch(&project.repo_path)
            .ok()
            .or_else(|| core_git::current_branch(&project.repo_path).ok())
    }

    /// A branch an active workspace of the project already uses on that host,
    /// or one that exists in the local repository.
    async fn branch_taken(
        &self,
        project: &Project,
        host_id: &str,
        branch: &str,
        local: bool,
    ) -> bool {
        let used = self
            .store
            .list_workspaces(&project.id)
            .await
            .unwrap_or_default()
            .iter()
            .any(|workspace| {
                workspace.status == WorkspaceStatus::Active
                    && workspace.host_id == host_id
                    && workspace.branch.as_deref().map(str::trim) == Some(branch)
            });
        used || (local && core_git::branch_exists(&project.repo_path, branch).unwrap_or(false))
    }

    async fn create(
        &mut self,
        project: &Project,
        identity: &Value,
        branch: &str,
        worktree: bool,
        source_branch: Option<&str>,
    ) -> Step<()> {
        self.set_phase("creatingWorkspace").await?;
        let request = self.operation.request.clone();
        let name = identity_field(identity, "workspaceName")?;
        let (request_type, payload) = if worktree {
            (
                "workspace.createManaged",
                json!({
                    "projectId": project.id,
                    "name": name,
                    "branch": branch,
                    "sourceBranch": source_branch,
                    "reuseExistingBranch": false,
                    "parentWorkspaceId": request.parent_workspace_id,
                    "hostId": request.host_id,
                    "issueUrl": request.issue_url,
                    "deferSetup": true,
                }),
            )
        } else {
            (
                "workspace.createShared",
                json!({
                    "projectId": project.id,
                    "name": name,
                    "parentWorkspaceId": request.parent_workspace_id,
                    "hostId": request.host_id,
                    "issueUrl": request.issue_url,
                }),
            )
        };
        let created = self
            .call_to_completion(request_type, payload, CREATE_DEADLINE)
            .await?;
        let workspace = created
            .get("workspace")
            .cloned()
            .ok_or_else(|| HostError::state("The workspace was created without a record."))?;
        self.operation.workspace = Some(workspace);
        if let Some(command) = created
            .get("deferredSetupCommand")
            .and_then(Value::as_str)
            .map(str::trim)
            .filter(|command| !command.is_empty())
        {
            self.operation.setup = Some(json!({ "command": command }));
        }
        self.save().await;
        // A cancel that arrived during creation stops here, with the
        // workspace recorded so its launch can still be retried.
        self.check_cancelled()
    }

    /// Joins the section AI Assist picked, or the one the request names.
    /// Like the app, a failure here leaves the workspace in place with a
    /// warning; no section ("Others") is a valid outcome.
    pub(super) async fn assign_section(&mut self) {
        let Some(workspace_id) = self.operation.workspace_id().map(str::to_owned) else {
            return;
        };
        let section_id = match self.wanted_section().await {
            Ok(Some(section_id)) => section_id,
            Ok(None) => return,
            Err(message) => {
                self.operation.warnings.push(message);
                return;
            }
        };
        if self.set_phase("assigningSection").await.is_err() {
            return;
        }
        let payload = json!({ "workspaceId": workspace_id, "sectionId": section_id });
        match self
            .call(
                "workspaceSection.setForWorkspace",
                payload,
                SECTION_DEADLINE,
            )
            .await
        {
            Ok(_) => self.operation.section_id = Some(section_id),
            Err(Stop::Failed(error)) => self.operation.warnings.push(format!(
                "The workspace was not added to its section: {error}"
            )),
            Err(Stop::Cancelled) => {}
        }
        self.save().await;
    }

    async fn wanted_section(&self) -> Result<Option<String>, String> {
        let sections = || async {
            self.store
                .list_workspace_sections()
                .await
                .map_err(|error| format!("Sections are unavailable: {error}"))
        };
        match &self.operation.request.section {
            SectionPolicy::None => Ok(None),
            SectionPolicy::Auto => Ok(self
                .operation
                .identity
                .as_ref()
                .and_then(|identity| identity["sectionId"].as_str())
                .map(str::to_owned)),
            SectionPolicy::Id(id) => sections()
                .await?
                .into_iter()
                .find(|section| &section.id == id)
                .map(|section| Some(section.id))
                .ok_or_else(|| format!("Section not found: {id}")),
            SectionPolicy::Name(name) => sections()
                .await?
                .into_iter()
                .find(|section| section.name.eq_ignore_ascii_case(name))
                .map(|section| Some(section.id))
                .ok_or_else(|| format!("Section not found: {name}")),
        }
    }
}

fn identity_field(identity: &Value, key: &str) -> Step<String> {
    identity
        .get(key)
        .and_then(Value::as_str)
        .map(str::trim)
        .filter(|value| !value.is_empty())
        .map(str::to_owned)
        .ok_or_else(|| Stop::Failed(state(format!("AI Assist returned no {key}."))))
}

#[cfg(test)]
mod tests {
    use alera_core::runtime::ProjectKind;

    use super::{numbered_branch, uses_worktree};
    use crate::terminal_host::server::prompt_workspace_operation::StartMode;

    #[test]
    fn auto_mode_uses_a_worktree_only_for_git_projects() {
        assert!(uses_worktree(StartMode::Auto, ProjectKind::GitRepository).unwrap());
        assert!(!uses_worktree(StartMode::Auto, ProjectKind::Folder).unwrap());
        assert!(!uses_worktree(StartMode::ProjectCheckout, ProjectKind::GitRepository).unwrap());
        assert!(uses_worktree(StartMode::Worktree, ProjectKind::Folder).is_err());
    }

    #[test]
    fn numbered_branches_keep_the_generated_prefix() {
        assert_eq!(numbered_branch("feat/login", 2), "feat/login-2");
    }
}
