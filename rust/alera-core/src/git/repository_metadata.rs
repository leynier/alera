use super::{head_branch_name, open_repo, GitError};

pub fn current_branch(path: &str) -> Result<String, GitError> {
    Ok(head_branch_name(&open_repo(path)?))
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
