use std::path::Path;

use git2::{
    Delta, Diff, DiffFindOptions, DiffOptions, Repository, Status, StatusEntry, StatusOptions,
};

use super::{
    open_repo, GitChangeArea, GitChangeEntry, GitChangeStatus, GitDiffFile, GitDiffResult,
    GitError, GitErrorKind, GitStatusResult,
};

#[path = "git_diff_combined.rs"]
mod git_diff_combined;
#[path = "git_diff_paths.rs"]
mod git_diff_paths;
#[path = "git_diff_render.rs"]
mod git_diff_render;
#[path = "git_diff_untracked.rs"]
mod git_diff_untracked;

use git_diff_combined::{append_combined_diff_file, git_diff_all_for_file};
use git_diff_paths::GitPathContext;
use git_diff_render::render_diff_for_path;
use git_diff_untracked::untracked_diff_file;

pub(super) const MAX_DIFF_PATCH_BYTES: usize = 512 * 1024;

pub(super) fn git_status(path: String) -> Result<GitStatusResult, GitError> {
    let repo = open_repo(&path)?;
    let paths = GitPathContext::new(&repo, &path)?;
    let mut options = status_options();
    let statuses = repo
        .statuses(Some(&mut options))
        .map_err(GitError::from_git2)?;
    let mut entries = Vec::new();

    for entry in statuses.iter() {
        if let Some(change) = status_entry_to_change(&repo, &paths, &entry, GitChangeArea::Staged)?
        {
            entries.push(change);
        }
        if let Some(change) =
            status_entry_to_change(&repo, &paths, &entry, GitChangeArea::Untracked)?
        {
            entries.push(change);
            continue;
        }
        if let Some(change) =
            status_entry_to_change(&repo, &paths, &entry, GitChangeArea::Unstaged)?
        {
            entries.push(change);
        }
    }

    entries.sort_by(|a, b| {
        area_sort_key(a.area)
            .cmp(&area_sort_key(b.area))
            .then_with(|| a.path.cmp(&b.path))
    });
    Ok(GitStatusResult { entries })
}

pub(super) fn git_diff(
    path: String,
    file_path: String,
    area: GitChangeArea,
) -> Result<GitDiffResult, GitError> {
    let repo = open_repo(&path)?;
    let paths = GitPathContext::new(&repo, &path)?;
    let files = diff_file_for_area(&repo, &paths, &file_path, area)?
        .into_iter()
        .collect::<Vec<_>>();
    let truncated = files.iter().any(|file| file.truncated);
    Ok(GitDiffResult { files, truncated })
}

pub(super) fn git_diff_all(
    path: String,
    file_path: Option<String>,
) -> Result<GitDiffResult, GitError> {
    let repo = open_repo(&path)?;
    let paths = GitPathContext::new(&repo, &path)?;
    if let Some(file_path) = file_path {
        return git_diff_all_for_file(&repo, &paths, &file_path);
    }
    let status = git_status(path)?;
    let mut files = Vec::new();
    let mut total_bytes = 0usize;
    let mut truncated = false;

    for entry in status.entries {
        if let Some(file) = diff_file_for_area(&repo, &paths, &entry.path, entry.area)? {
            if append_combined_diff_file(&mut files, &mut total_bytes, &mut truncated, file) {
                break;
            }
        }
    }

    Ok(GitDiffResult { files, truncated })
}

