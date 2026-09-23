//! Stage, unstage and discard for a workspace, including its submodule rules.

use super::*;

pub fn git_stage(path: String, file_path: Option<String>) -> Result<(), GitError> {
    let repo = open_repo(&path)?;
    if let Some(file_path) = file_path {
        return stage_selected_path(&repo, &path, &file_path);
    }
    let status = git_status(path.clone())?;
    stage_status_entries(&repo, &path, &status.entries)
}

pub fn git_stage_area(
    path: String,
    area: GitChangeArea,
    file_path: Option<String>,
) -> Result<(), GitError> {
    let repo = open_repo(&path)?;
    let status = git_status(path.clone())?;
    let entries = entries_for_area_and_scope(status.entries, area, file_path.as_deref());
    stage_status_entries(&repo, &path, &entries)
}

pub fn git_unstage(path: String, file_path: Option<String>) -> Result<(), GitError> {
    let repo = open_repo(&path)?;
    if let Some(file_path) = file_path {
        return unstage_selected_path(&repo, &path, &file_path);
    }
    let status = git_status(path.clone())?;
    unstage_status_entries(&repo, &path, &status.entries)
}

pub fn git_unstage_area(
    path: String,
    area: GitChangeArea,
    file_path: Option<String>,
) -> Result<(), GitError> {
    let repo = open_repo(&path)?;
    let status = git_status(path.clone())?;
    let entries = entries_for_area_and_scope(status.entries, area, file_path.as_deref());
    unstage_status_entries(&repo, &path, &entries)
}

pub fn git_discard(path: String, file_path: Option<String>) -> Result<(), GitError> {
    let repo = open_repo(&path)?;
    let reject_dirty_submodules = file_path.is_some();
    let status = match file_path.as_deref() {
        Some(file_path) => git_status_for_path(path.clone(), file_path.to_string())?,
        None => git_status(path.clone())?,
    };
    let pathspecs = scoped_pathspecs(&repo, &path, file_path.as_deref())?;
    discard_status_entries(
        &repo,
        &path,
        &status.entries,
        &pathspecs,
        reject_dirty_submodules,
    )
}

pub fn git_discard_area(
    path: String,
    area: GitChangeArea,
    file_path: Option<String>,
) -> Result<(), GitError> {
    let repo = open_repo(&path)?;
    let status = git_status(path.clone())?;
    let entries = entries_for_area_and_scope(status.entries, area, file_path.as_deref());
    let pathspecs = scoped_pathspecs(&repo, &path, file_path.as_deref())?;
    discard_status_entries(&repo, &path, &entries, &pathspecs, false)
}

fn discard_status_entries(
    repo: &Repository,
    path: &str,
    entries: &[GitChangeEntry],
    pathspecs: &[String],
    reject_dirty_submodules: bool,
) -> Result<(), GitError> {
    let mut skipped_submodules = HashSet::new();
    for entry in entries.iter().filter(|entry| {
        entry.area == GitChangeArea::Unstaged
            && entry
                .submodule
                .as_ref()
                .is_some_and(|status| status.commit_changed && status.inspectable)
    }) {
        let discarded = git_diff_impl::discard_submodule_gitlink(
            repo,
            path,
            &entry.path,
            !reject_dirty_submodules,
        )?;
        if !discarded {
            skipped_submodules.insert(entry.path.clone());
        }
    }

    let has_tracked_unstaged = entries.iter().any(|entry| {
        entry.area == GitChangeArea::Unstaged
            && is_parent_discardable(entry)
            && !skipped_submodules.contains(&entry.path)
    });
    if has_tracked_unstaged {
        let mut checkout = CheckoutBuilder::new();
        checkout.force();
        let has_non_discardable_submodule = !skipped_submodules.is_empty()
            || entries.iter().any(|entry| {
                entry.area == GitChangeArea::Unstaged
                    && entry.submodule.is_some()
                    && !is_parent_discardable(entry)
            });
        if has_non_discardable_submodule {
            checkout.disable_pathspec_match(true);
            for entry in entries.iter().filter(|entry| {
                entry.area == GitChangeArea::Unstaged
                    && is_parent_discardable(entry)
                    && !skipped_submodules.contains(&entry.path)
            }) {
                for workspace_path in entry.old_path.iter().chain(std::iter::once(&entry.path)) {
                    checkout.path(repo_relative_path(repo, path, workspace_path)?);
                }
            }
        } else if pathspecs != [String::from(".")] {
            checkout.disable_pathspec_match(true);
            for pathspec in pathspecs {
                checkout.path(pathspec);
            }
        }
        repo.checkout_index(None, Some(&mut checkout))
            .map_err(GitError::from_git2)?;
    }

    for entry in entries.iter().filter(|entry| {
        entry.area == GitChangeArea::Untracked
            || (entry.area == GitChangeArea::Unstaged
                && entry.status == GitChangeStatus::Renamed
                && entry.old_path.as_deref() != Some(entry.path.as_str()))
    }) {
        delete_workspace_relative_path(path, &entry.path)?;
    }

    Ok(())
}

fn entries_for_area_and_scope(
    entries: Vec<GitChangeEntry>,
    area: GitChangeArea,
    file_path: Option<&str>,
) -> Vec<GitChangeEntry> {
    entries
        .into_iter()
        .filter(|entry| {
            entry.area == area
                && file_path.is_none_or(|file_path| {
                    workspace_path_is_in_scope(&entry.path, file_path)
                        || entry
                            .old_path
                            .as_deref()
                            .is_some_and(|old_path| workspace_path_is_in_scope(old_path, file_path))
                })
        })
        .collect()
}

