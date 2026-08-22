use git2::{Diff, DiffFindOptions, DiffFormat, DiffLineType, DiffOptions, Oid, Repository};

#[path = "git_reading_diff_submodule.rs"]
mod git_reading_diff_submodule;

use super::git_diff_untracked::git_patch_path;
use super::{
    build_untracked_patch, git_status, git_status_for_path, open_repo, read_untracked_text_up_to,
    GitChangeArea, GitError, GitErrorKind, GitPathContext,
};
use git_reading_diff_submodule::submodule_child_workdir;

const MAX_READING_DIFF_BYTES: usize = 4 * 1024 * 1024;

pub(crate) fn git_reading_diff_patch(
    path: String,
    file_path: Option<String>,
    old_path: Option<String>,
    area: Option<GitChangeArea>,
    commit_oid: Option<String>,
    parent_oid: Option<String>,
    base_ref: Option<String>,
) -> Result<Vec<u8>, GitError> {
    git_reading_diff_patch_with_prefix(
        path, file_path, old_path, area, commit_oid, parent_oid, base_ref, None,
    )
}

#[allow(clippy::too_many_arguments)]
fn git_reading_diff_patch_with_prefix(
    path: String,
    file_path: Option<String>,
    old_path: Option<String>,
    area: Option<GitChangeArea>,
    commit_oid: Option<String>,
    parent_oid: Option<String>,
    base_ref: Option<String>,
    output_prefix: Option<&str>,
) -> Result<Vec<u8>, GitError> {
    let repo = open_repo(&path)?;
    let paths = GitPathContext::new(&repo, &path)?;
    if let Some(base_ref) = base_ref {
        if area.is_some() || commit_oid.is_some() || parent_oid.is_some() {
            return Err(GitError::new(
                GitErrorKind::Internal,
                "a range reading diff cannot also select a worktree area or commit",
            ));
        }
        let base_ref = base_ref.trim();
        if base_ref.is_empty() {
            return Err(GitError::new(
                GitErrorKind::InvalidBranchName,
                "base branch is empty",
            ));
        }
        let base_oid = repo
            .revparse_single(base_ref)
            .and_then(|object| object.peel_to_commit())
            .map(|commit| commit.id())
            .map_err(GitError::from_git2)?;
        let head_oid = super::super::current_head_commit(&repo)?
            .ok_or_else(|| {
                GitError::new(GitErrorKind::DetachedHead, "repository has no HEAD commit")
            })?
            .id();
        let merge_base = repo
            .merge_base(base_oid, head_oid)
            .map_err(GitError::from_git2)?;
        let base_tree = repo
            .find_commit(merge_base)
            .and_then(|commit| commit.tree())
            .map_err(GitError::from_git2)?;
        let head_tree = repo
            .find_commit(head_oid)
            .and_then(|commit| commit.tree())
            .map_err(GitError::from_git2)?;
        let mut options = DiffOptions::new();
        apply_output_prefix(&mut options, output_prefix);
        options.disable_pathspec_match(true);
        if let Some(file_path) = file_path.as_deref() {
            options.pathspec(paths.to_repo_path(file_path));
        }
        if let Some(old_path) = old_path.as_deref() {
            options.pathspec(paths.to_repo_path(old_path));
        }
        let mut diff = repo
            .diff_tree_to_tree(Some(&base_tree), Some(&head_tree), Some(&mut options))
            .map_err(GitError::from_git2)?;
        let mut find_options = DiffFindOptions::new();
        find_options.renames(true).copies(true);
        diff.find_similar(Some(&mut find_options))
            .map_err(GitError::from_git2)?;
        return raw_patch(&mut diff, MAX_READING_DIFF_BYTES);
    }
    if let Some(commit_oid) = commit_oid {
        if area.is_some() {
            return Err(GitError::new(
                GitErrorKind::Internal,
                "a commit reading diff cannot also select a worktree area",
            ));
        }
        let commit_oid = Oid::from_str(&commit_oid).map_err(GitError::from_git2)?;
        let parent_oid = parent_oid
            .as_deref()
            .map(Oid::from_str)
            .transpose()
            .map_err(GitError::from_git2)?;
        let repo_path = file_path.as_deref().map(|value| paths.to_repo_path(value));
        let old_repo_path = old_path.as_deref().map(|value| paths.to_repo_path(value));
        let mut pathspecs = repo_path.as_deref().into_iter().collect::<Vec<_>>();
        if let Some(old_repo_path) = old_repo_path.as_deref() {
            pathspecs.push(old_repo_path);
        }
        let mut diff = diff_for_commit_range_with_prefix(
            &repo,
            parent_oid,
            commit_oid,
            &pathspecs,
            output_prefix,
        )?;
        return raw_patch(&mut diff, MAX_READING_DIFF_BYTES);
    }
    if parent_oid.is_some() {
        return Err(GitError::new(
            GitErrorKind::Internal,
            "a parent commit requires a commit reading diff",
        ));
    }

    let status = match (&file_path, &old_path) {
        (Some(file_path), None) => git_status_for_path(path.clone(), file_path.clone())?,
        _ => git_status(path.clone())?,
    };
    let mut output = Vec::new();
    for entry in status.entries {
        if area.is_some_and(|selected| selected != entry.area) {
            continue;
        }
        if file_path.as_ref().is_some_and(|selected| {
            selected != &entry.path && entry.old_path.as_ref() != Some(selected)
        }) {
            continue;
        }
        let repo_path = paths.to_repo_path(&entry.path);
        if let Some(submodule) = &entry.submodule {
            if submodule.commit_changed {
                let mut diff = diff_for_area_with_prefix(
                    &repo,
                    &[repo_path.as_str()],
                    entry.area,
                    output_prefix,
                )?;
                append_limited_patch(&mut output, &mut diff, MAX_READING_DIFF_BYTES)?;
            }
            if entry.area == GitChangeArea::Unstaged
                && submodule.inspectable
                && (submodule.tracked_changes || submodule.untracked_changes)
            {
                let child_path = submodule_child_workdir(&path, &entry.path)?;
                let child_prefix = prefixed_path(output_prefix, &entry.path);
                let child_patch = git_reading_diff_patch_with_prefix(
                    child_path,
                    None,
                    None,
                    None,
                    None,
                    None,
                    None,
                    Some(&child_prefix),
                )?;
                append_limited_bytes(&mut output, &child_patch, MAX_READING_DIFF_BYTES)?;
            }
            continue;
        }
        if entry.area == GitChangeArea::Untracked {
            let value =
                read_untracked_text_up_to(&repo, &repo_path, MAX_READING_DIFF_BYTES as u64)?;
            if value.is_large && !value.is_binary {
                return Err(GitError::new(
                    GitErrorKind::Internal,
                    "reading diff input exceeds the 4 MiB safety limit",
                ));
            }
            let output_path = prefixed_path(output_prefix, &entry.path);
            if let Some(content) = value.content {
                append_limited_bytes(
                    &mut output,
                    build_untracked_patch(
                        &output_path,
                        &content,
                        value.is_symlink,
                        value.is_executable,
                    )
                    .as_bytes(),
                    MAX_READING_DIFF_BYTES,
                )?;
            } else {
                append_limited_bytes(
                    &mut output,
                    untracked_placeholder_patch(&output_path, value.is_binary, value.is_executable)
                        .as_bytes(),
                    MAX_READING_DIFF_BYTES,
                )?;
            }
        } else {
            let old_repo_path = old_path
                .as_deref()
                .or(entry.old_path.as_deref())
                .map(|value| paths.to_repo_path(value));
            let mut pathspecs = vec![repo_path.as_str()];
            if let Some(old_repo_path) = old_repo_path.as_deref() {
                pathspecs.push(old_repo_path);
            }
            let mut diff = diff_for_area_with_prefix(&repo, &pathspecs, entry.area, output_prefix)?;
            append_limited_patch(&mut output, &mut diff, MAX_READING_DIFF_BYTES)?;
        }
    }
    Ok(output)
}

