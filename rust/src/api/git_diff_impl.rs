use std::collections::HashMap;
use std::path::Path;

use git2::{
    Delta, Diff, DiffFindOptions, DiffFormat, DiffLineType, DiffOptions, Oid, Repository, Status,
    StatusEntry, StatusOptions,
};

use super::{
    open_repo, GitChangeArea, GitChangeEntry, GitChangeGroup, GitChangeStatus, GitChangeTreeRow,
    GitChangeTreeRowKind, GitCommitChangeEntry, GitCommitCompareResult, GitCommitCompareStatus,
    GitCommitCompareSummary, GitDiffFile, GitDiffLine, GitDiffLineKind, GitDiffResult, GitError,
    GitErrorKind, GitStatusResult, GitSubmoduleStatus,
};

#[path = "git_diff_combined.rs"]
mod git_diff_combined;
#[path = "git_diff_render.rs"]
mod git_diff_render;
#[path = "git_diff_untracked.rs"]
mod git_diff_untracked;

use git_diff_combined::{append_combined_diff_file, git_diff_all_for_file};
use git_diff_render::render_diff_for_path;
use git_diff_untracked::untracked_diff_file;

#[path = "git_submodule_impl.rs"]
mod git_submodule_impl;

use super::git_diff_paths::GitPathContext;

pub(super) const MAX_DIFF_PATCH_BYTES: usize = 512 * 1024;
pub(super) const MAX_DIFF_BLOB_BYTES: u64 = 20 * 1024 * 1024;

type LineStats = (Option<u32>, Option<u32>);
type CommitDiffLineStatsByPath = HashMap<String, LineStats>;

pub(super) fn git_status(path: String) -> Result<GitStatusResult, GitError> {
    let repo = open_repo(&path)?;
    let paths = GitPathContext::new(&repo, &path)?;
    let mut options = status_options();
    git_status_with_options(&repo, &paths, &mut options)
}

pub(super) fn git_status_for_path(
    path: String,
    file_path: String,
) -> Result<GitStatusResult, GitError> {
    let repo = open_repo(&path)?;
    let paths = GitPathContext::new(&repo, &path)?;
    let mut options = status_options();
    options
        .disable_pathspec_match(true)
        .pathspec(paths.to_repo_path(&file_path));
    git_status_with_options(&repo, &paths, &mut options)
}

pub(super) fn git_submodule_status(
    path: String,
    submodule_path: String,
    area: GitChangeArea,
) -> Result<GitStatusResult, GitError> {
    git_submodule_impl::git_submodule_status(path, submodule_path, area)
}

pub(super) fn git_submodule_worktree_status(
    path: String,
    submodule_path: String,
) -> Result<GitStatusResult, GitError> {
    git_submodule_impl::git_submodule_worktree_status(path, submodule_path)
}

pub(super) fn discard_submodule_gitlink(
    repo: &Repository,
    workspace_path: &str,
    submodule_path: &str,
    skip_dirty: bool,
) -> Result<bool, GitError> {
    let paths = GitPathContext::new(repo, workspace_path)?;
    git_submodule_impl::discard_gitlink_change(repo, &paths, submodule_path, skip_dirty)
}

fn git_status_with_options(
    repo: &Repository,
    paths: &GitPathContext,
    options: &mut StatusOptions,
) -> Result<GitStatusResult, GitError> {
    let statuses = repo.statuses(Some(options)).map_err(GitError::from_git2)?;
    let mut entries = Vec::new();

    for entry in statuses.iter() {
        if let Some(change) = status_entry_to_change(repo, paths, &entry, GitChangeArea::Staged)? {
            entries.push(change);
        }
        if let Some(change) = status_entry_to_change(repo, paths, &entry, GitChangeArea::Untracked)?
        {
            entries.push(change);
            continue;
        }
        if let Some(change) = status_entry_to_change(repo, paths, &entry, GitChangeArea::Unstaged)?
        {
            entries.push(change);
        }
    }

    entries.sort_by(|a, b| {
        area_sort_key(a.area)
            .cmp(&area_sort_key(b.area))
            .then_with(|| a.path.cmp(&b.path))
    });
    Ok(status_result_from_entries(entries))
}

