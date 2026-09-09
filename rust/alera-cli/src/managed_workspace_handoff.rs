//! Move current git work between the main worktree and a child worktree.
//!
//! Hand off takes the main checkout's branch and uncommitted files into a new
//! linked workspace. Hand on brings a linked workspace back onto main and then
//! removes that child worktree. Both keep the existing workspace model.

use std::path::PathBuf;

use alera_core::git::{self as core_git, GitErrorKind};
use alera_core::runtime::{
    RuntimeStore, Workspace, WorkspaceCreationResult, WorkspaceKind, WorkspaceStatus,
};
use anyhow::{anyhow, bail, Context, Result};
use chrono::Utc;
use serde::{Deserialize, Serialize};

use crate::managed_workspace::{
    create_managed_workspace, validate_workspace_storage_path, ManagedWorkspaceCreateRequest,
};

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct ManagedWorkspaceHandOffRequest {
    pub id: String,
    pub branch: String,
    #[serde(default)]
    pub name: Option<String>,
    #[serde(default)]
    pub reuse_existing_branch: bool,
    #[serde(default)]
    pub workspace_root: Option<String>,
    #[serde(default)]
    pub path: Option<String>,
    #[serde(default)]
    pub defer_setup: bool,
    #[serde(skip)]
    pub setup_script_directory: Option<PathBuf>,
}

#[derive(Debug, Clone, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct ManagedWorkspaceHandOnRequest {
    pub id: String,
    #[serde(default)]
    #[allow(dead_code)] // Retained for older callers; safe transfer never closes sessions.
    pub close_sessions: bool,
    #[serde(default)]
    #[allow(dead_code)] // Retained as an additive compatibility field.
    pub active_workspace_id: Option<String>,
}

#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct WorkspaceHandOnResult {
    pub workspace: Workspace,
    pub removed_workspace_id: String,
    pub recovery_stash_oid: Option<String>,
}

pub async fn hand_off_managed_workspace(
    store: &RuntimeStore,
    request: ManagedWorkspaceHandOffRequest,
) -> Result<WorkspaceCreationResult> {
    let main = require_main_workspace(store, &request.id).await?;
    let project = store
        .find_project(&main.project_id)
        .await?
        .ok_or_else(|| anyhow!("Project not found: {}", main.project_id))?;
    let branch = require_trimmed(&request.branch, "Branch name is required")?;
    if !core_git::is_valid_branch_name(&branch)? {
        bail!("Invalid branch name: {branch}");
    }
    core_git::validate_handoff_state(&main.path)?;
    let current = core_git::current_branch(&main.path)?;
    if current == "HEAD" {
        bail!("Cannot hand off a detached HEAD; create or check out a branch first");
    }

    let reuse_existing_branch = request.reuse_existing_branch;
    if reuse_existing_branch {
        if current != branch {
            bail!(
                "Reuse existing branch only when \"{branch}\" is checked out on the main worktree"
            );
        }
        hand_off_current_branch(store, request, main, current).await
    } else {
        if current == branch {
            bail!("Choose a new branch name to hand off work from \"{current}\"");
        }
        if core_git::branch_exists(&project.repo_path, &branch)? {
            bail!("Branch \"{branch}\" already exists");
        }
        hand_off_new_branch(store, request, main, current, branch).await
    }
}

pub async fn hand_on_managed_workspace(
    store: &RuntimeStore,
    request: ManagedWorkspaceHandOnRequest,
) -> Result<WorkspaceHandOnResult> {
    let child = store
        .find_workspace(&request.id)
        .await?
        .ok_or_else(|| anyhow!("Workspace not found: {}", request.id))?;
    if child.kind != WorkspaceKind::Linked {
        bail!("Hand on is only available from a child worktree");
    }
    if child.status != WorkspaceStatus::Active {
        bail!("Workspace is not active: {}", child.id);
    }
    validate_workspace_storage_path(store, &child.id).await?;
    validate_transfer_owner(store, &child).await?;
    let project = store
        .find_project(&child.project_id)
        .await?
        .ok_or_else(|| anyhow!("Project not found: {}", child.project_id))?;
    let mut main = find_main_workspace(store, &project.id).await?;
    validate_transfer_owner(store, &main).await?;
    let branch = require_live_child_branch(&child)?;
    core_git::validate_handoff_state(&main.path)?;
    core_git::validate_handoff_state(&child.path)?;
    core_git::validate_no_ignored_handoff_files(&child.path)?;
    if !core_git::is_worktree_clean(&main.path)? {
        bail!("The main worktree has local changes. Commit, stash, or discard them before handing on.");
    }

    let stashed = core_git::stash_for_handoff(&child.path)
        .context("git stash on the child worktree failed")?;
    if let Err(error) = core_git::detach_head(&child.path) {
        restore_stashed_main(&child.path, &stashed)?;
        return Err(error).context("could not free the child branch");
    }
    if let Err(error) = core_git::checkout_branch(&main.path, &branch) {
        core_git::set_head_to_branch(&child.path, &branch).with_context(|| {
            format!(
                "Checkout failed ({error}); child is retained at {}. Recovery stash: {stashed:?}",
                child.path
            )
        })?;
        restore_stashed_main(&child.path, &stashed)?;
        return Err(error).context("git checkout on the main worktree failed");
    }
    main.branch = Some(branch.clone());
    main.updated_at = Utc::now();
    let main = store.upsert_workspace(main).await?;
    let mut detached_child = child.clone();
    detached_child.branch = Some("HEAD".to_string());
    store.upsert_workspace(detached_child).await?;
    if let Some(ref oid) = stashed {
        if let Err(error) = core_git::apply_handoff_stash(&main.path, oid) {
            return Err(error).context(
                "brought the branch onto main, but uncommitted changes remain in the stash",
            );
        }
    }

    core_git::validate_handoff_removal(&child.path)?;
    store.transfer_workspace_contents(&child, &main).await?;
    match core_git::remove_worktree(&project.repo_path, &child.path, false) {
        Ok(()) => {}
        Err(error)
            if error.kind == GitErrorKind::WorktreeNotFound
                && filesystem_entry_is_missing(&child.path) => {}
        Err(error) => return Err(error).context("Work moved onto main and its tabs persisted; empty child retained because worktree removal failed. Keep its branch when cleaning up"),
    }
    store.remove_workspace(&child.id, false).await?;

    Ok(WorkspaceHandOnResult {
        workspace: main,
        removed_workspace_id: child.id,
        recovery_stash_oid: stashed,
    })
}

