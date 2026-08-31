use std::fmt;
use std::path::Path;

use git2::{Branch, BranchType, ErrorCode, Repository, WorktreePruneOptions};

use crate::git_cli::git_in_dir;
pub mod hosted_review;
mod repository_metadata;
mod workflow_worktree;
mod worktree_creation;
pub use repository_metadata::{current_branch, is_worktree_clean, repository_remote_url};
pub use workflow_worktree::{ensure_workflow_worktree, verify_workflow_worktree};
pub use worktree_creation::create_worktree;

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
    GitCli,
    Conflict,
    RemoteNotFound,
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

pub fn list_branches(path: &str) -> Result<Vec<String>, GitError> {
    let repo = open_repo(path)?;
    let mut names = Vec::new();
    let branches = repo.branches(None).map_err(GitError::from_git2)?;
    for entry in branches {
        let (branch, _) = entry.map_err(GitError::from_git2)?;
        if let Some(name) = branch.name().map_err(GitError::from_git2)? {
            if name.ends_with("/HEAD") {
                continue;
            }
            names.push(name.to_string());
        }
    }
    names.sort();
    names.dedup();
    Ok(names)
}

pub fn branch_exists(repo_path: &str, branch: &str) -> Result<bool, GitError> {
    let repo = open_repo(repo_path)?;
    let result = match repo.find_branch(branch, BranchType::Local) {
        Ok(_) => Ok(true),
        Err(error) if error.code() == ErrorCode::NotFound => Ok(false),
        Err(error) => Err(GitError::from_git2(error)),
    };
    result
}

pub fn is_valid_branch_name(name: &str) -> Result<bool, GitError> {
    Branch::name_is_valid(name).map_err(GitError::from_git2)
}

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