/// Raw bytes of one side of a diffed file, used for binary previews such as
/// images. Returns `None` when that side does not exist (added or deleted
/// files), the entry is not a blob, or the content exceeds
/// [`MAX_DIFF_BLOB_BYTES`].
pub(super) fn git_diff_blob_bytes(
    path: String,
    file_path: String,
    old_path: Option<String>,
    area: Option<GitChangeArea>,
    commit_oid: Option<String>,
    parent_oid: Option<String>,
    old_side: bool,
) -> Result<Option<Vec<u8>>, GitError> {
    let repo = open_repo(&path)?;
    let paths = GitPathContext::new(&repo, &path)?;
    let new_repo_path = paths.to_repo_path(&file_path);
    let old_repo_path = old_path
        .as_deref()
        .map(|old| paths.to_repo_path(old))
        .unwrap_or_else(|| new_repo_path.clone());

    if let Some(commit_oid) = commit_oid {
        let oid = Oid::from_str(&commit_oid).map_err(GitError::from_git2)?;
        let commit = repo.find_commit(oid).map_err(GitError::from_git2)?;
        if old_side {
            let parent = match parent_oid {
                Some(parent_oid) => {
                    let parent_oid = Oid::from_str(&parent_oid).map_err(GitError::from_git2)?;
                    Some(repo.find_commit(parent_oid).map_err(GitError::from_git2)?)
                }
                None => commit.parent(0).ok(),
            };
            let Some(parent) = parent else {
                return Ok(None);
            };
            let tree = parent.tree().map_err(GitError::from_git2)?;
            return Ok(tree_blob_bytes(&repo, &tree, &old_repo_path));
        }
        let tree = commit.tree().map_err(GitError::from_git2)?;
        return Ok(tree_blob_bytes(&repo, &tree, &new_repo_path));
    }

    match area {
        Some(GitChangeArea::Staged) => {
            if old_side {
                let Some(tree) = repo.head().ok().and_then(|head| head.peel_to_tree().ok()) else {
                    return Ok(None);
                };
                Ok(tree_blob_bytes(&repo, &tree, &old_repo_path))
            } else {
                index_blob_bytes(&repo, &new_repo_path)
            }
        }
        Some(GitChangeArea::Unstaged) => {
            if old_side {
                index_blob_bytes(&repo, &old_repo_path)
            } else {
                Ok(workdir_file_bytes(&repo, &new_repo_path))
            }
        }
        Some(GitChangeArea::Untracked) => {
            if old_side {
                Ok(None)
            } else {
                Ok(workdir_file_bytes(&repo, &new_repo_path))
            }
        }
        None => Ok(None),
    }
}

fn tree_blob_bytes(repo: &Repository, tree: &git2::Tree<'_>, repo_path: &str) -> Option<Vec<u8>> {
    let entry = tree.get_path(Path::new(repo_path)).ok()?;
    blob_bytes(repo, entry.id())
}

fn index_blob_bytes(repo: &Repository, repo_path: &str) -> Result<Option<Vec<u8>>, GitError> {
    let index = repo.index().map_err(GitError::from_git2)?;
    let Some(entry) = index.get_path(Path::new(repo_path), 0) else {
        return Ok(None);
    };
    Ok(blob_bytes(repo, entry.id))
}

fn blob_bytes(repo: &Repository, oid: Oid) -> Option<Vec<u8>> {
    let blob = repo.find_blob(oid).ok()?;
    if blob.size() as u64 > MAX_DIFF_BLOB_BYTES {
        return None;
    }
    Some(blob.content().to_vec())
}

fn workdir_file_bytes(repo: &Repository, repo_path: &str) -> Option<Vec<u8>> {
    let full_path = repo.workdir()?.join(repo_path);
    let metadata = std::fs::metadata(&full_path).ok()?;
    if !metadata.is_file() || metadata.len() > MAX_DIFF_BLOB_BYTES {
        return None;
    }
    std::fs::read(&full_path).ok()
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
    let status = git_status(path.clone())?;
    let mut files = Vec::new();
    let mut total_bytes = 0usize;
    let mut truncated = false;

    'changes: for entry in status.entries {
        if let Some(submodule) = &entry.submodule {
            if submodule.commit_changed {
                if let Some(file) = diff_file_for_area(&repo, &paths, &entry.path, entry.area)? {
                    if append_combined_diff_file(&mut files, &mut total_bytes, &mut truncated, file)
                    {
                        break;
                    }
                }
            }
            if entry.area == GitChangeArea::Unstaged
                && submodule.inspectable
                && (submodule.tracked_changes || submodule.untracked_changes)
            {
                let inner = git_submodule_worktree_status(path.clone(), entry.path.clone())?;
                for inner_entry in inner.entries {
                    let inner_path = format!("{}/{}", entry.path, inner_entry.path);
                    if let Some(file) =
                        diff_file_for_area(&repo, &paths, &inner_path, inner_entry.area)?
                    {
                        if append_combined_diff_file(
                            &mut files,
                            &mut total_bytes,
                            &mut truncated,
                            file,
                        ) {
                            break 'changes;
                        }
                    }
                }
            }
            continue;
        }
        if let Some(file) = diff_file_for_area(&repo, &paths, &entry.path, entry.area)? {
            if append_combined_diff_file(&mut files, &mut total_bytes, &mut truncated, file) {
                break;
            }
        }
    }

    Ok(GitDiffResult { files, truncated })
}

