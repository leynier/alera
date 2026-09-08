use git2::{build::CheckoutBuilder, Branch, BranchType, ErrorCode, Repository, RepositoryState};

use super::{open_repo, GitError, GitErrorKind};

pub fn list_branches(path: &str) -> Result<Vec<String>, GitError> {
    let repo = open_repo(path)?;
    let mut names = Vec::new();
    let branches = repo.branches(None).map_err(GitError::from_git2)?;
    for entry in branches {
        let (branch, _) = entry.map_err(GitError::from_git2)?;
        if let Some(name) = branch.name().map_err(GitError::from_git2)? {
            if name.ends_with("/HEAD") {
                continue;
            }
            names.push(name.to_string());
        }
    }
    names.sort();
    names.dedup();
    Ok(names)
}

pub fn branch_exists(repo_path: &str, branch: &str) -> Result<bool, GitError> {
    let repo = open_repo(repo_path)?;
    let result = match repo.find_branch(branch, BranchType::Local) {
        Ok(_) => Ok(true),
        Err(error) if error.code() == ErrorCode::NotFound => Ok(false),
        Err(error) => Err(GitError::from_git2(error)),
    };
    result
}

/// Creates a local branch at the current HEAD and makes it active without
/// modifying the index or working tree.
pub fn create_and_checkout_branch(path: &str, branch: &str) -> Result<(), GitError> {
    let repo = open_repo(path)?;
    let branch = branch.trim();
    if branch.is_empty() || !is_valid_branch_name(branch)? {
        return Err(GitError::new(GitErrorKind::InvalidBranchName, branch));
    }
    if repo.state() != RepositoryState::Clean {
        return Err(GitError::new(
            GitErrorKind::Conflict,
            "finish or abort the in-progress git operation before creating a branch",
        ));
    }
    if repo.head_detached().map_err(GitError::from_git2)? {
        return Err(GitError::new(
            GitErrorKind::DetachedHead,
            "cannot create a branch from detached HEAD",
        ));
    }
    let head = repo.head().map_err(|error| match error.code() {
        ErrorCode::UnbornBranch => GitError::new(
            GitErrorKind::BranchNotFound,
            "create the first commit before creating another branch",
        ),
        _ => GitError::from_git2(error),
    })?;
    let commit = head.peel_to_commit().map_err(GitError::from_git2)?;
    let mut created = repo
        .branch(branch, &commit, false)
        .map_err(|error| match error.code() {
            ErrorCode::Exists => GitError::new(GitErrorKind::BranchAlreadyExists, branch),
            ErrorCode::InvalidSpec => GitError::new(GitErrorKind::InvalidBranchName, branch),
            _ => GitError::from_git2(error),
        })?;
    let reference_name = format!("refs/heads/{branch}");
    if let Err(error) = repo.set_head(&reference_name) {
        let _ = created.delete();
        return Err(GitError::from_git2(error));
    }
    // Both branches point at the same commit, so changing symbolic HEAD is
    // sufficient and intentionally preserves pending staged/unstaged changes.
    Ok(())
}

/// Checks out [branch] in the worktree at [path].
///
/// Local branches switch in place. A remote-tracking name such as
/// `origin/feature` creates a local `feature` branch that tracks it when that
/// local name does not already exist. Checkout is safe: local changes that
/// would be overwritten are rejected.
pub fn checkout_branch(path: &str, branch: &str) -> Result<(), GitError> {
    let repo = open_repo(path)?;
    let branch = branch.trim();
    if branch.is_empty() {
        return Err(GitError::new(GitErrorKind::InvalidBranchName, branch));
    }
    if repo.state() != RepositoryState::Clean {
        return Err(GitError::new(
            GitErrorKind::Conflict,
            "finish or abort the in-progress git operation before switching branches",
        ));
    }

    let current = super::current_branch(path)?;
    if current == branch {
        return Ok(());
    }

    if repo.find_branch(branch, BranchType::Local).is_ok() {
        return checkout_local_branch(&repo, branch);
    }

    if repo.find_branch(branch, BranchType::Remote).is_ok() {
        let local_name = local_name_for_remote_branch(&repo, branch)?;
        if let Ok(local) = repo.find_branch(&local_name, BranchType::Local) {
            let remote = repo
                .find_branch(branch, BranchType::Remote)
                .map_err(GitError::from_git2)?;
            let local_oid = local
                .get()
                .peel_to_commit()
                .map_err(GitError::from_git2)?
                .id();
            let remote_oid = remote
                .get()
                .peel_to_commit()
                .map_err(GitError::from_git2)?
                .id();
            if local_oid != remote_oid {
                return Err(GitError::new(
                    GitErrorKind::Conflict,
                    format!(
                        "local branch \"{local_name}\" differs from \"{branch}\"; switch to the local branch or rename it first"
                    ),
                ));
            }
            if current == local_name {
                return Ok(());
            }
            return checkout_local_branch(&repo, &local_name);
        }
        create_local_tracking_branch(&repo, branch, &local_name)?;
        if let Err(error) = checkout_local_branch(&repo, &local_name) {
            if let Ok(mut created) = repo.find_branch(&local_name, BranchType::Local) {
                let _ = created.delete();
            }
            return Err(error);
        }
        return Ok(());
    }

    Err(GitError::new(GitErrorKind::BranchNotFound, branch))
}

