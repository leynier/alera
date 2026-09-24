use std::path::Path;

use alera_core::git as core_git;
use alera_core::git_cli::git_in_dir;
use alera_core::source_control::{self, open_repo};
use flutter_rust_bridge::frb;

pub use alera_core::git::{GitError, GitErrorKind};
pub use alera_core::source_control::{
    GitChangeArea, GitChangeEntry, GitChangeGroup, GitChangeStatus, GitChangeTreeRow,
    GitChangeTreeRowKind, GitCommitChangeEntry, GitCommitCompareResult, GitCommitCompareStatus,
    GitCommitCompareSummary, GitDiffFile, GitDiffLine, GitDiffLineKind, GitDiffResult,
    GitHistoryItem, GitHistoryItemRef, GitHistoryRefCategory, GitHistoryResult, GitRangeCommit,
    GitRangeContext, GitRangeFile, GitRepositoryState, GitStashEntry, GitStatusResult,
    GitSubmoduleStatus,
};

#[path = "git_branch.rs"]
pub mod git_branch;
#[path = "git_hosted_review.rs"]
pub mod git_hosted_review;

#[cfg(test)]
use git2::{BranchType, RepositoryState};
#[cfg(test)]
use git_branch::{
    branch_exists, current_branch, is_valid_branch_name, list_branches, refresh_source_branch,
};

pub struct GitWorktreeEntry {
    pub path: String,
    pub branch: String,
}

pub struct GitRemote {
    pub name: String,
    pub url: Option<String>,
}

// The git model and its working-tree operations live in `alera_core::source_control`,
// so the runtime host serves mobile the same rules. These mirrors only describe
// the shapes to the bridge codegen; the Dart classes do not change.

#[frb(mirror(GitRepositoryState))]
pub struct _GitRepositoryState {
    pub branch: String,
    pub upstream: Option<String>,
    pub ahead: u32,
    pub behind: u32,
    pub has_conflicts: bool,
    pub head_message: Option<String>,
}

#[frb(mirror(GitStashEntry))]
pub struct _GitStashEntry {
    pub index: u32,
    pub reference: String,
    pub message: String,
    pub oid: String,
}

#[frb(mirror(GitChangeArea))]
pub enum _GitChangeArea {
    Untracked,
    Unstaged,
    Staged,
}

#[frb(mirror(GitChangeStatus))]
pub enum _GitChangeStatus {
    Modified,
    Added,
    Deleted,
    Renamed,
    Copied,
    Untracked,
}

#[frb(mirror(GitChangeTreeRowKind))]
pub enum _GitChangeTreeRowKind {
    Directory,
    File,
}

#[frb(mirror(GitDiffLineKind))]
pub enum _GitDiffLineKind {
    Addition,
    Deletion,
    Hunk,
    Header,
    Context,
}

#[frb(mirror(GitSubmoduleStatus))]
pub struct _GitSubmoduleStatus {
    pub commit_changed: bool,
    pub tracked_changes: bool,
    pub untracked_changes: bool,
    pub inspectable: bool,
}

