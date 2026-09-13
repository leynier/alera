//! Commit and amend, refusing staged changes outside the workspace.

use super::*;

pub fn git_commit(path: String, message: String) -> Result<String, GitError> {
    let repo = open_repo(&path)?;
    if repository_has_conflicts(&repo)? {
        return Err(GitError::new(
            GitErrorKind::Conflict,
            "resolve conflicts before committing",
        ));
    }
    let message = message.trim();
    if message.is_empty() {
        return Err(GitError::new(
            GitErrorKind::NothingToCommit,
            "empty message",
        ));
    }

    let mut index = repo.index().map_err(GitError::from_git2)?;
    let (parents, cleanup_state) = commit_parent_commits(&repo)?;
    let first_parent = parents.first();
    reject_out_of_scope_staged_entries(&repo, &path, first_parent, &index)?;
    let tree_id = index.write_tree().map_err(GitError::from_git2)?;
    let tree = repo.find_tree(tree_id).map_err(GitError::from_git2)?;
    if let Some(parent) = first_parent {
        if parent.tree_id() == tree_id {
            return Err(GitError::new(
                GitErrorKind::NothingToCommit,
                "no staged changes",
            ));
        }
    }
    let signature = git_signature(&repo)?;
    let parents = parents.iter().collect::<Vec<_>>();
    let oid = repo
        .commit(
            Some("HEAD"),
            &signature,
            &signature,
            message,
            &tree,
            &parents,
        )
        .map_err(GitError::from_git2)?;
    if cleanup_state {
        repo.cleanup_state().map_err(GitError::from_git2)?;
    }
    Ok(oid.to_string())
}

pub fn git_commit_amend(path: String, message: String) -> Result<String, GitError> {
    let repo = open_repo(&path)?;
    if repository_has_conflicts(&repo)? {
        return Err(GitError::new(
            GitErrorKind::Conflict,
            "resolve conflicts before amending",
        ));
    }
    let message = message.trim();
    if message.is_empty() {
        return Err(GitError::new(
            GitErrorKind::NothingToCommit,
            "empty message",
        ));
    }

    let head = current_head_commit(&repo)?.ok_or_else(|| {
        GitError::new(
            GitErrorKind::NothingToCommit,
            "no commit to amend on this branch",
        )
    })?;
    if repo.state() != RepositoryState::Clean {
        return Err(GitError::new(
            GitErrorKind::Conflict,
            "finish or abort the in-progress git operation before amending",
        ));
    }

    let mut index = repo.index().map_err(GitError::from_git2)?;
    reject_out_of_scope_staged_entries(&repo, &path, Some(&head), &index)?;
    let tree_id = index.write_tree().map_err(GitError::from_git2)?;
    if head.tree_id() == tree_id {
        return Err(GitError::new(
            GitErrorKind::NothingToCommit,
            "no staged changes",
        ));
    }
    let tree = repo.find_tree(tree_id).map_err(GitError::from_git2)?;
    let author = head.author();
    let committer = git_signature(&repo)?;
    let oid = head
        .amend(
            Some("HEAD"),
            Some(&author),
            Some(&committer),
            None,
            Some(message),
            Some(&tree),
        )
        .map_err(GitError::from_git2)?;
    Ok(oid.to_string())
}

fn reject_out_of_scope_staged_entries(
    repo: &Repository,
    workspace_path: &str,
    parent: Option<&git2::Commit<'_>>,
    index: &Index,
) -> Result<(), GitError> {
    let scope = workspace_repo_relative_path(repo, workspace_path)?;
    if scope == "." {
        return Ok(());
    }

    let parent_tree = if let Some(parent) = parent {
        Some(parent.tree().map_err(GitError::from_git2)?)
    } else {
        None
    };
    let mut options = DiffOptions::new();
    let diff = repo
        .diff_tree_to_index(parent_tree.as_ref(), Some(index), Some(&mut options))
        .map_err(GitError::from_git2)?;
    for delta in diff.deltas() {
        let old_path = delta.old_file().path().map(pathspec_string);
        let new_path = delta.new_file().path().map(pathspec_string);
        for path in old_path.iter().chain(new_path.iter()) {
            if !repo_path_is_in_scope(path, &scope) {
                return Err(GitError::new(
                    GitErrorKind::WorkspaceScope,
                    format!("staged change outside workspace: {path}"),
                ));
            }
        }
    }
    Ok(())
}

fn git_signature(repo: &Repository) -> Result<Signature<'_>, GitError> {
    repo.signature().map_err(|_| {
        GitError::new(
            GitErrorKind::MissingIdentity,
            "Configure Git user.name and user.email before committing.",
        )
    })
}
