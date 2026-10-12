use super::workspace_comparison::{git_workspace_comparison, parse_oid};
use super::{
    current_head_commit, git_diff_paths::GitPathContext, open_repo, repository_has_conflicts,
    GitError, GitErrorKind, GitWorkspaceComparison,
};
use git2::{Index, RepositoryState};
use std::{
    collections::BTreeSet,
    fs,
    path::{Component, Path, PathBuf},
};

struct IndexLock {
    lock: PathBuf,
    head: Option<PathBuf>,
    candidate: PathBuf,
}
impl Drop for IndexLock {
    fn drop(&mut self) {
        let _ = fs::remove_file(&self.lock);
        if let Some(head) = &self.head {
            let _ = fs::remove_file(head);
        }
        let _ = fs::remove_file(&self.candidate);
        let _ = fs::remove_file(self.candidate.with_extension("lock"));
    }
}

pub fn git_commit_selected(
    path: String,
    snapshot: GitWorkspaceComparison,
    file_paths: Vec<String>,
    message: String,
) -> Result<String, GitError> {
    let repo = open_repo(&path)?;
    if repo.state() != RepositoryState::Clean || repository_has_conflicts(&repo)? {
        return Err(GitError::new(
            GitErrorKind::Conflict,
            "finish the current Git operation before committing",
        ));
    }
    if message.trim().is_empty() || file_paths.is_empty() {
        return Err(GitError::new(
            GitErrorKind::NothingToCommit,
            "select files and enter a commit message",
        ));
    }
    let paths = GitPathContext::new(&repo, &path)?;
    let mut selected = BTreeSet::new();
    for file in &file_paths {
        if file.is_empty()
            || Path::new(file).is_absolute()
            || file.contains('\\')
            || Path::new(file)
                .components()
                .any(|part| !matches!(part, Component::Normal(_)))
        {
            return Err(GitError::new(
                GitErrorKind::WorkspaceScope,
                "invalid selected file path",
            ));
        }
        let entry = snapshot
            .entries
            .iter()
            .find(|entry| entry.path == *file)
            .ok_or_else(|| {
                GitError::new(
                    GitErrorKind::WorkspaceScope,
                    "selected file is outside the snapshot",
                )
            })?;
        selected.insert(paths.to_repo_path(file));
        if let Some(old) = &entry.old_path {
            selected.insert(paths.to_repo_path(old));
        }
    }
    let mut real_index = repo.index().map_err(GitError::from_git2)?;
    let index_path = real_index
        .path()
        .ok_or_else(|| GitError::new(GitErrorKind::Conflict, "repository index is unavailable"))?
        .to_path_buf();
    let lock_path = index_path.with_extension("lock");
    // Hold Git's standard index lock through validation, ref update and index
    // reconciliation, so another client cannot have its staged work overwritten.
    let lock_file = fs::OpenOptions::new()
        .write(true)
        .create_new(true)
        .open(&lock_path)
        .map_err(GitError::from_io)?;
    drop(lock_file);
    let mut guard = IndexLock {
        lock: lock_path,
        head: None,
        candidate: repo
            .path()
            .join(format!("alera-selected-{}", uuid::Uuid::new_v4())),
    };
    let head_lock = repo.path().join("HEAD.lock");
    let head_file = fs::OpenOptions::new()
        .write(true)
        .create_new(true)
        .open(&head_lock)
        .map_err(GitError::from_io)?;
    drop(head_file);
    guard.head = Some(head_lock);
    let current = git_workspace_comparison(path.clone(), None)?;
    if current.head_oid != snapshot.head_oid
        || current.head_ref != snapshot.head_ref
        || current.tree_oid != snapshot.tree_oid
        || current.index_oid != snapshot.index_oid
    {
        return Err(GitError::new(
            GitErrorKind::Conflict,
            "files, staged changes or HEAD changed; review the commit again",
        ));
    }
    if !snapshot.head_ref.starts_with("refs/heads/") {
        return Err(GitError::new(
            GitErrorKind::DetachedHead,
            "check out a branch before committing",
        ));
    }
    let head = current_head_commit(&repo)?;
    let worktree = repo
        .find_tree(parse_oid(&snapshot.tree_oid)?)
        .map_err(GitError::from_git2)?;
    let mut disk_index = Index::new().map_err(GitError::from_git2)?;
    disk_index
        .read_tree(&worktree)
        .map_err(GitError::from_git2)?;
    let mut commit_index = Index::new().map_err(GitError::from_git2)?;
    if let Some(head) = &head {
        commit_index
            .read_tree(&head.tree().map_err(GitError::from_git2)?)
            .map_err(GitError::from_git2)?;
    }
    for file in &selected {
        if let Some(entry) = disk_index.get_path(Path::new(file), 0) {
            commit_index.add(&entry).map_err(GitError::from_git2)?;
        } else if commit_index.get_path(Path::new(file), 0).is_some() {
            commit_index
                .remove_path(Path::new(file))
                .map_err(GitError::from_git2)?;
        }
    }
    let tree_oid = commit_index
        .write_tree_to(&repo)
        .map_err(GitError::from_git2)?;
    if head.as_ref().is_some_and(|head| head.tree_id() == tree_oid) {
        return Err(GitError::new(
            GitErrorKind::NothingToCommit,
            "selected files have no changes",
        ));
    }
    if index_path.exists() {
        fs::copy(&index_path, &guard.candidate).map_err(GitError::from_io)?;
    }
    let mut next_index = Index::open(&guard.candidate).map_err(GitError::from_git2)?;
    real_index.read(true).map_err(GitError::from_git2)?;
    for file in &selected {
        if let Some(entry) = commit_index.get_path(Path::new(file), 0) {
            next_index.add(&entry).map_err(GitError::from_git2)?;
        } else if next_index.get_path(Path::new(file), 0).is_some() {
            next_index
                .remove_path(Path::new(file))
                .map_err(GitError::from_git2)?;
        }
    }
    next_index.write().map_err(GitError::from_git2)?;
    fs::write(
        &guard.lock,
        fs::read(&guard.candidate).map_err(GitError::from_io)?,
    )
    .map_err(GitError::from_io)?;
    let signature = repo.signature().map_err(|_| {
        GitError::new(
            GitErrorKind::MissingIdentity,
            "Configure Git user.name and user.email before committing.",
        )
    })?;
    let tree = repo.find_tree(tree_oid).map_err(GitError::from_git2)?;
    let parents: Vec<_> = head.iter().collect();
    // Create the commit without updating HEAD, then compare-and-swap its ref.
    let oid = repo
        .commit(
            None,
            &signature,
            &signature,
            message.trim(),
            &tree,
            &parents,
        )
        .map_err(GitError::from_git2)?;
    if let Some(head) = head {
        repo.reference_matching(
            &snapshot.head_ref,
            oid,
            true,
            head.id(),
            "alera: commit selected files",
        )
        .map_err(GitError::from_git2)?;
    } else {
        repo.reference(
            &snapshot.head_ref,
            oid,
            false,
            "alera: initial selected commit",
        )
        .map_err(GitError::from_git2)?;
    }
    fs::rename(&guard.lock, &index_path).map_err(|error| {
        GitError::new(
            GitErrorKind::Conflict,
            format!("Commit {oid} was created, but the index could not be updated: {error}"),
        )
    })?;
    Ok(oid.to_string())
}
