use std::collections::HashSet;
use std::path::{Component, Path, PathBuf};

use crate::git_cli::git_in_dir;
use git2::{
    build::CheckoutBuilder, BranchType, DiffOptions, ErrorCode, Index, ObjectType, Oid, Repository,
    RepositoryState, Signature, StashApplyOptions, StashSaveOptions,
};

#[path = "git_ancestry_impl.rs"]
mod git_ancestry_impl;
#[path = "git_commit_state_impl.rs"]
mod git_commit_state_impl;
#[path = "git_diff_impl.rs"]
pub(crate) mod git_diff_impl;
#[path = "git_diff_paths.rs"]
pub(crate) mod git_diff_paths;
#[path = "git_history_impl.rs"]
mod git_history_impl;
#[path = "git_range_impl.rs"]
mod git_range_impl;
mod source_control_actions;
mod working_tree_commit;
mod working_tree_paths;
mod working_tree_remote;
mod working_tree_stage;
mod working_tree_stash;

use git_commit_state_impl::{commit_parent_commits, current_head_commit, repository_has_conflicts};

pub use crate::git::{GitError, GitErrorKind};
pub use git_diff_impl::git_reading_diff_patch::git_reading_diff_patch;
pub use git_diff_paths::GitPathContext;
pub use source_control_actions::{
    can_discard_from_parent, can_stage_from_parent, can_unstage_from_parent,
    is_submodule_worktree_only, source_control_actions, source_control_primary_action,
    SourceControlActions, SourceControlPrimaryAction,
};
pub use working_tree_commit::{git_commit, git_commit_amend};
use working_tree_paths::{
    pathspec_string, relative_path, repo_path_is_in_scope, repo_relative_path, scoped_pathspecs,
    workspace_repo_relative_path,
};
pub use working_tree_remote::{git_fetch, git_pull, git_push};
pub use working_tree_stage::{
    git_discard, git_discard_area, git_stage, git_stage_area, git_unstage, git_unstage_area,
};
pub use working_tree_stash::{git_list_stashes, git_stash, git_stash_pop};

pub struct GitRepositoryState {
    pub branch: String,
    pub upstream: Option<String>,
    pub ahead: u32,
    pub behind: u32,
    pub has_conflicts: bool,
    pub head_message: Option<String>,
}