fn status_options() -> StatusOptions {
    let mut options = StatusOptions::new();
    options
        .include_untracked(true)
        .recurse_untracked_dirs(true)
        .renames_head_to_index(true)
        .renames_index_to_workdir(true);
    options
}
fn status_entry_to_change(
    repo: &Repository,
    paths: &GitPathContext,
    entry: &StatusEntry<'_>,
    area: GitChangeArea,
) -> Result<Option<GitChangeEntry>, GitError> {
    let status = entry.status();
    match area {
        GitChangeArea::Staged => {
            if !has_staged_status(status) {
                return Ok(None);
            }
            let Some(delta) = entry.head_to_index() else {
                return Ok(None);
            };
            let repo_path = delta_path(&delta, false)?;
            let old_path = old_path_for_delta(&delta)?;
            let Some(path) = visible_workspace_path(paths, &repo_path, old_path.as_deref()) else {
                return Ok(None);
            };
            let mut change = GitChangeEntry {
                path: path.clone(),
                old_path: old_path
                    .as_deref()
                    .and_then(|old_path| paths.to_workspace_path(old_path)),
                area,
                status: change_status_for_delta(delta.status(), area),
                added: None,
                removed: None,
                is_binary: delta.old_file().is_binary() || delta.new_file().is_binary(),
                is_large: false,
            };
            if let Some(stats) =
                diff_line_stats_for_paths(repo, &repo_path, old_path.as_deref(), area)?
            {
                change.added = Some(stats.0);
                change.removed = Some(stats.1);
            }
            Ok(Some(change))
        }
        GitChangeArea::Untracked => {
            if !status.contains(Status::WT_NEW) {
                return Ok(None);
            }
            let path = entry
                .index_to_workdir()
                .as_ref()
                .map(|delta| delta_path(delta, false))
                .transpose()?
                .or_else(|| entry.path().ok().map(ToString::to_string));
            let Some(repo_path) = path else {
                return Ok(None);
            };
            let Some(path) = paths.to_workspace_path(&repo_path) else {
                return Ok(None);
            };
            Ok(Some(GitChangeEntry {
                path,
                old_path: None,
                area,
                status: GitChangeStatus::Untracked,
                added: None,
                removed: Some(0),
                is_binary: false,
                is_large: false,
            }))
        }
        GitChangeArea::Unstaged => {
            if !has_unstaged_status(status) {
                return Ok(None);
            }
            if status.contains(Status::CONFLICTED) {
                let Some(repo_path) = status_entry_path(entry)? else {
                    return Ok(None);
                };
                let Some(path) = paths.to_workspace_path(&repo_path) else {
                    return Ok(None);
                };
                return Ok(Some(GitChangeEntry {
                    path,
                    old_path: None,
                    area,
                    status: GitChangeStatus::Modified,
                    added: None,
                    removed: None,
                    is_binary: false,
                    is_large: false,
                }));
            }
            let Some(delta) = entry.index_to_workdir() else {
                return Ok(None);
            };
            let repo_path = delta_path(&delta, false)?;
            let old_path = old_path_for_delta(&delta)?;
            let Some(path) = visible_workspace_path(paths, &repo_path, old_path.as_deref()) else {
                return Ok(None);
            };
            let mut change = GitChangeEntry {
                path: path.clone(),
                old_path: old_path
                    .as_deref()
                    .and_then(|old_path| paths.to_workspace_path(old_path)),
                area,
                status: change_status_for_delta(delta.status(), area),
                added: None,
                removed: None,
                is_binary: delta.old_file().is_binary() || delta.new_file().is_binary(),
                is_large: false,
            };
            if let Some(stats) =
                diff_line_stats_for_paths(repo, &repo_path, old_path.as_deref(), area)?
            {
                change.added = Some(stats.0);
                change.removed = Some(stats.1);
            }
            Ok(Some(change))
        }
    }
}

fn has_staged_status(status: Status) -> bool {
    status.intersects(
        Status::INDEX_NEW
            | Status::INDEX_MODIFIED
            | Status::INDEX_DELETED
            | Status::INDEX_RENAMED
            | Status::INDEX_TYPECHANGE,
    )
}

fn has_unstaged_status(status: Status) -> bool {
    status.intersects(
        Status::WT_MODIFIED
            | Status::WT_DELETED
            | Status::WT_RENAMED
            | Status::WT_TYPECHANGE
            | Status::CONFLICTED,
    )
}

fn area_sort_key(area: GitChangeArea) -> u8 {
    match area {
        GitChangeArea::Untracked => 0,
        GitChangeArea::Unstaged => 1,
        GitChangeArea::Staged => 2,
    }
}

