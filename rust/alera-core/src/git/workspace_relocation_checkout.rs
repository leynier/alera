use std::path::Path;

use git2::{ErrorCode, Oid, Repository, WorktreeAddOptions};

use super::{open_repo, GitError, GitErrorKind};

pub fn checkout_commit(path: &str) -> Result<String, GitError> {
    open_repo(path)?
        .head()
        .and_then(|head| head.peel_to_commit())
        .map(|commit| commit.id().to_string())
        .map_err(GitError::from_git2)
}

pub fn local_branch_commit(path: &str, branch: &str) -> Result<String, GitError> {
    open_repo(path)?
        .find_branch(branch, git2::BranchType::Local)
        .and_then(|branch| branch.into_reference().peel_to_commit())
        .map(|commit| commit.id().to_string())
        .map_err(GitError::from_git2)
}

pub fn checkouts_share_repository(left: &str, right: &str) -> Result<bool, GitError> {
    let left = open_repo(left)?;
    let right = open_repo(right)?;
    Ok(canonical(left.commondir())? == canonical(right.commondir())?)
}

pub fn is_workspace_relocation_worktree(
    repository_path: &str,
    path: &str,
    relocation_id: &str,
) -> Result<bool, GitError> {
    let id = uuid::Uuid::parse_str(relocation_id).map_err(|_| conflict("Invalid relocation ID"))?;
    let repo = open_repo(repository_path)?;
    let admin_name = relocation_admin_name(&repo, id)?;
    let worktree = match repo.find_worktree(&admin_name) {
        Ok(worktree) => worktree,
        Err(error) if error.code() == ErrorCode::NotFound => return Ok(false),
        Err(error) => return Err(GitError::from_git2(error)),
    };
    worktree.validate().map_err(GitError::from_git2)?;
    // Opening from a Worktree follows its folder's .git pointer too. Compare
    // against the operation's administrative directory independently instead.
    let registered = repo.commondir().join("worktrees").join(&admin_name);
    let actual = open_repo(path)?;
    Ok(canonical(worktree.path())? == canonical(Path::new(path))?
        && canonical(&registered)? == canonical(actual.path())?
        && canonical(actual.commondir())? == canonical(repo.commondir())?)
}

/// The operation owns a uniquely named worktree registration and branch reflog
/// entry. A retry never adopts an unrelated directory or an existing branch.
pub fn create_workspace_relocation_worktree(
    repository_path: &str,
    relocation_id: &str,
    path: &str,
    branch: &str,
    source_commit: &str,
    reuse_existing_branch: bool,
) -> Result<(), GitError> {
    let id = uuid::Uuid::parse_str(relocation_id).map_err(|_| conflict("Invalid relocation ID"))?;
    if !super::is_valid_branch_name(branch)? {
        return Err(conflict("Invalid relocation branch name"));
    }
    let repo = open_repo(repository_path)?;
    let expected = Oid::from_str(source_commit).map_err(GitError::from_git2)?;
    repo.find_commit(expected).map_err(GitError::from_git2)?;
    let admin_name = relocation_admin_name(&repo, id)?;
    validate_admin_path(&repo, &admin_name)?;
    match repo.find_worktree(&admin_name) {
        Ok(worktree) => {
            worktree.validate().map_err(GitError::from_git2)?;
            if canonical(worktree.path())? != canonical(Path::new(path))?
                || !checkouts_share_repository(repository_path, path)?
                || checkout_commit(path)? != source_commit
                || super::current_branch(path)? != branch
                || !super::is_worktree_clean(path)?
            {
                return Err(conflict("The relocation worktree changed after preparation. Its files and registration were retained."));
            }
            return Ok(());
        }
        Err(error) if error.code() == ErrorCode::NotFound => {}
        Err(error) => return Err(GitError::from_git2(error)),
    }
    match std::fs::symlink_metadata(path) {
        Ok(_) => return Err(conflict("The relocation destination already exists without this operation's worktree registration; no files were changed")),
        Err(error) if error.kind() == std::io::ErrorKind::NotFound => {}
        Err(error) => return Err(conflict(error.to_string())),
    }
    let reference_name = format!("refs/heads/{branch}");
    let message = format!("alera workspace relocation {id}: create branch");
    let reference = relocation_branch(
        &repo,
        &reference_name,
        expected,
        reuse_existing_branch,
        &message,
    )?;
    if let Some(occupied) = super::branch_checkout_path(repository_path, branch)? {
        return Err(conflict(format!(
            "Relocation branch {branch} is still checked out at {occupied}"
        )));
    }
    if let Some(parent) = Path::new(path).parent() {
        std::fs::create_dir_all(parent).map_err(|error| conflict(error.to_string()))?;
    }
    let mut options = WorktreeAddOptions::new();
    options.reference(Some(&reference));
    repo.worktree(&admin_name, Path::new(path), Some(&options))
        .map_err(GitError::from_git2)?;
    Ok(())
}

