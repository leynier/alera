//! Git primitives exposed to Flutter through flutter_rust_bridge.
//!
//! Every operation here is local and backed by `git2` (libgit2). The single
//! operation that needs the network — `clone` — is delegated to the system
//! `git` CLI through `git_cmd`, so the user's credential helper keeps working.
//! Business logic (paths, slugs, persistence, reconciliation) stays on the Dart
//! side; this module only models the raw git plumbing.

use std::path::Path;

use camino::Utf8Path;
use git2::{Branch, BranchType, ErrorCode, Repository, WorktreeAddOptions, WorktreePruneOptions};

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
    // `discover` (rather than `open`) so operations work when `path` is a
    // subdirectory of the work tree, matching `is_git_repository` and the
    // behaviour of `git -C <path> ...`.
    Repository::discover(path).map_err(|error| match error.code() {
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

/// Builds the `.git/worktrees/<id>` admin id from the target path's basename,
/// appending a numeric suffix when that id is already taken — mirroring
/// `git worktree add`, which disambiguates same-basename worktrees instead of
/// rejecting them. The id is internal: `list_worktrees`/`remove_worktree` match
/// worktrees by path, not by id, so any unique id is safe here.
fn unique_worktree_admin_name(repo: &Repository, path: &str) -> String {
    let base = worktree_admin_name(path);
    let existing = existing_worktree_admin_names(repo);
    if !existing.contains(&base) {
        return base;
    }
    let mut suffix = 1u32;
    loop {
        let candidate = format!("{base}{suffix}");
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
    let remotes = repo.remotes().map_err(GitError::from_git2)?;
    for remote in remotes.iter() {
        let Some(remote) = remote.map_err(GitError::from_git2)? else {
            continue;
        };
        if let Some(remainder) = remote_branch.strip_prefix(remote) {
            if remainder.starts_with('/') {
                return Ok(true);
            }
        }
    }
    Ok(false)
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

    // Match `git worktree add`: refuse an occupied target up front (an existing
    // empty directory is fine) so a blocked path never creates an orphan branch
    // or worktree admin entry that would make a later retry fail.
    if is_path_occupied(&path) {
        return Err(GitError::new(GitErrorKind::WorktreeAlreadyExists, path));
    }

    // Resolve the source as any committish (local branch, remote-tracking ref
    // like `origin/main`, tag, or SHA) to match `git worktree add`'s semantics.
    let source_commit = repo
        .revparse_single(&source_branch)
        .map_err(|_| GitError::new(GitErrorKind::BranchNotFound, source_branch.clone()))?
        .peel_to_commit()
        .map_err(GitError::from_git2)?;

    let upstream_name = remote_tracking_upstream_name(&repo, &source_branch)?;
    let mut branch =
        repo.branch(&new_branch, &source_commit, false)
            .map_err(|error| match error.code() {
                ErrorCode::Exists => {
                    GitError::new(GitErrorKind::BranchAlreadyExists, new_branch.clone())
                }
                ErrorCode::InvalidSpec => {
                    GitError::new(GitErrorKind::InvalidBranchName, new_branch.clone())
                }
                _ => GitError::from_git2(error),
            })?;
    if let Some(upstream_name) = upstream_name.as_deref() {
        if let Err(error) = branch.set_upstream(Some(upstream_name)) {
            let _ = branch.delete();
            return Err(GitError::from_git2(error));
        }
    }
    // Scope `reference`/`options` so the borrows they hold on `repo` end before
    // the rollback path below mutates refs.
    let worktree_result = {
        let reference = branch.into_reference();
        let mut options = WorktreeAddOptions::new();
        options.reference(Some(&reference));
        let admin_name = unique_worktree_admin_name(&repo, &path);
        repo.worktree(&admin_name, Path::new(&path), Some(&options))
    };
    if let Err(error) = worktree_result {
        // The branch was created above; if the worktree could not be added the
        // whole action failed, so roll the branch back to keep it atomic and
        // let a retry succeed instead of hitting BranchAlreadyExists.
        if let Ok(mut created) = repo.find_branch(&new_branch, BranchType::Local) {
            let _ = created.delete();
        }
        return Err(match error.code() {
            ErrorCode::Exists => GitError::new(GitErrorKind::WorktreeAlreadyExists, path.clone()),
            _ => GitError::from_git2(error),
        });
    }
    Ok(())
}

/// Whether `path` is occupied for the purpose of `git worktree add`: it exists
/// and is anything other than an empty directory.
fn is_path_occupied(path: &str) -> bool {
    let target = Path::new(path);
    match std::fs::read_dir(target) {
        // A directory is free only when empty.
        Ok(mut entries) => entries.next().is_some(),
        // Not a directory: occupied if it exists (e.g. a file), free otherwise.
        Err(_) => target.exists(),
    }
}

/// Removes the worktree whose checkout lives at `path`, deleting the working
/// tree files. Mirrors `git worktree remove --force <path>`.
pub fn remove_worktree(repo_path: String, path: String, force: bool) -> Result<(), GitError> {
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
pub fn delete_branch(repo_path: String, branch: String, _force: bool) -> Result<(), GitError> {
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
    fn rejects_bare_repository() {
        let bare = tempfile::tempdir().expect("tempdir");
        run_git(bare.path(), &["init", "--bare"]);

        assert!(!is_git_repository(path_str(bare.path())).unwrap());
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
        let worktree_base = tempfile::tempdir().expect("tempdir");
        let worktree_path = path_str(&worktree_base.path().join("feature"));

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
        let worktree_base = tempfile::tempdir().expect("tempdir");
        let worktree_path = path_str(&worktree_base.path().join("dupe"));
        let error = create_worktree(
            path_str(repo.path()),
            "feature".to_string(),
            worktree_path,
            "main".to_string(),
        )
        .unwrap_err();
        assert!(matches!(error.kind, GitErrorKind::BranchAlreadyExists));
    }

    #[test]
    fn operates_from_subdirectory() {
        let repo = init_repo();
        let subdir = repo.path().join("nested").join("dir");
        std::fs::create_dir_all(&subdir).expect("create subdir");

        let subdir_path = path_str(&subdir);
        assert!(is_git_repository(subdir_path.clone()).unwrap());
        assert_eq!(current_branch(subdir_path.clone()).unwrap(), "main");
        assert!(list_branches(subdir_path)
            .unwrap()
            .contains(&"main".to_string()));
    }

    #[test]
    fn creates_worktree_from_remote_tracking_branch() {
        let repo = init_repo();
        run_git(
            repo.path(),
            &["remote", "add", "origin", "https://example.com/repo.git"],
        );
        // Simulate a fetched remote-tracking ref without a network fetch.
        run_git(
            repo.path(),
            &["update-ref", "refs/remotes/origin/feature", "HEAD"],
        );

        let worktree_base = tempfile::tempdir().expect("tempdir");
        let worktree_path = path_str(&worktree_base.path().join("from-remote"));
        create_worktree(
            path_str(repo.path()),
            "local-feature".to_string(),
            worktree_path,
            "origin/feature".to_string(),
        )
        .unwrap();

        assert!(branch_exists(path_str(repo.path()), "local-feature".to_string()).unwrap());
        let repo_handle = Repository::open(repo.path()).unwrap();
        let config = repo_handle.config().unwrap();
        assert_eq!(
            config.get_string("branch.local-feature.remote").unwrap(),
            "origin"
        );
        assert_eq!(
            config.get_string("branch.local-feature.merge").unwrap(),
            "refs/heads/feature"
        );
    }

    #[test]
    fn rolls_back_branch_when_worktree_fails() {
        let repo = init_repo();
        // Block the worktree path with a non-empty directory so `repo.worktree`
        // fails after the branch has been created.
        let worktree_base = tempfile::tempdir().expect("tempdir");
        let blocked = worktree_base.path().join("blocked");
        std::fs::create_dir_all(&blocked).expect("create blocker dir");
        std::fs::write(blocked.join("busy.txt"), "x").expect("write blocker");
        let worktree_path = path_str(&blocked);

        let error = create_worktree(
            path_str(repo.path()),
            "feature".to_string(),
            worktree_path.clone(),
            "main".to_string(),
        )
        .unwrap_err();
        assert!(!matches!(error.kind, GitErrorKind::BranchAlreadyExists));
        // The branch must have been rolled back.
        assert!(!branch_exists(path_str(repo.path()), "feature".to_string()).unwrap());

        // After clearing the blocker, a retry succeeds (no orphan branch).
        std::fs::remove_dir_all(&worktree_path).expect("remove blocker dir");
        create_worktree(
            path_str(repo.path()),
            "feature".to_string(),
            worktree_path,
            "main".to_string(),
        )
        .unwrap();
        assert!(branch_exists(path_str(repo.path()), "feature".to_string()).unwrap());
    }

    #[test]
    fn creates_same_basename_worktrees_under_different_parents() {
        // The same repo can back two worktrees whose target paths share a
        // basename but live under different parents (e.g. the repo opened as two
        // Alera projects). Both must succeed; `git worktree add` disambiguates
        // the internal admin id rather than reporting WorktreeAlreadyExists.
        let repo = init_repo();
        let parent_a = tempfile::tempdir().expect("tempdir");
        let parent_b = tempfile::tempdir().expect("tempdir");
        let path_a = path_str(&parent_a.path().join("shared"));
        let path_b = path_str(&parent_b.path().join("shared"));

        create_worktree(
            path_str(repo.path()),
            "feature-a".to_string(),
            path_a.clone(),
            "main".to_string(),
        )
        .unwrap();
        create_worktree(
            path_str(repo.path()),
            "feature-b".to_string(),
            path_b.clone(),
            "main".to_string(),
        )
        .unwrap();

        assert!(Path::new(&path_a).join(".git").exists());
        assert!(Path::new(&path_b).join(".git").exists());

        let worktrees = list_worktrees(path_str(repo.path())).unwrap();
        let target_a = canonical(&path_a);
        let target_b = canonical(&path_b);
        assert!(worktrees
            .iter()
            .any(|entry| canonical(&entry.path) == target_a && entry.branch == "feature-a"));
        assert!(worktrees
            .iter()
            .any(|entry| canonical(&entry.path) == target_b && entry.branch == "feature-b"));
    }

    #[test]
    fn split_clone_destination_uses_basename_under_parent() {
        assert_eq!(
            split_clone_destination("repos/demo").unwrap(),
            ("repos".to_string(), "demo".to_string())
        );
        assert_eq!(
            split_clone_destination("/abs/repos/demo").unwrap(),
            ("/abs/repos".to_string(), "demo".to_string())
        );
        assert_eq!(
            split_clone_destination("demo").unwrap(),
            (".".to_string(), "demo".to_string())
        );
    }

    #[test]
    fn clones_from_local_source_into_nested_destination() {
        let source = init_repo();
        let workspace = tempfile::tempdir().expect("tempdir");
        let destination = workspace.path().join("nested").join("cloned");
        std::fs::create_dir_all(destination.parent().unwrap()).expect("create parent");

        clone_repository(path_str(source.path()), path_str(&destination)).unwrap();

        // The clone lands exactly at the destination, not double-nested.
        assert!(destination.join(".git").exists());
        assert!(!destination.join("cloned").exists());
        assert!(is_git_repository(path_str(&destination)).unwrap());
    }
}
