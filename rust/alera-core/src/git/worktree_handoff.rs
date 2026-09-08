use git2::{ErrorCode, RepositoryState, Signature, StashFlags, StashSaveOptions};

use super::{open_repo, GitError, GitErrorKind};

/// Stashes staged, unstaged, and untracked files. Returns whether a stash was
/// created. Ignored files stay in place.
pub fn stash_include_untracked(path: &str) -> Result<bool, GitError> {
    let mut repo = open_repo(path)?;
    if repo.state() != RepositoryState::Clean {
        return Err(GitError::new(
            GitErrorKind::Conflict,
            "finish or abort the in-progress git operation before moving work",
        ));
    }
    let signature = Signature::now("Alera", "alera@example.com").map_err(GitError::from_git2)?;
    let mut options = StashSaveOptions::new(signature);
    options.flags(Some(StashFlags::INCLUDE_UNTRACKED));
    match repo.stash_save_ext(Some(&mut options)) {
        Ok(_) => Ok(true),
        Err(error) if error.code() == ErrorCode::NotFound => Ok(false),
        Err(error) => Err(GitError::from_git2(error)),
    }
}

pub fn stash_pop(path: &str) -> Result<(), GitError> {
    let mut repo = open_repo(path)?;
    let mut options = git2::StashApplyOptions::new();
    repo.stash_pop(0, Some(&mut options))
        .map_err(GitError::from_git2)
}

/// Detaches HEAD at the current commit without touching the index or files.
pub fn detach_head(path: &str) -> Result<(), GitError> {
    let repo = open_repo(path)?;
    if repo.head_detached().map_err(GitError::from_git2)? {
        return Ok(());
    }
    let oid = repo
        .head()
        .map_err(GitError::from_git2)?
        .peel_to_commit()
        .map_err(GitError::from_git2)?
        .id();
    repo.set_head_detached(oid).map_err(GitError::from_git2)
}

/// Points HEAD at [branch] without checking out files. Both must already share
/// the same commit, which is the post-stash / post-detach case.
pub fn set_head_to_branch(path: &str, branch: &str) -> Result<(), GitError> {
    let repo = open_repo(path)?;
    let reference = format!("refs/heads/{branch}");
    repo.find_reference(&reference)
        .map_err(|error| match error.code() {
            ErrorCode::NotFound => GitError::new(GitErrorKind::BranchNotFound, branch),
            _ => GitError::from_git2(error),
        })?;
    repo.set_head(&reference).map_err(GitError::from_git2)
}

/// Preferred branch to leave on the main worktree after moving another branch.
pub fn default_branch(path: &str) -> Result<String, GitError> {
    let repo = open_repo(path)?;
    if let Some(name) = origin_head_branch(&repo)? {
        if repo.find_branch(&name, git2::BranchType::Local).is_ok() {
            return Ok(name);
        }
    }
    for candidate in ["main", "master"] {
        if repo.find_branch(candidate, git2::BranchType::Local).is_ok() {
            return Ok(candidate.to_string());
        }
    }
    super::current_branch(path)
}

pub fn branch_checkout_path(repo_path: &str, branch: &str) -> Result<Option<String>, GitError> {
    let repo = open_repo(repo_path)?;
    super::checkout_path_for_branch(&repo, branch)
}

fn origin_head_branch(repo: &git2::Repository) -> Result<Option<String>, GitError> {
    let reference = match repo.find_reference("refs/remotes/origin/HEAD") {
        Ok(reference) => reference,
        Err(error) if error.code() == ErrorCode::NotFound => return Ok(None),
        Err(error) => return Err(GitError::from_git2(error)),
    };
    let target = match reference.symbolic_target() {
        Ok(Some(target)) => target.to_string(),
        Ok(None) => return Ok(None),
        Err(_) => return Ok(None),
    };
    Ok(target
        .strip_prefix("refs/remotes/origin/")
        .or_else(|| target.strip_prefix("origin/"))
        .map(ToString::to_string))
}

#[cfg(test)]
#[path = "worktree_handoff_tests.rs"]
mod tests;
