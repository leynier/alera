use std::path::{Component, Path};

use git2::{
    build::CheckoutBuilder, ErrorCode, ObjectType, Oid, Repository, Submodule, SubmoduleIgnore,
    SubmoduleStatus,
};

use super::{
    commit_change_entries, commit_diff_file_for_path, diff_file_for_area, diff_for_commit_range,
    git_diff_render::diff_lines_from_patch, git_status, git_status_for_path,
    status_result_from_entries, GitChangeArea, GitChangeEntry, GitChangeStatus, GitDiffFile,
    GitError, GitErrorKind, GitPathContext, GitStatusResult, GitSubmoduleStatus,
};

// git2 0.21 exposes every SubmoduleStatus predicate except WD_INDEX_MODIFIED.
// This bit is part of libgit2's stable public enum and represents staged
// tracked changes inside the submodule worktree.
const WD_INDEX_MODIFIED_BIT: u32 = 1 << 11;

pub(super) enum SubmoduleDiff {
    NotSubmodule,
    NoDiff,
    File(GitDiffFile),
}

struct ResolvedSubmodule<'repo> {
    submodule: Submodule<'repo>,
    workspace_path: String,
    inner_path: String,
}

pub(super) fn status_for_path(
    repo: &Repository,
    repo_path: &str,
    area: GitChangeArea,
) -> Result<Option<GitSubmoduleStatus>, GitError> {
    let Some(submodule) = exact_submodule(repo, repo_path)? else {
        return Ok(None);
    };
    let name = submodule.name().map_err(GitError::from_git2)?;
    let status = repo
        .submodule_status(name, SubmoduleIgnore::None)
        .map_err(GitError::from_git2)?;
    let (from_oid, to_oid) = commit_range(&submodule, area);
    Ok(Some(GitSubmoduleStatus {
        commit_changed: from_oid != to_oid,
        tracked_changes: has_tracked_worktree_changes(status),
        untracked_changes: status.is_wd_untracked(),
        inspectable: from_oid.is_some()
            && to_oid.is_some()
            && !status.is_wd_uninitialized()
            && !status.is_wd_deleted(),
    }))
}

pub(super) fn git_submodule_status(
    path: String,
    submodule_path: String,
    area: GitChangeArea,
) -> Result<GitStatusResult, GitError> {
    let parent = super::open_repo(&path)?;
    let paths = GitPathContext::new(&parent, &path)?;
    let repo_path = paths.to_repo_path(&submodule_path);
    let Some(resolved) = containing_submodule(&parent, &paths, &repo_path)? else {
        return Err(GitError::new(
            GitErrorKind::WorkspaceScope,
            format!("configured submodule not found: {submodule_path}"),
        ));
    };
    if !resolved.inner_path.is_empty() {
        return Err(GitError::new(
            GitErrorKind::WorkspaceScope,
            format!("submodule path must identify a configured root: {submodule_path}"),
        ));
    }

    let range = commit_range(&resolved.submodule, area);
    let name = resolved.submodule.name().map_err(GitError::from_git2)?;
    let current_status = parent
        .submodule_status(name, SubmoduleIgnore::None)
        .map_err(GitError::from_git2)?;
    if current_status.is_wd_uninitialized() {
        return Err(GitError::new(
            GitErrorKind::NotARepository,
            format!("Submodule Is Not Initialized: {}", resolved.workspace_path),
        ));
    }
    if range.0 != range.1 && (range.0.is_none() || range.1.is_none()) {
        return Ok(status_result_from_entries(Vec::new()));
    }
    let child = open_submodule(&parent, &resolved)?;
    let child_path = child_workdir_string(&child, &resolved.workspace_path)?;

    if let (Some(from_oid), Some(to_oid)) = range {
        if from_oid != to_oid {
            let range_entries = commit_range_entries(&child, &child_path, from_oid, to_oid, area)?;
            if area == GitChangeArea::Staged {
                return Ok(status_result_from_entries(range_entries));
            }
            let working = git_status(child_path)?;
            let mut entries = range_entries
                .into_iter()
                .filter(|range_entry| {
                    !working.entries.iter().any(|working_entry| {
                        working_entry.area == range_entry.area
                            && working_entry.path == range_entry.path
                    })
                })
                .collect::<Vec<_>>();
            entries.extend(working.entries);
            return Ok(status_result_from_entries(entries));
        }
    }

    if area == GitChangeArea::Staged {
        return Ok(status_result_from_entries(Vec::new()));
    }
    git_status(child_path)
}