pub struct GitStashEntry {
    pub index: u32,
    pub reference: String,
    pub message: String,
    pub oid: String,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum GitChangeArea {
    Untracked,
    Unstaged,
    Staged,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum GitChangeStatus {
    Modified,
    Added,
    Deleted,
    Renamed,
    Copied,
    Untracked,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum GitChangeTreeRowKind {
    Directory,
    File,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum GitDiffLineKind {
    Addition,
    Deletion,
    Hunk,
    Header,
    Context,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct GitSubmoduleStatus {
    pub commit_changed: bool,
    pub tracked_changes: bool,
    pub untracked_changes: bool,
    pub inspectable: bool,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct GitChangeEntry {
    pub path: String,
    pub old_path: Option<String>,
    pub area: GitChangeArea,
    pub status: GitChangeStatus,
    pub added: Option<u32>,
    pub removed: Option<u32>,
    pub is_binary: bool,
    pub is_large: bool,
    pub submodule: Option<GitSubmoduleStatus>,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct GitChangeTreeRow {
    pub kind: GitChangeTreeRowKind,
    pub name: String,
    pub path: String,
    pub depth: u32,
    pub file_count: u32,
    pub entry: Option<GitChangeEntry>,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct GitChangeGroup {
    pub area: GitChangeArea,
    pub entries: Vec<GitChangeEntry>,
    pub tree_rows: Vec<GitChangeTreeRow>,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct GitStatusResult {
    pub entries: Vec<GitChangeEntry>,
    pub groups: Vec<GitChangeGroup>,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct GitDiffLine {
    pub text: String,
    pub kind: GitDiffLineKind,
}

pub struct GitDiffFile {
    pub path: String,
    pub old_path: Option<String>,
    pub area: GitChangeArea,
    pub status: GitChangeStatus,
    pub lines: Vec<GitDiffLine>,
    pub added: Option<u32>,
    pub removed: Option<u32>,
    pub is_binary: bool,
    pub is_large: bool,
    pub is_gitlink: bool,
    pub truncated: bool,
    pub line_preview_truncated: bool,
}

pub struct GitDiffResult {
    pub files: Vec<GitDiffFile>,
    pub truncated: bool,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum GitHistoryRefCategory {
    Branches,
    RemoteBranches,
    Tags,
    Commits,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct GitHistoryItemRef {
    pub id: String,
    pub name: String,
    pub revision: Option<String>,
    pub category: Option<GitHistoryRefCategory>,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct GitHistoryItem {
    pub id: String,
    pub parent_ids: Vec<String>,
    pub subject: String,
    pub message: String,
    pub display_id: Option<String>,
    pub author: Option<String>,
    pub author_email: Option<String>,
    pub timestamp: Option<i64>,
    pub references: Vec<GitHistoryItemRef>,
}

pub struct GitHistoryResult {
    pub items: Vec<GitHistoryItem>,
    pub current_ref: Option<GitHistoryItemRef>,
    pub remote_ref: Option<GitHistoryItemRef>,
    pub base_ref: Option<GitHistoryItemRef>,
    pub merge_base: Option<String>,
    pub has_incoming_changes: bool,
    pub has_outgoing_changes: bool,
    pub has_more: bool,
    pub limit: u32,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum GitCommitCompareStatus {
    Ready,
    InvalidCommit,
    Error,
}

pub struct GitCommitChangeEntry {
    pub path: String,
    pub old_path: Option<String>,
    pub status: GitChangeStatus,
    pub added: Option<u32>,
    pub removed: Option<u32>,
}

pub struct GitCommitCompareSummary {
    pub commit_oid: String,
    pub parent_oid: Option<String>,
    pub compare_ref: String,
    pub base_ref: String,
    pub changed_files: u32,
    pub status: GitCommitCompareStatus,
    pub error_message: Option<String>,
}

pub struct GitCommitCompareResult {
    pub summary: GitCommitCompareSummary,
    pub entries: Vec<GitCommitChangeEntry>,
}

/// One commit on the range from merge-base(base, HEAD) to HEAD.
pub struct GitRangeCommit {
    pub oid: String,
    pub subject: String,
    pub message: String,
}

/// One file changed between merge-base(base, HEAD) and HEAD.
pub struct GitRangeFile {
    pub path: String,
    pub status: GitChangeStatus,
    pub added: Option<u32>,
    pub removed: Option<u32>,
}

/// Tree-to-tree range summary used for AI pull-request prompts.
pub struct GitRangeContext {
    pub base_ref: String,
    pub head_oid: String,
    pub head_branch: Option<String>,
    pub merge_base: Option<String>,
    pub commits: Vec<GitRangeCommit>,
    pub files: Vec<GitRangeFile>,
    pub patch: String,
}

pub fn open_repo(path: &str) -> Result<Repository, GitError> {
    // `discover` (rather than `open`) so operations work when `path` is a
    // subdirectory of the work tree, matching `is_git_repository` and the
    // behaviour of `git -C <path> ...`.
    Repository::discover(path).map_err(|error| match error.code() {
        ErrorCode::NotFound => GitError::new(GitErrorKind::NotARepository, path),
        _ => GitError::from_git2(error),
    })
}

fn head_branch_name(repo: &Repository) -> String {
    match repo.head() {
        Ok(head) => {
            if repo.head_detached().unwrap_or(false) {
                "HEAD".to_string()
            } else {
                match head.shorthand() {
                    Ok(name) => name.to_string(),
                    Err(_) => "HEAD".to_string(),
                }
            }
        }
        Err(error) if error.code() == ErrorCode::UnbornBranch => unborn_branch_name(repo),
        Err(_) => "HEAD".to_string(),
    }
}

fn unborn_branch_name(repo: &Repository) -> String {
    if let Ok(reference) = repo.find_reference("HEAD") {
        if let Ok(Some(target)) = reference.symbolic_target() {
            return target
                .strip_prefix("refs/heads/")
                .unwrap_or(target)
                .to_string();
        }
    }
    "HEAD".to_string()
}

pub fn is_git_repository(path: String) -> Result<bool, GitError> {
    match Repository::discover(&path) {
        Ok(repo) => Ok(repo.workdir().is_some()),
        Err(error) => match error.code() {
            ErrorCode::NotFound => Ok(false),
            _ => {
                let lowered = error.message().to_lowercase();
                if lowered.contains("permission denied")
                    || lowered.contains("operation not permitted")
                {
                    Err(GitError::new(GitErrorKind::AccessDenied, path))
                } else {
                    Ok(false)
                }
            }
        },
    }
}

pub fn is_ancestor(
    path: String,
    ancestor_ref: String,
    descendant_ref: String,
) -> Result<bool, GitError> {
    git_ancestry_impl::is_ancestor(path, ancestor_ref, descendant_ref)
}

pub fn git_status(path: String) -> Result<GitStatusResult, GitError> {
    git_diff_impl::git_status(path)
}

pub fn git_status_for_path(path: String, file_path: String) -> Result<GitStatusResult, GitError> {
    git_diff_impl::git_status_for_path(path, file_path)
}

pub fn git_submodule_status(
    path: String,
    submodule_path: String,
    area: GitChangeArea,
) -> Result<GitStatusResult, GitError> {
    git_diff_impl::git_submodule_status(path, submodule_path, area)
}

pub fn git_diff(
    path: String,
    file_path: String,
    area: GitChangeArea,
) -> Result<GitDiffResult, GitError> {
    git_diff_impl::git_diff(path, file_path, area)
}

pub fn git_diff_all(path: String, file_path: Option<String>) -> Result<GitDiffResult, GitError> {
    git_diff_impl::git_diff_all(path, file_path)
}

pub fn git_history(
    path: String,
    limit: Option<u32>,
    base_ref: Option<String>,
) -> Result<GitHistoryResult, GitError> {
    git_history_impl::git_history(path, limit, base_ref)
}

pub fn git_commit_compare(
    path: String,
    commit_id: String,
) -> Result<GitCommitCompareResult, GitError> {
    git_diff_impl::git_commit_compare(path, commit_id)
}

pub fn git_commit_diff(
    path: String,
    commit_oid: String,
    parent_oid: Option<String>,
    file_path: Option<String>,
    old_path: Option<String>,
) -> Result<GitDiffResult, GitError> {
    git_diff_impl::git_commit_diff(path, commit_oid, parent_oid, file_path, old_path)
}

/// Summarizes commits and the tree-to-tree patch from merge-base([base_ref],
/// [head_ref]) to [head_ref]. HEAD is used when no explicit head is provided.
pub fn git_range_context(
    path: String,
    base_ref: String,
    commit_limit: Option<u32>,
    head_ref: Option<String>,
) -> Result<GitRangeContext, GitError> {
    git_range_impl::git_range_context(path, base_ref, commit_limit, head_ref)
}

pub fn git_repository_state(path: String) -> Result<GitRepositoryState, GitError> {
    let repo = open_repo(&path)?;
    let branch = head_branch_name(&repo);
    let mut upstream = None;
    let mut ahead = 0;
    let mut behind = 0;

    if branch != "HEAD" {
        if let Ok(local) = repo.find_branch(&branch, BranchType::Local) {
            if let Ok(upstream_branch) = local.upstream() {
                upstream = upstream_branch
                    .name()
                    .map_err(GitError::from_git2)?
                    .map(ToString::to_string);
                if let (Some(local_oid), Some(upstream_oid)) =
                    (local.get().target(), upstream_branch.get().target())
                {
                    let counts = repo
                        .graph_ahead_behind(local_oid, upstream_oid)
                        .map_err(GitError::from_git2)?;
                    ahead = counts.0 as u32;
                    behind = counts.1 as u32;
                }
            }
        }
    }

    let head_message = current_head_commit(&repo)?.and_then(|commit| {
        commit
            .message()
            .ok()
            .map(|message| message.trim_end_matches(['\r', '\n']).to_string())
    });

    Ok(GitRepositoryState {
        branch,
        upstream,
        ahead,
        behind,
        has_conflicts: repository_has_conflicts(&repo)?,
        head_message,
    })
}