pub(super) fn git_commit_compare(
    path: String,
    commit_id: String,
) -> Result<GitCommitCompareResult, GitError> {
    let repo = open_repo(&path)?;
    let commit = match repo.revparse_single(&format!("{commit_id}^{{commit}}")) {
        Ok(object) => match object.peel_to_commit() {
            Ok(commit) => commit,
            Err(_) => return Ok(invalid_commit_compare(commit_id)),
        },
        Err(_) => return Ok(invalid_commit_compare(commit_id)),
    };
    let commit_oid = commit.id();
    let parent_oid = commit.parent_id(0).ok();
    let mut summary = GitCommitCompareSummary {
        commit_oid: commit_oid.to_string(),
        parent_oid: parent_oid.map(|oid| oid.to_string()),
        compare_ref: short_oid(commit_oid),
        base_ref: parent_oid
            .map(short_oid)
            .unwrap_or_else(|| "empty tree".to_string()),
        changed_files: 0,
        status: GitCommitCompareStatus::Ready,
        error_message: None,
    };
    match commit_change_entries(&repo, &path, parent_oid, commit_oid) {
        Ok(entries) => {
            summary.changed_files = entries.len() as u32;
            Ok(GitCommitCompareResult { summary, entries })
        }
        Err(error) => Ok(GitCommitCompareResult {
            summary: GitCommitCompareSummary {
                status: GitCommitCompareStatus::Error,
                error_message: Some(error.context),
                ..summary
            },
            entries: Vec::new(),
        }),
    }
}

