use git2::{build::CheckoutBuilder, DiffOptions, Repository, RepositoryState, Tree};

use super::{head_oid, invalid, oid, GitError, WorkflowIntegrationReceipt};

pub(super) fn apply(
    repo: &Repository,
    receipt: &WorkflowIntegrationReceipt,
) -> Result<(), GitError> {
    let request = &receipt.request;
    let branch = format!("refs/heads/alera/workflows/{}", request.integration.id);
    let mut transaction = repo.transaction().map_err(GitError::from_git2)?;
    transaction.lock_ref(&branch).map_err(GitError::from_git2)?;
    transaction.lock_ref("HEAD").map_err(GitError::from_git2)?;
    if repo.state() != RepositoryState::Clean
        || repo
            .head()
            .map_err(GitError::from_git2)?
            .name()
            .map_err(GitError::from_git2)?
            != branch
    {
        return Err(invalid(
            "integration checkout identity or Git operation changed",
        ));
    }
    let expected = oid(&request.expected_sha)?;
    let target = oid(&receipt.integrated_sha)?;
    let head = head_oid(repo)?;
    if head != expected && head != target {
        return Err(invalid(
            "integration head drifted; existing work was preserved",
        ));
    }
    let candidate = repo.find_commit(target).map_err(GitError::from_git2)?;
    let tree = candidate.tree().map_err(GitError::from_git2)?;
    if !matches_checkout(repo, &tree)? {
        let old = repo.find_commit(expected).map_err(GitError::from_git2)?;
        if head != expected || !matches_checkout(repo, &old.tree().map_err(GitError::from_git2)?)? {
            return Err(invalid(
                "integration checkout changed or is partial; inspect before recovery",
            ));
        }
        let mut options = CheckoutBuilder::new();
        options.safe().overwrite_ignored(false);
        repo.checkout_tree(candidate.as_object(), Some(&mut options))
            .map_err(GitError::from_git2)?;
        if !matches_checkout(repo, &tree)? {
            return Err(invalid(
                "integration checkout did not reach its prepared tree",
            ));
        }
    }
    if head == target {
        return Ok(());
    }
    let signature = candidate.committer();
    transaction
        .set_target(
            &branch,
            target,
            Some(&signature),
            "workflow result integration",
        )
        .map_err(GitError::from_git2)?;
    // Only one reference is updated: libgit2 multi-reference commits are not atomic.
    transaction.commit().map_err(GitError::from_git2)
}

fn matches_checkout(repo: &Repository, tree: &Tree<'_>) -> Result<bool, GitError> {
    let mut index = repo.index().map_err(GitError::from_git2)?;
    index.read(true).map_err(GitError::from_git2)?;
    if index.has_conflicts() || index.write_tree_to(repo).map_err(GitError::from_git2)? != tree.id()
    {
        return Ok(false);
    }
    let mut options = DiffOptions::new();
    options
        .include_untracked(true)
        .recurse_untracked_dirs(true)
        .include_typechange(true)
        .ignore_submodules(false);
    Ok(repo
        .diff_index_to_workdir(Some(&index), Some(&mut options))
        .map_err(GitError::from_git2)?
        .deltas()
        .len()
        == 0)
}