fn checkout_local_branch(repo: &Repository, branch: &str) -> Result<(), GitError> {
    let reference_name = format!("refs/heads/{branch}");
    let object = repo
        .revparse_single(&reference_name)
        .map_err(|error| match error.code() {
            ErrorCode::NotFound => GitError::new(GitErrorKind::BranchNotFound, branch),
            _ => GitError::from_git2(error),
        })?;
    let mut checkout = CheckoutBuilder::new();
    repo.checkout_tree(&object, Some(&mut checkout))
        .map_err(|error| match error.code() {
            ErrorCode::Conflict => GitError::new(
                GitErrorKind::Conflict,
                "commit or stash local changes before switching branches",
            ),
            _ => GitError::from_git2(error),
        })?;
    repo.set_head(&reference_name)
        .map_err(GitError::from_git2)?;
    Ok(())
}

fn create_local_tracking_branch(
    repo: &Repository,
    remote_branch: &str,
    local_name: &str,
) -> Result<(), GitError> {
    if local_name.is_empty() || !is_valid_branch_name(local_name)? {
        return Err(GitError::new(GitErrorKind::InvalidBranchName, local_name));
    }
    let remote = repo
        .find_branch(remote_branch, BranchType::Remote)
        .map_err(|error| match error.code() {
            ErrorCode::NotFound => GitError::new(GitErrorKind::BranchNotFound, remote_branch),
            _ => GitError::from_git2(error),
        })?;
    let commit = remote.get().peel_to_commit().map_err(GitError::from_git2)?;
    let mut created =
        repo.branch(local_name, &commit, false)
            .map_err(|error| match error.code() {
                ErrorCode::Exists => GitError::new(GitErrorKind::BranchAlreadyExists, local_name),
                ErrorCode::InvalidSpec => {
                    GitError::new(GitErrorKind::InvalidBranchName, local_name)
                }
                _ => GitError::from_git2(error),
            })?;
    if let Err(error) = created.set_upstream(Some(remote_branch)) {
        let _ = created.delete();
        return Err(GitError::from_git2(error));
    }
    Ok(())
}

fn local_name_for_remote_branch(
    repo: &Repository,
    remote_branch: &str,
) -> Result<String, GitError> {
    let remotes = repo.remotes().map_err(GitError::from_git2)?;
    let mut best: Option<String> = None;
    for remote in remotes.iter() {
        let Some(remote) = remote.map_err(GitError::from_git2)? else {
            continue;
        };
        let prefix = format!("{remote}/");
        if let Some(rest) = remote_branch.strip_prefix(&prefix) {
            if rest.is_empty() {
                continue;
            }
            if best
                .as_ref()
                .is_none_or(|current| rest.len() < current.len())
            {
                best = Some(rest.to_string());
            }
        }
    }
    best.ok_or_else(|| GitError::new(GitErrorKind::BranchNotFound, remote_branch))
}

pub fn is_valid_branch_name(name: &str) -> Result<bool, GitError> {
    Branch::name_is_valid(name).map_err(GitError::from_git2)
}

pub fn delete_branch(repo_path: &str, branch: &str, _force: bool) -> Result<(), GitError> {
    let repo = open_repo(repo_path)?;
    let mut target = repo
        .find_branch(branch, BranchType::Local)
        .map_err(|error| match error.code() {
            ErrorCode::NotFound => GitError::new(GitErrorKind::BranchNotFound, branch),
            _ => GitError::from_git2(error),
        })?;
    target.delete().map_err(GitError::from_git2)?;
    Ok(())
}