pub(super) fn git_submodule_worktree_status(
    path: String,
    submodule_path: String,
) -> Result<GitStatusResult, GitError> {
    let parent = super::open_repo(&path)?;
    let paths = GitPathContext::new(&parent, &path)?;
    let repo_path = paths.to_repo_path(&submodule_path);
    let Some(resolved) = containing_submodule(&parent, &paths, &repo_path)? else {
        return Err(GitError::new(
            GitErrorKind::WorkspaceScope,
            format!("configured submodule not found: {submodule_path}"),
        ));
    };
    if !resolved.inner_path.is_empty() {
        return Err(GitError::new(
            GitErrorKind::WorkspaceScope,
            format!("submodule path must identify a configured root: {submodule_path}"),
        ));
    }
    let name = resolved.submodule.name().map_err(GitError::from_git2)?;
    let current_status = parent
        .submodule_status(name, SubmoduleIgnore::None)
        .map_err(GitError::from_git2)?;
    if current_status.is_wd_uninitialized() {
        return Err(GitError::new(
            GitErrorKind::NotARepository,
            format!("Submodule Is Not Initialized: {}", resolved.workspace_path),
        ));
    }
    let child = open_submodule(&parent, &resolved)?;
    git_status(child_workdir_string(&child, &resolved.workspace_path)?)
}

pub(super) fn diff_file_for_submodule(
    parent: &Repository,
    paths: &GitPathContext,
    workspace_file_path: &str,
    area: GitChangeArea,
) -> Result<SubmoduleDiff, GitError> {
    let repo_path = paths.to_repo_path(workspace_file_path);
    let Some(resolved) = containing_submodule(parent, paths, &repo_path)? else {
        return Ok(SubmoduleDiff::NotSubmodule);
    };
    let range = commit_range(&resolved.submodule, area);

    if resolved.inner_path.is_empty() {
        return if range.0 != range.1 {
            Ok(SubmoduleDiff::File(pointer_diff(
                &resolved.workspace_path,
                area,
                range.0,
                range.1,
            )))
        } else {
            Ok(SubmoduleDiff::NoDiff)
        };
    }

    let child = open_submodule(parent, &resolved)?;
    let child_path = child_workdir_string(&child, &resolved.workspace_path)?;
    let child_paths = GitPathContext::new(&child, &child_path)?;
    let file = match range {
        (Some(from_oid), Some(to_oid)) if area == GitChangeArea::Staged && from_oid != to_oid => {
            let mut diff = diff_for_commit_range(
                &child,
                Some(from_oid),
                to_oid,
                &[resolved.inner_path.as_str()],
            )?;
            let mut file = commit_diff_file_for_path(
                &child,
                &child_paths,
                &mut diff,
                &resolved.inner_path,
                None,
            )?;
            if let Some(file) = file.as_mut() {
                file.area = area;
            }
            file
        }
        _ => {
            let has_matching_worktree_entry =
                git_status_for_path(child_path.clone(), resolved.inner_path.clone())?
                    .entries
                    .iter()
                    .any(|entry| entry.area == area && entry.path == resolved.inner_path);
            match range {
                _ if has_matching_worktree_entry => {
                    diff_file_for_area(&child, &child_paths, &resolved.inner_path, area)?
                }
                (Some(from_oid), Some(to_oid)) if from_oid != to_oid => {
                    let mut diff = diff_for_commit_range(
                        &child,
                        Some(from_oid),
                        to_oid,
                        &[resolved.inner_path.as_str()],
                    )?;
                    let mut file = commit_diff_file_for_path(
                        &child,
                        &child_paths,
                        &mut diff,
                        &resolved.inner_path,
                        None,
                    )?;
                    if let Some(file) = file.as_mut() {
                        file.area = area;
                    }
                    file
                }
                _ => diff_file_for_area(&child, &child_paths, &resolved.inner_path, area)?,
            }
        }
    };
    let Some(mut file) = file else {
        return Ok(SubmoduleDiff::NoDiff);
    };
    prefix_diff_file(&mut file, &resolved.workspace_path);
    Ok(SubmoduleDiff::File(file))
}