async fn hand_off_new_branch(
    store: &RuntimeStore,
    request: ManagedWorkspaceHandOffRequest,
    mut main: Workspace,
    current: String,
    branch: String,
) -> Result<WorkspaceCreationResult> {
    let home = core_git::default_branch(&main.path)?;
    if let Some(path) = core_git::branch_checkout_path(&main.path, &home)? {
        if !path_equals(&path, &main.path) {
            bail!("Default branch {home} is checked out at {path}");
        }
    }
    let stashed =
        core_git::stash_for_handoff(&main.path).context("git stash on the main worktree failed")?;
    if let Err(error) = core_git::create_and_checkout_branch(&main.path, &branch) {
        restore_stashed_main(&main.path, &stashed)?;
        return Err(error).context("could not create the hand-off branch");
    }
    if let Err(error) = core_git::checkout_branch(&main.path, &home) {
        restore_created_branch(&main.path, &current, &branch, &stashed)?;
        return Err(error).context("could not return the main worktree to its original branch");
    }
    main.branch = Some(home);
    main.updated_at = Utc::now();
    store.upsert_workspace(main.clone()).await?;

    let mut created = match create_child_from_existing_branch(store, &request, &main, &branch).await
    {
        Ok(created) => created,
        Err(error) => {
            return Err(error).context(format!("Main is on its default branch. Created branch {branch} and recovery stash {stashed:?} retained; retry creating the child with that branch"));
        }
    };
    created.workspace.reuses_existing_branch = false;
    created.workspace = store.upsert_workspace(created.workspace).await?;
    apply_stashed_changes(&created.workspace.path, &stashed)?;
    main.updated_at = Utc::now();
    store.upsert_workspace(main.clone()).await?;
    store
        .transfer_workspace_contents(&main, &created.workspace)
        .await?;
    report_recovery_stash(&mut created, &stashed);
    Ok(created)
}

async fn hand_off_current_branch(
    store: &RuntimeStore,
    request: ManagedWorkspaceHandOffRequest,
    mut main: Workspace,
    current: String,
) -> Result<WorkspaceCreationResult> {
    let home = core_git::default_branch(&main.path)?;
    if home == current {
        bail!("Choose a new branch name to hand off work from \"{current}\"");
    }
    if let Some(path) = core_git::branch_checkout_path(&main.path, &home)? {
        if !path_equals(&path, &main.path) {
            bail!("Branch \"{home}\" is already checked out in another worktree");
        }
    }
    let stashed =
        core_git::stash_for_handoff(&main.path).context("git stash on the main worktree failed")?;
    if let Err(error) = core_git::checkout_branch(&main.path, &home) {
        restore_stashed_main(&main.path, &stashed)?;
        return Err(error).context("could not free the current branch on the main worktree");
    }
    main.branch = Some(home.clone());
    main.updated_at = Utc::now();
    store.upsert_workspace(main.clone()).await?;

    let mut created = match create_child_from_existing_branch(store, &request, &main, &current)
        .await
    {
        Ok(created) => created,
        Err(error) => {
            return Err(error).context(format!("Main is on {home}; branch {current} and recovery stash {stashed:?} retained. Retry creating the child with that branch"));
        }
    };
    apply_stashed_changes(&created.workspace.path, &stashed)?;
    main.branch = Some(home);
    main.updated_at = Utc::now();
    store.upsert_workspace(main.clone()).await?;
    store
        .transfer_workspace_contents(&main, &created.workspace)
        .await?;
    report_recovery_stash(&mut created, &stashed);
    Ok(created)
}