fn diff_file_for_area(
    repo: &Repository,
    paths: &GitPathContext,
    workspace_file_path: &str,
    area: GitChangeArea,
) -> Result<Option<GitDiffFile>, GitError> {
    let file_path = paths.to_repo_path(workspace_file_path);
    match area {
        GitChangeArea::Untracked => {
            if !is_untracked_file(repo, &file_path)? {
                return Ok(None);
            }
            match untracked_diff_file(repo, paths, &file_path) {
                Ok(file) => Ok(Some(file)),
                Err(_error) => {
                    let path = paths
                        .to_workspace_path(&file_path)
                        .unwrap_or_else(|| workspace_file_path.to_string());
                    Ok(Some(untracked_placeholder_diff_file(path)))
                }
            }
        }
        GitChangeArea::Staged | GitChangeArea::Unstaged => {
            let Some(selection) = selected_delta_for_area(repo, &file_path, area)? else {
                return Ok(None);
            };
            let mut pathspecs = vec![selection.path.as_str()];
            if let Some(old_path) = selection.old_path.as_deref() {
                pathspecs.push(old_path);
            }
            let mut diff = diff_for_area(repo, &pathspecs, area)?;
            let rendered = render_diff_for_path(&mut diff, &selection.path)?;
            if rendered.patch.is_empty() {
                return Ok(None);
            }
            let Some(path) =
                visible_workspace_path(paths, &selection.path, selection.old_path.as_deref())
            else {
                return Ok(None);
            };
            Ok(Some(GitDiffFile {
                path,
                old_path: selection
                    .old_path
                    .as_deref()
                    .and_then(|old_path| paths.to_workspace_path(old_path)),
                area,
                status: selection.status,
                patch: rendered.patch,
                added: Some(rendered.added),
                removed: Some(rendered.removed),
                is_binary: rendered.is_binary,
                is_large: false,
                truncated: rendered.truncated,
            }))
        }
    }
}

fn untracked_placeholder_diff_file(path: String) -> GitDiffFile {
    GitDiffFile {
        path,
        old_path: None,
        area: GitChangeArea::Untracked,
        status: GitChangeStatus::Untracked,
        patch: String::new(),
        added: None,
        removed: Some(0),
        is_binary: false,
        is_large: false,
        truncated: false,
    }
}

struct DiffSelection {
    path: String,
    old_path: Option<String>,
    status: GitChangeStatus,
}

fn selected_delta_for_area(
    repo: &Repository,
    file_path: &str,
    area: GitChangeArea,
) -> Result<Option<DiffSelection>, GitError> {
    let diff = diff_for_area(repo, &[], area)?;
    for delta in diff.deltas() {
        let new_path = delta_path(&delta, false)?;
        let old_path = old_path_for_delta(&delta)?;
        let delta_status = delta.status();
        if selected_delta_matches_path(delta_status, &new_path, old_path.as_deref(), file_path) {
            return Ok(Some(DiffSelection {
                path: new_path,
                old_path,
                status: change_status_for_delta(delta_status, area),
            }));
        }
    }
    Ok(None)
}

fn selected_delta_matches_path(
    delta_status: Delta,
    new_path: &str,
    old_path: Option<&str>,
    file_path: &str,
) -> bool {
    new_path == file_path || (delta_status == Delta::Renamed && old_path == Some(file_path))
}

fn visible_workspace_path(
    paths: &GitPathContext,
    repo_path: &str,
    old_path: Option<&str>,
) -> Option<String> {
    paths
        .to_workspace_path(repo_path)
        .or_else(|| old_path.and_then(|old_path| paths.to_workspace_path(old_path)))
}

