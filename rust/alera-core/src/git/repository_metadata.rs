use super::{head_branch_name, open_repo, GitError};

pub fn current_branch(path: &str) -> Result<String, GitError> {
    Ok(head_branch_name(&open_repo(path)?))
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
