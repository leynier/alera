//! Fetch, pull and push through the git CLI so the credential helper applies.

use super::*;

pub fn git_fetch(path: String) -> Result<(), GitError> {
    git_cli_in_path(&path, &["fetch", "--all", "--prune"])
}

pub fn git_pull(path: String) -> Result<(), GitError> {
    git_cli_in_path(&path, &["pull"])
}

pub fn git_push(path: String) -> Result<(), GitError> {
    let repo = open_repo(&path)?;
    let state = git_repository_state(path.clone())?;
    if state.branch == "HEAD" {
        return Err(GitError::new(
            GitErrorKind::DetachedHead,
            "cannot push detached HEAD",
        ));
    }
    if state.upstream.is_some() {
        return git_cli_in_path(&path, &["push"]);
    }
    if repo.find_remote("origin").is_err() {
        return Err(GitError::new(
            GitErrorKind::RemoteNotFound,
            "remote origin not found",
        ));
    }
    git_cli_in_path(&path, &["push", "-u", "origin", &state.branch])
}

fn git_cli_in_path(path: &str, args: &[&str]) -> Result<(), GitError> {
    git_in_dir(Path::new(path), args)
        .map(|_| ())
        .map_err(|error| GitError::new(GitErrorKind::GitCli, error.message))
}
