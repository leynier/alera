use std::path::Path;

use git2::{BranchType, ErrorCode, WorktreeAddOptions};

use super::{
    is_path_occupied, open_repo, remote_tracking_upstream_name, unique_worktree_admin_name,
    GitError, GitErrorKind,
};

pub fn create_worktree(
    repo_path: &str,
    target_branch: &str,
    path: &str,
    source_branch: &str,
    reuse_existing_branch: bool,
) -> Result<(), GitError> {
    let repo = open_repo(repo_path)?;

    if is_path_occupied(path) {
        return Err(GitError::new(GitErrorKind::WorktreeAlreadyExists, path));
    }

    if reuse_existing_branch {
        let branch =
            repo.find_branch(target_branch, BranchType::Local)
                .map_err(|error| match error.code() {
                    ErrorCode::NotFound => {
                        GitError::new(GitErrorKind::BranchNotFound, target_branch)
                    }
                    _ => GitError::from_git2(error),
                })?;
        let worktree_result = {
            let reference = branch.into_reference();
            let mut options = WorktreeAddOptions::new();
            options.reference(Some(&reference));
            let admin_name = unique_worktree_admin_name(&repo, path);
            repo.worktree(&admin_name, Path::new(path), Some(&options))
        };
        return worktree_result
            .map(|_| ())
            .map_err(|error| match error.code() {
                ErrorCode::Exists => GitError::new(GitErrorKind::WorktreeAlreadyExists, path),
                _ => GitError::from_git2(error),
            });
    }

    let source_commit = repo
        .revparse_single(source_branch)
        .map_err(|_| GitError::new(GitErrorKind::BranchNotFound, source_branch))?
        .peel_to_commit()
        .map_err(GitError::from_git2)?;

    let upstream_name = remote_tracking_upstream_name(&repo, source_branch)?;
    let mut branch =
        repo.branch(target_branch, &source_commit, false)
            .map_err(|error| match error.code() {
                ErrorCode::Exists => {
                    GitError::new(GitErrorKind::BranchAlreadyExists, target_branch)
                }
                ErrorCode::InvalidSpec => {
                    GitError::new(GitErrorKind::InvalidBranchName, target_branch)
                }
                _ => GitError::from_git2(error),
            })?;
    if let Some(upstream_name) = upstream_name.as_deref() {
        if let Err(error) = branch.set_upstream(Some(upstream_name)) {
            let _ = branch.delete();
            return Err(GitError::from_git2(error));
        }
    }

    let worktree_result = {
        let reference = branch.into_reference();
        let mut options = WorktreeAddOptions::new();
        options.reference(Some(&reference));
        let admin_name = unique_worktree_admin_name(&repo, path);
        repo.worktree(&admin_name, Path::new(path), Some(&options))
    };
    if let Err(error) = worktree_result {
        if let Ok(mut created) = repo.find_branch(target_branch, BranchType::Local) {
            let _ = created.delete();
        }
        return Err(match error.code() {
            ErrorCode::Exists => GitError::new(GitErrorKind::WorktreeAlreadyExists, path),
            _ => GitError::from_git2(error),
        });
    }
    Ok(())
}
