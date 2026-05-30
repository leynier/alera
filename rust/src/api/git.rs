//! Git primitives exposed to Flutter through flutter_rust_bridge.
//!
//! Every operation here is local and backed by `git2` (libgit2). The single
//! operation that needs the network — `clone` — is delegated to the system
//! `git` CLI through `git_cmd`, so the user's credential helper keeps working.
//! Business logic (paths, slugs, persistence, reconciliation) stays on the Dart
//! side; this module only models the raw git plumbing.

use std::path::Path;

use camino::Utf8Path;
use git2::{
    Branch, BranchType, ErrorCode, Repository, WorktreeAddOptions, WorktreePruneOptions,
};

/// A single git worktree entry, mirroring one record of `git worktree list`.
pub struct GitWorktreeEntry {
    pub path: String,
    pub branch: String,
}

/// Discriminates the structured git failures surfaced to Dart. Kept as a plain
/// (field-less) enum so flutter_rust_bridge mirrors it as a Dart `enum` without
/// pulling in `freezed`.
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
    Internal,
}

/// Structured git failure surfaced to Dart. `context` carries the relevant
/// detail for the [`GitErrorKind`] (an offending path, branch name, or the
/// underlying git message). The Dart `RustGitBackend` translates each kind into
/// a domain `GitException`.
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
}

fn open_repo(path: &str) -> Result<Repository, GitError> {
    Repository::open(path).map_err(|error| match error.code() {
        ErrorCode::NotFound => GitError::new(GitErrorKind::NotARepository, path),
        _ => GitError::from_git2(error),
    })
}

/// Resolves the short branch name for a repository's HEAD, matching the
/// behaviour of `git branch --show-current` (detached/unknown → `HEAD`, but a
/// valid unborn branch still reports its name).
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
        .unwrap_or_else(|| path.to_string())
}

/// Canonicalizes a path for comparison, tolerating paths that no longer exist.
fn canonical(path: &str) -> String {
    std::fs::canonicalize(path)
        .map(|resolved| resolved.to_string_lossy().to_string())
        .unwrap_or_else(|_| path.trim_end_matches('/').to_string())
}