pub(super) fn discard_gitlink_change(
    parent: &Repository,
    paths: &GitPathContext,
    workspace_path: &str,
    skip_dirty: bool,
) -> Result<bool, GitError> {
    let repo_path = paths.to_repo_path(workspace_path);
    let Some(resolved) = containing_submodule(parent, paths, &repo_path)? else {
        return Err(GitError::new(
            GitErrorKind::WorkspaceScope,
            format!("configured submodule not found: {workspace_path}"),
        ));
    };
    if !resolved.inner_path.is_empty() {
        return Err(GitError::new(
            GitErrorKind::WorkspaceScope,
            format!("submodule path must identify a configured root: {workspace_path}"),
        ));
    }

    let index = parent.index().map_err(GitError::from_git2)?;
    let index_entry = index
        .get_path(Path::new(&repo_path), 0)
        .filter(|entry| entry.mode & 0o170000 == 0o160000)
        .ok_or_else(|| {
            GitError::new(
                GitErrorKind::Internal,
                format!("submodule gitlink is missing from the index: {workspace_path}"),
            )
        })?;
    let child = open_submodule(parent, &resolved)?;
    let child_path = child_workdir_string(&child, &resolved.workspace_path)?;
    if !git_status(child_path)?.entries.is_empty() {
        if skip_dirty {
            return Ok(false);
        }
        return Err(GitError::new(
            GitErrorKind::Conflict,
            format!(
                "commit, stash, or discard changes inside the submodule before discarding its gitlink: {workspace_path}"
            ),
        ));
    }
    let target = child
        .find_object(index_entry.id, Some(ObjectType::Commit))
        .map_err(GitError::from_git2)?;
    let mut checkout = CheckoutBuilder::new();
    checkout.force();
    child
        .checkout_tree(&target, Some(&mut checkout))
        .map_err(GitError::from_git2)?;
    child
        .set_head_detached(index_entry.id)
        .map_err(GitError::from_git2)?;
    Ok(true)
}

fn exact_submodule<'repo>(
    repo: &'repo Repository,
    repo_path: &str,
) -> Result<Option<Submodule<'repo>>, GitError> {
    match repo.find_submodule(repo_path) {
        Ok(submodule) if normalize_path(submodule.path()) == repo_path => Ok(Some(submodule)),
        Ok(_) => Ok(None),
        Err(error) if error.code() == ErrorCode::NotFound => Ok(None),
        Err(error) => Err(GitError::from_git2(error)),
    }
}

fn containing_submodule<'repo>(
    repo: &'repo Repository,
    paths: &GitPathContext,
    repo_path: &str,
) -> Result<Option<ResolvedSubmodule<'repo>>, GitError> {
    let mut best: Option<(usize, String)> = None;
    for submodule in repo.submodules().map_err(GitError::from_git2)? {
        let submodule_path = normalize_path(submodule.path());
        if repo_path == submodule_path || repo_path.starts_with(&format!("{submodule_path}/")) {
            let length = submodule_path.len();
            if best
                .as_ref()
                .is_none_or(|(best_length, _)| length > *best_length)
            {
                best = Some((
                    length,
                    submodule.name().map_err(GitError::from_git2)?.to_string(),
                ));
            }
        }
    }
    let Some((_, name)) = best else {
        return Ok(None);
    };
    let submodule = repo.find_submodule(&name).map_err(GitError::from_git2)?;
    let submodule_repo_path = normalize_path(submodule.path());
    let Some(workspace_path) = paths.to_workspace_path(&submodule_repo_path) else {
        return Ok(None);
    };
    let inner_path = repo_path
        .strip_prefix(&format!("{submodule_repo_path}/"))
        .unwrap_or("")
        .to_string();
    Ok(Some(ResolvedSubmodule {
        submodule,
        workspace_path,
        inner_path,
    }))
}

fn open_submodule(
    parent: &Repository,
    resolved: &ResolvedSubmodule<'_>,
) -> Result<Repository, GitError> {
    let relative_path = resolved.submodule.path();
    if relative_path.as_os_str().is_empty()
        || relative_path
            .components()
            .any(|component| !matches!(component, Component::Normal(_)))
    {
        return Err(GitError::new(
            GitErrorKind::WorkspaceScope,
            format!("invalid submodule path: {}", resolved.workspace_path),
        ));
    }
    let parent_workdir = parent
        .workdir()
        .ok_or_else(|| GitError::new(GitErrorKind::NotARepository, "bare parent repository"))?;
    let parent_root =
        std::fs::canonicalize(parent_workdir).unwrap_or_else(|_| parent_workdir.into());
    let candidate = parent_workdir.join(relative_path);
    let candidate_root = std::fs::canonicalize(&candidate).map_err(|_| {
        GitError::new(
            GitErrorKind::NotARepository,
            format!("Submodule Is Not Initialized: {}", resolved.workspace_path),
        )
    })?;
    if candidate_root == parent_root || !candidate_root.starts_with(&parent_root) {
        return Err(GitError::new(
            GitErrorKind::WorkspaceScope,
            format!(
                "submodule path escapes worktree: {}",
                resolved.workspace_path
            ),
        ));
    }
    resolved.submodule.open().map_err(|_| {
        GitError::new(
            GitErrorKind::NotARepository,
            format!("Submodule Is Not Initialized: {}", resolved.workspace_path),
        )
    })
}

