use git2::{
    DiffFindOptions, DiffFormat, DiffLineType, DiffOptions, ErrorCode, Oid, Repository, Sort,
};

use super::{
    current_head_commit, head_branch_name, open_repo, GitChangeStatus, GitError, GitErrorKind,
    GitRangeCommit, GitRangeContext, GitRangeFile,
};

const DEFAULT_COMMIT_LIMIT: u32 = 40;
const MAX_COMMIT_LIMIT: u32 = 100;
const MAX_RANGE_PATCH_BYTES: usize = 200 * 1024;

pub(super) fn git_range_context(
    path: String,
    base_ref: String,
    commit_limit: Option<u32>,
) -> Result<GitRangeContext, GitError> {
    let repo = open_repo(&path)?;
    let base_name = base_ref.trim();
    if base_name.is_empty() {
        return Err(GitError::new(
            GitErrorKind::InvalidBranchName,
            "base branch is empty",
        ));
    }
    let base_oid = resolve_ref_oid(&repo, base_name)?;
    let Some(head_commit) = current_head_commit(&repo)? else {
        return Err(GitError::new(
            GitErrorKind::DetachedHead,
            "repository has no HEAD commit",
        ));
    };
    let head_oid = head_commit.id();
    let head_branch = {
        let name = head_branch_name(&repo);
        if name == "HEAD" {
            None
        } else {
            Some(name)
        }
    };
    let merge_base_oid = repo
        .merge_base(base_oid, head_oid)
        .map_err(GitError::from_git2)?;
    let limit = commit_limit
        .unwrap_or(DEFAULT_COMMIT_LIMIT)
        .clamp(1, MAX_COMMIT_LIMIT) as usize;

    let commits = collect_commits_not_in_base(&repo, head_oid, merge_base_oid, limit)?;
    let (files, patch) = collect_range_diff(&repo, merge_base_oid, head_oid)?;

    Ok(GitRangeContext {
        base_ref: base_name.to_string(),
        head_branch,
        merge_base: Some(merge_base_oid.to_string()),
        commits,
        files,
        patch,
    })
}

fn resolve_ref_oid(repo: &Repository, name: &str) -> Result<Oid, GitError> {
    if name.starts_with('-') {
        return Err(GitError::new(
            GitErrorKind::InvalidBranchName,
            format!("invalid base ref '{name}'"),
        ));
    }
    let object = match repo.revparse_single(name) {
        Ok(object) => object,
        Err(error)
            if matches!(
                error.code(),
                ErrorCode::NotFound | ErrorCode::Ambiguous | ErrorCode::InvalidSpec
            ) =>
        {
            return Err(GitError::new(
                GitErrorKind::BranchNotFound,
                format!("base ref '{name}' was not found"),
            ));
        }
        Err(error) => return Err(GitError::from_git2(error)),
    };
    object
        .peel_to_commit()
        .map(|commit| commit.id())
        .map_err(GitError::from_git2)
}

fn collect_commits_not_in_base(
    repo: &Repository,
    head_oid: Oid,
    merge_base_oid: Oid,
    limit: usize,
) -> Result<Vec<GitRangeCommit>, GitError> {
    let mut revwalk = repo.revwalk().map_err(GitError::from_git2)?;
    revwalk.push(head_oid).map_err(GitError::from_git2)?;
    if merge_base_oid != head_oid {
        revwalk.hide(merge_base_oid).map_err(GitError::from_git2)?;
    }
    revwalk
        .set_sorting(Sort::TOPOLOGICAL | Sort::TIME)
        .map_err(GitError::from_git2)?;
    let mut commits = Vec::new();
    for oid in revwalk {
        let oid = oid.map_err(GitError::from_git2)?;
        if oid == merge_base_oid {
            continue;
        }
        let commit = repo.find_commit(oid).map_err(GitError::from_git2)?;
        let message = commit
            .message()
            .map_err(GitError::from_git2)
            .unwrap_or("")
            .trim()
            .to_string();
        let subject = match commit.summary() {
            Ok(Some(value)) => {
                let trimmed = value.trim();
                if trimmed.is_empty() {
                    short_oid(oid)
                } else {
                    trimmed.to_string()
                }
            }
            Ok(None) | Err(_) => short_oid(oid),
        };
        commits.push(GitRangeCommit {
            oid: oid.to_string(),
            subject,
            message,
        });
        if commits.len() >= limit {
            break;
        }
    }
    Ok(commits)
}

