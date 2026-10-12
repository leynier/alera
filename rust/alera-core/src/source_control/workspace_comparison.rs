use git2::{Delta, DiffFindOptions, DiffOptions, Index, IndexAddOption, Oid, Patch, Repository};
use serde::{Deserialize, Serialize};

use super::git_diff_impl::git_diff_render::diff_lines_from_patch;
use super::{
    current_head_commit, git_diff_paths::GitPathContext, open_repo, GitChangeArea, GitChangeEntry,
    GitChangeStatus, GitDiffFile, GitDiffResult, GitError, GitErrorKind,
};

#[derive(Clone, Debug, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct GitWorkspaceComparison {
    pub base_ref: Option<String>,
    pub base_oid: String,
    pub head_oid: Option<String>,
    pub head_ref: String,
    pub tree_oid: String,
    pub index_oid: String,
    pub entries: Vec<GitChangeEntry>,
    pub added: u32,
    pub removed: u32,
}

pub fn git_workspace_default_branch(path: String) -> Result<String, GitError> {
    let repo = open_repo(&path)?;
    let remotes = repo.remotes().map_err(GitError::from_git2)?;
    let mut names: Vec<_> = remotes
        .iter()
        .filter_map(|name| name.ok().flatten())
        .collect();
    names.sort_by_key(|name| (*name != "origin", *name));
    for remote in names {
        if let Ok(reference) = repo.find_reference(&format!("refs/remotes/{remote}/HEAD")) {
            if let Some(target) = reference.symbolic_target().ok().flatten() {
                if let Some(branch) = target.strip_prefix(&format!("refs/remotes/{remote}/")) {
                    return Ok(branch.to_string());
                }
            }
        }
    }
    if let Ok(branch) = repo
        .config()
        .and_then(|config| config.get_string("init.defaultBranch"))
    {
        return Ok(branch);
    }
    for branch in ["main", "master"] {
        if repo.find_branch(branch, git2::BranchType::Local).is_ok() {
            return Ok(branch.to_string());
        }
    }
    crate::git::current_branch(&path)
}

// The detached in-memory index captures disk content, including untracked files,
// without changing the user's index. Git's filters and ignored-file rules apply.
pub(super) fn worktree_snapshot(repo: &Repository) -> Result<(Oid, Oid), GitError> {
    let mut original = repo.index().map_err(GitError::from_git2)?;
    let index_oid = original.write_tree().map_err(GitError::from_git2)?;
    let mut index = Index::new().map_err(GitError::from_git2)?;
    for entry in original.iter() {
        index.add(&entry).map_err(GitError::from_git2)?;
    }
    repo.set_index(&mut index).map_err(GitError::from_git2)?;
    let result = (|| {
        index.update_all(["*"], None).map_err(GitError::from_git2)?;
        index
            .add_all(["*"], IndexAddOption::DEFAULT, None)
            .map_err(GitError::from_git2)?;
        index.write_tree_to(repo).map_err(GitError::from_git2)
    })();
    repo.set_index(&mut original).map_err(GitError::from_git2)?;
    result.map(|tree| (tree, index_oid))
}

