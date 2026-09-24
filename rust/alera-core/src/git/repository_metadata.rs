use super::{head_branch_name, open_repo, GitError};

pub fn current_branch(path: &str) -> Result<String, GitError> {
    Ok(head_branch_name(&open_repo(path)?))
}

/// Project checkouts cannot adopt a linked worktree or a repository subdirectory.
pub fn project_checkout_branch(path: &str) -> Result<String, GitError> {
    let repo = open_repo(path)?;
    let invalid = || {
        GitError::new(
            super::GitErrorKind::Conflict,
            "Choose the main working directory of a non-bare Git repository",
        )
    };
    if repo.is_bare() || repo.is_worktree() {
        return Err(invalid());
    }
    let workdir = repo.workdir().ok_or_else(invalid)?;
    let canonical = |path: &std::path::Path| {
        std::fs::canonicalize(path)
            .map_err(|error| GitError::new(super::GitErrorKind::AccessDenied, error.to_string()))
    };
    if canonical(workdir)? != canonical(std::path::Path::new(path))? {
        return Err(invalid());
    }
    Ok(head_branch_name(&repo))
}

pub fn is_worktree_clean(path: &str) -> Result<bool, GitError> {
    let repo = open_repo(path)?;
    let mut options = git2::StatusOptions::new();
    options
        .include_untracked(true)
        .recurse_untracked_dirs(true)
        .include_ignored(false);
    let clean = repo
        .statuses(Some(&mut options))
        .map_err(GitError::from_git2)?
        .is_empty();
    Ok(clean)
}

pub fn repository_remote_url(path: &str) -> Result<Option<String>, GitError> {
    let repo = open_repo(path)?;
    if let Ok(remote) = repo.find_remote("origin") {
        return remote
            .url()
            .map(|url| Some(url.to_string()))
            .map_err(GitError::from_git2);
    }
    let remotes = repo.remotes().map_err(GitError::from_git2)?;
    for name in remotes.iter() {
        let Some(name) = name.map_err(GitError::from_git2)? else {
            continue;
        };
        let remote = repo.find_remote(name).map_err(GitError::from_git2)?;
        return remote
            .url()
            .map(|url| Some(url.to_string()))
            .map_err(GitError::from_git2);
    }
    Ok(None)
}

#[cfg(test)]
mod checkout_inspection_tests {
    use super::*;

    #[test]
    fn project_inspection_accepts_main_root_but_rejects_linked_bare_and_subdirectories() {
        let dir = tempfile::tempdir().unwrap();
        let path = dir.path().join("main");
        let repo = git2::Repository::init(&path).unwrap();
        repo.set_head("refs/heads/main").unwrap();
        let tree = repo.index().unwrap().write_tree().unwrap();
        let signature = git2::Signature::now("Test", "test@example.test").unwrap();
        let commit = repo
            .commit(
                Some("HEAD"),
                &signature,
                &signature,
                "Initial",
                &repo.find_tree(tree).unwrap(),
                &[],
            )
            .unwrap();
        let path_str = path.to_str().unwrap();
        assert_eq!(project_checkout_branch(path_str).unwrap(), "main");
        let linked = dir.path().join("linked");
        repo.worktree("linked", &linked, None).unwrap();
        assert!(project_checkout_branch(linked.to_str().unwrap()).is_err());
        let child = path.join("child");
        std::fs::create_dir(&child).unwrap();
        assert!(project_checkout_branch(child.to_str().unwrap()).is_err());
        let bare = dir.path().join("bare");
        git2::Repository::init_bare(&bare).unwrap();
        assert!(project_checkout_branch(bare.to_str().unwrap()).is_err());
        repo.set_head_detached(commit).unwrap();
        assert_eq!(project_checkout_branch(path_str).unwrap(), "HEAD");
        assert!(repo.head_detached().unwrap());
    }

    #[cfg(unix)]
    #[test]
    fn project_inspection_resolves_symlink_alias_without_mutating_unborn_branch() {
        let dir = tempfile::tempdir().unwrap();
        let path = dir.path().join("main");
        let repo = git2::Repository::init(&path).unwrap();
        repo.set_head("refs/heads/unborn").unwrap();
        let alias = dir.path().join("alias");
        std::os::unix::fs::symlink(&path, &alias).unwrap();
        assert_eq!(
            project_checkout_branch(alias.to_str().unwrap()).unwrap(),
            "unborn"
        );
        assert_eq!(
            repo.head().err().unwrap().code(),
            git2::ErrorCode::UnbornBranch
        );
        assert_eq!(
            std::fs::read_to_string(repo.path().join("HEAD")).unwrap(),
            "ref: refs/heads/unborn\n"
        );
    }
}