pub fn delete_branch(repo_path: &str, branch: &str, _force: bool) -> Result<(), GitError> {
    let repo = open_repo(repo_path)?;
    let mut target = repo
        .find_branch(branch, BranchType::Local)
        .map_err(|error| match error.code() {
            ErrorCode::NotFound => GitError::new(GitErrorKind::BranchNotFound, branch),
            _ => GitError::from_git2(error),
        })?;
    target.delete().map_err(GitError::from_git2)?;
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

fn open_repo(path: &str) -> Result<Repository, GitError> {
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

fn worktree_admin_name(path: &str) -> String {
    Path::new(path)
        .file_name()
        .map(|name| name.to_string_lossy().to_string())
        .filter(|name| !name.trim().is_empty())
        .unwrap_or_else(|| "worktree".to_string())
        .replace(|ch: char| ch.is_ascii_control() || ch == '/', "-")
}

fn unique_worktree_admin_name(repo: &Repository, path: &str) -> String {
    let base = worktree_admin_name(path);
    let existing = existing_worktree_admin_names(repo);
    if !existing.contains(&base) {
        return base;
    }
    let parent = Path::new(path)
        .parent()
        .and_then(Path::file_name)
        .map(|name| name.to_string_lossy().to_string())
        .filter(|name| !name.trim().is_empty())
        .unwrap_or_else(|| "parent".to_string())
        .replace(|ch: char| ch.is_ascii_control() || ch == '/', "-");
    let mut suffix = 1usize;
    loop {
        let candidate = format!("{parent}-{base}-{suffix}");
        if !existing.contains(&candidate) {
            return candidate;
        }
        suffix += 1;
    }
}

fn existing_worktree_admin_names(repo: &Repository) -> std::collections::HashSet<String> {
    let mut names = std::collections::HashSet::new();
    if let Ok(list) = repo.worktrees() {
        for entry in list.iter() {
            if let Ok(Some(name)) = entry {
                names.insert(name.to_string());
            }
        }
    }
    names
}

fn canonical(path: &str) -> String {
    let target = Path::new(path);
    if let Ok(resolved) = std::fs::canonicalize(target) {
        return resolved.to_string_lossy().trim_end_matches('/').to_string();
    }
    if let (Some(parent), Some(name)) = (target.parent(), target.file_name()) {
        if let Ok(resolved_parent) = std::fs::canonicalize(parent) {
            return resolved_parent
                .join(name)
                .to_string_lossy()
                .trim_end_matches('/')
                .to_string();
        }
    }
    path.trim_end_matches('/').to_string()
}

fn git_cli_in_path(path: &str, args: &[&str]) -> Result<(), GitError> {
    git_in_dir(Path::new(path), args)
        .map(|_| ())
        .map_err(|error| GitError::new(GitErrorKind::GitCli, error.message))
}

fn git_fetch_remote(path: &str, remote: &str) -> Result<(), GitError> {
    git_cli_in_path(path, &["fetch", "--prune", remote])
}

fn git_pull_ff_only(path: &str) -> Result<(), GitError> {
    git_cli_in_path(path, &["pull", "--ff-only"])
}

fn find_remote_tracking_branch_name(
    repo: &Repository,
    source_branch: &str,
) -> Result<Option<String>, GitError> {
    let mut candidates = vec![source_branch];
    if let Some(stripped) = source_branch.strip_prefix("refs/remotes/") {
        candidates.push(stripped);
    }

    for candidate in candidates {
        match repo.find_branch(candidate, BranchType::Remote) {
            Ok(branch) => {
                return Ok(branch
                    .name()
                    .map_err(GitError::from_git2)?
                    .map(ToString::to_string));
            }
            Err(error) if error.code() == ErrorCode::NotFound => {}
            Err(error) => return Err(GitError::from_git2(error)),
        }
    }

    Ok(None)
}

fn configured_remote_for_tracking_branch(
    repo: &Repository,
    remote_branch: &str,
) -> Result<Option<String>, GitError> {
    let remotes = repo.remotes().map_err(GitError::from_git2)?;
    for remote in remotes.iter() {
        let Some(remote) = remote.map_err(GitError::from_git2)? else {
            continue;
        };
        if let Some(remainder) = remote_branch.strip_prefix(remote) {
            if remainder.starts_with('/') {
                return Ok(Some(remote.to_string()));
            }
        }
    }
    Ok(None)
}

fn checkout_path_for_branch(
    repo: &Repository,
    branch_name: &str,
) -> Result<Option<String>, GitError> {
    if head_branch_name(repo) == branch_name {
        if let Some(workdir) = repo.workdir() {
            return Ok(Some(workdir.to_string_lossy().to_string()));
        }
    }

    let names = repo.worktrees().map_err(GitError::from_git2)?;
    for entry in names.iter() {
        let Ok(Some(name)) = entry else {
            continue;
        };
        let worktree = repo.find_worktree(name).map_err(GitError::from_git2)?;
        let path = worktree.path();
        let Ok(worktree_repo) = Repository::open(path) else {
            continue;
        };
        if head_branch_name(&worktree_repo) == branch_name {
            return Ok(Some(path.to_string_lossy().to_string()));
        }
    }

    Ok(None)
}

fn fast_forward_local_branch(
    repo_path: &str,
    branch_name: &str,
    upstream_name: &str,
) -> Result<(), GitError> {
    let repo = open_repo(repo_path)?;
    let branch = repo
        .find_branch(branch_name, BranchType::Local)
        .map_err(|error| match error.code() {
            ErrorCode::NotFound => GitError::new(GitErrorKind::BranchNotFound, branch_name),
            _ => GitError::from_git2(error),
        })?;
    let upstream = repo
        .find_branch(upstream_name, BranchType::Remote)
        .map_err(|error| match error.code() {
            ErrorCode::NotFound => GitError::new(GitErrorKind::BranchNotFound, upstream_name),
            _ => GitError::from_git2(error),
        })?;
    let local_oid = branch
        .get()
        .target()
        .ok_or_else(|| GitError::new(GitErrorKind::Internal, branch_name))?;
    let upstream_oid = upstream
        .get()
        .target()
        .ok_or_else(|| GitError::new(GitErrorKind::Internal, upstream_name))?;
    if local_oid == upstream_oid {
        return Ok(());
    }

    if repo
        .graph_descendant_of(upstream_oid, local_oid)
        .map_err(GitError::from_git2)?
    {
        let reference_name = branch
            .get()
            .name()
            .map_err(GitError::from_git2)?
            .to_string();
        drop(upstream);
        drop(branch);
        let mut reference = repo
            .find_reference(&reference_name)
            .map_err(GitError::from_git2)?;
        reference
            .set_target(
                upstream_oid,
                "fast-forward source branch before worktree creation",
            )
            .map_err(GitError::from_git2)?;
        return Ok(());
    }

    if repo
        .graph_descendant_of(local_oid, upstream_oid)
        .map_err(GitError::from_git2)?
    {
        return Ok(());
    }

    Err(GitError::new(
        GitErrorKind::Conflict,
        format!("source branch \"{branch_name}\" has diverged from \"{upstream_name}\""),
    ))
}

fn remote_tracking_upstream_name(
    repo: &Repository,
    source_branch: &str,
) -> Result<Option<String>, GitError> {
    let mut candidates = vec![source_branch];
    if let Some(stripped) = source_branch.strip_prefix("refs/remotes/") {
        candidates.push(stripped);
    }

    for candidate in candidates {
        match repo.find_branch(candidate, BranchType::Remote) {
            Ok(branch) => {
                let Some(remote_branch) = branch.name().map_err(GitError::from_git2)? else {
                    return Ok(None);
                };
                let remote_branch = remote_branch.to_string();
                if has_configured_remote_for_tracking_branch(repo, &remote_branch)? {
                    return Ok(Some(remote_branch));
                }
                return Ok(None);
            }
            Err(error) if error.code() == ErrorCode::NotFound => {}
            Err(error) => return Err(GitError::from_git2(error)),
        }
    }

    Ok(None)
}

fn has_configured_remote_for_tracking_branch(
    repo: &Repository,
    remote_branch: &str,
) -> Result<bool, GitError> {
    Ok(configured_remote_for_tracking_branch(repo, remote_branch)?.is_some())
}

fn is_path_occupied(path: &str) -> bool {
    let target = Path::new(path);
    match std::fs::read_dir(target) {
        Ok(mut entries) => entries.next().is_some(),
        Err(_) => target.exists(),
    }
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