#[frb(mirror(GitChangeEntry))]
pub struct _GitChangeEntry {
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

#[frb(mirror(GitChangeTreeRow))]
pub struct _GitChangeTreeRow {
    pub kind: GitChangeTreeRowKind,
    pub name: String,
    pub path: String,
    pub depth: u32,
    pub file_count: u32,
    pub entry: Option<GitChangeEntry>,
}

#[frb(mirror(GitChangeGroup))]
pub struct _GitChangeGroup {
    pub area: GitChangeArea,
    pub entries: Vec<GitChangeEntry>,
    pub tree_rows: Vec<GitChangeTreeRow>,
}

#[frb(mirror(GitStatusResult))]
pub struct _GitStatusResult {
    pub entries: Vec<GitChangeEntry>,
    pub groups: Vec<GitChangeGroup>,
}

#[frb(mirror(GitDiffLine))]
pub struct _GitDiffLine {
    pub text: String,
    pub kind: GitDiffLineKind,
}

#[frb(mirror(GitDiffFile))]
pub struct _GitDiffFile {
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

#[frb(mirror(GitDiffResult))]
pub struct _GitDiffResult {
    pub files: Vec<GitDiffFile>,
    pub truncated: bool,
}

#[frb(mirror(GitHistoryRefCategory))]
pub enum _GitHistoryRefCategory {
    Branches,
    RemoteBranches,
    Tags,
    Commits,
}

#[frb(mirror(GitHistoryItemRef))]
pub struct _GitHistoryItemRef {
    pub id: String,
    pub name: String,
    pub revision: Option<String>,
    pub category: Option<GitHistoryRefCategory>,
}

#[frb(mirror(GitHistoryItem))]
pub struct _GitHistoryItem {
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

#[frb(mirror(GitHistoryResult))]
pub struct _GitHistoryResult {
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

#[frb(mirror(GitCommitCompareStatus))]
pub enum _GitCommitCompareStatus {
    Ready,
    InvalidCommit,
    Error,
}

#[frb(mirror(GitCommitChangeEntry))]
pub struct _GitCommitChangeEntry {
    pub path: String,
    pub old_path: Option<String>,
    pub status: GitChangeStatus,
    pub added: Option<u32>,
    pub removed: Option<u32>,
}

#[frb(mirror(GitCommitCompareSummary))]
pub struct _GitCommitCompareSummary {
    pub commit_oid: String,
    pub parent_oid: Option<String>,
    pub compare_ref: String,
    pub base_ref: String,
    pub changed_files: u32,
    pub status: GitCommitCompareStatus,
    pub error_message: Option<String>,
}

#[frb(mirror(GitCommitCompareResult))]
pub struct _GitCommitCompareResult {
    pub summary: GitCommitCompareSummary,
    pub entries: Vec<GitCommitChangeEntry>,
}

/// One commit on the range from merge-base(base, HEAD) to HEAD.
#[frb(mirror(GitRangeCommit))]
pub struct _GitRangeCommit {
    pub oid: String,
    pub subject: String,
    pub message: String,
}

/// One file changed between merge-base(base, HEAD) and HEAD.
#[frb(mirror(GitRangeFile))]
pub struct _GitRangeFile {
    pub path: String,
    pub status: GitChangeStatus,
    pub added: Option<u32>,
    pub removed: Option<u32>,
}

/// Tree-to-tree range summary used for AI pull-request prompts.
#[frb(mirror(GitRangeContext))]
pub struct _GitRangeContext {
    pub base_ref: String,
    pub head_oid: String,
    pub head_branch: Option<String>,
    pub merge_base: Option<String>,
    pub commits: Vec<GitRangeCommit>,
    pub files: Vec<GitRangeFile>,
    pub patch: String,
}

#[frb(mirror(GitErrorKind))]
pub enum _GitErrorKind {
    NotARepository,
    AccessDenied,
    BranchNotFound,
    BranchAlreadyExists,
    InvalidBranchName,
    WorktreeAlreadyExists,
    WorktreeNotFound,
    CloneFailed,
    GitCli,
    DetachedHead,
    NoUpstream,
    RemoteNotFound,
    NothingToCommit,
    Conflict,
    WorkspaceScope,
    MissingIdentity,
    Internal,
}

#[frb(mirror(GitError))]
pub struct _GitError {
    pub kind: GitErrorKind,
    pub context: String,
}

pub fn is_git_repository(path: String) -> Result<bool, GitError> {
    source_control::is_git_repository(path)
}

pub fn is_ancestor(
    path: String,
    ancestor_ref: String,
    descendant_ref: String,
) -> Result<bool, GitError> {
    source_control::is_ancestor(path, ancestor_ref, descendant_ref)
}

pub fn git_status(path: String) -> Result<GitStatusResult, GitError> {
    source_control::git_status(path)
}

pub fn git_status_for_path(path: String, file_path: String) -> Result<GitStatusResult, GitError> {
    source_control::git_status_for_path(path, file_path)
}

pub fn git_submodule_status(
    path: String,
    submodule_path: String,
    area: GitChangeArea,
) -> Result<GitStatusResult, GitError> {
    source_control::git_submodule_status(path, submodule_path, area)
}

pub fn git_diff(
    path: String,
    file_path: String,
    area: GitChangeArea,
) -> Result<GitDiffResult, GitError> {
    source_control::git_diff(path, file_path, area)
}

pub fn git_diff_all(path: String, file_path: Option<String>) -> Result<GitDiffResult, GitError> {
    source_control::git_diff_all(path, file_path)
}

pub fn git_history(
    path: String,
    limit: Option<u32>,
    base_ref: Option<String>,
) -> Result<GitHistoryResult, GitError> {
    source_control::git_history(path, limit, base_ref)
}

pub fn git_commit_compare(
    path: String,
    commit_id: String,
) -> Result<GitCommitCompareResult, GitError> {
    source_control::git_commit_compare(path, commit_id)
}

pub fn git_commit_diff(
    path: String,
    commit_oid: String,
    parent_oid: Option<String>,
    file_path: Option<String>,
    old_path: Option<String>,
) -> Result<GitDiffResult, GitError> {
    source_control::git_commit_diff(path, commit_oid, parent_oid, file_path, old_path)
}

/// Summarizes commits and the tree-to-tree patch from merge-base([base_ref],
/// [head_ref]) to [head_ref]. HEAD is used when no explicit head is provided.
pub fn git_range_context(
    path: String,
    base_ref: String,
    commit_limit: Option<u32>,
    head_ref: Option<String>,
) -> Result<GitRangeContext, GitError> {
    source_control::git_range_context(path, base_ref, commit_limit, head_ref)
}

pub fn git_repository_state(path: String) -> Result<GitRepositoryState, GitError> {
    source_control::git_repository_state(path)
}

pub fn git_stage(path: String, file_path: Option<String>) -> Result<(), GitError> {
    source_control::git_stage(path, file_path)
}

pub fn git_stage_area(
    path: String,
    area: GitChangeArea,
    file_path: Option<String>,
) -> Result<(), GitError> {
    source_control::git_stage_area(path, area, file_path)
}

pub fn git_unstage(path: String, file_path: Option<String>) -> Result<(), GitError> {
    source_control::git_unstage(path, file_path)
}

pub fn git_unstage_area(
    path: String,
    area: GitChangeArea,
    file_path: Option<String>,
) -> Result<(), GitError> {
    source_control::git_unstage_area(path, area, file_path)
}

pub fn git_discard(path: String, file_path: Option<String>) -> Result<(), GitError> {
    source_control::git_discard(path, file_path)
}

pub fn git_discard_area(
    path: String,
    area: GitChangeArea,
    file_path: Option<String>,
) -> Result<(), GitError> {
    source_control::git_discard_area(path, area, file_path)
}

pub fn git_commit(path: String, message: String) -> Result<String, GitError> {
    source_control::git_commit(path, message)
}

pub fn git_commit_amend(path: String, message: String) -> Result<String, GitError> {
    source_control::git_commit_amend(path, message)
}

pub fn git_fetch(path: String) -> Result<(), GitError> {
    source_control::git_fetch(path)
}

pub fn git_pull(path: String) -> Result<(), GitError> {
    source_control::git_pull(path)
}

pub fn git_push(path: String) -> Result<(), GitError> {
    source_control::git_push(path)
}

pub fn git_list_stashes(path: String) -> Result<Vec<GitStashEntry>, GitError> {
    source_control::git_list_stashes(path)
}

pub fn git_stash(path: String) -> Result<(), GitError> {
    source_control::git_stash(path)
}

pub fn git_stash_pop(path: String, stash_index: u32) -> Result<(), GitError> {
    source_control::git_stash_pop(path, stash_index)
}

/// Adds a linked worktree at `path` for `target_branch`. By default this creates
/// `target_branch` from `source_branch`; when `reuse_existing_branch` is true,
/// `target_branch` must already exist locally.
pub fn create_worktree(
    repo_path: String,
    target_branch: String,
    path: String,
    source_branch: String,
    reuse_existing_branch: bool,
) -> Result<(), GitError> {
    core_git::create_worktree(
        &repo_path,
        &target_branch,
        &path,
        &source_branch,
        reuse_existing_branch,
    )
}

/// Removes the worktree whose checkout lives at `path`, deleting the working
/// tree files. Mirrors `git worktree remove --force <path>`.
pub fn remove_worktree(repo_path: String, path: String, force: bool) -> Result<(), GitError> {
    core_git::remove_worktree(&repo_path, &path, force)
}

/// Force-deletes a local branch. Mirrors `git branch -D <branch>`.
pub fn delete_branch(repo_path: String, branch: String, force: bool) -> Result<(), GitError> {
    core_git::delete_branch(&repo_path, &branch, force)
}

/// Lists the main work tree plus every linked worktree, with each entry's
/// branch short name. Mirrors `git worktree list --porcelain` (the main work
/// tree is included so callers can use its presence as a liveness guard).
pub fn list_worktrees(repo_path: String) -> Result<Vec<GitWorktreeEntry>, GitError> {
    core_git::list_worktrees(&repo_path).map(|entries| {
        entries
            .into_iter()
            .map(|entry| GitWorktreeEntry {
                path: entry.path,
                branch: entry.branch,
            })
            .collect()
    })
}

/// Lists the repository's configured remotes with their fetch URLs. Used to
/// detect the git hosting provider (GitHub, Azure DevOps, ...) from the remote
/// identity. Remotes without a URL yield `None`.
pub fn list_remotes(path: String) -> Result<Vec<GitRemote>, GitError> {
    let repo = open_repo(&path)?;
    let names = repo.remotes().map_err(GitError::from_git2)?;
    let mut remotes = Vec::new();
    for name in names.iter() {
        let Some(name) = name.map_err(GitError::from_git2)? else {
            continue;
        };
        let url = match repo.find_remote(name) {
            Ok(remote) => remote.url().ok().map(ToString::to_string),
            Err(_) => None,
        };
        remotes.push(GitRemote {
            name: name.to_string(),
            url,
        });
    }
    Ok(remotes)
}

/// Splits `destination_path` into the parent directory to run `git` in and the
/// final path component to use as the clone target. Cloning `basename` from
/// inside `parent` yields exactly `parent/basename`, so a relative destination
/// is not double-prefixed by `git -C <parent>`.
fn split_clone_destination(destination_path: &str) -> Result<(String, String), GitError> {
    let destination = Path::new(destination_path);
    let name = destination
        .file_name()
        .and_then(|name| name.to_str())
        .ok_or_else(|| {
            GitError::new(
                GitErrorKind::CloneFailed,
                format!("invalid destination path: {destination_path}"),
            )
        })?;
    let parent = destination
        .parent()
        .filter(|parent| !parent.as_os_str().is_empty())
        .and_then(|parent| parent.to_str())
        .unwrap_or(".");
    Ok((parent.to_string(), name.to_string()))
}

/// Clones a repository into `destination_path` using the system `git` CLI so
/// the user's credential helper authenticates private remotes. Mirrors
/// `git clone --progress -- <url> <destination_path>`.
pub fn clone_repository(url: String, destination_path: String) -> Result<(), GitError> {
    let (parent, name) = split_clone_destination(&destination_path)?;

    git_in_dir(
        Path::new(&parent),
        &["clone", "--progress", "--", &url, &name],
    )
    .map_err(|error| GitError::new(GitErrorKind::CloneFailed, error.message))?;
    Ok(())
}

#[cfg(test)]
#[path = "git_tests.rs"]
mod git_tests;