pub fn git_workspace_comparison(
    path: String,
    base_ref: Option<String>,
) -> Result<GitWorkspaceComparison, GitError> {
    let repo = open_repo(&path)?;
    let head = current_head_commit(&repo)?;
    let head_ref = repo
        .head()
        .ok()
        .and_then(|head| head.name().ok().map(str::to_owned))
        .unwrap_or_else(|| {
            repo.find_reference("HEAD")
                .ok()
                .and_then(|head| head.symbolic_target().ok().flatten().map(str::to_owned))
                .unwrap_or_default()
        });
    let base_oid = match (head.as_ref(), base_ref.as_deref()) {
        (Some(head), Some(base)) => {
            let commit = repo
                .revparse_single(base)
                .and_then(|object| object.peel_to_commit())
                .map_err(GitError::from_git2)?;
            let oid = repo
                .merge_base(head.id(), commit.id())
                .map_err(GitError::from_git2)?;
            repo.find_commit(oid)
                .and_then(|commit| commit.tree())
                .map_err(GitError::from_git2)?
                .id()
        }
        (Some(head), None) => head.tree_id(),
        (None, _) => repo
            .treebuilder(None)
            .and_then(|builder| builder.write())
            .map_err(GitError::from_git2)?,
    };
    let (tree_oid, index_oid) = worktree_snapshot(&repo)?;
    let mut comparison = GitWorkspaceComparison {
        base_ref,
        base_oid: base_oid.to_string(),
        head_oid: head.map(|head| head.id().to_string()),
        head_ref,
        tree_oid: tree_oid.to_string(),
        index_oid: index_oid.to_string(),
        entries: Vec::new(),
        added: 0,
        removed: 0,
    };
    let paths = GitPathContext::new(&repo, &path)?;
    let diff = comparison_diff(&repo, &comparison, &paths)?;
    for (position, delta) in diff.deltas().enumerate() {
        let Some(repo_path) = delta.new_file().path().or_else(|| delta.old_file().path()) else {
            continue;
        };
        let Some(file_path) = paths.to_workspace_path(&repo_path.to_string_lossy()) else {
            continue;
        };
        let patch = Patch::from_diff(&diff, position).map_err(GitError::from_git2)?;
        let stats = patch
            .as_ref()
            .map(|patch| patch.line_stats())
            .transpose()
            .map_err(GitError::from_git2)?;
        let is_binary = delta.flags().contains(git2::DiffFlags::BINARY);
        let added = (!is_binary).then_some(stats.map_or(0, |(_, added, _)| added as u32));
        let removed = (!is_binary).then_some(stats.map_or(0, |(_, _, removed)| removed as u32));
        comparison.added = comparison.added.saturating_add(added.unwrap_or(0));
        comparison.removed = comparison.removed.saturating_add(removed.unwrap_or(0));
        comparison.entries.push(GitChangeEntry {
            path: file_path,
            old_path: (delta.status() == Delta::Renamed)
                .then(|| {
                    delta
                        .old_file()
                        .path()
                        .and_then(|path| paths.to_workspace_path(&path.to_string_lossy()))
                })
                .flatten(),
            area: GitChangeArea::Unstaged,
            status: match delta.status() {
                Delta::Added => GitChangeStatus::Added,
                Delta::Deleted => GitChangeStatus::Deleted,
                Delta::Renamed => GitChangeStatus::Renamed,
                Delta::Copied => GitChangeStatus::Copied,
                _ => GitChangeStatus::Modified,
            },
            added,
            removed,
            is_binary,
            is_large: false,
            submodule: None,
        });
    }
    Ok(comparison)
}

fn comparison_diff<'a>(
    repo: &'a Repository,
    snapshot: &GitWorkspaceComparison,
    paths: &GitPathContext,
) -> Result<git2::Diff<'a>, GitError> {
    let base = repo
        .find_tree(parse_oid(&snapshot.base_oid)?)
        .map_err(GitError::from_git2)?;
    let tree = repo
        .find_tree(parse_oid(&snapshot.tree_oid)?)
        .map_err(GitError::from_git2)?;
    let mut options = DiffOptions::new();
    if !paths.is_workspace_root() {
        options.pathspec(paths.to_repo_path(""));
        options.disable_pathspec_match(true);
    }
    let mut diff = repo
        .diff_tree_to_tree(Some(&base), Some(&tree), Some(&mut options))
        .map_err(GitError::from_git2)?;
    diff.find_similar(Some(DiffFindOptions::new().renames(true)))
        .map_err(GitError::from_git2)?;
    Ok(diff)
}

pub fn git_workspace_comparison_diff(
    path: String,
    snapshot: GitWorkspaceComparison,
    file_path: String,
) -> Result<GitDiffResult, GitError> {
    let repo = open_repo(&path)?;
    let paths = GitPathContext::new(&repo, &path)?;
    let entry = snapshot
        .entries
        .iter()
        .find(|entry| entry.path == file_path)
        .ok_or_else(|| {
            GitError::new(
                GitErrorKind::WorkspaceScope,
                "file is outside the comparison",
            )
        })?;
    let repo_path = paths.to_repo_path(&file_path);
    let diff = comparison_diff(&repo, &snapshot, &paths)?;
    let position = diff.deltas().position(|delta| {
        delta
            .new_file()
            .path()
            .or_else(|| delta.old_file().path())
            .is_some_and(|path| path.to_string_lossy() == repo_path)
    });
    let mut lines = Vec::new();
    let mut truncated = false;
    if let Some(position) = position {
        if let Some(mut patch) = Patch::from_diff(&diff, position).map_err(GitError::from_git2)? {
            let buffer = patch.to_buf().map_err(GitError::from_git2)?;
            let bytes = &buffer[..buffer.len().min(512 * 1024)];
            (lines, truncated) = diff_lines_from_patch(&String::from_utf8_lossy(bytes));
            truncated |= buffer.len() > bytes.len();
        }
    }
    Ok(GitDiffResult {
        files: vec![GitDiffFile {
            path: entry.path.clone(),
            old_path: entry.old_path.clone(),
            area: entry.area,
            status: entry.status,
            lines,
            added: entry.added,
            removed: entry.removed,
            is_binary: entry.is_binary,
            is_large: truncated,
            is_gitlink: false,
            truncated,
            line_preview_truncated: truncated,
        }],
        truncated,
    })
}

pub(super) fn parse_oid(value: &str) -> Result<Oid, GitError> {
    Oid::from_str(value).map_err(GitError::from_git2)
}