pub(super) fn git_commit_diff(
    path: String,
    commit_oid: String,
    parent_oid: Option<String>,
    file_path: Option<String>,
    old_path: Option<String>,
) -> Result<GitDiffResult, GitError> {
    let repo = open_repo(&path)?;
    let paths = GitPathContext::new(&repo, &path)?;
    let commit_oid = Oid::from_str(&commit_oid).map_err(GitError::from_git2)?;
    let parent_oid = parent_oid
        .as_deref()
        .map(Oid::from_str)
        .transpose()
        .map_err(GitError::from_git2)?;
    if let Some(file_path) = file_path {
        let repo_path = paths.to_repo_path(&file_path);
        let old_repo_path = old_path
            .as_deref()
            .map(|old_path| paths.to_repo_path(old_path));
        let mut diff = diff_for_commit_range(
            &repo,
            parent_oid,
            commit_oid,
            &[repo_path.as_str(), old_repo_path.as_deref().unwrap_or("")],
        )?;
        let file = commit_diff_file_for_path(
            &repo,
            &paths,
            &mut diff,
            &repo_path,
            old_repo_path.as_deref(),
        )?;
        return Ok(GitDiffResult {
            files: file.into_iter().collect(),
            truncated: false,
        });
    }

    let mut diff = diff_for_commit_range(&repo, parent_oid, commit_oid, &[])?;
    let mut files = Vec::new();
    let mut total_bytes = 0usize;
    let mut truncated = false;
    let selections = commit_diff_selections(&diff)?;
    for selection in selections {
        let Some(file) = commit_diff_file_for_path(
            &repo,
            &paths,
            &mut diff,
            &selection.path,
            selection.old_path.as_deref(),
        )?
        else {
            continue;
        };
        if append_combined_diff_file(&mut files, &mut total_bytes, &mut truncated, file) {
            break;
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
            let change_status = change_status_for_delta(delta.status(), area);
            let Some(path) =
                visible_workspace_path(paths, &repo_path, old_path.as_deref(), change_status)
            else {
                return Ok(None);
            };
            let mut change = GitChangeEntry {
                path: path.clone(),
                old_path: old_path
                    .as_deref()
                    .and_then(|old_path| paths.to_workspace_path(old_path)),
                area,
                status: change_status,
                added: None,
                removed: None,
                is_binary: delta.old_file().is_binary() || delta.new_file().is_binary(),
                is_large: false,
                submodule: git_submodule_impl::status_for_path(repo, &repo_path, area)?,
            };
            if change.submodule.is_none() {
                if let Some(stats) =
                    diff_line_stats_for_paths(repo, &repo_path, old_path.as_deref(), area)?
                {
                    change.added = Some(stats.0);
                    change.removed = Some(stats.1);
                }
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
                submodule: None,
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
                    submodule: None,
                }));
            }
            let Some(delta) = entry.index_to_workdir() else {
                return Ok(None);
            };
            let repo_path = delta_path(&delta, false)?;
            let old_path = old_path_for_delta(&delta)?;
            let change_status = change_status_for_delta(delta.status(), area);
            let Some(path) =
                visible_workspace_path(paths, &repo_path, old_path.as_deref(), change_status)
            else {
                return Ok(None);
            };
            let mut change = GitChangeEntry {
                path: path.clone(),
                old_path: old_path
                    .as_deref()
                    .and_then(|old_path| paths.to_workspace_path(old_path)),
                area,
                status: change_status,
                added: None,
                removed: None,
                is_binary: delta.old_file().is_binary() || delta.new_file().is_binary(),
                is_large: false,
                submodule: git_submodule_impl::status_for_path(repo, &repo_path, area)?,
            };
            if change.submodule.is_none() {
                if let Some(stats) =
                    diff_line_stats_for_paths(repo, &repo_path, old_path.as_deref(), area)?
                {
                    change.added = Some(stats.0);
                    change.removed = Some(stats.1);
                }
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
    match git_submodule_impl::diff_file_for_submodule(repo, paths, workspace_file_path, area)? {
        git_submodule_impl::SubmoduleDiff::NotSubmodule => {}
        git_submodule_impl::SubmoduleDiff::NoDiff => return Ok(None),
        git_submodule_impl::SubmoduleDiff::File(file) => return Ok(Some(file)),
    }
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
            if rendered.lines.is_empty() {
                return Ok(None);
            }
            let Some(path) = visible_workspace_path(
                paths,
                &selection.path,
                selection.old_path.as_deref(),
                selection.status,
            ) else {
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
                lines: rendered.lines,
                added: Some(rendered.added),
                removed: Some(rendered.removed),
                is_binary: rendered.is_binary,
                is_large: false,
                is_gitlink: false,
                truncated: rendered.truncated,
                line_preview_truncated: rendered.line_preview_truncated,
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
        lines: Vec::new(),
        added: None,
        removed: Some(0),
        is_binary: false,
        is_large: false,
        is_gitlink: false,
        truncated: false,
        line_preview_truncated: false,
    }
}

fn invalid_commit_compare(commit_id: String) -> GitCommitCompareResult {
    GitCommitCompareResult {
        summary: GitCommitCompareSummary {
            commit_oid: String::new(),
            parent_oid: None,
            compare_ref: commit_id.clone(),
            base_ref: "parent".to_string(),
            changed_files: 0,
            status: GitCommitCompareStatus::InvalidCommit,
            error_message: Some(format!(
                "Commit {commit_id} could not be resolved in this repository."
            )),
        },
        entries: Vec::new(),
    }
}

fn commit_change_entries(
    repo: &Repository,
    workspace_path: &str,
    parent_oid: Option<Oid>,
    commit_oid: Oid,
) -> Result<Vec<GitCommitChangeEntry>, GitError> {
    let paths = GitPathContext::new(repo, workspace_path)?;
    let mut diff = diff_for_commit_range(repo, parent_oid, commit_oid, &[])?;
    let stats = commit_diff_stats_by_path(&mut diff)?;
    let selections = commit_diff_selections(&diff)?;
    let mut entries = Vec::new();
    for selection in selections {
        let Some(path) = visible_workspace_path(
            &paths,
            &selection.path,
            selection.old_path.as_deref(),
            selection.status,
        ) else {
            continue;
        };
        let old_path = selection
            .old_path
            .as_deref()
            .and_then(|old_path| paths.to_workspace_path(old_path));
        let (added, removed) = stats.get(&selection.path).copied().unwrap_or((None, None));
        entries.push(GitCommitChangeEntry {
            path,
            old_path,
            status: selection.status,
            added,
            removed,
        });
    }
    entries.sort_by(|a, b| a.path.cmp(&b.path));
    Ok(entries)
}

