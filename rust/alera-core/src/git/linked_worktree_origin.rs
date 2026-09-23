use super::{open_repo, GitError, GitErrorKind};

/// Recover ownership from Git metadata without assuming a managed-folder layout.
pub fn linked_worktree_repository_origin(path: &str) -> Result<String, GitError> {
    let invalid = || {
        GitError::new(
            GitErrorKind::Conflict,
            "The path is not a registered linked worktree root",
        )
    };
    let canonical = |path: &std::path::Path| {
        std::fs::canonicalize(path)
            .map_err(|error| GitError::new(GitErrorKind::AccessDenied, error.to_string()))
    };
    let repo = open_repo(path)?;
    let checkout = canonical(std::path::Path::new(path))?;
    if !repo.is_worktree() || canonical(repo.workdir().ok_or_else(invalid)?)? != checkout {
        return Err(invalid());
    }
    let owner = git2::Repository::open(repo.commondir()).map_err(GitError::from_git2)?;
    if owner.is_worktree() {
        return Err(invalid());
    }
    let origin = canonical(owner.workdir().unwrap_or_else(|| owner.path()))?;
    let origin = origin.to_str().ok_or_else(invalid)?.to_string();
    if !super::list_worktrees(&origin)?
        .iter()
        .any(|entry| std::fs::canonicalize(&entry.path).is_ok_and(|path| path == checkout))
    {
        return Err(invalid());
    }
    Ok(origin)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn linked_origin_uses_git_metadata_for_normal_and_bare_repositories() {
        let directory = tempfile::tempdir().unwrap();
        for bare in [false, true] {
            let root = directory
                .path()
                .join(if bare { "legacy.git" } else { "principal" });
            let repo = if bare {
                git2::Repository::init_bare(&root)
            } else {
                git2::Repository::init(&root)
            }
            .unwrap();
            repo.set_head("refs/heads/main").unwrap();
            let tree = repo.treebuilder(None).unwrap().write().unwrap();
            let signature = git2::Signature::now("Test", "test@example.test").unwrap();
            repo.commit(
                Some("HEAD"),
                &signature,
                &signature,
                "Initial",
                &repo.find_tree(tree).unwrap(),
                &[],
            )
            .unwrap();
            let linked = directory
                .path()
                .join(if bare { "legacy-linked" } else { "linked" });
            crate::git::create_worktree(
                root.to_str().unwrap(),
                "task",
                linked.to_str().unwrap(),
                "main",
                false,
            )
            .unwrap();
            let expected = root.canonicalize().unwrap().to_str().unwrap().to_string();
            assert_eq!(
                linked_worktree_repository_origin(linked.to_str().unwrap()).unwrap(),
                expected
            );
            assert!(linked_worktree_repository_origin(root.to_str().unwrap()).is_err());
            let child = linked.join("child");
            std::fs::create_dir(&child).unwrap();
            assert!(linked_worktree_repository_origin(child.to_str().unwrap()).is_err());
            #[cfg(unix)]
            {
                let alias = directory
                    .path()
                    .join(if bare { "legacy-alias" } else { "alias" });
                std::os::unix::fs::symlink(&linked, &alias).unwrap();
                assert_eq!(
                    linked_worktree_repository_origin(alias.to_str().unwrap()).unwrap(),
                    expected
                );
            }
            assert_eq!(
                crate::git::current_branch(root.to_str().unwrap()).unwrap(),
                "main"
            );
            assert_eq!(
                crate::git::current_branch(linked.to_str().unwrap()).unwrap(),
                "task"
            );
        }
    }
}