async fn create_child_from_existing_branch(
    store: &RuntimeStore,
    request: &ManagedWorkspaceHandOffRequest,
    main: &Workspace,
    branch: &str,
) -> Result<WorkspaceCreationResult> {
    create_managed_workspace(
        store,
        ManagedWorkspaceCreateRequest {
            id: None,
            project_id: main.project_id.clone(),
            name: request.name.clone(),
            branch: branch.to_string(),
            source_branch: None,
            reuse_existing_branch: true,
            workspace_root: request.workspace_root.clone(),
            path: request.path.clone(),
            parent_workspace_id: Some(main.id.clone()),
            host_id: None,
            defer_setup: request.defer_setup,
            skip_setup: false,
            setup_script_directory: request.setup_script_directory.clone(),
        },
    )
    .await
}

async fn require_main_workspace(store: &RuntimeStore, workspace_id: &str) -> Result<Workspace> {
    let workspace = store
        .find_workspace(workspace_id)
        .await?
        .ok_or_else(|| anyhow!("Workspace not found: {workspace_id}"))?;
    if workspace.kind != WorkspaceKind::Main {
        bail!("Hand off is only available from the main worktree");
    }
    if workspace.status != WorkspaceStatus::Active {
        bail!("Workspace is not active: {workspace_id}");
    }
    validate_transfer_owner(store, &workspace).await?;
    Ok(workspace)
}

async fn validate_transfer_owner(store: &RuntimeStore, workspace: &Workspace) -> Result<()> {
    if workspace.host_id != alera_core::runtime::LOCAL_HOST_ID {
        bail!("Hand Off and Hand On require local worktrees");
    }
    if crate::managed_workspace::workspace_has_active_automation_owner(store, &workspace.id).await?
    {
        bail!("Workspace is owned by an active automation");
    }
    Ok(())
}

async fn find_main_workspace(store: &RuntimeStore, project_id: &str) -> Result<Workspace> {
    store
        .list_workspaces(project_id)
        .await?
        .into_iter()
        .find(|workspace| {
            workspace.kind == WorkspaceKind::Main && workspace.status == WorkspaceStatus::Active
        })
        .ok_or_else(|| anyhow!("Main workspace not found for project {project_id}"))
}

fn apply_stashed_changes(path: &str, stashed: &Option<String>) -> Result<()> {
    if let Some(oid) = stashed {
        core_git::apply_handoff_stash(path, oid).with_context(|| {
            format!("Worktree retained at {path}; recovery stash {oid} retained. Resolve conflicts and apply it with --index before retrying")
        })?;
    }
    Ok(())
}

fn report_recovery_stash(result: &mut WorkspaceCreationResult, stash: &Option<String>) {
    if let Some(oid) = stash {
        result.setup_report.steps.push(alera_core::runtime::WorktreeSetupStepReport {
            kind: alera_core::runtime::WorktreeSetupStepKind::Config,
            label: "Recovery Stash".into(), succeeded: true,
            message: Some(format!("Recovery stash {oid} retained as 'alera handoff recovery'. Remove it in Git Stashes after verifying the transferred work.")),
            exit_code: None, stdout_tail: None, stderr_tail: None,
        });
    }
}

fn restore_stashed_main(path: &str, stashed: &Option<String>) -> Result<()> {
    apply_stashed_changes(path, stashed)
}

fn restore_created_branch(
    path: &str,
    original: &str,
    _created: &str,
    stashed: &Option<String>,
) -> Result<()> {
    core_git::checkout_branch(path, original).with_context(|| {
        format!("Could not restore {original} at {path}; recovery stash {stashed:?} retained")
    })?;
    restore_stashed_main(path, stashed)
}

fn filesystem_entry_is_missing(path: &str) -> bool {
    matches!(
        std::fs::symlink_metadata(path),
        Err(error) if error.kind() == std::io::ErrorKind::NotFound
    )
}

fn require_live_child_branch(child: &Workspace) -> Result<String> {
    let live = core_git::current_branch(&child.path)?;
    if live == "HEAD" {
        bail!("Cannot hand on a detached HEAD");
    }
    let expected = child
        .branch
        .as_deref()
        .map(str::trim)
        .filter(|value| !value.is_empty())
        .ok_or_else(|| anyhow!("Child workspace has no branch to bring onto main"))?;
    if expected != live {
        bail!("Workspace branch does not match live worktree: expected {expected}, found {live}");
    }
    Ok(live)
}

fn require_trimmed(value: &str, message: &str) -> Result<String> {
    let trimmed = value.trim();
    if trimmed.is_empty() {
        bail!("{message}");
    }
    Ok(trimmed.to_string())
}

fn path_equals(left: &str, right: &str) -> bool {
    canonical_path(left) == canonical_path(right)
}

fn canonical_path(path: &str) -> String {
    let target = std::path::Path::new(path);
    if let Ok(resolved) = std::fs::canonicalize(target) {
        return resolved.to_string_lossy().trim_end_matches('/').to_string();
    }
    path.trim_end_matches('/').to_string()
}

#[cfg(test)]
#[path = "managed_workspace_handoff_tests.rs"]
mod tests;