fn commit_diff_file_for_path(
    _repo: &Repository,
    paths: &GitPathContext,
    diff: &mut Diff<'_>,
    repo_path: &str,
    old_repo_path: Option<&str>,
) -> Result<Option<GitDiffFile>, GitError> {
    let selections = commit_diff_selections(diff)?;
    let selection = selections
        .iter()
        .find(|selection| {
            selected_delta_matches_path(
                delta_for_status(selection.status),
                &selection.path,
                selection.old_path.as_deref(),
                repo_path,
            )
        })
        .or_else(|| {
            old_repo_path.and_then(|old_repo_path| {
                selections.iter().find(|selection| {
                    selection.status == GitChangeStatus::Renamed
                        && selection.old_path.as_deref() == Some(old_repo_path)
                })
            })
        });
    let Some(selection) = selection else {
        return Ok(None);
    };
    let rendered = render_diff_for_path(diff, &selection.path)?;
    let Some(path) = visible_workspace_path(
        paths,
        &selection.path,
        selection.old_path.as_deref(),
        selection.status,
    ) else {
        return Ok(None);
    };
    Ok(Some(GitDiffFile {
        path,
        old_path: selection
            .old_path
            .as_deref()
            .and_then(|old_path| paths.to_workspace_path(old_path)),
        area: GitChangeArea::Staged,
        status: selection.status,
        lines: rendered.lines,
        added: Some(rendered.added),
        removed: Some(rendered.removed),
        is_binary: rendered.is_binary,
        is_large: false,
        is_gitlink: false,
        truncated: rendered.truncated,
        line_preview_truncated: rendered.line_preview_truncated,
    }))
}

fn diff_for_commit_range<'repo>(
    repo: &'repo Repository,
    parent_oid: Option<Oid>,
    commit_oid: Oid,
    pathspecs: &[&str],
) -> Result<Diff<'repo>, GitError> {
    let commit = repo.find_commit(commit_oid).map_err(GitError::from_git2)?;
    let commit_tree = commit.tree().map_err(GitError::from_git2)?;
    let parent_tree = parent_oid
        .map(|oid| {
            repo.find_commit(oid)
                .and_then(|commit| commit.tree())
                .map_err(GitError::from_git2)
        })
        .transpose()?;
    let mut options = DiffOptions::new();
    let mut has_pathspec = false;
    for pathspec in pathspecs.iter().filter(|pathspec| !pathspec.is_empty()) {
        options.pathspec(pathspec);
        has_pathspec = true;
    }
    if has_pathspec {
        options.disable_pathspec_match(true);
    }
    let mut diff = repo
        .diff_tree_to_tree(parent_tree.as_ref(), Some(&commit_tree), Some(&mut options))
        .map_err(GitError::from_git2)?;
    let mut find_options = DiffFindOptions::new();
    find_options.renames(true).copies(true);
    diff.find_similar(Some(&mut find_options))
        .map_err(GitError::from_git2)?;
    Ok(diff)
}

fn commit_diff_selections(diff: &Diff<'_>) -> Result<Vec<DiffSelection>, GitError> {
    let mut selections = Vec::new();
    for delta in diff.deltas() {
        let path = delta_path(&delta, false)?;
        let old_path = old_path_for_delta(&delta)?;
        selections.push(DiffSelection {
            path,
            old_path,
            status: change_status_for_delta(delta.status(), GitChangeArea::Staged),
        });
    }
    Ok(selections)
}

fn commit_diff_stats_by_path(diff: &mut Diff<'_>) -> Result<CommitDiffLineStatsByPath, GitError> {
    let mut stats = HashMap::<String, (u32, u32)>::new();
    diff.print(DiffFormat::Patch, |delta, _hunk, line| {
        let Ok(path) = delta_path(&delta, false) else {
            return true;
        };
        let entry = stats.entry(path).or_insert((0, 0));
        match line.origin_value() {
            DiffLineType::Addition => entry.0 = entry.0.saturating_add(line.num_lines()),
            DiffLineType::Deletion => entry.1 = entry.1.saturating_add(line.num_lines()),
            _ => {}
        }
        true
    })
    .map_err(GitError::from_git2)?;
    Ok(stats
        .into_iter()
        .map(|(path, (added, removed))| {
            (
                path,
                (
                    if added > 0 { Some(added) } else { None },
                    if removed > 0 { Some(removed) } else { None },
                ),
            )
        })
        .collect())
}

fn delta_for_status(status: GitChangeStatus) -> Delta {
    match status {
        GitChangeStatus::Added | GitChangeStatus::Untracked => Delta::Added,
        GitChangeStatus::Deleted => Delta::Deleted,
        GitChangeStatus::Renamed => Delta::Renamed,
        GitChangeStatus::Copied => Delta::Copied,
        GitChangeStatus::Modified => Delta::Modified,
    }
}

