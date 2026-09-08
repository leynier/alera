use std::path::Path;

use git2::{ErrorCode, Oid, Repository, WorktreePruneOptions};
use serde::{Deserialize, Serialize};

use super::{open_repo, preview_workflow_cleanup, GitError, GitErrorKind};

#[cfg(test)]
mod tests;

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct WorkflowCleanupRemoval {
    pub cleanup_id: String,
    pub resource_id: String,
    pub path: String,
    pub base_sha: String,
    pub expected_head: String,
    pub remove_branch: bool,
}

#[derive(Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
struct Receipt {
    repository: std::path::PathBuf,
    request: WorkflowCleanupRemoval,
}

/// The caller must hold managed resource locks and verify process quiescence.
/// A retained Git receipt bridges removal and runtime persistence; it never
/// authorizes a different selection or a replacement checkout at the same path.
pub fn remove_workflow_cleanup_resource(
    repo_path: &str,
    request: &WorkflowCleanupRemoval,
) -> Result<(), GitError> {
    uuid::Uuid::parse_str(&request.cleanup_id).map_err(|_| invalid("invalid cleanup id"))?;
    uuid::Uuid::parse_str(&request.resource_id).map_err(|_| invalid("invalid resource id"))?;
    let path = Path::new(&request.path);
    if !path.is_absolute() || path.parent().is_none() {
        return Err(invalid("cleanup requires an absolute resource path"));
    }
    let repo = open_repo(repo_path)?;
    let branch = format!("refs/heads/alera/workflows/{}", request.resource_id);
    let receipt = format!(
        "refs/alera/workflow-cleanup/{}/{}",
        request.cleanup_id, request.resource_id
    );
    let expected = Oid::from_str(&request.expected_head).map_err(GitError::from_git2)?;
    // Serialize branch updates during inspection and pruning, including normal
    // Git commits from another process. Filesystem writers still need host guards.
    let mut transaction = repo.transaction().map_err(GitError::from_git2)?;
    transaction.lock_ref(&branch).map_err(GitError::from_git2)?;
    let recorded = verify_receipt(&repo, &receipt, request)?;
    let finished = format!("{receipt}-retired");
    if verify_receipt(&repo, &finished, request)? {
        return Ok(());
    }
    let exists = match std::fs::symlink_metadata(path) {
        Ok(_) => true,
        Err(error) if error.kind() == std::io::ErrorKind::NotFound => false,
        Err(error) => return Err(invalid(error.to_string())),
    };
    if exists {
        let current = preview_workflow_cleanup(
            repo_path,
            &request.path,
            &request.base_sha,
            &request.resource_id,
        )?;
        if current.head_sha != request.expected_head
            || current.dirty
            || current.locked
            || current.operation_in_progress
        {
            return Err(invalid("cleanup resource changed or is not clean and idle"));
        }
        if !recorded {
            persist_receipt(&repo, &receipt, request)?;
        }
        let worktree = repo
            .find_worktree(&request.resource_id)
            .map_err(GitError::from_git2)?;
        let mut options = WorktreePruneOptions::new();
        options.valid(true).working_tree(true).locked(false);
        worktree
            .prune(Some(&mut options))
            .map_err(GitError::from_git2)?;
    } else {
        if !recorded {
            return Err(invalid("missing cleanup resource has no removal receipt"));
        }
        // libgit2 may have removed the checkout before a crash left its
        // registration behind. Never prune an occupied or redirected path.
        match repo.find_worktree(&request.resource_id) {
            Ok(worktree) => {
                if worktree.path() != path {
                    return Err(invalid("cleanup registration path changed"));
                }
                let mut options = WorktreePruneOptions::new();
                options.valid(false).working_tree(false).locked(false);
                worktree
                    .prune(Some(&mut options))
                    .map_err(GitError::from_git2)?;
            }
            Err(error) if error.code() == ErrorCode::NotFound => {}
            Err(error) => return Err(GitError::from_git2(error)),
        }
    }
    match repo.find_reference(&branch) {
        Ok(reference) => {
            if reference.target() != Some(expected) {
                return Err(invalid("cleanup branch changed; branch retained"));
            }
            if request.remove_branch {
                if super::checkout_path_for_branch(
                    &repo,
                    &format!("alera/workflows/{}", request.resource_id),
                )?
                .is_some()
                {
                    return Err(invalid(
                        "cleanup branch is checked out elsewhere; branch retained",
                    ));
                }
                transaction.remove(&branch).map_err(GitError::from_git2)?;
            }
        }
        Err(error) if error.code() == ErrorCode::NotFound && request.remove_branch && recorded => {}
        Err(error) => return Err(GitError::from_git2(error)),
    }
    let receipt_oid = repo
        .find_reference(&receipt)
        .map_err(GitError::from_git2)?
        .target()
        .ok_or_else(|| invalid("cleanup receipt is not a direct reference"))?;
    transaction
        .lock_ref(&finished)
        .map_err(GitError::from_git2)?;
    transaction
        .set_target(&finished, receipt_oid, None, "workflow cleanup retired")
        .map_err(GitError::from_git2)?;
    transaction.commit().map_err(GitError::from_git2)
}

