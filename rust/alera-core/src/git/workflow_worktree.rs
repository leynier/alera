//! Exact-commit creation for a durably reserved workflow resource. No refresh,
//! rollback, deletion or branch reset is safe here: partial work is retained.

use std::io::Write;
use std::path::Path;

use git2::{ErrorCode, Oid, Repository, WorktreeAddOptions};

use super::{open_repo, GitError, GitErrorKind};

pub fn is_registered_workflow_worktree(
    repo_path: &str,
    path: &str,
    id: &str,
) -> Result<bool, GitError> {
    let repo = match open_repo(repo_path) {
        Ok(repo) => repo,
        Err(error) if error.kind == GitErrorKind::NotARepository => return Ok(false),
        Err(error) => return Err(error),
    };
    match repo.find_worktree(id) {
        Ok(worktree) => Ok(canonical(worktree.path())? == canonical(Path::new(path))?),
        Err(error) if error.code() == ErrorCode::NotFound => Ok(false),
        Err(error) => Err(GitError::from_git2(error)),
    }
}

pub fn ensure_workflow_worktree(
    repo_path: &str,
    path: &str,
    base_sha: &str,
    id: &str,
) -> Result<(), GitError> {
    uuid::Uuid::parse_str(id).map_err(|_| invalid("invalid workflow resource id"))?;
    let repo = open_repo(repo_path)?;
    let _receipt_config = receipt_config(&repo)?;
    let oid = Oid::from_str(base_sha).map_err(GitError::from_git2)?;
    repo.find_commit(oid).map_err(GitError::from_git2)?;
    let reference_name = format!("refs/heads/alera/workflows/{id}");
    let receipt = format!("alera workflow {id} at {base_sha}");
    let existing = match repo.find_reference(&reference_name) {
        Ok(reference) => Some(reference),
        Err(error) if error.code() == ErrorCode::NotFound => None,
        Err(error) => return Err(GitError::from_git2(error)),
    };
    let reference = if let Some(reference) = existing {
        verify_reference_receipt(&repo, &reference_name, &receipt)?;
        if reference.target() != Some(oid) {
            return Err(invalid("workflow branch moved from its reserved base"));
        }
        reference
    } else {
        if occupied(path)? || repo.find_worktree(id).is_ok() {
            return Err(invalid(
                "workflow destination already exists without its branch receipt",
            ));
        }
        // The handle-local config forces the receipt with ref creation, even
        // when ordinary reflogs are disabled. Never force an existing ref.
        repo.reference_ensure_log(&reference_name)
            .map_err(GitError::from_git2)?;
        repo.reference(&reference_name, oid, false, &receipt)
            .map_err(GitError::from_git2)?
    };
    match repo.find_worktree(id) {
        Ok(_) => return verify_workflow_worktree(repo_path, path, base_sha, id),
        Err(error) if error.code() == ErrorCode::NotFound => {}
        Err(error) => return Err(GitError::from_git2(error)),
    }
    if occupied(path)? {
        return Err(invalid(
            "workflow destination is occupied; existing files were preserved",
        ));
    }
    let parent = Path::new(path)
        .parent()
        .ok_or_else(|| invalid("workflow destination has no parent"))?;
    std::fs::create_dir_all(parent).map_err(|error| invalid(error.to_string()))?;
    let mut options = WorktreeAddOptions::new();
    options.reference(Some(&reference));
    repo.worktree(id, Path::new(path), Some(&options))
        .map_err(GitError::from_git2)?;
    verify_workflow_worktree(repo_path, path, base_sha, id)
}

fn receipt_config(repo: &Repository) -> Result<tempfile::NamedTempFile, GitError> {
    // git2 exposes file-backed config overlays, not libgit2's memory backend.
    // This private temporary override never changes repository/user config and
    // contains no copied settings or credentials. Keep it alive with the handle.
    let mut file = tempfile::NamedTempFile::new().map_err(|error| invalid(error.to_string()))?;
    file.write_all(b"[core]\nlogAllRefUpdates = true\n")
        .map_err(|error| invalid(error.to_string()))?;
    let mut config = repo.config().map_err(GitError::from_git2)?;
    config
        .add_file(file.path(), git2::ConfigLevel::App, true)
        .map_err(GitError::from_git2)?;
    repo.set_config(&config).map_err(GitError::from_git2)?;
    Ok(file)
}

pub fn verify_workflow_worktree(
    repo_path: &str,
    path: &str,
    base_sha: &str,
    id: &str,
) -> Result<(), GitError> {
    uuid::Uuid::parse_str(id).map_err(|_| invalid("invalid workflow resource id"))?;
    let repo = open_repo(repo_path)?;
    let reference_name = format!("refs/heads/alera/workflows/{id}");
    verify_reference_receipt(
        &repo,
        &reference_name,
        &format!("alera workflow {id} at {base_sha}"),
    )?;
    let worktree = repo.find_worktree(id).map_err(GitError::from_git2)?;
    worktree.validate().map_err(GitError::from_git2)?;
    let metadata = std::fs::symlink_metadata(path).map_err(|error| invalid(error.to_string()))?;
    if metadata.file_type().is_symlink()
        || !metadata.is_dir()
        || canonical(worktree.path())? != canonical(Path::new(path))?
    {
        return Err(invalid("workflow worktree path identity changed"));
    }
    let checkout = Repository::open(path).map_err(GitError::from_git2)?;
    if !checkout.is_worktree()
        || canonical(checkout.commondir())? != canonical(repo.commondir())?
        || canonical(checkout.path())? != canonical(&repo.commondir().join("worktrees").join(id))?
        || checkout
            .head()
            .map_err(GitError::from_git2)?
            .name()
            .map_err(GitError::from_git2)?
            != reference_name
        || checkout.head().map_err(GitError::from_git2)?.target()
            != Some(Oid::from_str(base_sha).map_err(GitError::from_git2)?)
    {
        return Err(invalid(
            "workflow repository, branch or base identity changed",
        ));
    }
    Ok(())
}

fn verify_reference_receipt(
    repo: &Repository,
    reference: &str,
    receipt: &str,
) -> Result<(), GitError> {
    let log = repo.reflog(reference).map_err(GitError::from_git2)?;
    let first = log
        .len()
        .checked_sub(1)
        .and_then(|index| log.get(index))
        .ok_or_else(|| invalid("workflow branch has no ownership receipt"))?;
    if first.id_old() != Oid::ZERO_SHA1
        || first.message().map_err(GitError::from_git2)? != Some(receipt)
    {
        return Err(invalid("workflow branch belongs to another resource"));
    }
    Ok(())
}

fn canonical(path: &Path) -> Result<std::path::PathBuf, GitError> {
    path.canonicalize()
        .map_err(|error| invalid(error.to_string()))
}

fn occupied(path: &str) -> Result<bool, GitError> {
    match Path::new(path).symlink_metadata() {
        Ok(_) => Ok(true),
        Err(error) if error.kind() == std::io::ErrorKind::NotFound => Ok(false),
        Err(error) => Err(invalid(error.to_string())),
    }
}

fn invalid(message: impl Into<String>) -> GitError {
    GitError::new(GitErrorKind::Conflict, message)
}