/// Returns `true` when `path` resolves to a git repository (work tree). Mirrors
/// `git rev-parse --is-inside-work-tree`; surfaces permission failures as
/// [`GitErrorKind::AccessDenied`] so the UI can explain sandbox denials.
pub fn is_git_repository(path: String) -> Result<bool, GitError> {
    match Repository::discover(&path) {
        Ok(_) => Ok(true),
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

/// Lists local and remote-tracking branch short names, sorted and de-duplicated,
/// excluding `*/HEAD` symbolic entries. Mirrors
/// `git for-each-ref --format=%(refname:short) refs/heads refs/remotes`.
pub fn list_branches(path: String) -> Result<Vec<String>, GitError> {
    let repo = open_repo(&path)?;
    let mut names: Vec<String> = Vec::new();
    let branches = repo.branches(None).map_err(GitError::from_git2)?;
    for entry in branches {
        let (branch, _kind) = entry.map_err(GitError::from_git2)?;
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

/// Returns the current branch short name, or `HEAD` when detached. Mirrors
/// `git branch --show-current`.
pub fn current_branch(path: String) -> Result<String, GitError> {
    let repo = open_repo(&path)?;
    Ok(head_branch_name(&repo))
}

/// Returns `true` when a local branch named `branch` exists.
pub fn branch_exists(repo_path: String, branch: String) -> Result<bool, GitError> {
    let repo = open_repo(&repo_path)?;
    let exists = match repo.find_branch(&branch, BranchType::Local) {
        Ok(_) => true,
        Err(error) if error.code() == ErrorCode::NotFound => false,
        Err(error) => return Err(GitError::from_git2(error)),
    };
    Ok(exists)
}

/// Validates a branch name. Mirrors `git check-ref-format --branch`.
pub fn is_valid_branch_name(name: String) -> Result<bool, GitError> {
    Branch::name_is_valid(&name).map_err(GitError::from_git2)
}

/// Creates `new_branch` from `source_branch` and adds a linked worktree at
/// `path`. Mirrors `git worktree add -b <new_branch> <path> <source_branch>`.
pub fn create_worktree(
    repo_path: String,
    new_branch: String,
    path: String,
    source_branch: String,
) -> Result<(), GitError> {
    let repo = open_repo(&repo_path)?;

    let source = repo
        .find_branch(&source_branch, BranchType::Local)
        .map_err(|_| GitError::new(GitErrorKind::BranchNotFound, source_branch.clone()))?;
    let source_commit = source
        .get()
        .peel_to_commit()
        .map_err(GitError::from_git2)?;

    let branch = repo
        .branch(&new_branch, &source_commit, false)
        .map_err(|error| match error.code() {
            ErrorCode::Exists => {
                GitError::new(GitErrorKind::BranchAlreadyExists, new_branch.clone())
            }
            ErrorCode::InvalidSpec => {
                GitError::new(GitErrorKind::InvalidBranchName, new_branch.clone())
            }
            _ => GitError::from_git2(error),
        })?;
    let reference = branch.into_reference();

    let mut options = WorktreeAddOptions::new();
    options.reference(Some(&reference));
    let admin_name = worktree_admin_name(&path);
    repo.worktree(&admin_name, Path::new(&path), Some(&options))
        .map_err(|error| match error.code() {
            ErrorCode::Exists => {
                GitError::new(GitErrorKind::WorktreeAlreadyExists, path.clone())
            }
            _ => GitError::from_git2(error),
        })?;
    Ok(())
}

/// Removes the worktree whose checkout lives at `path`, deleting the working
/// tree files. Mirrors `git worktree remove --force <path>`.
pub fn remove_worktree(
    repo_path: String,
    path: String,
    force: bool,
) -> Result<(), GitError> {
    let repo = open_repo(&repo_path)?;
    let target = canonical(&path);

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
    let worktree =
        found.ok_or_else(|| GitError::new(GitErrorKind::WorktreeNotFound, path.clone()))?;

    let mut options = WorktreePruneOptions::new();
    options.valid(true).working_tree(true).locked(force);
    worktree
        .prune(Some(&mut options))
        .map_err(GitError::from_git2)?;
    Ok(())
}

/// Force-deletes a local branch. Mirrors `git branch -D <branch>`.
pub fn delete_branch(
    repo_path: String,
    branch: String,
    _force: bool,
) -> Result<(), GitError> {
    let repo = open_repo(&repo_path)?;
    let mut target = repo
        .find_branch(&branch, BranchType::Local)
        .map_err(|error| match error.code() {
            ErrorCode::NotFound => GitError::new(GitErrorKind::BranchNotFound, branch.clone()),
            _ => GitError::from_git2(error),
        })?;
    target.delete().map_err(GitError::from_git2)?;
    Ok(())
}

/// Lists the main work tree plus every linked worktree, with each entry's
/// branch short name. Mirrors `git worktree list --porcelain` (the main work
/// tree is included so callers can use its presence as a liveness guard).
pub fn list_worktrees(repo_path: String) -> Result<Vec<GitWorktreeEntry>, GitError> {
    let repo = open_repo(&repo_path)?;
    let mut entries: Vec<GitWorktreeEntry> = Vec::new();

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

/// Clones a repository into `destination_path` using the system `git` CLI so
/// the user's credential helper authenticates private remotes. Mirrors
/// `git clone --progress -- <url> <destination_path>`.
pub fn clone_repository(url: String, destination_path: String) -> Result<(), GitError> {
    let destination = Path::new(&destination_path);
    let parent = destination
        .parent()
        .filter(|parent| !parent.as_os_str().is_empty())
        .unwrap_or_else(|| Path::new("."));
    let parent = Utf8Path::from_path(parent).ok_or_else(|| {
        GitError::new(
            GitErrorKind::CloneFailed,
            format!("destination parent is not valid UTF-8: {destination_path}"),
        )
    })?;

    git_cmd::git_in_dir(
        parent,
        &["clone", "--progress", "--", &url, &destination_path],
    )
    .map_err(|error| GitError::new(GitErrorKind::CloneFailed, error.to_string()))?;
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::path::Path;
    use std::process::Command;

    fn run_git(dir: &Path, args: &[&str]) {
        let status = Command::new("git")
            .args(args)
            .current_dir(dir)
            .env("GIT_AUTHOR_NAME", "Test")
            .env("GIT_AUTHOR_EMAIL", "test@example.com")
            .env("GIT_COMMITTER_NAME", "Test")
            .env("GIT_COMMITTER_EMAIL", "test@example.com")
            .status()
            .expect("git command runs");
        assert!(status.success(), "git {:?} failed", args);
    }

    fn init_repo() -> tempfile::TempDir {
        let dir = tempfile::tempdir().expect("tempdir");
        run_git(dir.path(), &["init", "-b", "main"]);
        std::fs::write(dir.path().join("README.md"), "hello").expect("write");
        run_git(dir.path(), &["add", "."]);
        run_git(dir.path(), &["commit", "-m", "initial"]);
        dir
    }

    fn path_str(path: &Path) -> String {
        path.to_string_lossy().to_string()
    }

    #[test]
    fn detects_repository() {
        let repo = init_repo();
        assert!(is_git_repository(path_str(repo.path())).unwrap());

        let plain = tempfile::tempdir().expect("tempdir");
        assert!(!is_git_repository(path_str(plain.path())).unwrap());
    }

    #[test]
    fn reports_branches_and_current() {
        let repo = init_repo();
        run_git(repo.path(), &["branch", "feature"]);

        let branches = list_branches(path_str(repo.path())).unwrap();
        assert!(branches.contains(&"main".to_string()));
        assert!(branches.contains(&"feature".to_string()));

        assert_eq!(current_branch(path_str(repo.path())).unwrap(), "main");
        assert!(branch_exists(path_str(repo.path()), "feature".to_string()).unwrap());
        assert!(!branch_exists(path_str(repo.path()), "missing".to_string()).unwrap());
    }

    #[test]
    fn validates_branch_names() {
        assert!(is_valid_branch_name("feature/login".to_string()).unwrap());
        assert!(!is_valid_branch_name("bad branch".to_string()).unwrap());
    }

    #[test]
    fn creates_lists_and_removes_worktree() {
        let repo = init_repo();
        let worktree_path = repo.path().join("..").join("wt-feature");
        let worktree_path = worktree_path.to_string_lossy().to_string();

        create_worktree(
            path_str(repo.path()),
            "feature".to_string(),
            worktree_path.clone(),
            "main".to_string(),
        )
        .unwrap();

        assert!(branch_exists(path_str(repo.path()), "feature".to_string()).unwrap());
        let worktrees = list_worktrees(path_str(repo.path())).unwrap();
        assert!(worktrees.iter().any(|entry| entry.branch == "feature"));
        assert!(worktrees.iter().any(|entry| entry.branch == "main"));

        remove_worktree(path_str(repo.path()), worktree_path.clone(), true).unwrap();
        let worktrees = list_worktrees(path_str(repo.path())).unwrap();
        assert!(!worktrees.iter().any(|entry| entry.branch == "feature"));

        delete_branch(path_str(repo.path()), "feature".to_string(), true).unwrap();
        assert!(!branch_exists(path_str(repo.path()), "feature".to_string()).unwrap());
    }

    #[test]
    fn rejects_duplicate_branch() {
        let repo = init_repo();
        run_git(repo.path(), &["branch", "feature"]);
        let worktree_path = path_str(&repo.path().join("..").join("wt-dupe"));
        let error = create_worktree(
            path_str(repo.path()),
            "feature".to_string(),
            worktree_path,
            "main".to_string(),
        )
        .unwrap_err();
        assert!(matches!(error.kind, GitErrorKind::BranchAlreadyExists));
    }
}