fn diff_for_commit_range_with_prefix<'repo>(
    repo: &'repo Repository,
    parent_oid: Option<Oid>,
    commit_oid: Oid,
    pathspecs: &[&str],
    output_prefix: Option<&str>,
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
    if !pathspecs.is_empty() {
        options.disable_pathspec_match(true);
    }
    for pathspec in pathspecs {
        options.pathspec(pathspec);
    }
    apply_output_prefix(&mut options, output_prefix);
    let mut diff = repo
        .diff_tree_to_tree(parent_tree.as_ref(), Some(&commit_tree), Some(&mut options))
        .map_err(GitError::from_git2)?;
    find_renames_and_copies(&mut diff)?;
    Ok(diff)
}

fn diff_for_area_with_prefix<'repo>(
    repo: &'repo Repository,
    pathspecs: &[&str],
    area: GitChangeArea,
    output_prefix: Option<&str>,
) -> Result<Diff<'repo>, GitError> {
    let mut options = DiffOptions::new();
    if !pathspecs.is_empty() {
        options.disable_pathspec_match(true);
    }
    for pathspec in pathspecs {
        options.pathspec(pathspec);
    }
    apply_output_prefix(&mut options, output_prefix);
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
    find_renames_and_copies(&mut diff)?;
    Ok(diff)
}

