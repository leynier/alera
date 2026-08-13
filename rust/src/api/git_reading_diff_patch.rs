use git2::{Diff, DiffFindOptions, DiffFormat, DiffLineType, DiffOptions, Oid};

#[path = "git_reading_diff_submodule.rs"]
mod git_reading_diff_submodule;

use super::{
    build_untracked_patch, diff_for_area, diff_for_commit_range, git_status, git_status_for_path,
    open_repo, read_untracked_text_up_to, GitChangeArea, GitError, GitErrorKind, GitPathContext,
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
        let mut diff = diff_for_commit_range(&repo, parent_oid, commit_oid, &pathspecs)?;
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
                let mut diff = diff_for_area(&repo, &[repo_path.as_str()], entry.area)?;
                append_limited_patch(&mut output, &mut diff, MAX_READING_DIFF_BYTES)?;
            }
            if entry.area == GitChangeArea::Unstaged
                && submodule.inspectable
                && (submodule.tracked_changes || submodule.untracked_changes)
            {
                let child_path = submodule_child_workdir(&path, &entry.path)?;
                let child_patch =
                    git_reading_diff_patch(child_path, None, None, None, None, None, None)?;
                append_limited_bytes(
                    &mut output,
                    &prefix_submodule_patch(&child_patch, &entry.path),
                    MAX_READING_DIFF_BYTES,
                )?;
            }
            continue;
        }
        if entry.area == GitChangeArea::Untracked {
            let value =
                read_untracked_text_up_to(&repo, &repo_path, MAX_READING_DIFF_BYTES as u64)?;
            if value.is_large {
                return Err(GitError::new(
                    GitErrorKind::Internal,
                    "reading diff input exceeds the 4 MiB safety limit",
                ));
            }
            if let Some(content) = value.content {
                append_limited_bytes(
                    &mut output,
                    build_untracked_patch(&entry.path, &content, value.is_symlink).as_bytes(),
                    MAX_READING_DIFF_BYTES,
                )?;
            } else {
                append_limited_bytes(
                    &mut output,
                    untracked_placeholder_patch(&entry.path, value.is_binary).as_bytes(),
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
            let mut diff = diff_for_area(&repo, &pathspecs, entry.area)?;
            append_limited_patch(&mut output, &mut diff, MAX_READING_DIFF_BYTES)?;
        }
    }
    Ok(output)
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

fn untracked_placeholder_patch(path: &str, is_binary: bool) -> String {
    let description = if is_binary {
        "Binary file"
    } else {
        "Non-regular file"
    };
    format!(
        "diff --git a/{path} b/{path}\nnew file mode 100644\n{description} /dev/null and b/{path} differ\n"
    )
}

fn prefix_submodule_patch(patch: &[u8], prefix: &str) -> Vec<u8> {
    let mut output = Vec::with_capacity(patch.len().saturating_add(prefix.len() * 4));
    for line in patch.split_inclusive(|byte| *byte == b'\n') {
        let structural = line.starts_with(b"diff --git ")
            || line.starts_with(b"--- ")
            || line.starts_with(b"+++ ")
            || line.starts_with(b"rename from ")
            || line.starts_with(b"rename to ")
            || line.starts_with(b"copy from ")
            || line.starts_with(b"copy to ")
            || line.starts_with(b"Binary file ")
            || line.starts_with(b"Binary files ")
            || line.starts_with(b"Large file ");
        if !structural {
            output.extend_from_slice(line);
            continue;
        }
        let text = prefix_submodule_header(&String::from_utf8_lossy(line), prefix);
        output.extend_from_slice(text.as_bytes());
    }
    output
}

fn prefix_submodule_header(value: &str, prefix: &str) -> String {
    let mut value = value.to_string();
    let insertions = [
        ("diff --git a/", format!("diff --git a/{prefix}/")),
        ("diff --git \"a/", format!("diff --git \"a/{prefix}/")),
        (" b/", format!(" b/{prefix}/")),
        (" \"b/", format!(" \"b/{prefix}/")),
        ("--- a/", format!("--- a/{prefix}/")),
        ("--- \"a/", format!("--- \"a/{prefix}/")),
        ("+++ b/", format!("+++ b/{prefix}/")),
        ("+++ \"b/", format!("+++ \"b/{prefix}/")),
        ("rename from ", format!("rename from {prefix}/")),
        ("rename to ", format!("rename to {prefix}/")),
        ("copy from ", format!("copy from {prefix}/")),
        ("copy to ", format!("copy to {prefix}/")),
        ("Binary files a/", format!("Binary files a/{prefix}/")),
        ("Binary files \"a/", format!("Binary files \"a/{prefix}/")),
    ];
    for (needle, replacement) in insertions {
        value = value.replacen(needle, &replacement, 1);
    }
    value
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