fn relocation_branch<'repo>(
    repo: &'repo Repository,
    name: &str,
    expected: Oid,
    reuse: bool,
    message: &str,
) -> Result<git2::Reference<'repo>, GitError> {
    match repo.find_reference(name) {
        Ok(reference) => {
            if reference.target() != Some(expected) {
                return Err(conflict(
                    "The relocation branch no longer points to the prepared commit",
                ));
            }
            if !reuse {
                let log = repo.reflog(name).map_err(GitError::from_git2)?;
                if !log.get(0).is_some_and(|entry| {
                    entry.id_old().is_zero()
                        && entry.id_new() == expected
                        && entry.message().ok().flatten() == Some(message)
                }) {
                    return Err(conflict("The destination branch was created or changed outside this relocation; no reference was overwritten"));
                }
            }
            Ok(reference)
        }
        Err(error) if error.code() == ErrorCode::NotFound && !reuse => {
            repo.reference_ensure_log(name)
                .map_err(GitError::from_git2)?;
            repo.reference(name, expected, false, message)
                .map_err(GitError::from_git2)
        }
        Err(error) => Err(GitError::from_git2(error)),
    }
}

fn canonical(path: &Path) -> Result<std::path::PathBuf, GitError> {
    std::fs::canonicalize(path).map_err(|error| conflict(error.to_string()))
}

fn conflict(message: impl Into<String>) -> GitError {
    GitError::new(GitErrorKind::Conflict, message)
}

fn relocation_admin_name(repo: &Repository, id: uuid::Uuid) -> Result<String, GitError> {
    let compact = format!("alera-{}", id.simple());
    let legacy = format!("alera-relocation-{id}");
    let mut existing = None;
    for name in [&compact, &legacy] {
        match repo.find_worktree(name) {
            Ok(_) if existing.is_some() => return Err(conflict(
                "Multiple worktree registrations claim this relocation; preserve them for recovery",
            )),
            Ok(_) => existing = Some(name.clone()),
            Err(error) if error.code() == ErrorCode::NotFound => {}
            Err(error) => return Err(GitError::from_git2(error)),
        }
    }
    Ok(existing.unwrap_or(compact))
}

pub fn validate_workspace_relocation_storage(
    repository_path: &str,
    relocation_id: &str,
) -> Result<(), GitError> {
    let id = uuid::Uuid::parse_str(relocation_id).map_err(|_| conflict("Invalid relocation ID"))?;
    let repo = open_repo(repository_path)?;
    validate_admin_path(&repo, &relocation_admin_name(&repo, id)?)
}

fn validate_admin_path(repo: &Repository, name: &str) -> Result<(), GitError> {
    #[cfg(windows)]
    {
        // libgit2 reserves this suffix even for a linked administrative folder.
        // core.longpaths does not bypass its repository-open validation.
        let suffix =
            "objects/pack/pack-.pack.lock".len() + git2::Oid::ZERO_SHA1.as_bytes().len() * 2;
        let path = repo.commondir().join("worktrees").join(name);
        if path.to_string_lossy().chars().count() + 1 + suffix > 260 {
            return Err(conflict("The repository path leaves insufficient space for Git worktree metadata on Windows. Use a shorter project checkout path before relocating; no new branch or worktree was created."));
        }
    }
    #[cfg(not(windows))]
    let _ = (repo, name);
    Ok(())
}
