use git2::{Branch, BranchType, ErrorCode, RepositoryState};

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
