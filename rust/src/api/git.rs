use std::path::{Component, Path, PathBuf};

use alera_core::git as core_git;
use camino::Utf8Path;
use git2::{
    build::CheckoutBuilder, BranchType, DiffOptions, ErrorCode, Index, ObjectType, Oid, Repository,
    RepositoryState, Signature, StashApplyOptions, StashSaveOptions,
};

#[path = "git_diff_impl.rs"]
mod git_diff_impl;
#[path = "git_diff_paths.rs"]
mod git_diff_paths;
#[path = "git_history_impl.rs"]
mod git_history_impl;

pub struct GitWorktreeEntry {
    pub path: String,
    pub branch: String,
}

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
pub struct GitChangeEntry {
    pub path: String,
    pub old_path: Option<String>,
    pub area: GitChangeArea,
    pub status: GitChangeStatus,
    pub added: Option<u32>,
    pub removed: Option<u32>,
    pub is_binary: bool,
    pub is_large: bool,
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

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum GitErrorKind {
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

#[derive(Debug)]
pub struct GitError {
    pub kind: GitErrorKind,
    pub context: String,
}

impl GitError {
    fn new(kind: GitErrorKind, context: impl Into<String>) -> Self {
        Self {
            kind,
            context: context.into(),
        }
    }

    fn from_git2(error: git2::Error) -> Self {
        let message = error.message().to_string();
        let lowered = message.to_lowercase();
        let kind = if lowered.contains("permission denied")
            || lowered.contains("operation not permitted")
        {
            GitErrorKind::AccessDenied
        } else {
            GitErrorKind::Internal
        };
        Self::new(kind, message)
    }

    fn from_io(error: std::io::Error) -> Self {
        let message = error.to_string();
        let lowered = message.to_lowercase();
        let kind = if lowered.contains("permission denied")
            || lowered.contains("operation not permitted")
        {
            GitErrorKind::AccessDenied
        } else {
            GitErrorKind::Internal
        };
        Self::new(kind, message)
    }
}

impl From<core_git::GitError> for GitError {
    fn from(error: core_git::GitError) -> Self {
        let kind = match error.kind {
            core_git::GitErrorKind::NotARepository => GitErrorKind::NotARepository,
            core_git::GitErrorKind::AccessDenied => GitErrorKind::AccessDenied,
            core_git::GitErrorKind::BranchNotFound => GitErrorKind::BranchNotFound,
            core_git::GitErrorKind::BranchAlreadyExists => GitErrorKind::BranchAlreadyExists,
            core_git::GitErrorKind::InvalidBranchName => GitErrorKind::InvalidBranchName,
            core_git::GitErrorKind::WorktreeAlreadyExists => GitErrorKind::WorktreeAlreadyExists,
            core_git::GitErrorKind::WorktreeNotFound => GitErrorKind::WorktreeNotFound,
            core_git::GitErrorKind::GitCli => GitErrorKind::GitCli,
            core_git::GitErrorKind::Conflict => GitErrorKind::Conflict,
            core_git::GitErrorKind::RemoteNotFound => GitErrorKind::RemoteNotFound,
            core_git::GitErrorKind::Internal => GitErrorKind::Internal,
        };
        GitError::new(kind, error.context)
    }
}

fn open_repo(path: &str) -> Result<Repository, GitError> {
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

pub fn list_branches(path: String) -> Result<Vec<String>, GitError> {
    core_git::list_branches(&path).map_err(Into::into)
}

pub fn current_branch(path: String) -> Result<String, GitError> {
    core_git::current_branch(&path).map_err(Into::into)
}

pub fn branch_exists(repo_path: String, branch: String) -> Result<bool, GitError> {
    core_git::branch_exists(&repo_path, &branch).map_err(Into::into)
}

pub fn is_valid_branch_name(name: String) -> Result<bool, GitError> {
    core_git::is_valid_branch_name(&name).map_err(Into::into)
}

pub fn git_status(path: String) -> Result<GitStatusResult, GitError> {
    git_diff_impl::git_status(path)
}

pub fn git_status_for_path(path: String, file_path: String) -> Result<GitStatusResult, GitError> {
    git_diff_impl::git_status_for_path(path, file_path)
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
    let status = match file_path.as_deref() {
        Some(file_path) => git_status_for_path(path.clone(), file_path.to_string())?,
        None => git_status(path.clone())?,
    };
    let pathspecs = scoped_pathspecs(&repo, &path, file_path.as_deref())?;
    discard_status_entries(&repo, &path, &status.entries, &pathspecs)
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
    discard_status_entries(&repo, &path, &entries, &pathspecs)
}

fn discard_status_entries(
    repo: &Repository,
    path: &str,
    entries: &[GitChangeEntry],
    pathspecs: &[String],
) -> Result<(), GitError> {
    let has_tracked_unstaged = entries
        .iter()
        .any(|entry| entry.area == GitChangeArea::Unstaged);
    if has_tracked_unstaged {
        let mut checkout = CheckoutBuilder::new();
        checkout.force();
        if pathspecs != [String::from(".")] {
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

pub fn git_commit(path: String, message: String) -> Result<String, GitError> {
    let repo = open_repo(&path)?;
    if repository_has_conflicts(&repo)? {
        return Err(GitError::new(
            GitErrorKind::Conflict,
            "resolve conflicts before committing",
        ));
    }
    let message = message.trim();
    if message.is_empty() {
        return Err(GitError::new(
            GitErrorKind::NothingToCommit,
            "empty message",
        ));
    }

    let mut index = repo.index().map_err(GitError::from_git2)?;
    let (parents, cleanup_state) = commit_parent_commits(&repo)?;
    let first_parent = parents.first();
    reject_out_of_scope_staged_entries(&repo, &path, first_parent, &index)?;
    let tree_id = index.write_tree().map_err(GitError::from_git2)?;
    let tree = repo.find_tree(tree_id).map_err(GitError::from_git2)?;
    if let Some(parent) = first_parent {
        if parent.tree_id() == tree_id {
            return Err(GitError::new(
                GitErrorKind::NothingToCommit,
                "no staged changes",
            ));
        }
    }
    let signature = git_signature(&repo)?;
    let parents = parents.iter().collect::<Vec<_>>();
    let oid = repo
        .commit(
            Some("HEAD"),
            &signature,
            &signature,
            message,
            &tree,
            &parents,
        )
        .map_err(GitError::from_git2)?;
    if cleanup_state {
        repo.cleanup_state().map_err(GitError::from_git2)?;
    }
    Ok(oid.to_string())
}

pub fn git_commit_amend(path: String, message: String) -> Result<String, GitError> {
    let repo = open_repo(&path)?;
    if repository_has_conflicts(&repo)? {
        return Err(GitError::new(
            GitErrorKind::Conflict,
            "resolve conflicts before amending",
        ));
    }
    let message = message.trim();
    if message.is_empty() {
        return Err(GitError::new(
            GitErrorKind::NothingToCommit,
            "empty message",
        ));
    }

    let head = current_head_commit(&repo)?.ok_or_else(|| {
        GitError::new(
            GitErrorKind::NothingToCommit,
            "no commit to amend on this branch",
        )
    })?;
    if repo.state() != RepositoryState::Clean {
        return Err(GitError::new(
            GitErrorKind::Conflict,
            "finish or abort the in-progress git operation before amending",
        ));
    }

    let mut index = repo.index().map_err(GitError::from_git2)?;
    reject_out_of_scope_staged_entries(&repo, &path, Some(&head), &index)?;
    let tree_id = index.write_tree().map_err(GitError::from_git2)?;
    if head.tree_id() == tree_id {
        return Err(GitError::new(
            GitErrorKind::NothingToCommit,
            "no staged changes",
        ));
    }
    let tree = repo.find_tree(tree_id).map_err(GitError::from_git2)?;
    let author = head.author();
    let committer = git_signature(&repo)?;
    let oid = head
        .amend(
            Some("HEAD"),
            Some(&author),
            Some(&committer),
            None,
            Some(message),
            Some(&tree),
        )
        .map_err(GitError::from_git2)?;
    Ok(oid.to_string())
}

pub fn git_fetch(path: String) -> Result<(), GitError> {
    git_cli_in_path(&path, &["fetch", "--all", "--prune"])
}

pub fn git_pull(path: String) -> Result<(), GitError> {
    git_cli_in_path(&path, &["pull"])
}

pub fn refresh_source_branch(repo_path: String, source_branch: String) -> Result<(), GitError> {
    core_git::refresh_source_branch(&repo_path, &source_branch).map_err(Into::into)
}

pub fn git_push(path: String) -> Result<(), GitError> {
    let repo = open_repo(&path)?;
    let state = git_repository_state(path.clone())?;
    if state.branch == "HEAD" {
        return Err(GitError::new(
            GitErrorKind::DetachedHead,
            "cannot push detached HEAD",
        ));
    }
    if state.upstream.is_some() {
        return git_cli_in_path(&path, &["push"]);
    }
    if repo.find_remote("origin").is_err() {
        return Err(GitError::new(
            GitErrorKind::RemoteNotFound,
            "remote origin not found",
        ));
    }
    git_cli_in_path(&path, &["push", "-u", "origin", &state.branch])
}

pub fn git_list_stashes(path: String) -> Result<Vec<GitStashEntry>, GitError> {
    let mut repo = open_repo(&path)?;
    let mut entries = Vec::new();
    repo.stash_foreach(|index, message, oid| {
        entries.push(GitStashEntry {
            index: index as u32,
            reference: format!("stash@{{{index}}}"),
            message: message.to_string(),
            oid: oid.to_string(),
        });
        true
    })
    .map_err(GitError::from_git2)?;
    Ok(entries)
}

pub fn git_stash(path: String) -> Result<(), GitError> {
    let mut repo = open_repo(&path)?;
    let signature = Signature::now("Alera", "alera@example.com").map_err(GitError::from_git2)?;
    let mut options = StashSaveOptions::new(signature);
    options.flags(Some(git2::StashFlags::DEFAULT));
    reject_out_of_scope_tracked_changes(&repo, &path)?;
    repo.stash_save_ext(Some(&mut options))
        .map_err(|error| match error.code() {
            ErrorCode::NotFound => GitError::new(GitErrorKind::NothingToCommit, "nothing to stash"),
            _ => GitError::from_git2(error),
        })?;
    Ok(())
}

pub fn git_stash_pop(path: String, stash_index: u32) -> Result<(), GitError> {
    let mut repo = open_repo(&path)?;
    reject_out_of_scope_stash_pop(&mut repo, &path, stash_index)?;
    let mut options = StashApplyOptions::new();
    repo.stash_pop(stash_index as usize, Some(&mut options))
        .map_err(GitError::from_git2)?;
    Ok(())
}

fn repository_has_conflicts(repo: &Repository) -> Result<bool, GitError> {
    let index = repo.index().map_err(GitError::from_git2)?;
    Ok(index.has_conflicts())
}

fn commit_parent_commits(repo: &Repository) -> Result<(Vec<git2::Commit<'_>>, bool), GitError> {
    let head = current_head_commit(repo)?;
    match repo.state() {
        RepositoryState::Clean => Ok((head.into_iter().collect(), false)),
        RepositoryState::Merge => {
            let head = head.ok_or_else(|| {
                GitError::new(GitErrorKind::Conflict, "merge state has no HEAD commit")
            })?;
            let mut parents = vec![head];
            for oid in merge_head_oids(repo)? {
                parents.push(repo.find_commit(oid).map_err(GitError::from_git2)?);
            }
            Ok((parents, true))
        }
        RepositoryState::CherryPick | RepositoryState::Revert => {
            let head = head.ok_or_else(|| {
                GitError::new(GitErrorKind::Conflict, "operation state has no HEAD commit")
            })?;
            Ok((vec![head], true))
        }
        _ => Err(GitError::new(
            GitErrorKind::Conflict,
            "finish or abort the in-progress git operation before committing",
        )),
    }
}

fn current_head_commit(repo: &Repository) -> Result<Option<git2::Commit<'_>>, GitError> {
    match repo.head() {
        Ok(head) => head.peel_to_commit().map(Some).map_err(GitError::from_git2),
        Err(error) if matches!(error.code(), ErrorCode::UnbornBranch | ErrorCode::NotFound) => {
            Ok(None)
        }
        Err(error) => Err(GitError::from_git2(error)),
    }
}

fn merge_head_oids(repo: &Repository) -> Result<Vec<Oid>, GitError> {
    let path = repo.path().join("MERGE_HEAD");
    let contents = std::fs::read_to_string(path).map_err(GitError::from_io)?;
    contents
        .lines()
        .filter(|line| !line.trim().is_empty())
        .map(|line| Oid::from_str(line.trim()).map_err(GitError::from_git2))
        .collect()
}

fn reject_out_of_scope_staged_entries(
    repo: &Repository,
    workspace_path: &str,
    parent: Option<&git2::Commit<'_>>,
    index: &Index,
) -> Result<(), GitError> {
    let scope = workspace_repo_relative_path(repo, workspace_path)?;
    if scope == "." {
        return Ok(());
    }

    let parent_tree = if let Some(parent) = parent {
        Some(parent.tree().map_err(GitError::from_git2)?)
    } else {
        None
    };
    let mut options = DiffOptions::new();
    let diff = repo
        .diff_tree_to_index(parent_tree.as_ref(), Some(index), Some(&mut options))
        .map_err(GitError::from_git2)?;
    for delta in diff.deltas() {
        let old_path = delta.old_file().path().map(pathspec_string);
        let new_path = delta.new_file().path().map(pathspec_string);
        for path in old_path.iter().chain(new_path.iter()) {
            if !repo_path_is_in_scope(path, &scope) {
                return Err(GitError::new(
                    GitErrorKind::WorkspaceScope,
                    format!("staged change outside workspace: {path}"),
                ));
            }
        }
    }
    Ok(())
}

fn repo_path_is_in_scope(path: &str, scope: &str) -> bool {
    scope == "."
        || path == scope
        || path
            .strip_prefix(scope)
            .is_some_and(|remainder| remainder.starts_with('/'))
}

fn reject_out_of_scope_tracked_changes(
    repo: &Repository,
    workspace_path: &str,
) -> Result<(), GitError> {
    let scope = workspace_repo_relative_path(repo, workspace_path)?;
    if scope == "." {
        return Ok(());
    }
    let workdir = repo
        .workdir()
        .ok_or_else(|| GitError::new(GitErrorKind::NotARepository, workspace_path))?;
    let status = git_status(workdir.to_string_lossy().to_string())?;
    for entry in status
        .entries
        .iter()
        .filter(|entry| entry.area != GitChangeArea::Untracked)
    {
        if let Some(old_path) = entry.old_path.as_deref() {
            if !repo_path_is_in_scope(old_path, &scope) {
                return Err(GitError::new(
                    GitErrorKind::WorkspaceScope,
                    format!("tracked change outside workspace: {old_path}"),
                ));
            }
        }
        if !repo_path_is_in_scope(&entry.path, &scope) {
            return Err(GitError::new(
                GitErrorKind::WorkspaceScope,
                format!("tracked change outside workspace: {}", entry.path),
            ));
        }
    }
    Ok(())
}

fn reject_out_of_scope_stash_pop(
    repo: &mut Repository,
    workspace_path: &str,
    stash_index: u32,
) -> Result<(), GitError> {
    let scope = workspace_repo_relative_path(repo, workspace_path)?;
    if scope == "." {
        return Ok(());
    }

    let stash_oid = stash_oid(repo, stash_index)?;
    let stash = repo.find_commit(stash_oid).map_err(GitError::from_git2)?;
    let stash_tree = stash.tree().map_err(GitError::from_git2)?;
    let head = stash.parent(0).map_err(GitError::from_git2)?;
    let head_tree = head.tree().map_err(GitError::from_git2)?;

    reject_tree_diff_out_of_scope(
        repo,
        Some(&head_tree),
        Some(&stash_tree),
        &scope,
        "stash change outside workspace",
    )?;

    if stash.parent_count() > 1 {
        let index_parent = stash.parent(1).map_err(GitError::from_git2)?;
        let index_tree = index_parent.tree().map_err(GitError::from_git2)?;
        reject_tree_diff_out_of_scope(
            repo,
            Some(&head_tree),
            Some(&index_tree),
            &scope,
            "stash index change outside workspace",
        )?;
    }

    if stash.parent_count() > 2 {
        let untracked_parent = stash.parent(2).map_err(GitError::from_git2)?;
        let untracked_tree = untracked_parent.tree().map_err(GitError::from_git2)?;
        reject_tree_diff_out_of_scope(
            repo,
            None,
            Some(&untracked_tree),
            &scope,
            "stash untracked change outside workspace",
        )?;
    }

    Ok(())
}

fn stash_oid(repo: &mut Repository, stash_index: u32) -> Result<Oid, GitError> {
    let mut oid = None;
    repo.stash_foreach(|index, _, stash_oid| {
        if index as u32 == stash_index {
            oid = Some(*stash_oid);
            return false;
        }
        true
    })
    .map_err(GitError::from_git2)?;
    oid.ok_or_else(|| GitError::new(GitErrorKind::Internal, "stash not found"))
}

fn reject_tree_diff_out_of_scope(
    repo: &Repository,
    old_tree: Option<&git2::Tree<'_>>,
    new_tree: Option<&git2::Tree<'_>>,
    scope: &str,
    context: &str,
) -> Result<(), GitError> {
    let diff = repo
        .diff_tree_to_tree(old_tree, new_tree, None)
        .map_err(GitError::from_git2)?;
    for delta in diff.deltas() {
        let old_path = delta.old_file().path().map(pathspec_string);
        let new_path = delta.new_file().path().map(pathspec_string);
        for path in old_path.iter().chain(new_path.iter()) {
            if !repo_path_is_in_scope(path, scope) {
                return Err(GitError::new(
                    GitErrorKind::WorkspaceScope,
                    format!("{context}: {path}"),
                ));
            }
        }
    }
    Ok(())
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
        .filter(|entry| entry.area != GitChangeArea::Staged)
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

fn repo_relative_path(
    repo: &Repository,
    workspace_path: &str,
    workspace_relative_path: &str,
) -> Result<String, GitError> {
    let workspace = std::fs::canonicalize(workspace_path).map_err(GitError::from_io)?;
    repo_relative_path_from_workspace(repo, workspace_path, &workspace, workspace_relative_path)
}

fn workspace_repo_relative_path(
    repo: &Repository,
    workspace_path: &str,
) -> Result<String, GitError> {
    let workspace = std::fs::canonicalize(workspace_path).map_err(GitError::from_io)?;
    repo_relative_path_from_workspace(repo, workspace_path, &workspace, "")
}

fn repo_relative_path_from_workspace(
    repo: &Repository,
    workspace_path: &str,
    workspace: &Path,
    workspace_relative_path: &str,
) -> Result<String, GitError> {
    let workdir = repo
        .workdir()
        .ok_or_else(|| GitError::new(GitErrorKind::NotARepository, workspace_path))?;
    let workdir = std::fs::canonicalize(workdir).map_err(GitError::from_io)?;
    let target = workspace.join(relative_path(workspace_relative_path)?);
    let relative = target
        .strip_prefix(&workdir)
        .map_err(|_| GitError::new(GitErrorKind::Internal, "path outside repository"))?;
    Ok(pathspec_string(relative))
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

fn git_signature(repo: &Repository) -> Result<Signature<'_>, GitError> {
    repo.signature().map_err(|_| {
        GitError::new(
            GitErrorKind::MissingIdentity,
            "Configure Git user.name and user.email before committing.",
        )
    })
}

fn scoped_pathspecs(
    repo: &Repository,
    workspace_path: &str,
    file_path: Option<&str>,
) -> Result<Vec<String>, GitError> {
    let workdir = repo
        .workdir()
        .ok_or_else(|| GitError::new(GitErrorKind::NotARepository, workspace_path))?;
    let workdir = std::fs::canonicalize(workdir).map_err(GitError::from_io)?;
    let workspace = std::fs::canonicalize(workspace_path).map_err(GitError::from_io)?;
    let target = match file_path {
        Some(file_path) => workspace.join(relative_path(file_path)?),
        None => workspace,
    };
    let relative = target
        .strip_prefix(&workdir)
        .map_err(|_| GitError::new(GitErrorKind::Internal, "path outside repository"))?;
    let pathspec = pathspec_string(relative);
    Ok(vec![pathspec])
}

fn pathspec_string(path: &Path) -> String {
    let value = path
        .components()
        .filter_map(|component| match component {
            Component::Normal(part) => Some(part.to_string_lossy().to_string()),
            _ => None,
        })
        .collect::<Vec<_>>()
        .join("/");
    if value.is_empty() {
        ".".to_string()
    } else {
        value
    }
}

fn relative_path(path: &str) -> Result<PathBuf, GitError> {
    let source = Path::new(path);
    if source.is_absolute() {
        return Err(GitError::new(GitErrorKind::Internal, path));
    }
    let mut out = PathBuf::new();
    for component in source.components() {
        match component {
            Component::Normal(part) => out.push(part),
            Component::CurDir => {}
            Component::ParentDir | Component::RootDir | Component::Prefix(_) => {
                return Err(GitError::new(GitErrorKind::Internal, path));
            }
        }
    }
    Ok(out)
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

fn git_cli_in_path(path: &str, args: &[&str]) -> Result<(), GitError> {
    git_cmd::git_in_dir(Utf8Path::new(path), args)
        .map(|_| ())
        .map_err(|error| GitError::new(GitErrorKind::GitCli, error.to_string()))
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
    .map_err(Into::into)
}

/// Removes the worktree whose checkout lives at `path`, deleting the working
/// tree files. Mirrors `git worktree remove --force <path>`.
pub fn remove_worktree(repo_path: String, path: String, force: bool) -> Result<(), GitError> {
    core_git::remove_worktree(&repo_path, &path, force).map_err(Into::into)
}

/// Force-deletes a local branch. Mirrors `git branch -D <branch>`.
pub fn delete_branch(repo_path: String, branch: String, force: bool) -> Result<(), GitError> {
    core_git::delete_branch(&repo_path, &branch, force).map_err(Into::into)
}

/// Lists the main work tree plus every linked worktree, with each entry's
/// branch short name. Mirrors `git worktree list --porcelain` (the main work
/// tree is included so callers can use its presence as a liveness guard).
pub fn list_worktrees(repo_path: String) -> Result<Vec<GitWorktreeEntry>, GitError> {
    core_git::list_worktrees(&repo_path)
        .map(|entries| {
            entries
                .into_iter()
                .map(|entry| GitWorktreeEntry {
                    path: entry.path,
                    branch: entry.branch,
                })
                .collect()
        })
        .map_err(Into::into)
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

    git_cmd::git_in_dir(
        Utf8Path::new(&parent),
        &["clone", "--progress", "--", &url, &name],
    )
    .map_err(|error| GitError::new(GitErrorKind::CloneFailed, error.to_string()))?;
    Ok(())
}

#[cfg(test)]
#[path = "git_tests.rs"]
mod git_tests;