fn find_renames_and_copies(diff: &mut Diff<'_>) -> Result<(), GitError> {
    let mut options = DiffFindOptions::new();
    options.renames(true).copies(true);
    diff.find_similar(Some(&mut options))
        .map_err(GitError::from_git2)
}

fn append_limited_patch(
    output: &mut Vec<u8>,
    diff: &mut Diff<'_>,
    limit: usize,
) -> Result<(), GitError> {
    let patch = raw_patch(diff, limit.saturating_sub(output.len()))?;
    append_limited_bytes(output, &patch, limit)
}

fn append_limited_bytes(output: &mut Vec<u8>, value: &[u8], limit: usize) -> Result<(), GitError> {
    if output.len().saturating_add(value.len()) > limit {
        return Err(GitError::new(
            GitErrorKind::Internal,
            "reading diff input exceeds the 4 MiB safety limit",
        ));
    }
    output.extend_from_slice(value);
    Ok(())
}

fn untracked_placeholder_patch(path: &str, is_binary: bool, is_executable: bool) -> String {
    let description = if is_binary {
        "Binary file"
    } else {
        "Non-regular file"
    };
    let mode = if is_executable { "100755" } else { "100644" };
    let old_path = git_patch_path("a", path);
    let new_path = git_patch_path("b", path);
    format!(
        "diff --git {old_path} {new_path}\nnew file mode {mode}\n{description} /dev/null and {new_path} differ\n"
    )
}

fn prefixed_path(prefix: Option<&str>, path: &str) -> String {
    prefix.map_or_else(|| path.to_string(), |prefix| format!("{prefix}/{path}"))
}

fn apply_output_prefix(options: &mut DiffOptions, output_prefix: Option<&str>) {
    if let Some(prefix) = output_prefix {
        options.old_prefix(format!("a/{prefix}/"));
        options.new_prefix(format!("b/{prefix}/"));
    }
}

fn raw_patch(diff: &mut Diff<'_>, limit: usize) -> Result<Vec<u8>, GitError> {
    let mut output = Vec::new();
    let mut too_large = false;
    let result = diff.print(DiffFormat::Patch, |_delta, _hunk, line| {
        if too_large {
            return false;
        }
        let has_source_origin = matches!(
            line.origin_value(),
            DiffLineType::Context | DiffLineType::Addition | DiffLineType::Deletion
        );
        let additional = line
            .content()
            .len()
            .saturating_add(usize::from(has_source_origin));
        if output.len().saturating_add(additional) > limit {
            too_large = true;
            return false;
        }
        match line.origin_value() {
            DiffLineType::Context | DiffLineType::Addition | DiffLineType::Deletion => {
                output.push(line.origin() as u8)
            }
            DiffLineType::ContextEOFNL
            | DiffLineType::AddEOFNL
            | DiffLineType::DeleteEOFNL
            | DiffLineType::FileHeader
            | DiffLineType::HunkHeader
            | DiffLineType::Binary => {}
        }
        output.extend_from_slice(line.content());
        true
    });
    if too_large {
        return Err(GitError::new(
            GitErrorKind::Internal,
            "reading diff input exceeds the 4 MiB safety limit",
        ));
    }
    result.map_err(GitError::from_git2)?;
    Ok(output)
}

#[cfg(test)]
#[path = "git_reading_diff_patch_tests.rs"]
mod tests;
