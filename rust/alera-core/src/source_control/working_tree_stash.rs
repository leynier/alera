//! Stash save, pop and listing, scoped to the workspace.

use super::*;

pub fn git_list_stashes(path: String) -> Result<Vec<GitStashEntry>, GitError> {
    let mut repo = open_repo(&path)?;
    let mut entries = Vec::new();
    repo.stash_foreach(|index, message, oid| {
        entries.push(GitStashEntry {
            index: index as u32,
            reference: format!("stash@{{{index}}}"),
            message: message.to_string(),
            oid: oid.to_string(),
        });
        true
    })
    .map_err(GitError::from_git2)?;
    Ok(entries)
}

pub fn git_stash(path: String) -> Result<(), GitError> {
    let mut repo = open_repo(&path)?;
    let signature = Signature::now("Alera", "alera@example.com").map_err(GitError::from_git2)?;
    let mut options = StashSaveOptions::new(signature);
    options.flags(Some(git2::StashFlags::DEFAULT));
    reject_out_of_scope_tracked_changes(&repo, &path)?;
    repo.stash_save_ext(Some(&mut options))
        .map_err(|error| match error.code() {
            ErrorCode::NotFound => GitError::new(GitErrorKind::NothingToCommit, "nothing to stash"),
            _ => GitError::from_git2(error),
        })?;
    Ok(())
}

pub fn git_stash_pop(path: String, stash_index: u32) -> Result<(), GitError> {
    let mut repo = open_repo(&path)?;
    reject_out_of_scope_stash_pop(&mut repo, &path, stash_index)?;
    let mut options = StashApplyOptions::new();
    repo.stash_pop(stash_index as usize, Some(&mut options))
        .map_err(GitError::from_git2)?;
    Ok(())
}

fn reject_out_of_scope_tracked_changes(
    repo: &Repository,
    workspace_path: &str,
) -> Result<(), GitError> {
    let scope = workspace_repo_relative_path(repo, workspace_path)?;
    if scope == "." {
        return Ok(());
    }
    let workdir = repo
        .workdir()
        .ok_or_else(|| GitError::new(GitErrorKind::NotARepository, workspace_path))?;
    let status = git_status(workdir.to_string_lossy().to_string())?;
    for entry in status
        .entries
        .iter()
        .filter(|entry| entry.area != GitChangeArea::Untracked)
    {
        if let Some(old_path) = entry.old_path.as_deref() {
            if !repo_path_is_in_scope(old_path, &scope) {
                return Err(GitError::new(
                    GitErrorKind::WorkspaceScope,
                    format!("tracked change outside workspace: {old_path}"),
                ));
            }
        }
        if !repo_path_is_in_scope(&entry.path, &scope) {
            return Err(GitError::new(
                GitErrorKind::WorkspaceScope,
                format!("tracked change outside workspace: {}", entry.path),
            ));
        }
    }
    Ok(())
}

fn reject_out_of_scope_stash_pop(
    repo: &mut Repository,
    workspace_path: &str,
    stash_index: u32,
) -> Result<(), GitError> {
    let scope = workspace_repo_relative_path(repo, workspace_path)?;
    if scope == "." {
        return Ok(());
    }

    let stash_oid = stash_oid(repo, stash_index)?;
    let stash = repo.find_commit(stash_oid).map_err(GitError::from_git2)?;
    let stash_tree = stash.tree().map_err(GitError::from_git2)?;
    let head = stash.parent(0).map_err(GitError::from_git2)?;
    let head_tree = head.tree().map_err(GitError::from_git2)?;

    reject_tree_diff_out_of_scope(
        repo,
        Some(&head_tree),
        Some(&stash_tree),
        &scope,
        "stash change outside workspace",
    )?;

    if stash.parent_count() > 1 {
        let index_parent = stash.parent(1).map_err(GitError::from_git2)?;
        let index_tree = index_parent.tree().map_err(GitError::from_git2)?;
        reject_tree_diff_out_of_scope(
            repo,
            Some(&head_tree),
            Some(&index_tree),
            &scope,
            "stash index change outside workspace",
        )?;
    }

    if stash.parent_count() > 2 {
        let untracked_parent = stash.parent(2).map_err(GitError::from_git2)?;
        let untracked_tree = untracked_parent.tree().map_err(GitError::from_git2)?;
        reject_tree_diff_out_of_scope(
            repo,
            None,
            Some(&untracked_tree),
            &scope,
            "stash untracked change outside workspace",
        )?;
    }

    Ok(())
}

fn stash_oid(repo: &mut Repository, stash_index: u32) -> Result<Oid, GitError> {
    let mut oid = None;
    repo.stash_foreach(|index, _, stash_oid| {
        if index as u32 == stash_index {
            oid = Some(*stash_oid);
            return false;
        }
        true
    })
    .map_err(GitError::from_git2)?;
    oid.ok_or_else(|| GitError::new(GitErrorKind::Internal, "stash not found"))
}

fn reject_tree_diff_out_of_scope(
    repo: &Repository,
    old_tree: Option<&git2::Tree<'_>>,
    new_tree: Option<&git2::Tree<'_>>,
    scope: &str,
    context: &str,
) -> Result<(), GitError> {
    let diff = repo
        .diff_tree_to_tree(old_tree, new_tree, None)
        .map_err(GitError::from_git2)?;
    for delta in diff.deltas() {
        let old_path = delta.old_file().path().map(pathspec_string);
        let new_path = delta.new_file().path().map(pathspec_string);
        for path in old_path.iter().chain(new_path.iter()) {
            if !repo_path_is_in_scope(path, scope) {
                return Err(GitError::new(
                    GitErrorKind::WorkspaceScope,
                    format!("{context}: {path}"),
                ));
            }
        }
    }
    Ok(())
}
