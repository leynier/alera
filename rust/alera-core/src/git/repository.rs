use std::path::Path;

use git2::{BranchType, ErrorCode, Repository};

use super::{GitError, GitErrorKind};
use crate::git_cli::git_in_dir;

pub(super) fn open_repo(path: &str) -> Result<Repository, GitError> {
    Repository::discover(path).map_err(|error| match error.code() {
        ErrorCode::NotFound => GitError::new(GitErrorKind::NotARepository, path),
        _ => GitError::from_git2(error),
    })
}

pub(super) fn head_branch_name(repo: &Repository) -> String {
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

pub(super) fn unborn_branch_name(repo: &Repository) -> String {
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

pub(super) fn worktree_admin_name(path: &str) -> String {
    Path::new(path)
        .file_name()
        .map(|name| name.to_string_lossy().to_string())
        .filter(|name| !name.trim().is_empty())
        .unwrap_or_else(|| "worktree".to_string())
        .replace(|ch: char| ch.is_ascii_control() || ch == '/', "-")
}

pub(super) fn unique_worktree_admin_name(repo: &Repository, path: &str) -> String {
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

pub(super) fn existing_worktree_admin_names(
    repo: &Repository,
) -> std::collections::HashSet<String> {
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

pub(super) fn canonical(path: &str) -> String {
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

pub(super) fn git_cli_in_path(path: &str, args: &[&str]) -> Result<(), GitError> {
    git_in_dir(Path::new(path), args)
        .map(|_| ())
        .map_err(|error| GitError::new(GitErrorKind::GitCli, error.message))
}

pub(super) fn git_fetch_remote(path: &str, remote: &str) -> Result<(), GitError> {
    git_cli_in_path(path, &["fetch", "--prune", remote])
}

pub(super) fn git_pull_ff_only(path: &str) -> Result<(), GitError> {
    git_cli_in_path(path, &["pull", "--ff-only"])
}

pub(super) fn find_remote_tracking_branch_name(
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

pub(super) fn configured_remote_for_tracking_branch(
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

pub(super) fn checkout_path_for_branch(
    repo: &Repository,
    branch_name: &str,
) -> Result<Option<String>, GitError> {
    if worktree_occupies_branch(repo, branch_name) {
        if let Some(workdir) = repo.workdir() {
            return Ok(Some(workdir.to_string_lossy().to_string()));
        }
    }

    // Linked worktrees are not the main checkout. `Repository::worktrees`
    // also omits the main worktree, so occupancy checks from a linked
    // worktree must inspect the common repository separately.
    if repo.is_worktree() {
        if let Ok(main_repo) = Repository::open(repo.commondir()) {
            if worktree_occupies_branch(&main_repo, branch_name) {
                if let Some(workdir) = main_repo.workdir() {
                    return Ok(Some(workdir.to_string_lossy().to_string()));
                }
            }
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
        if worktree_occupies_branch(&worktree_repo, branch_name) {
            return Ok(Some(path.to_string_lossy().to_string()));
        }
    }

    Ok(None)
}

pub(super) fn worktree_occupies_branch(repo: &Repository, branch_name: &str) -> bool {
    if head_branch_name(repo) == branch_name {
        return true;
    }
    occupied_operation_branch(repo).as_deref() == Some(branch_name)
}

pub(super) fn occupied_operation_branch(repo: &Repository) -> Option<String> {
    let git_dir = repo.path();
    for relative in [
        "rebase-merge/head-name",
        "rebase-apply/head-name",
        "BISECT_START",
    ] {
        if let Some(name) = operation_branch_from_file(&git_dir.join(relative)) {
            return Some(name);
        }
    }
    None
}

pub(super) fn operation_branch_from_file(path: &Path) -> Option<String> {
    let contents = std::fs::read_to_string(path).ok()?;
    let value = contents.lines().next()?.trim();
    if value.is_empty() {
        return None;
    }
    Some(
        value
            .strip_prefix("refs/heads/")
            .unwrap_or(value)
            .to_string(),
    )
}

pub(super) fn fast_forward_local_branch(
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

pub(super) fn remote_tracking_upstream_name(
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

pub(super) fn has_configured_remote_for_tracking_branch(
    repo: &Repository,
    remote_branch: &str,
) -> Result<bool, GitError> {
    Ok(configured_remote_for_tracking_branch(repo, remote_branch)?.is_some())
}

pub(super) fn is_path_occupied(path: &str) -> bool {
    let target = Path::new(path);
    match std::fs::read_dir(target) {
        Ok(mut entries) => entries.next().is_some(),
        Err(_) => target.exists(),
    }
}