fn diff_for_area<'repo>(
    repo: &'repo Repository,
    pathspecs: &[&str],
    area: GitChangeArea,
) -> Result<Diff<'repo>, GitError> {
    let mut options = DiffOptions::new();
    if !pathspecs.is_empty() {
        options.disable_pathspec_match(true);
    }
    for pathspec in pathspecs {
        options.pathspec(pathspec);
    }
    let mut diff = match area {
        GitChangeArea::Staged => {
            let index = repo.index().map_err(GitError::from_git2)?;
            let head_tree = repo.head().ok().and_then(|head| head.peel_to_tree().ok());
            repo.diff_tree_to_index(head_tree.as_ref(), Some(&index), Some(&mut options))
                .map_err(GitError::from_git2)
        }
        GitChangeArea::Unstaged => repo
            .diff_index_to_workdir(None, Some(&mut options))
            .map_err(GitError::from_git2),
        GitChangeArea::Untracked => unreachable!("untracked diffs are built from disk"),
    }?;
    let mut find_options = DiffFindOptions::new();
    find_options.renames(true).copies(true);
    diff.find_similar(Some(&mut find_options))
        .map_err(GitError::from_git2)?;
    Ok(diff)
}

fn is_untracked_file(repo: &Repository, file_path: &str) -> Result<bool, GitError> {
    match repo.status_file(Path::new(file_path)) {
        Ok(status) => {
            Ok(status.contains(Status::WT_NEW) && !staged_status_blocks_untracked(status))
        }
        Err(error) if error.code() == git2::ErrorCode::NotFound => Ok(false),
        Err(error) => Err(GitError::from_git2(error)),
    }
}

fn staged_status_blocks_untracked(status: Status) -> bool {
    status.intersects(Status::INDEX_NEW | Status::INDEX_MODIFIED)
}

fn diff_line_stats_for_paths(
    repo: &Repository,
    path: &str,
    old_path: Option<&str>,
    area: GitChangeArea,
) -> Result<Option<(u32, u32)>, GitError> {
    let mut pathspecs = vec![path];
    if let Some(old_path) = old_path {
        pathspecs.push(old_path);
    }
    let mut diff = diff_for_area(repo, &pathspecs, area)?;
    let rendered = render_diff_for_path(&mut diff, path)?;
    if rendered.is_binary || rendered.patch.is_empty() {
        return Ok(None);
    }
    Ok(Some((rendered.added, rendered.removed)))
}

fn delta_path(delta: &git2::DiffDelta<'_>, old: bool) -> Result<String, GitError> {
    let path = if old {
        delta.old_file().path()
    } else {
        delta.new_file().path().or_else(|| delta.old_file().path())
    };
    path.map(|path| path.to_string_lossy().to_string())
        .ok_or_else(|| GitError::new(GitErrorKind::Internal, "diff entry has no path"))
}

fn status_entry_path(entry: &StatusEntry<'_>) -> Result<Option<String>, GitError> {
    if let Some(delta) = entry.index_to_workdir().or_else(|| entry.head_to_index()) {
        return delta_path(&delta, false).map(Some);
    }
    Ok(entry.path().ok().map(ToString::to_string))
}

fn old_path_for_delta(delta: &git2::DiffDelta<'_>) -> Result<Option<String>, GitError> {
    if matches!(delta.status(), Delta::Renamed | Delta::Copied) {
        return delta_path(delta, true).map(Some);
    }
    Ok(None)
}

fn change_status_for_delta(delta: Delta, area: GitChangeArea) -> GitChangeStatus {
    match delta {
        Delta::Added => GitChangeStatus::Added,
        Delta::Deleted => GitChangeStatus::Deleted,
        Delta::Renamed => GitChangeStatus::Renamed,
        Delta::Copied => GitChangeStatus::Copied,
        Delta::Untracked => GitChangeStatus::Untracked,
        Delta::Modified | Delta::Typechange | Delta::Conflicted | Delta::Unreadable => {
            if area == GitChangeArea::Untracked {
                GitChangeStatus::Untracked
            } else {
                GitChangeStatus::Modified
            }
        }
        Delta::Unmodified | Delta::Ignored => GitChangeStatus::Modified,
    }
}
