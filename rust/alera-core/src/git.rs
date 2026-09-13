use std::fmt;
use std::path::Path;

use git2::{BranchType, ErrorCode, Repository, WorktreeAddOptions, WorktreePruneOptions};

mod branch_deletion;
mod branch_operations;
#[cfg(test)]
#[path = "git_branch_tests.rs"]
mod branch_tests;
pub mod hosted_review;
mod repository;
mod repository_metadata;
mod worktree_handoff;
pub use branch_deletion::validate_branch_deletion;
pub use branch_operations::{
    branch_exists, checkout_branch, create_and_checkout_branch, create_and_checkout_branch_from,
    delete_branch, is_valid_branch_name, list_branches, reset_branch_to_ref,
    reset_branch_to_ref_from,
};
use repository::{
    canonical, checkout_path_for_branch, configured_remote_for_tracking_branch,
    fast_forward_local_branch, find_remote_tracking_branch_name, git_cli_in_path, git_fetch_remote,
    git_pull_ff_only, head_branch_name, is_path_occupied, open_repo, remote_tracking_upstream_name,
    unique_worktree_admin_name,
};
pub use repository_metadata::{current_branch, is_worktree_clean, repository_remote_url};
pub use worktree_handoff::{
    apply_handoff_stash, branch_checkout_path, default_branch, detach_head, set_head_to_branch,
    stash_for_handoff, stash_include_untracked, stash_pop, validate_handoff_removal,
    validate_handoff_state, validate_no_ignored_handoff_files,
};

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct GitWorktreeEntry {
    pub path: String,
    pub branch: String,
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

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct GitError {
    pub kind: GitErrorKind,
    pub context: String,
}

impl GitError {
    pub fn new(kind: GitErrorKind, context: impl Into<String>) -> Self {
        Self {
            kind,
            context: context.into(),
        }
    }

    pub fn from_git2(error: git2::Error) -> Self {
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

    pub fn from_io(error: std::io::Error) -> Self {
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

impl fmt::Display for GitError {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        if self.context.is_empty() {
            write!(f, "{:?}", self.kind)
        } else {
            f.write_str(&self.context)
        }
    }
}

impl std::error::Error for GitError {}

pub fn refresh_source_branch(repo_path: &str, source_branch: &str) -> Result<(), GitError> {
    let repo = open_repo(repo_path)?;

    if let Some(remote_branch) = find_remote_tracking_branch_name(&repo, source_branch)? {
        let remote = configured_remote_for_tracking_branch(&repo, &remote_branch)?
            .ok_or_else(|| GitError::new(GitErrorKind::RemoteNotFound, remote_branch.clone()))?;
        return git_fetch_remote(repo_path, &remote);
    }

    let branch = repo
        .find_branch(source_branch, BranchType::Local)
        .map_err(|error| match error.code() {
            ErrorCode::NotFound => GitError::new(GitErrorKind::BranchNotFound, source_branch),
            _ => GitError::from_git2(error),
        })?;
    let upstream_name = match branch.upstream() {
        Ok(upstream) => upstream
            .name()
            .map_err(GitError::from_git2)?
            .map(ToString::to_string),
        Err(error) if error.code() == ErrorCode::NotFound => return Ok(()),
        Err(error) => return Err(GitError::from_git2(error)),
    };
    let Some(upstream_name) = upstream_name else {
        return Ok(());
    };
    let Some(remote) = configured_remote_for_tracking_branch(&repo, &upstream_name)? else {
        return Ok(());
    };
    let checked_out_path = checkout_path_for_branch(&repo, source_branch)?;
    drop(branch);

    if let Some(path) = checked_out_path {
        return git_pull_ff_only(&path);
    }

    git_fetch_remote(repo_path, &remote)?;
    fast_forward_local_branch(repo_path, source_branch, &upstream_name)
}

pub fn create_worktree(
    repo_path: &str,
    target_branch: &str,
    path: &str,
    source_branch: &str,
    reuse_existing_branch: bool,
) -> Result<(), GitError> {
    let repo = open_repo(repo_path)?;

    if is_path_occupied(path) {
        return Err(GitError::new(GitErrorKind::WorktreeAlreadyExists, path));
    }

    if reuse_existing_branch {
        let branch =
            repo.find_branch(target_branch, BranchType::Local)
                .map_err(|error| match error.code() {
                    ErrorCode::NotFound => {
                        GitError::new(GitErrorKind::BranchNotFound, target_branch)
                    }
                    _ => GitError::from_git2(error),
                })?;
        let worktree_result = {
            let reference = branch.into_reference();
            let mut options = WorktreeAddOptions::new();
            options.reference(Some(&reference));
            let admin_name = unique_worktree_admin_name(&repo, path);
            repo.worktree(&admin_name, Path::new(path), Some(&options))
        };
        return worktree_result
            .map(|_| ())
            .map_err(|error| match error.code() {
                ErrorCode::Exists => GitError::new(GitErrorKind::WorktreeAlreadyExists, path),
                _ => GitError::from_git2(error),
            });
    }

    let source_commit = repo
        .revparse_single(source_branch)
        .map_err(|_| GitError::new(GitErrorKind::BranchNotFound, source_branch))?
        .peel_to_commit()
        .map_err(GitError::from_git2)?;

    let upstream_name = remote_tracking_upstream_name(&repo, source_branch)?;
    let mut branch =
        repo.branch(target_branch, &source_commit, false)
            .map_err(|error| match error.code() {
                ErrorCode::Exists => {
                    GitError::new(GitErrorKind::BranchAlreadyExists, target_branch)
                }
                ErrorCode::InvalidSpec => {
                    GitError::new(GitErrorKind::InvalidBranchName, target_branch)
                }
                _ => GitError::from_git2(error),
            })?;
    if let Some(upstream_name) = upstream_name.as_deref() {
        if let Err(error) = branch.set_upstream(Some(upstream_name)) {
            let _ = branch.delete();
            return Err(GitError::from_git2(error));
        }
    }

    let worktree_result = {
        let reference = branch.into_reference();
        let mut options = WorktreeAddOptions::new();
        options.reference(Some(&reference));
        let admin_name = unique_worktree_admin_name(&repo, path);
        repo.worktree(&admin_name, Path::new(path), Some(&options))
    };
    if let Err(error) = worktree_result {
        if let Ok(mut created) = repo.find_branch(target_branch, BranchType::Local) {
            let _ = created.delete();
        }
        return Err(match error.code() {
            ErrorCode::Exists => GitError::new(GitErrorKind::WorktreeAlreadyExists, path),
            _ => GitError::from_git2(error),
        });
    }
    Ok(())
}

pub fn remove_worktree(repo_path: &str, path: &str, force: bool) -> Result<(), GitError> {
    let repo = open_repo(repo_path)?;
    let target = canonical(path);

    let names = repo.worktrees().map_err(GitError::from_git2)?;
    let mut found = None;
    for entry in names.iter() {
        let Ok(Some(name)) = entry else {
            continue;
        };
        if let Ok(worktree) = repo.find_worktree(name) {
            if canonical(&worktree.path().to_string_lossy()) == target {
                found = Some(worktree);
                break;
            }
        }
    }
    let worktree = found.ok_or_else(|| GitError::new(GitErrorKind::WorktreeNotFound, path))?;

    let mut options = WorktreePruneOptions::new();
    options.valid(true).working_tree(true).locked(force);
    if let Err(error) = worktree.prune(Some(&mut options)) {
        if Path::new(path).exists() {
            return Err(GitError::from_git2(error));
        }
        let mut metadata_options = WorktreePruneOptions::new();
        metadata_options.locked(force);
        worktree
            .prune(Some(&mut metadata_options))
            .map_err(GitError::from_git2)?;
    }
    Ok(())
}

pub fn list_worktrees(repo_path: &str) -> Result<Vec<GitWorktreeEntry>, GitError> {
    let repo = open_repo(repo_path)?;
    let mut entries = Vec::new();

    if let Some(workdir) = repo.workdir() {
        entries.push(GitWorktreeEntry {
            path: workdir.to_string_lossy().trim_end_matches('/').to_string(),
            branch: head_branch_name(&repo),
        });
    }

    let names = repo.worktrees().map_err(GitError::from_git2)?;
    for entry in names.iter() {
        let Ok(Some(name)) = entry else {
            continue;
        };
        if let Ok(worktree) = repo.find_worktree(name) {
            let worktree_path = worktree.path().to_string_lossy().to_string();
            let branch = match Repository::open(worktree.path()) {
                Ok(worktree_repo) => head_branch_name(&worktree_repo),
                Err(_) => "HEAD".to_string(),
            };
            entries.push(GitWorktreeEntry {
                path: worktree_path.trim_end_matches('/').to_string(),
                branch,
            });
        }
    }
    Ok(entries)
}

/// How far a worktree's HEAD trails its upstream tracking branch, plus the
/// most recent upstream-only commit subjects for the dispatch preamble.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct GitBaseDrift {
    pub base: String,
    pub behind: u64,
    pub recent_subjects: Vec<String>,
}

const BASE_DRIFT_SUBJECT_LIMIT: usize = 5;

/// Measures drift between a worktree's HEAD and its upstream tracking branch
/// without fetching. Returns `None` when the branch has no upstream - a
/// worktree with no tracking base has nothing to drift from.
pub fn probe_base_drift(worktree_path: &str) -> Result<Option<GitBaseDrift>, GitError> {
    let repo = open_repo(worktree_path)?;
    let head = match repo.head() {
        Ok(head) => head,
        // Unborn/empty worktrees cannot be behind anything.
        Err(error) if error.code() == ErrorCode::UnbornBranch => return Ok(None),
        Err(error) => return Err(GitError::from_git2(error)),
    };
    let Some(head_oid) = head.target() else {
        return Ok(None);
    };
    if repo.head_detached().unwrap_or(false) {
        return Ok(None);
    }
    let branch_name = match head.shorthand() {
        Ok(name) => name.to_string(),
        Err(_) => return Ok(None),
    };
    let branch = match repo.find_branch(&branch_name, BranchType::Local) {
        Ok(branch) => branch,
        Err(error) if error.code() == ErrorCode::NotFound => return Ok(None),
        Err(error) => return Err(GitError::from_git2(error)),
    };
    let upstream = match branch.upstream() {
        Ok(upstream) => upstream,
        Err(error) if error.code() == ErrorCode::NotFound => return Ok(None),
        Err(error) => return Err(GitError::from_git2(error)),
    };
    let upstream_name = upstream
        .name()
        .map_err(GitError::from_git2)?
        .unwrap_or("upstream")
        .to_string();
    let Some(upstream_oid) = upstream.get().target() else {
        return Ok(None);
    };
    let (_ahead, behind) = repo
        .graph_ahead_behind(head_oid, upstream_oid)
        .map_err(GitError::from_git2)?;
    if behind == 0 {
        return Ok(Some(GitBaseDrift {
            base: upstream_name,
            behind: 0,
            recent_subjects: Vec::new(),
        }));
    }
    // Walk upstream-only commits (upstream, hiding HEAD) for the newest
    // subjects the worktree has not seen.
    let mut walk = repo.revwalk().map_err(GitError::from_git2)?;
    walk.push(upstream_oid).map_err(GitError::from_git2)?;
    walk.hide(head_oid).map_err(GitError::from_git2)?;
    let mut recent_subjects = Vec::new();
    for oid in walk.take(BASE_DRIFT_SUBJECT_LIMIT) {
        let oid = oid.map_err(GitError::from_git2)?;
        let commit = repo.find_commit(oid).map_err(GitError::from_git2)?;
        let subject = commit
            .summary()
            .map_err(GitError::from_git2)?
            .unwrap_or("<no subject>")
            .to_string();
        recent_subjects.push(subject);
    }
    Ok(Some(GitBaseDrift {
        base: upstream_name,
        behind: behind as u64,
        recent_subjects,
    }))
}
