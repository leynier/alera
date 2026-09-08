use git2::{RepositoryState, StatusOptions};
use serde::{Deserialize, Serialize};

use super::{open_repo, GitError};
#[cfg(test)]
mod tests;

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct WorkflowCleanupGitPreview {
    pub head_sha: String,
    pub dirty: bool,
    pub operation_in_progress: bool,
    pub locked: bool,
    pub changed_paths: Vec<String>,
    pub paths_truncated: bool,
}

/// Pure Git inspection. Runtime ownership and process checks are separate
/// mandatory guards; this snapshot alone never authorizes resource removal.
pub fn preview_workflow_cleanup(
    repo_path: &str,
    path: &str,
    base_sha: &str,
    id: &str,
) -> Result<WorkflowCleanupGitPreview, GitError> {
    let head_sha = super::workflow_worktree::inspect_workflow_worktree_tip(
        repo_path, path, base_sha, id, false,
    )?;
    let repository = open_repo(repo_path)?;
    let worktree = repository.find_worktree(id).map_err(GitError::from_git2)?;
    let checkout = open_repo(path)?;
    let mut options = StatusOptions::new();
    options
        .include_untracked(true)
        .recurse_untracked_dirs(true)
        .include_ignored(true)
        .recurse_ignored_dirs(true)
        .exclude_submodules(false)
        .update_index(false);
    let statuses = checkout
        .statuses(Some(&mut options))
        .map_err(GitError::from_git2)?;
    let changed_paths = statuses
        .iter()
        .take(128)
        .map(|entry| {
            entry
                .path()
                .unwrap_or("<non-UTF-8 path>")
                .chars()
                .take(1024)
                .collect()
        })
        .collect();
    Ok(WorkflowCleanupGitPreview {
        head_sha,
        dirty: !statuses.is_empty(),
        operation_in_progress: checkout.state() != RepositoryState::Clean,
        locked: !matches!(
            worktree.is_locked().map_err(GitError::from_git2)?,
            git2::WorktreeLockStatus::Unlocked
        ),
        changed_paths,
        paths_truncated: statuses.len() > 128
            || statuses.iter().take(128).any(|entry| {
                entry
                    .path()
                    .map_or(true, |path| path.chars().count() > 1024)
            }),
    })
}