fn short_oid(oid: Oid) -> String {
    oid.to_string().chars().take(7).collect()
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
    status: GitChangeStatus,
) -> Option<String> {
    paths.to_workspace_path(repo_path).or_else(|| {
        if matches!(status, GitChangeStatus::Renamed | GitChangeStatus::Deleted) {
            old_path.and_then(|old_path| paths.to_workspace_path(old_path))
        } else {
            None
        }
    })
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
    if rendered.is_binary || rendered.lines.is_empty() {
        return Ok(None);
    }
    Ok(Some((rendered.added, rendered.removed)))
}

fn status_result_from_entries(entries: Vec<GitChangeEntry>) -> GitStatusResult {
    let groups = [
        GitChangeArea::Staged,
        GitChangeArea::Unstaged,
        GitChangeArea::Untracked,
    ]
    .into_iter()
    .filter_map(|area| {
        let entries = entries
            .iter()
            .filter(|entry| entry.area == area)
            .cloned()
            .collect::<Vec<_>>();
        if entries.is_empty() {
            return None;
        }
        let tree_rows = build_tree_rows(&entries);
        Some(GitChangeGroup {
            area,
            entries,
            tree_rows,
        })
    })
    .collect();
    GitStatusResult { entries, groups }
}

fn build_tree_rows(entries: &[GitChangeEntry]) -> Vec<GitChangeTreeRow> {
    let mut root = StatusTreeNode::directory(String::new(), String::new(), 0);
    for entry in entries {
        let parts = entry
            .path
            .split('/')
            .filter(|part| !part.is_empty())
            .collect::<Vec<_>>();
        if parts.is_empty() {
            continue;
        }
        let mut parent = &mut root;
        for index in 0..parts.len().saturating_sub(1) {
            let path = parts[..=index].join("/");
            parent = parent.directory_child(parts[index].to_string(), path, index as u32);
        }
        parent.children.push(StatusTreeNode::file(
            parts.last().unwrap().to_string(),
            entry.path.clone(),
            parts.len().saturating_sub(1) as u32,
            entry.clone(),
        ));
    }
    root.sort_recursively();
    let mut rows = Vec::new();
    for child in &root.children {
        child.append_rows(&mut rows);
    }
    rows
}

struct StatusTreeNode {
    name: String,
    path: String,
    depth: u32,
    entry: Option<GitChangeEntry>,
    children: Vec<StatusTreeNode>,
}

impl StatusTreeNode {
    fn directory(name: String, path: String, depth: u32) -> Self {
        Self {
            name,
            path,
            depth,
            entry: None,
            children: Vec::new(),
        }
    }

    fn file(name: String, path: String, depth: u32, entry: GitChangeEntry) -> Self {
        Self {
            name,
            path,
            depth,
            entry: Some(entry),
            children: Vec::new(),
        }
    }

    fn directory_child(&mut self, name: String, path: String, depth: u32) -> &mut StatusTreeNode {
        if let Some(index) = self
            .children
            .iter()
            .position(|child| child.entry.is_none() && child.name == name)
        {
            return &mut self.children[index];
        }
        self.children
            .push(StatusTreeNode::directory(name, path, depth));
        self.children.last_mut().expect("directory child exists")
    }

    fn sort_recursively(&mut self) {
        self.children.sort_by(|a, b| match (&a.entry, &b.entry) {
            (None, Some(_)) => std::cmp::Ordering::Less,
            (Some(_), None) => std::cmp::Ordering::Greater,
            _ => a.name.cmp(&b.name),
        });
        for child in &mut self.children {
            child.sort_recursively();
        }
    }

    fn append_rows(&self, rows: &mut Vec<GitChangeTreeRow>) {
        rows.push(GitChangeTreeRow {
            kind: if self.entry.is_some() {
                GitChangeTreeRowKind::File
            } else {
                GitChangeTreeRowKind::Directory
            },
            name: self.name.clone(),
            path: self.path.clone(),
            depth: self.depth,
            file_count: self.file_count(),
            entry: self.entry.clone(),
        });
        for child in &self.children {
            child.append_rows(rows);
        }
    }

    fn file_count(&self) -> u32 {
        if self.entry.is_some() {
            return 1;
        }
        self.children
            .iter()
            .map(StatusTreeNode::file_count)
            .sum::<u32>()
    }
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