fn collect_range_diff(
    repo: &Repository,
    base_oid: Oid,
    head_oid: Oid,
) -> Result<(Vec<GitRangeFile>, String), GitError> {
    let base_tree = repo
        .find_commit(base_oid)
        .and_then(|commit| commit.tree())
        .map_err(GitError::from_git2)?;
    let head_tree = repo
        .find_commit(head_oid)
        .and_then(|commit| commit.tree())
        .map_err(GitError::from_git2)?;
    let mut options = DiffOptions::new();
    let mut diff = repo
        .diff_tree_to_tree(Some(&base_tree), Some(&head_tree), Some(&mut options))
        .map_err(GitError::from_git2)?;
    let mut find_options = DiffFindOptions::new();
    find_options.renames(true).copies(true);
    diff.find_similar(Some(&mut find_options))
        .map_err(GitError::from_git2)?;

    let mut stats = std::collections::HashMap::<String, (u32, u32)>::new();
    let mut statuses = std::collections::HashMap::<String, GitChangeStatus>::new();
    for delta in diff.deltas() {
        let path = delta
            .new_file()
            .path()
            .or_else(|| delta.old_file().path())
            .map(|path| path.to_string_lossy().to_string())
            .ok_or_else(|| GitError::new(GitErrorKind::Internal, "diff entry has no path"))?;
        let status = match delta.status() {
            git2::Delta::Added => GitChangeStatus::Added,
            git2::Delta::Deleted => GitChangeStatus::Deleted,
            git2::Delta::Renamed => GitChangeStatus::Renamed,
            git2::Delta::Copied => GitChangeStatus::Copied,
            git2::Delta::Untracked => GitChangeStatus::Untracked,
            _ => GitChangeStatus::Modified,
        };
        statuses.insert(path, status);
    }

    let mut patch = String::new();
    let mut truncated = false;
    diff.print(DiffFormat::Patch, |delta, _hunk, line| {
        if truncated {
            return true;
        }
        let path = delta
            .new_file()
            .path()
            .or_else(|| delta.old_file().path())
            .map(|path| path.to_string_lossy().to_string());
        if let Some(path) = path {
            let entry = stats.entry(path).or_insert((0, 0));
            match line.origin_value() {
                DiffLineType::Addition => entry.0 = entry.0.saturating_add(line.num_lines()),
                DiffLineType::Deletion => entry.1 = entry.1.saturating_add(line.num_lines()),
                _ => {}
            }
        }
        let content = String::from_utf8_lossy(line.content());
        let mut text = match line.origin_value() {
            DiffLineType::Context
            | DiffLineType::Addition
            | DiffLineType::Deletion
            | DiffLineType::ContextEOFNL
            | DiffLineType::AddEOFNL
            | DiffLineType::DeleteEOFNL => {
                let mut text = String::new();
                text.push(line.origin());
                text.push_str(content.trim_end_matches('\n'));
                text
            }
            _ => content.trim_end_matches('\n').to_string(),
        };
        if patch.len().saturating_add(text.len()).saturating_add(1) > MAX_RANGE_PATCH_BYTES {
            truncated = true;
            text.truncate(MAX_RANGE_PATCH_BYTES.saturating_sub(patch.len()));
        }
        if !text.is_empty() {
            if !patch.is_empty() {
                patch.push('\n');
            }
            patch.push_str(&text);
        }
        !truncated
    })
    .map_err(GitError::from_git2)?;
    if truncated {
        patch.push_str("\n...(diff truncated)");
    }

    let mut files = statuses
        .into_iter()
        .map(|(path, status)| {
            let (added, removed) = stats.get(&path).copied().unwrap_or((0, 0));
            GitRangeFile {
                path,
                status,
                added: if added > 0 { Some(added) } else { None },
                removed: if removed > 0 { Some(removed) } else { None },
            }
        })
        .collect::<Vec<_>>();
    files.sort_by(|a, b| a.path.cmp(&b.path));
    Ok((files, patch))
}

fn short_oid(oid: Oid) -> String {
    oid.to_string().chars().take(7).collect()
}