fn workspace_path_is_in_scope(path: &str, scope: &str) -> bool {
    scope.is_empty()
        || path == scope
        || path
            .strip_prefix(scope)
            .is_some_and(|remainder| remainder.starts_with('/'))
}

fn stage_selected_path(
    repo: &Repository,
    workspace_path: &str,
    file_path: &str,
) -> Result<(), GitError> {
    let status = git_status_for_path(workspace_path.to_string(), file_path.to_string())?;
    stage_status_entries(repo, workspace_path, &status.entries)
}

fn stage_status_entries(
    repo: &Repository,
    workspace_path: &str,
    entries: &[GitChangeEntry],
) -> Result<(), GitError> {
    let mut index = repo.index().map_err(GitError::from_git2)?;
    for entry in entries
        .iter()
        .filter(|entry| entry.area != GitChangeArea::Staged && !is_submodule_worktree_only(entry))
    {
        if let Some(old_path) = entry.old_path.as_deref() {
            let repo_path = repo_relative_path(repo, workspace_path, old_path)?;
            remove_index_path_if_present(&mut index, Path::new(&repo_path))?;
        }
        let repo_path = repo_relative_path(repo, workspace_path, &entry.path)?;
        let path = Path::new(&repo_path);
        if entry.status == GitChangeStatus::Deleted || !repo_workdir_path_exists(repo, path)? {
            remove_index_path_if_present(&mut index, path)?;
        } else {
            index.add_path(path).map_err(GitError::from_git2)?;
        }
    }
    index.write().map_err(GitError::from_git2)?;
    Ok(())
}

fn is_parent_discardable(entry: &GitChangeEntry) -> bool {
    entry
        .submodule
        .as_ref()
        .is_none_or(|status| status.commit_changed && status.inspectable)
}

fn unstage_selected_path(
    repo: &Repository,
    workspace_path: &str,
    file_path: &str,
) -> Result<(), GitError> {
    let status = git_status_for_path(workspace_path.to_string(), file_path.to_string())?;
    unstage_status_entries(repo, workspace_path, &status.entries)
}

fn unstage_status_entries(
    repo: &Repository,
    workspace_path: &str,
    entries: &[GitChangeEntry],
) -> Result<(), GitError> {
    let mut paths = entries
        .iter()
        .filter(|entry| entry.area == GitChangeArea::Staged)
        .flat_map(|entry| entry.old_path.iter().chain(std::iter::once(&entry.path)))
        .cloned()
        .collect::<Vec<_>>();
    paths.sort();
    paths.dedup();
    if paths.is_empty() {
        return Ok(());
    }

    let mut index = repo.index().map_err(GitError::from_git2)?;
    let head = repo
        .head()
        .ok()
        .and_then(|head| head.peel(ObjectType::Commit).ok());
    let head_index = if let Some(head) = head.as_ref() {
        let commit = head
            .as_commit()
            .ok_or_else(|| GitError::new(GitErrorKind::Internal, "HEAD is not a commit"))?;
        let tree = commit.tree().map_err(GitError::from_git2)?;
        let mut head_index = Index::new().map_err(GitError::from_git2)?;
        head_index.read_tree(&tree).map_err(GitError::from_git2)?;
        Some(head_index)
    } else {
        None
    };

    for path in paths {
        let repo_path = repo_relative_path(repo, workspace_path, &path)?;
        let path = Path::new(&repo_path);
        if let Some(head_index) = head_index.as_ref() {
            if let Some(head_entry) = head_index.get_path(path, 0) {
                index.add(&head_entry).map_err(GitError::from_git2)?;
            } else {
                remove_index_path_if_present(&mut index, path)?;
            }
        } else {
            remove_index_path_if_present(&mut index, path)?;
        }
    }
    index.write().map_err(GitError::from_git2)?;
    Ok(())
}

fn remove_index_path_if_present(index: &mut Index, path: &Path) -> Result<(), GitError> {
    if index.get_path(path, 0).is_some() {
        index.remove_path(path).map_err(GitError::from_git2)?;
    }
    Ok(())
}

fn repo_workdir_path_exists(repo: &Repository, path: &Path) -> Result<bool, GitError> {
    let workdir = repo
        .workdir()
        .ok_or_else(|| GitError::new(GitErrorKind::NotARepository, "bare repository"))?;
    Ok(workdir.join(path).exists())
}

fn delete_workspace_relative_path(workspace_path: &str, relative: &str) -> Result<(), GitError> {
    let root = std::fs::canonicalize(workspace_path).map_err(GitError::from_io)?;
    let path = root.join(relative_path(relative)?);
    if !path.starts_with(&root) {
        return Err(GitError::new(GitErrorKind::Internal, relative));
    }
    let metadata = match std::fs::symlink_metadata(&path) {
        Ok(metadata) => metadata,
        Err(error) if error.kind() == std::io::ErrorKind::NotFound => return Ok(()),
        Err(error) => return Err(GitError::from_io(error)),
    };
    if metadata.is_dir() && !metadata.file_type().is_symlink() {
        std::fs::remove_dir_all(&path).map_err(GitError::from_io)
    } else {
        std::fs::remove_file(&path).map_err(GitError::from_io)
    }
}