fn child_workdir_string(child: &Repository, display_path: &str) -> Result<String, GitError> {
    child
        .workdir()
        .map(|path| path.to_string_lossy().to_string())
        .ok_or_else(|| GitError::new(GitErrorKind::NotARepository, display_path))
}

fn commit_range(submodule: &Submodule<'_>, area: GitChangeArea) -> (Option<Oid>, Option<Oid>) {
    match area {
        GitChangeArea::Staged => (submodule.head_id(), submodule.index_id()),
        GitChangeArea::Unstaged | GitChangeArea::Untracked => (
            submodule.index_id().or_else(|| submodule.head_id()),
            submodule.workdir_id(),
        ),
    }
}

fn has_tracked_worktree_changes(status: SubmoduleStatus) -> bool {
    status.is_wd_wd_modified() || status.bits() & WD_INDEX_MODIFIED_BIT != 0
}

fn commit_range_entries(
    child: &Repository,
    child_path: &str,
    from_oid: Oid,
    to_oid: Oid,
    area: GitChangeArea,
) -> Result<Vec<GitChangeEntry>, GitError> {
    Ok(
        commit_change_entries(child, child_path, Some(from_oid), to_oid)?
            .into_iter()
            .map(|entry| GitChangeEntry {
                path: entry.path,
                old_path: entry.old_path,
                area,
                status: entry.status,
                added: entry.added,
                removed: entry.removed,
                is_binary: false,
                is_large: false,
                submodule: None,
            })
            .collect(),
    )
}

fn pointer_diff(
    workspace_path: &str,
    area: GitChangeArea,
    from_oid: Option<Oid>,
    to_oid: Option<Oid>,
) -> GitDiffFile {
    let (status, added, removed) = match (from_oid, to_oid) {
        (None, Some(_)) => (GitChangeStatus::Added, Some(1), None),
        (Some(_), None) => (GitChangeStatus::Deleted, None, Some(1)),
        _ => (GitChangeStatus::Modified, Some(1), Some(1)),
    };
    let patch = match (from_oid, to_oid) {
        (Some(from_oid), Some(to_oid)) => format!(
            "diff --git a/{0} b/{0}\nindex {1}..{2} 160000\n--- a/{0}\n+++ b/{0}\n@@ -1 +1 @@\n-Subproject commit {1}\n+Subproject commit {2}\n",
            workspace_path, from_oid, to_oid
        ),
        (None, Some(to_oid)) => format!(
            "diff --git a/{0} b/{0}\nnew file mode 160000\n--- /dev/null\n+++ b/{0}\n@@ -0,0 +1 @@\n+Subproject commit {1}\n",
            workspace_path, to_oid
        ),
        (Some(from_oid), None) => format!(
            "diff --git a/{0} b/{0}\ndeleted file mode 160000\n--- a/{0}\n+++ /dev/null\n@@ -1 +0,0 @@\n-Subproject commit {1}\n",
            workspace_path, from_oid
        ),
        (None, None) => String::new(),
    };
    let (lines, line_preview_truncated) = diff_lines_from_patch(&patch);
    GitDiffFile {
        path: workspace_path.to_string(),
        old_path: None,
        area,
        status,
        lines,
        added,
        removed,
        is_binary: false,
        is_large: false,
        is_gitlink: true,
        truncated: false,
        line_preview_truncated,
    }
}

fn prefix_diff_file(file: &mut GitDiffFile, submodule_path: &str) {
    file.path = format!("{submodule_path}/{}", file.path);
    if let Some(old_path) = file.old_path.as_mut() {
        *old_path = format!("{submodule_path}/{old_path}");
    }
}

fn normalize_path(path: &Path) -> String {
    path.components()
        .filter_map(|component| match component {
            Component::Normal(part) => Some(part.to_string_lossy().to_string()),
            _ => None,
        })
        .collect::<Vec<_>>()
        .join("/")
}