fn verify_receipt(
    repo: &Repository,
    name: &str,
    request: &WorkflowCleanupRemoval,
) -> Result<bool, GitError> {
    let reference = match repo.find_reference(name) {
        Ok(reference) => reference,
        Err(error) if error.code() == ErrorCode::NotFound => return Ok(false),
        Err(error) => return Err(GitError::from_git2(error)),
    };
    let commit = reference.peel_to_commit().map_err(GitError::from_git2)?;
    if commit.parent_count() != 1
        || commit
            .parent_id(0)
            .map_err(GitError::from_git2)?
            .to_string()
            != request.expected_head
    {
        return Err(invalid("cleanup receipt commit identity changed"));
    }
    let tree = commit.tree().map_err(GitError::from_git2)?;
    let entry = tree
        .get_name("receipt.json")
        .ok_or_else(|| invalid("cleanup receipt is missing"))?;
    let blob = repo.find_blob(entry.id()).map_err(GitError::from_git2)?;
    if blob.size() > 64 * 1024 {
        return Err(invalid("cleanup receipt is too large"));
    }
    let stored: Receipt =
        serde_json::from_slice(blob.content()).map_err(|_| invalid("invalid cleanup receipt"))?;
    if stored.request != *request
        || stored.repository
            != repo
                .commondir()
                .canonicalize()
                .map_err(|error| invalid(error.to_string()))?
    {
        return Err(invalid("cleanup receipt selection changed"));
    }
    Ok(true)
}

fn persist_receipt(
    repo: &Repository,
    name: &str,
    request: &WorkflowCleanupRemoval,
) -> Result<(), GitError> {
    let bytes = serde_json::to_vec(&Receipt {
        repository: repo
            .commondir()
            .canonicalize()
            .map_err(|error| invalid(error.to_string()))?,
        request: request.clone(),
    })
    .map_err(|error| invalid(error.to_string()))?;
    if bytes.len() > 64 * 1024 {
        return Err(invalid("cleanup receipt is too large"));
    }
    let blob = repo.blob(&bytes).map_err(GitError::from_git2)?;
    let mut builder = repo.treebuilder(None).map_err(GitError::from_git2)?;
    builder
        .insert("receipt.json", blob, 0o100644)
        .map_err(GitError::from_git2)?;
    let tree = repo
        .find_tree(builder.write().map_err(GitError::from_git2)?)
        .map_err(GitError::from_git2)?;
    let parent = repo
        .find_commit(Oid::from_str(&request.expected_head).map_err(GitError::from_git2)?)
        .map_err(GitError::from_git2)?;
    let signature =
        git2::Signature::now("Alera", "workflow@alera.invalid").map_err(GitError::from_git2)?;
    // Keeping the reviewed tip as a parent preserves its objects even when the
    // user explicitly includes the task branch in cleanup.
    let commit = repo
        .commit(
            None,
            &signature,
            &signature,
            "workflow cleanup receipt",
            &tree,
            &[&parent],
        )
        .map_err(GitError::from_git2)?;
    repo.reference(name, commit, false, "workflow cleanup receipt")
        .map_err(GitError::from_git2)?;
    Ok(())
}

fn invalid(message: impl Into<String>) -> GitError {
    GitError::new(GitErrorKind::Conflict, message)
}
