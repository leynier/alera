use git2::{ErrorCode, RepositoryState, Signature, StashFlags};

use super::{open_repo, GitError, GitErrorKind};

/// Stashes staged, unstaged, and untracked files. Returns whether a stash was
/// created. Ignored files stay in place.
pub fn stash_include_untracked(path: &str) -> Result<bool, GitError> {
    Ok(stash_for_handoff(path)?.is_some())
}

pub fn validate_handoff_state(path: &str) -> Result<(), GitError> {
    let repo = open_repo(path)?;
    if repo.state() != RepositoryState::Clean
        || repo.index().map_err(GitError::from_git2)?.has_conflicts()
    {
        return Err(GitError::new(GitErrorKind::Conflict,
            "finish or abort the in-progress git operation and resolve the index before moving work"));
    }
    repo.head()
        .map_err(GitError::from_git2)?
        .peel_to_commit()
        .map_err(GitError::from_git2)?;
    Ok(())
}

/// The OID belongs to this operation even if another worktree adds a stash.
pub fn stash_for_handoff(path: &str) -> Result<Option<String>, GitError> {
    validate_handoff_state(path)?;
    let mut repo = open_repo(path)?;
    if repo.state() != RepositoryState::Clean {
        return Err(GitError::new(
            GitErrorKind::Conflict,
            "finish or abort the in-progress git operation before moving work",
        ));
    }
    let signature = Signature::now("Alera", "alera@example.com").map_err(GitError::from_git2)?;
    match repo.stash_save(
        &signature,
        "alera handoff recovery (includes index and untracked files)",
        Some(StashFlags::INCLUDE_UNTRACKED),
    ) {
        Ok(oid) => Ok(Some(oid.to_string())),
        Err(error) if error.code() == ErrorCode::NotFound => Ok(None),
        Err(error) => Err(GitError::from_git2(error)),
    }
}

/// Apply an immutable stash commit. libgit2 only exposes stack-index application.
/// Retain the recovery stash rather than racing a shared reflog pop/drop.
pub fn apply_handoff_stash(path: &str, oid: &str) -> Result<(), GitError> {
    let repo = open_repo(path)?;
    let expected = git2::Oid::from_str(oid).map_err(GitError::from_git2)?;
    let commit = repo.find_commit(expected).map_err(GitError::from_git2)?;
    if !(2..=3).contains(&commit.parent_count()) {
        return Err(GitError::new(
            GitErrorKind::Conflict,
            "Invalid handoff recovery stash",
        ));
    }
    crate::git_cli::git_in_dir(
        std::path::Path::new(path),
        &["stash", "apply", "--index", &expected.to_string()],
    )
    .map(|_| ())
    .map_err(|error| {
        GitError::new(
            GitErrorKind::Conflict,
            format!("{error}; recovery stash {expected} retained"),
        )
    })
}

/// Ignored files are user data too: libgit2's worktree prune does not check them.
pub fn validate_handoff_removal(path: &str) -> Result<(), GitError> {
    validate_handoff_state(path)?;
    let repo = open_repo(path)?;
    let mut options = git2::StatusOptions::new();
    options
        .include_ignored(true)
        .include_untracked(true)
        .recurse_untracked_dirs(true);
    if !repo
        .statuses(Some(&mut options))
        .map_err(GitError::from_git2)?
        .is_empty()
    {
        return Err(GitError::new(GitErrorKind::Conflict,
            format!("Worktree {path} contains local or ignored files. Move them to a safe location before removing it; nothing was deleted")));
    }
    Ok(())
}

pub fn validate_no_ignored_handoff_files(path: &str) -> Result<(), GitError> {
    let repo = open_repo(path)?;
    let mut options = git2::StatusOptions::new();
    options.include_ignored(true);
    if repo
        .statuses(Some(&mut options))
        .map_err(GitError::from_git2)?
        .iter()
        .any(|entry| entry.status().contains(git2::Status::IGNORED))
    {
        return Err(GitError::new(GitErrorKind::Conflict,
            format!("Child worktree {path} contains ignored files. Move them to a safe location before Hand On; no work was moved")));
    }
    Ok(())
}

pub fn stash_pop(path: &str) -> Result<(), GitError> {
    let mut repo = open_repo(path)?;
    let mut options = git2::StashApplyOptions::new();
    options.reinstantiate_index();
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
        return Err(GitError::new(GitErrorKind::BranchNotFound,
            format!("Default branch {name} is not available locally. Fetch and create its local tracking branch before transferring work")));
    }
    if let Ok(name) = repo
        .config()
        .and_then(|config| config.get_string("init.defaultBranch"))
    {
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
